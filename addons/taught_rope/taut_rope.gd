class_name TautRope
extends Node2D

enum DetectionType{RAYCAST, SEGEMENT_CAST, AREA_CCD}

@export var detection_type: DetectionType = DetectionType.RAYCAST
@export var width: float = 2

@export_category('Physics')
@export_flags_2d_physics var collision_mask: int = 1
@export var CCD_group: StringName

var ray_margin: float = 1

var rope_start: Vector2 = Vector2.ZERO
var rope_end: Vector2
var wrapped_objects: Array[WrappedObject]
var unwrap_queue: Array[WrappedObject]
var global_points: Array[Vector2]
var local_points: Array[Vector2]

var space: PhysicsDirectSpaceState2D
var line_segment: SegmentShape2D = SegmentShape2D.new()
var endpoint_query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()

var CCD_shapes: Array[RID]

var debug_vectors: Array[Rect2]

class WrapPoint:
	var position: Vector2
	var prev_position: Vector2
	var direction: Vector2
	## stored the indices of where tangents were found in the polygon's vertices
	var tangent_index: int

class WrappedObject:
	var collider: CollisionObject2D:
		set(value):
			collider = value
			rid = collider.get_rid()
	var rid: RID
	var shape: int:
		set(value):
			shape = value
			shape_rid = PhysicsServer2D.body_get_shape(rid,shape)
	var shape_rid: RID
	var point1: WrapPoint = WrapPoint.new()
	var point2: WrapPoint = WrapPoint.new()
	var prev_cross: int
	var turns: int = 0
	## The direction point 2 wraps around the shape. +1 for clockwise, -1 CCW. Point 1 always wraps opposite
	var angular_direction: int
	
	## calcs wrap angle and returns true if the object should be released
	func calc_turns()->void:
		var cross: int = directional_cross()
		if cross == 0:
			return
		var dot: float = directional_dot()
		if cross != prev_cross:
			#crossed over the 180 or 0 degree mark relative to to other tangent point
			if  dot < 0:
				#if the directions are pointing opposite a full turn (not half turn) has been completed
				turns += cross * angular_direction
				
		prev_cross = cross
	
	## returns the sign of the cross product between the tangent directions
	func directional_cross()-> int:
		return sign(point1.direction.cross(point2.direction))
	
	## returns the dot product between the tangent directions
	func directional_dot() -> float:
		return point1.direction.dot(point2.direction)
	
	func get_global_transform()->Transform2D:
		return collider.global_transform * PhysicsServer2D.body_get_shape_transform(rid,shape)


func _ready() -> void:
	space = get_world_2d().direct_space_state
	rope_start = self.global_position
	rope_end = self.global_position
	
	#rope start fake wrapped object
	wrapped_objects.append(WrappedObject.new())
	#rope end fake wrapped object
	wrapped_objects.append(WrappedObject.new())
	
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = width / 2
	endpoint_query.shape = circle
	endpoint_query.collision_mask = collision_mask
	
	#if CCD_group != null:
		#get_tree().get_nodes_in_group(CCD_group)

