class_name TaughtRope
extends Node2D

enum DetectionType{RAYCAST, SEGEMENT_CAST, AREA_CCD}

@export var detection_type: DetectionType = DetectionType.RAYCAST

@export_category('Physics')
@export_flags_2d_physics var collision_mask: int = 1
@export var CCD_group: StringName

var rope_start: Vector2 = Vector2.ZERO
var rope_end: Vector2
var wrapped_objects: Array[WrappedObject]
var unwrap_queue: Array[WrappedObject]
var global_points: Array[Vector2]
var local_points: Array[Vector2]

var space: PhysicsDirectSpaceState2D
var line_segment: SegmentShape2D = SegmentShape2D.new()

var CCD_shapes: Array[RID]

var debug_vectors: Array[Rect2]

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
	var point1: Vector2
	var point2: Vector2
	var normal1: Vector2
	var normal2: Vector2
	var prev_point1: Vector2
	var prev_point2: Vector2
	# here using the dot product as its cheeper than calculating angles
	var prev_dot: float
	var prev_orth_dot: int
	var turns: int = 0
	var direction: int
	
	## calcs wrap angle and returns true if the object should be released
	func calc_turns()->void:
		#TODO could probably replace orth dot with a cross product to skip calculating orthogonal
		#orth dot describes which side of normal 1 does normal 2 lie, ie CC or CCW
		#TODO now that we are storing points in this object may be able to do this logic without normals
		var orth_dot: int = sign(normal1.orthogonal().dot(normal2))
		if orth_dot == 0:
			return
		#var quad: int = 1 + int(norm_dot < 0) + 2 * int(orth_dot < 0)
		var dot: float = normal1.dot(normal2)
		if orth_dot != prev_orth_dot:
			#orth changed side
			if dot + prev_dot > -1:
				#is the new angle plus the old angle less than 180 degrees (in dot product terms)
				#basically checking if it is closer to adding a half turn or full turn (only care about full turn)
				turns -= orth_dot * direction
		
		prev_dot = dot
		prev_orth_dot = orth_dot
	
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
	
	
	#if CCD_group != null:
		#get_tree().get_nodes_in_group(CCD_group)

func _physics_process(delta: float) -> void:
	
	wrapped_objects[0].point2 = rope_start
	wrapped_objects[-1].point1 = rope_end

	var curr_object: WrappedObject
	for i:int in range(1,wrapped_objects.size() - 1):
		curr_object = wrapped_objects[i]
		
		#find next tangent points
		var point: Rect2 = calc_tangent(curr_object, wrapped_objects[i-1].point2, curr_object.point1)
		curr_object.point1 = point.position
		curr_object.normal1 = point.size
		point = calc_tangent(curr_object, wrapped_objects[i+1].point1, curr_object.point2)
		curr_object.point2 = point.position
		curr_object.normal2 = point.size
		
		curr_object.calc_turns()
		if curr_object.turns < 0:
			# release object
			unwrap_queue.append(curr_object)
			
		
	for object:WrappedObject in unwrap_queue:
		wrapped_objects.erase(object)
	unwrap_queue.clear()
	
	for i:int in range(1, wrapped_objects.size()):
		#cast ray back to previous object
		var collision_point: Vector2
		var collision_object: WrappedObject = WrappedObject.new()
		var exclude: Array[RID] = [wrapped_objects[i-1].rid,wrapped_objects[i].rid]
		if detection_type == DetectionType.RAYCAST:
			var result: Dictionary = cast_ray(wrapped_objects[i].point1, wrapped_objects[i-1].point2,exclude)
			if result == {}:
				continue
			else:
				var normal: Vector2 = calc_normal(result.line_pos, result.position, i, result.object)
				collision_point = result.position
				collision_object = result.object
		elif detection_type == DetectionType.SEGEMENT_CAST:
			var result: Dictionary = cast_segment(wrapped_objects[i].point1, wrapped_objects[i-1].point2,exclude)
			if result == {}:
				continue
			else: 
				collision_point = result.point
				collision_object.collider = instance_from_id(result.collider_id)
				collision_object.shape = result.shape

		var point1: Rect2 = calc_tangent(collision_object, wrapped_objects[i-1].point2, collision_point)
		var point2: Rect2 = calc_tangent(collision_object, wrapped_objects[i].point1, collision_point)
		collision_object.prev_orth_dot = sign(point1.size.orthogonal().dot(point2.size))
		if collision_object.prev_orth_dot == 0:
			#the normals point same direction so we cant determine the wrap direction
			#cancel creating the object, the next itteration should hopefully catch when the rope is deeper in the object
			#and a non zero angle between normals will be made
			print('abort')
			continue
		collision_object.point1 = point1.position
		collision_object.normal1 = point1.size
		collision_object.point2 = point2.position
		collision_object.normal2 = point2.size
		
		collision_object.prev_dot = collision_object.normal1.dot(collision_object.normal2)
		#get the initial wrap direction +ve for CW and -ve for CCW
		collision_object.direction = - collision_object.prev_orth_dot
		wrapped_objects.insert(i,collision_object)
	
	for object: WrappedObject in wrapped_objects:
		object.prev_point1 = object.point1
		object.prev_point2 = object.point2
	
	calc_global_points()
	
	queue_redraw()

