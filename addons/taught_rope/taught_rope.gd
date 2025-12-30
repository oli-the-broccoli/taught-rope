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
	var array_index:int
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
	var tangent1: Vector2
	var tangent2: Vector2
	var normal1: Vector2
	var normal2: Vector2
	var half_turn: int = 0
	var prev_direction: int
	var wrap_angle: float = 0
	var direction: int
	
	## calcs wrap angle and returns true if the object should be released
	func calc_wrap_angle()->bool:
		var half_turns: int = floor(abs(wrap_angle/PI)) * direction
		var is_full_turn: bool = (half_turns % 2) == 0
		var norm_angle: float = normal1.angle_to(normal2)
		print(half_turns)
		if half_turns == 0 and abs(norm_angle) < PI/2:
			
			if sign(wrap_angle) != sign(norm_angle):
				print('removing')
				return true
		wrap_angle = snappedi(half_turns,2) * PI
		if is_full_turn:
			wrap_angle += norm_angle
		else:
			wrap_angle += (TAU - abs(norm_angle)) * - direction
		print(wrap_angle)
		return false
	
	func get_norm_angle()->float:
		return normal1.angle_to(normal2)
	
	func get_global_transform()->Transform2D:
		return collider.global_transform * PhysicsServer2D.body_get_shape_transform(rid,shape)

func _ready() -> void:
	space = get_world_2d().direct_space_state
	rope_start = self.global_position
	rope_end = self.global_position
	wrapped_objects.append(WrappedObject.new())
	wrapped_objects[0].tangent2 = rope_start
	global_points.append(rope_start)
	wrapped_objects.append(WrappedObject.new())
	wrapped_objects[-1].tangent1 = rope_end
	global_points.append(rope_end)
	
	
	#if CCD_group != null:
		#get_tree().get_nodes_in_group(CCD_group)
	


#func _notification(what: int) -> void:
	#match what:
		#NOTIFICATION_TRANSFORM_CHANGED:
			#draw_set_transform_matrix(self.global_transform.inverse())

func _physics_process(delta: float) -> void:
	global_points[0] = rope_start
	global_points[-1] = rope_end
	if detection_type == DetectionType.RAYCAST:
		

		var curr_object: WrappedObject = wrapped_objects[0]
		#var next_object: WrappedObject = wrapped_objects[1]
		for i:int in range(1,wrapped_objects.size() - 1):
			var point_i = i * 2 - 1
			#var prev_object: WrappedObject = curr_object
			curr_object = wrapped_objects[i]
			#next_object = wrapped_objects[i+1]
			
			var point: Rect2 = calc_tangent(curr_object,global_points[point_i-1],curr_object.normal1)
			global_points[point_i] = point.position
			curr_object.normal1 = point.size
			point = calc_tangent(curr_object,global_points[point_i+2],curr_object.normal2)
			global_points[point_i+1] = point.position
			curr_object.normal2 = point.size
			if curr_object.calc_wrap_angle() == true:
				# release object
				unwrap_queue.append(curr_object)
				
			
			
			
			#prev_object = curr_object
			#curr_object = next_object
		
		for i:int in range(0,unwrap_queue.size(),-1):
			var object: WrappedObject = unwrap_queue[i]
			var point_i: int = 2 * object.array_index - 1
			global_points.remove_at(point_i)
			global_points.remove_at(point_i + 1)
			wrapped_objects.remove_at(object.array_index)
			object.free()
		
		for i:int in range(1, wrapped_objects.size()):
			var point_i = i * 2 - 1
			#cast ray back to previous object
			var new_object: WrappedObject = cast_ray(global_points[point_i],global_points[point_i - 1],[wrapped_objects[i-1].rid])
			if new_object != null:
				var normal: Vector2 = calc_normal(point_i - 1,new_object,delta)
				var point: Rect2 = calc_tangent(new_object,global_points[point_i - 1],normal)
				global_points.insert(point_i,point.position)
				new_object.normal1 = point.size
				point = calc_tangent(new_object,global_points[point_i],normal)
				global_points.insert(point_i+1,point.position)
				new_object.normal2 = point.size
				var init_wrap_angle: float = new_object.normal1.angle_to(normal)
				init_wrap_angle += normal.angle_to(new_object.normal2)
				new_object.wrap_angle = init_wrap_angle
				new_object.direction = sign(init_wrap_angle)
				new_object.array_index = i
				wrapped_objects.insert(i,new_object)
	
	#calc_global_points()
	prev_global_points = global_points.duplicate()
	queue_redraw()

func cast_ray(A:Vector2,B:Vector2,exclude:Array[RID]) -> WrappedObject:
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(A,B,collision_mask)
	query.exclude = exclude
	var result: Dictionary = space.intersect_ray(query)
	if result == {}:
		return null
	else:
		var new_object: WrappedObject = WrappedObject.new()
		new_object.collider = result.collider
		new_object.shape = result.shape
		return new_object

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
			var angle: float = acos(radius/from_center.length()) * sign(from_center.angle_to(normal))
			result.size = from_center.normalized().rotated(angle)
			result.position = center + result.size * radius
		PhysicsServer2D.ShapeType.SHAPE_CAPSULE:
			pass
		PhysicsServer2D.ShapeType.SHAPE_RECTANGLE:
			pass
		PhysicsServer2D.ShapeType.SHAPE_CONCAVE_POLYGON:
			pass
		_:
			print("shape type not handled")
	
	return result

func calc_normal(index:int,object:WrappedObject,time_delta:float)->Vector2:
	#all movement relative to 1st point
	#line normal
	var delta1: Vector2 = global_points[index] - prev_global_points[index]
	var delta2: Vector2 = global_points[index+1] - prev_global_points[index+1] - delta1
	var line_orthogonal: Vector2 = (global_points[index] - global_points[index+1]).orthogonal()
	var line_normal: Vector2 = line_orthogonal * - sign(line_orthogonal.dot(delta2))
	#object normal
	var object_normal: Vector2 = Vector2.ZERO
	if object.collider in CCD_shapes:
		#can get previous position
		pass
	elif object.collider is RigidBody2D:
		object_normal = object.collider.linear_velocity * time_delta - delta1
	elif object.collider is CharacterBody2D:
		object_normal = object.collider.get_real_velocity() * time_delta - delta1
	debug_vector(object.collider.global_position,object.collider.global_position + object_normal * 100)
	var normal: Vector2 = (object_normal + line_normal).normalized()
	if normal.is_zero_approx():
		var vector_to_center: Vector2 = object.get_global_transform().origin - global_points[index]
		normal = line_orthogonal.normalized() * sign(line_orthogonal.dot(vector_to_center))
		return normal
	else:
		return normal

func _draw() -> void:
	draw_set_transform_matrix(self.global_transform.inverse())
	draw_polyline(global_points,Color.DARK_RED,2,true)
	for point: Vector2 in global_points:
		draw_circle(point,1,Color.WEB_GREEN,true)
	for vector in debug_vectors:
		draw_line(vector.position,vector.size,Color.WEB_PURPLE)

func calc_global_points()->void:
	global_points.clear()
	global_points.append(wrapped_objects[0].tangent2)
	for i:int in range(wrapped_objects.size()-1):
		global_points.append(wrapped_objects[i].tangent1)
		global_points.append(wrapped_objects[i].tangent2)
	global_points.append(wrapped_objects[-1].tangent1)

func debug_vector(from:Vector2,to:Vector2)->void:
	debug_vectors.append(Rect2(from,to))
