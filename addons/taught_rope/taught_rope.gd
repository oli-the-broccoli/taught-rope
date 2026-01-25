class_name TaughtRope
extends Node2D

enum DetectionType{RAYCAST,SHAPECAST,AREA}

@export var detection_type: DetectionType = DetectionType.RAYCAST

@export_category('Physics')
@export_flags_2d_physics var collision_mask: int = 1
@export var CCD_group: StringName

var rope_start: Vector2 = Vector2.ZERO
var rope_end: Vector2
var wrapped_objects: Array[WrappedObject]
var unwrap_queue: Array[WrappedObject]
var prev_global_points: Array[Vector2]
var global_points: Array[Vector2]
var local_points: Array[Vector2]

var space: PhysicsDirectSpaceState2D

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
	var normal1: Vector2
	var normal2: Vector2
	# here using the dot product as its cheeper than calculating angles
	var prev_dot: float
	var prev_orth_dot: int
	var turns: int = 0
	var direction: int
	
	## calcs wrap angle and returns true if the object should be released
	func calc_turns()->void:
		#TODO could probably replace orth dot with a cross product to skip calculating orthogonal
		#orth dot describes which side of normal 1 does normal 2 lie, ie CC or CCW
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

class wrapped_poly extends WrappedObject:
	var points: Array[Vector2]

func _ready() -> void:
	space = get_world_2d().direct_space_state
	rope_start = self.global_position
	rope_end = self.global_position
	wrapped_objects.append(WrappedObject.new())
	global_points.append(rope_start)
	wrapped_objects.append(WrappedObject.new())
	global_points.append(rope_end)
	prev_global_points = global_points.duplicate()
	
	#if CCD_group != null:
		#get_tree().get_nodes_in_group(CCD_group)
	


#func _notification(what: int) -> void:
	#match what:
		#NOTIFICATION_TRANSFORM_CHANGED:
			#draw_set_transform_matrix(self.global_transform.inverse())

func _physics_process(delta: float) -> void:
	
	global_points[0] = rope_start
	global_points[-1] = rope_end

	var curr_object: WrappedObject = wrapped_objects[0]
	#var next_object: WrappedObject = wrapped_objects[1]
	for i:int in range(1,wrapped_objects.size() - 1):
		var point_i = i * 2 - 1
		#var prev_object: WrappedObject = curr_object
		curr_object = wrapped_objects[i]
		#next_object = wrapped_objects[i+1]
		
		#find next tangent points
		var point: Rect2 = calc_tangent(curr_object,global_points[point_i-1],curr_object.normal1)
		global_points[point_i] = point.position
		curr_object.normal1 = point.size
		point = calc_tangent(curr_object,global_points[point_i+2],curr_object.normal2)
		global_points[point_i+1] = point.position
		curr_object.normal2 = point.size
		
		curr_object.calc_turns()
		if curr_object.turns < 0:
			# release object
			unwrap_queue.append(curr_object)
			
		
	for object:WrappedObject in unwrap_queue:
		var object_i = wrapped_objects.find(object)
		var point_i: int = 2 * object_i - 1
		global_points.remove_at(point_i)
		global_points.remove_at(point_i)
		wrapped_objects.remove_at(object_i)
	unwrap_queue.clear()
	
	for i:int in range(1, wrapped_objects.size()):
		var point_i = i * 2 - 1
		#cast ray back to previous object
		var exclude: Array[RID] = [wrapped_objects[i-1].rid,wrapped_objects[i].rid]
		var collision_result: Dictionary = cast_ray(global_points[point_i],global_points[point_i - 1],exclude)
		if collision_result != {}:
			var new_object: WrappedObject = collision_result.object
			var normal: Vector2 = calc_normal(collision_result.line_pos, collision_result.position, point_i - 1, new_object)
			var point1: Rect2 = calc_tangent(new_object,global_points[point_i - 1],normal)
			var point2: Rect2 = calc_tangent(new_object,global_points[point_i],normal)
			new_object.prev_orth_dot = sign(point1.size.orthogonal().dot(point2.size))
			if new_object.prev_orth_dot == 0:
				#the normals point same direction so we cant determine the wrap direction
				#cancel creating the object, the next itteration should hopefully catch when the rope is deeper in the object
				#and a non zero angle between normals will be made
				print('abort')
				continue
			global_points.insert(point_i,point1.position)
			new_object.normal1 = point1.size
			global_points.insert(point_i+1,point2.position)
			new_object.normal2 = point2.size
			new_object.prev_dot = new_object.normal1.dot(new_object.normal2)
			#get the initial wrap direction +ve for CW and -ve for CCW
			new_object.direction = - new_object.prev_orth_dot
			wrapped_objects.insert(i,new_object)
	
	prev_global_points = global_points.duplicate()
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
		collision_result['line_pos'] = (A - result.position).length() / (A-B).length()
		collision_result['position'] = result.position
		return collision_result