func cast_ray(A:Vector2,B:Vector2,exclude:Array[RID]) -> Dictionary:
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(A,B,collision_mask)
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
		collision_result['line_pos'] = (A - result.position).length() / (A-B).length()
		collision_result['position'] = result.position
		return collision_result

func cast_segment(from: Vector2, to: Vector2, exclude: Array[RID])->Dictionary:
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.exclude = exclude
	line_segment.a = from
	line_segment.b = to
	query.shape = line_segment
	return space.get_rest_info(query)
		

## returns a rect2 with the size represnting the tangent normal
func calc_tangent(object:WrappedObject, from:Vector2, point:Vector2)->Rect2:
	var shape_type = PhysicsServer2D.shape_get_type(object.shape_rid)
	# note that a rect is used to store a position and a normal (in the size)
	var result: Rect2 = Rect2(Vector2.ZERO,Vector2.ZERO)
	match shape_type:
		PhysicsServer2D.ShapeType.SHAPE_CIRCLE:
			var radius: float = PhysicsServer2D.shape_get_data(object.shape_rid)
			var center: Vector2 = object.get_global_transform().origin
			var from_center: Vector2 = (from - center)
			var angle: float = acos(radius/from_center.length()) * sign(from_center.cross(point - center))
			result.size = from_center.normalized().rotated(angle)
			result.position = center + result.size * radius
		PhysicsServer2D.ShapeType.SHAPE_CAPSULE:
			pass
		PhysicsServer2D.ShapeType.SHAPE_RECTANGLE:
			pass
		PhysicsServer2D.ShapeType.SHAPE_CONVEX_POLYGON:
			var poly_points: PackedVector2Array = PhysicsServer2D.shape_get_data(object.shape_rid)
			var high:int = poly_points.size() - 1
			var low:int = 0
			var mid: int = low + (high - low)/2
			var inside: Vector2 = (poly_points[0] + poly_points[mid]) / 2
			debug_vector(inside,from)
			#var side: int = sign((from - inside).cross(normal))
			#for i:int in range(poly_points.size()):
				#var rope: Vector2 = (poly_points[i] - from)
				#var prev: int = sign(rope.cross(poly_points[i-1]-from))
				#var next: int = sign(rope.cross(poly_points[wrap(i+1,0,poly_points.size()-1)]-from))
				#if prev == side and next == side:
					#mid = i
					#break
			
			#while high > low:
				#mid = low + (high - low) / 2
				#var rope: Vector2 = (poly_points[mid] - from)
				#debug_vector(poly_points[mid],from)
				#var prev: int = sign(rope.cross(poly_points[mid-1]-from))
				#var next: int = sign(rope.cross(poly_points[mid+1]-from))
				#if prev == side and next == side:
					#break
				#elif next != side:
					#low = mid + 1
				#elif prev != side:
					#high = mid - 1
			
			#result.position = poly_points[mid]
			#result.size = (result.position - from).orthogonal() * side
			#debug_vector(result.position, result.position + result.size * 1.5)
		_:
			print("shape type: ",shape_type , " not handled")
	
	return result

func calc_normal(line_pos:float,collision_position:Vector2,index:int, col_object: WrappedObject)->Vector2:
	var object: WrappedObject = wrapped_objects[index]
	var prev_object: WrappedObject = wrapped_objects[index - 1]
	var rope_orthogonal: Vector2 = (prev_object.point2 - object.point1).orthogonal().normalized()
	#rope velocity
	var point1_delta: Vector2 = prev_object.point2 - prev_object.prev_point2
	var point2_delta: Vector2 = object.point1 - object.prev_point1
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
		var vector_to_center: Vector2 = col_object.get_global_transform().origin - prev_object.point2
		normal = rope_orthogonal * sign(rope_orthogonal.dot(vector_to_center))
		return normal
	else:
		return normal

func _draw() -> void:
	draw_set_transform_matrix(self.global_transform.inverse())
	draw_polyline(global_points,Color.DARK_RED,1,true)
	for point: Vector2 in global_points:
		draw_circle(point,1,Color.WEB_GREEN,true)
	for vector in debug_vectors:
		draw_line(vector.position,vector.size,Color.WEB_PURPLE)
	debug_vectors.clear()
	

func calc_global_points()->void:
	global_points.clear()
	global_points.append(wrapped_objects[0].point2)
	for i:int in range(1,wrapped_objects.size()-1):
		global_points.append(wrapped_objects[i].point1)
		global_points.append(wrapped_objects[i].point2)
	global_points.append(wrapped_objects[-1].point1)

func debug_vector(from:Vector2,to:Vector2)->void:
	debug_vectors.append(Rect2(from,to))
