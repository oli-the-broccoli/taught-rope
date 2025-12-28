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
var prev_global_points: Array[Vector2]
var global_points: Array[Vector2]
var local_points: Array[Vector2]

var space: PhysicsDirectSpaceState2D

var CCD_shapes: Array[RID]

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
	var tangent1: Vector2
	var tangent2: Vector2
	var normal1: Vector2
	var normal2: Vector2
	var turns: int = 0
	
	func get_global_transform()->Transform2D:
		return collider.global_transform * PhysicsServer2D.body_get_shape_transform(rid,shape)

func _ready() -> void:
	space = get_world_2d().direct_space_state
	rope_start = self.global_position
	wrapped_objects.append(WrappedObject.new())
	wrapped_objects[0].tangent2 = rope_start
	global_points.append(rope_start)
	wrapped_objects.append(WrappedObject.new())
	wrapped_objects[-1].tangent1 = rope_end
	global_points.append(rope_end)
	
	draw_set_transform_matrix(self.global_transform.inverse())
	#if CCD_group != null:
		#get_tree().get_nodes_in_group(CCD_group)
	


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_TRANSFORM_CHANGED:
			draw_set_transform_matrix(self.global_transform.inverse())

func _physics_process(delta: float) -> void:
	global_points[0] = rope_start
	global_points[-1] = rope_end
	if detection_type == DetectionType.RAYCAST:
		

		var curr_object: WrappedObject = wrapped_objects[0]
		#var next_object: WrappedObject = wrapped_objects[1]
		for i:int in range(1,wrapped_objects.size() - 1):
			#var prev_object: WrappedObject = curr_object
			curr_object = wrapped_objects[i]
			#next_object = wrapped_objects[i+1]
			
			var point: Rect2 = calc_tangent(curr_object,global_points[i-1],curr_object.normal1)
			global_points[i] = point.position
			curr_object.normal1 = point.size
			point = calc_tangent(curr_object,global_points[i+1],curr_object.normal2)
			global_points[i+1] = point.position
			curr_object.normal2 = point.size
			
			#prev_object = curr_object
			#curr_object = next_object
		
		for i:int in range(wrapped_objects.size() - 1):
			var new_object: WrappedObject = cast_ray(wrapped_objects[i].tangent2,wrapped_objects[i+1].tangent2,[wrapped_objects[i+1].rid])
			if new_object != null:
				var normal: Vector2 = calc_normal(i,new_object,delta)
				var point: Rect2 = calc_tangent(new_object,global_points[i-1],normal)
				global_points.insert(i+1,point.position)
				new_object.normal1 = point.size
				point = calc_tangent(curr_object,global_points[i+1],normal)
				global_points.insert(i+2,point.position)
				new_object.normal2 = point.size
				wrapped_objects.insert(i+1,new_object)
	
	calc_global_points()
	prev_global_points = global_points

func cast_ray(A:Vector2,B:Vector2,exclude:Array[RID]) -> WrappedObject:
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(A,B,collision_mask)
	query.exclude = exclude
	var result: Dictionary = space.intersect_ray(query)
	if result == null:
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
	
	print("shape type not handled")
	return result

func calc_normal(index:int,object:WrappedObject,time_delta:float)->Vector2:
	#all movement relative to 1st point
	#line normal
	var delta1: Vector2 = global_points[index] - prev_global_points[index]
	var delta2: Vector2 = global_points[index+1] - prev_global_points[index+1] - delta1
	var line_orthogonal: Vector2 = (global_points[index] - global_points[index+1]).orthogonal()
	var line_normal: Vector2 = line_orthogonal * sign(line_orthogonal.dot(delta2))
	#object normal
	var object_normal: Vector2 = Vector2.ZERO
	if object.collider in CCD_shapes:
		#can get previous position
		pass
	elif object.collider is RigidBody2D:
		object_normal = object.linear_velocity * time_delta - delta1
	elif object.collider is CharacterBody2D:
		object_normal = object.get_real_velocity() * time_delta - delta1
	
	var normal: Vector2 = (object_normal + line_normal).normalized()
	if normal.is_zero_approx():
		var vector_to_center: Vector2 = object.get_global_transform().origin - global_points[index]
		normal = line_orthogonal.normalized() * sign(line_orthogonal.dot(vector_to_center))
		return normal
	else:
		return normal

func _draw() -> void:
	draw_polyline(global_points,Color.DARK_RED,2,true)
	for point: Vector2 in global_points:
		draw_circle(point,2,Color.WEB_GREEN,true)

func calc_global_points()->void:
	global_points.clear()
	global_points[0] = wrapped_objects[0].tangent2
	for i:int in range(wrapped_objects.size()-1):
		global_points.append(wrapped_objects[i].tangent1)
		global_points.append(wrapped_objects[i].tangent2)
	global_points.append(wrapped_objects[-1].tangent1)