## returns a rect2 with the size represnting the tangent normal
func calc_tangent(object:WrappedObject, from:Vector2, normal:Vector2)->Rect2:
	var shape_type = PhysicsServer2D.shape_get_type(object.shape_rid)
	# note that a rect is used to store a position and a normal (in the size)
	var result: Rect2 = Rect2(Vector2.ZERO,Vector2.ZERO)
	match shape_type:
		PhysicsServer2D.ShapeType.SHAPE_CIRCLE:
			var radius: float = PhysicsServer2D.shape_get_data(object.shape_rid)
			var center: Vector2 = object.get_global_transform().origin
			var from_center: Vector2 = (from - center)
			var angle: float = acos(radius/from_center.length()) * sign(from_center.cross(normal))
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
			var side: int = sign((from - inside).cross(normal))
			for i:int in range(poly_points.size()):
				var rope: Vector2 = (poly_points[i] - from)
				var prev: int = sign(rope.cross(poly_points[i-1]-from))
				var next: int = sign(rope.cross(poly_points[wrap(i+1,0,poly_points.size()-1)]-from))
				if prev == side and next == side:
					mid = i
					break
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
			result.position = poly_points[mid]
			result.size = (result.position - from).orthogonal() * side
			debug_vector(result.position, result.position + result.size * 1.5)
		_:
			print("shape type: ",shape_type , " not handled")
	
	return result

func calc_normal(line_pos:float,collision_position:Vector2,index:int,object:WrappedObject)->Vector2:
	var rope_orthogonal: Vector2 = (global_points[index] - global_points[index+1]).orthogonal().normalized()
	#rope velocity
	var point1_delta: Vector2 = global_points[index] - prev_global_points[index]
	var point2_delta: Vector2 = global_points[index+1] - prev_global_points[index+1]
	var rope_velocity: Vector2 = (line_pos * point2_delta + (1 - line_pos) * point1_delta) / get_physics_process_delta_time()
	
	#object point (of collision) velocity
	var point_velocity: Vector2 = Vector2.ZERO
	if object.collider in CCD_shapes:
		#can get previous position
		pass
	elif object.collider is RigidBody2D:
		point_velocity = object.collider.linear_velocity 
		point_velocity += object.collider.angular_velocity * (collision_position - object.collider.global_transform.origin).orthogonal()
	elif object.collider is CharacterBody2D:
		#cant get angular velocity
		point_velocity = object.collider.get_real_velocity()
	
	var normal: Vector2 = rope_orthogonal * rope_orthogonal.dot(point_velocity - rope_velocity)
	if normal.is_zero_approx():
		var vector_to_center: Vector2 = object.get_global_transform().origin - global_points[index]
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
	global_points.append(wrapped_objects[0].tangent2)
	for i:int in range(wrapped_objects.size()-1):
		global_points.append(wrapped_objects[i].tangent1)
		global_points.append(wrapped_objects[i].tangent2)
	global_points.append(wrapped_objects[-1].tangent1)

func debug_vector(from:Vector2,to:Vector2)->void:
	debug_vectors.append(Rect2(from,to))