func _physics_process(delta: float) -> void:
	
	#set the start and end rope positions
	wrapped_objects[0].point2.position = constrain_endpoint(rope_start)
	wrapped_objects[-1].point1.position = constrain_endpoint(rope_end)
	
	var curr_object: WrappedObject
	#loop through current wrapped object to update there tangents and check if they need to be released
	for i:int in range(1,wrapped_objects.size() - 1):
		curr_object = wrapped_objects[i]
		
		#find next tangent points
		calc_tangent(curr_object, wrapped_objects[i-1].point2.position, curr_object.point1, -curr_object.angular_direction)
		calc_tangent(curr_object, wrapped_objects[i+1].point1.position, curr_object.point2, curr_object.angular_direction)
		curr_object.calc_turns()
		if curr_object.turns < 0:
			# release object
			unwrap_queue.append(curr_object)
			
	
	#scane for new intersecting objects
	for i:int in range(1, wrapped_objects.size()):
		
		var collision_point: Vector2
		var collision_object: WrappedObject = WrappedObject.new()
		var exclude: Array[RID] = []#[wrapped_objects[i-1].rid, wrapped_objects[i].rid]
		var line_cast_segment: Rect2 = Rect2(wrapped_objects[i].point1.position, wrapped_objects[i-1].point2.position)
		line_cast_segment = _line_segment_margin(line_cast_segment, ray_margin)
		if detection_type == DetectionType.RAYCAST:
			#cast ray back to previous object
			var result: Dictionary = cast_ray(line_cast_segment,exclude)
			if result == {}:
				continue
			else:
				var normal: Vector2 = calc_normal(result.line_pos, result.position, i, result.object)
				collision_point = result.position
				collision_object = result.object
		elif detection_type == DetectionType.SEGEMENT_CAST:
			#cast segment back to previous object
			var result: Dictionary = cast_segment(line_cast_segment,exclude)
			if result == {}:
				continue
			else: 
				collision_point = result.point
				collision_object.collider = instance_from_id(result.collider_id)
				collision_object.shape = result.shape
		
		
		
		collision_object.point1.position = collision_point
		collision_object.point1.direction = line_cast_segment.size - collision_point
		collision_object.point2.position = collision_point
		collision_object.point2.direction = line_cast_segment.position - collision_point
		collision_object.prev_cross = collision_object.directional_cross()
		if collision_object.prev_cross == 0:
			#the directions are parallel so we cant determine the wrap direction
			#cancel creating the object, the next itteration should hopefully catch when the rope is deeper in the object
			#and a non zero angle between normals will be made
			print('abort')
			continue
		collision_object.angular_direction = collision_object.prev_cross
		calc_tangent(collision_object, wrapped_objects[i-1].point2.position, collision_object.point1, -collision_object.angular_direction)
		calc_tangent(collision_object, wrapped_objects[i].point1.position, collision_object.point2, collision_object.angular_direction)
		
		wrapped_objects.insert(i,collision_object)
	
	#release objects queued for release
	for object:WrappedObject in unwrap_queue:
		wrapped_objects.erase(object)
	unwrap_queue.clear()
	
	#update prev positions
	for object: WrappedObject in wrapped_objects:
		object.point1.prev_position = object.point1.position
		object.point2.prev_position = object.point2.position
	
	
	calc_global_points()
	queue_redraw()

func cast_ray(line:Rect2, exclude:Array[RID]) -> Dictionary:
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(line.position, line.size, collision_mask)
	query.hit_from_inside = false
	query.exclude = exclude
	var result: Dictionary = space.intersect_ray(query)
	var collision_result: Dictionary = {}
	if result == {}:
		return collision_result
	else:
		var new_object: WrappedObject = WrappedObject.new()
		new_object.collider = result.collider
		new_object.shape = result.shape
		collision_result['object'] = new_object
		#fraction along the rope segment that is colliding
		collision_result['line_pos'] = (line.position - result.position).length() / (line.position-line.size).length()
		collision_result['position'] = result.position
		return collision_result

func cast_segment(line: Rect2, exclude: Array[RID])->Dictionary:
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.exclude = exclude
	line_segment.a = line.position
	line_segment.b = line.size
	query.shape = line_segment
	return space.get_rest_info(query)

## shrink a line segment along its direction by margin
## rect2 is used to store the start and end position of the segment in position and size respectfully
func _line_segment_margin(segment:Rect2, margin: float)->Rect2:
	var dir: Vector2 = (segment.size - segment.position)
	dir = dir.normalized() * min(margin, dir.length() / 2)
	return Rect2(segment.position + dir, segment.size - dir)

func calc_tangent(object:WrappedObject, from:Vector2, point: WrapPoint, angular_direction: int)->bool:
	var shape_type:int = PhysicsServer2D.shape_get_type(object.shape_rid)
	# note that a rect is used to store a position and a normal (in the size)
	match shape_type:
		PhysicsServer2D.ShapeType.SHAPE_CIRCLE:
			var radius: float = PhysicsServer2D.shape_get_data(object.shape_rid)
			var center: Vector2 = object.get_global_transform().origin
			var from_center: Vector2 = (from - center)
			var angle: float = acos(radius/from_center.length()) * angular_direction
			point.position = center + from_center.normalized().rotated(angle) * radius
			point.direction = (from - point.position).normalized()
			bool()
			return true
		PhysicsServer2D.ShapeType.SHAPE_CAPSULE:
			pass
		PhysicsServer2D.ShapeType.SHAPE_RECTANGLE:
			pass
		PhysicsServer2D.ShapeType.SHAPE_CONVEX_POLYGON:
			var poly_points: PackedVector2Array = PhysicsServer2D.shape_get_data(object.shape_rid)
			var prev_direction: Vector2 = point.direction
			var poly_trans: Transform2D = object.get_global_transform()
			#find first tangent
			var from_p: Vector2 = from * poly_trans
			point.tangent_index = _find_tangent(point.tangent_index, from_p, angular_direction, poly_points)
			point.position = poly_trans * poly_points[point.tangent_index ]
			point.direction = (from - point.position).normalized()

			return true
		_:
			print("shape type: ",shape_type , " not handled")
	
	return false

## finds a tangent to the convex polygon given by points to the vector from. starts searching at the start_i index.
## returns -1 if no tangent is found ie, from is inside the polygon
func _find_tangent(start_i:int, from: Vector2, side:int, points: PackedVector2Array)->int:
	#most of the start_i is going to be correct so should optimise to return it quickly
	var size: int = points.size()
	for n: int in range(size):
		var i: int = (n >> 1) ^ ( -(n & 1)) #funky way of making the sequence 0, -1, 1, -2, 2... #https://stackoverflow.com/questions/2210923/zig-zag-decoding
		#can be read as (n div 2 ) * -1 ^ (n mod 2) in algebraic terms
		#this index needs to be positive as it will be returned
		i = posmod(i + start_i, size)
		#modulus operation to wrap
		var next_i: int = (i + 1) % size
		var rope: Vector2 = (points[i] - from)
		var prev: int = sign(rope.cross(points[i - 1] - from))
		var next: int = sign(rope.cross(points[next_i] - from))
		if prev == side and next == side:
			return i
	#should only return -1 if from is inside the polygon
	return -1

func calc_normal(line_pos:float,collision_position:Vector2,index:int, col_object: WrappedObject)->Vector2:
	var object: WrappedObject = wrapped_objects[index]
	var prev_object: WrappedObject = wrapped_objects[index - 1]
	var rope_orthogonal: Vector2 = (prev_object.point2.position - object.point1.position).orthogonal().normalized()
	#rope velocity
	var point1_delta: Vector2 = prev_object.point2.position - prev_object.point2.prev_position
	var point2_delta: Vector2 = object.point1.position - object.point1.prev_position
	var rope_velocity: Vector2 = (line_pos * point2_delta + (1 - line_pos) * point1_delta) / get_physics_process_delta_time()
	
	#object point (of collision) velocity
	var point_velocity: Vector2 = Vector2.ZERO
	if col_object.collider in CCD_shapes:
		#can get previous position
		pass
	elif col_object.collider is RigidBody2D:
		point_velocity = object.collider.linear_velocity 
		point_velocity += object.collider.angular_velocity * (collision_position - object.collider.global_transform.origin).orthogonal()
	elif col_object.collider is CharacterBody2D:
		#cant get angular velocity
		point_velocity = col_object.collider.get_real_velocity()
	
	var normal: Vector2 = rope_orthogonal * rope_orthogonal.dot(point_velocity - rope_velocity)
	if normal.is_zero_approx():
		var vector_to_center: Vector2 = col_object.get_global_transform().origin - collision_position
		normal = rope_orthogonal * sign(rope_orthogonal.dot(vector_to_center))
		return normal
	else:
		return normal


func constrain_endpoint(pos:Vector2)->Vector2:
	endpoint_query.transform.origin = pos
	var result: Dictionary = space.get_rest_info(endpoint_query)
	if result != {}:
		return result.point + result.normal * width / 2
	return pos

func _draw() -> void:
	draw_set_transform_matrix(self.global_transform.inverse())
	draw_polyline(global_points,Color.DARK_RED,1,true)
	for point: Vector2 in global_points:
		draw_circle(point,1,Color.WEB_GREEN,true)
	for vector:Rect2 in debug_vectors:
		draw_line(vector.position,vector.size,Color.WHITE)
	debug_vectors.clear()
	

## populate all the wrapped objections positions into one array
func calc_global_points()->void:
	global_points.resize((wrapped_objects.size() -1) * 2)
	global_points[0] = wrapped_objects[0].point2.position
	for i:int in range(1,wrapped_objects.size()-1):
		var p_i: int = (i * 2) - 1
		global_points[p_i] = wrapped_objects[i].point1.position
		global_points[p_i + 1] = wrapped_objects[i].point2.position
	global_points[-1] = wrapped_objects[-1].point1.position

func debug_vector(from:Vector2,to:Vector2)->void:
	debug_vectors.append(Rect2(from,to))
