class_name SoftRope
extends Node2D


@export var target_rope_length: float = 100:
	set(value):
		target_rope_length = max(value,0)
		_adjust_nodes()

@export var target_segment_length: float = 10:
	set(value):
		target_segment_length = max(value,0)
		_adjust_nodes()

@export var rope_width: float = 2:
	set(value):
		rope_width = value
		if collision_radius == 0:
			_collision_circle.radius = rope_width/2

@export var itterations: int = 10:
	set(value):
		itterations = value
		_normalised_bending_stiffness = bending_stiffness / value

@export var edit_start: bool = true

@export_group('Physics')
@export_range(-10,10,0.5,'or_greater',"or_less") var gravity_scale: float = 1.0

@export_subgroup('Friction')
@export var damping: float = 1
@export_range(0, 1, 0.01) var k_fp: float = 0.5
@export var k_fc: float = 0.5

@export_subgroup('Bending')
@export var bending_stiffness: float = 5:
	set(value):
		bending_stiffness = value
		_normalised_bending_stiffness = bending_stiffness / itterations
@export var free_bending_radius: float = 20

@export_subgroup('Collisions')
@export_flags_2d_physics var collision_mask: int = 1:
	set(value):
		collision_mask = value
		_node_query.collision_mask = value
@export var collision_itterations: int = 1
@export var resolve_collisions_while_constraining: bool = false
@export var collision_radius: float = 0:
	set(value):
		collision_radius = value
		if value == 0:
			_collision_circle.radius = rope_width/2
		else:
			_collision_circle.radius = collision_radius
		_node_query.shape = _collision_circle

@export_group('Rendering')
@export var draw_rope: bool = true
@export var rope_color: Color = Color.SADDLE_BROWN
@export var draw_nodes: bool = false
@export var node_radius: float = 1
@export var node_color: Color = Color.ORANGE



var num_nodes: int
var _segments: int
var _segment_length: float 

var _gravity: Vector2
var _normalised_bending_stiffness: float = bending_stiffness / itterations

var start_point: Vector2 = Vector2.ZERO

var _prev_positions: Array[Vector2]
var positions: Array[Vector2]
var velocities: Array[Vector2]
var collision_normals: Array[Vector2]

var _delta_nodes: int

var _space: PhysicsDirectSpaceState2D
var _collision_circle: CircleShape2D = CircleShape2D.new()
var _node_query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()

func _calc_segments()->void:
	_segments = max(round(target_rope_length / target_segment_length),1)
	_segment_length = target_rope_length / _segments
	num_nodes = _segments + 1

func _adjust_nodes()->void:
	_delta_nodes = max(round(target_rope_length / target_segment_length),1) - _segments

func _add_nodes(num: int = 1)->void:
	var index: int
	if edit_start:
		index = 0
	else:
		index = max(num_nodes - 2,0)
	for n:int in range(num):
		var k: float = (n + 1) / (num + 1)
		var next_i = min(index + n + 1, num_nodes)
		var pos: Vector2 = positions[index].lerp(positions[next_i],k)
		positions.insert(next_i, pos)
		_prev_positions.insert(next_i,pos)
		var vel: Vector2 = velocities[index].lerp(velocities[next_i],k)
		velocities.insert(next_i,vel)
		collision_normals.insert(next_i,Vector2.ZERO)

func _remove_nodes(num:int = 1)->void:
	num = min(num, num_nodes - 2)
	if edit_start:
		for n in range(num):
			positions.pop_front()
			_prev_positions.pop_front()
			velocities.pop_front()
			collision_normals.pop_front()
	else:
		for n in range(num):
			positions.pop_back()
			_prev_positions.pop_back()
			velocities.pop_back()
			collision_normals.pop_back()

func _ready() -> void:
	_space = get_world_2d().direct_space_state
	
	_delta_nodes = 0
	_calc_segments()
	positions.resize(num_nodes)
	_prev_positions.resize(num_nodes)
	velocities.resize(num_nodes)
	velocities.fill(Vector2.ZERO)
	collision_normals.resize(num_nodes)
	collision_normals.fill(Vector2.ZERO)
	
	_gravity = gravity_scale * ProjectSettings.get_setting('physics/2d/default_gravity_vector') * ProjectSettings.get_setting('physics/2d/default_gravity')
	
	for i:int in range(num_nodes):
		positions[i] = Vector2(0,i * _segment_length)
	_prev_positions = positions.duplicate(true)
	
	if collision_radius == 0:
		_collision_circle.radius = rope_width/2
	else:
		_collision_circle.radius = collision_radius
	_node_query.shape = _collision_circle



func _physics_process(delta: float) -> void:
	
	_simulate(delta)
	var col_period: int
	if resolve_collisions_while_constraining:
		col_period = 1
	else:
		col_period = round(itterations / collision_itterations)
	
	for i:int in range(itterations):
		#points being keyframed should be set here
		_constrain()
		_resolve_bending()
		if (i + 1) % col_period == 0:
			_resolve_collisions()
		
		positions[0] = start_point
	
	_calc_velocities()
	collision_normals.fill(Vector2.ZERO)
	
	#add/remove nodes
	
	if _delta_nodes != 0:
		if _delta_nodes > 0:	
			_add_nodes(_delta_nodes)
		elif _delta_nodes < 0:
			_remove_nodes(abs(_delta_nodes))
		_delta_nodes = 0
		_calc_segments()
	
	
	queue_redraw()

func _simulate(delta:float)->void:
	for i:int in range(positions.size()):
		velocities[i] += _gravity * delta
		velocities[i] *= max(1-damping*delta,0)
		positions[i] = positions[i] + velocities[i] * delta

func _constrain() ->void:
	#length constraint
	for i:int in range(1,positions.size()):
		var segment: Vector2 = (positions[i] - positions[i-1])
		var length: float = max(segment.length(),0.001) #too ensure not devidign by 0
		var move: Vector2 = segment/length * (length - _segment_length) * 0.5 #normalise and multiply by half the error
		if (i == 1):
			positions[i] -= move * 2
		else:
			positions[i] -= move
			positions[i-1] += move
	

func _resolve_bending()->void:
	if not bending_stiffness == 0:
		# ef describes the distance from the i to the midpoint between i-1 and i+1 when they are respectively equistance from i
		# in the condition that the segments lie on a circle of radius free_bending_radius
		# e2/2 + e1 describes this same distance for any placement of the three points
		var ef: float = (_segment_length ** 2) / 2 / free_bending_radius
		for i:int in range(1,positions.size()-1):
			var span: Vector2 = positions[i+1] - positions[i-1]
			var direction: Vector2 = (positions[i] - (positions[i-1] + span/2))
			if direction.length() > ef:
				var norm: Vector2 = direction.normalized()
				#var s: float = abs(norm.orthogonal().dot(span))
				var segment: Vector2 = positions[i] - positions[i-1]
				var e1: float = abs(segment.dot(norm))
				var e2: float = abs(span.dot(norm))
				var e: float = e2/2 + e1
				var h: float = (1.0/3.0) * e * _normalised_bending_stiffness
				positions[i-1] += norm * h
				positions[i] += - norm * 2 * h
				positions[i+1] += norm * h

func _resolve_collisions()->void:
	for i:int in range(positions.size()):
		#having no motion currently means the impact absorbs all energy
		#I can't really work out how this paramater is supposed to be used correctly
		#node_query.motion = (positions[i] - _prev_positions[i])
		_node_query.transform = Transform2D(0,positions[i])
		var result: Dictionary = _space.get_rest_info(_node_query)
		if result != {}:
			positions[i] = result.point + result.normal * (_collision_circle.radius + 0.01)
			collision_normals[i] = result.normal

func _calc_velocities()->void:
	for i:int in range(positions.size()):
		velocities[i] = (positions[i] - _prev_positions[i]) / self.get_physics_process_delta_time()
		
		#apply friction
		if not collision_normals[i].is_zero_approx():
			var v_norm: Vector2 = velocities[i].dot(collision_normals[i]) * collision_normals[i]
			var v_tan: Vector2 = velocities[i] - v_norm
			v_tan *= (1-k_fp)
			v_tan -= min(k_fc,v_tan.length()) * v_tan.normalized()
			velocities[i] = v_tan + v_norm
		
		_prev_positions[i] = positions[i]

func _draw() -> void:
	draw_set_transform_matrix(self.transform.inverse())
	
	if draw_rope:
		draw_polyline(positions,rope_color,rope_width,true)
	
	if draw_nodes:
		for point: Vector2 in positions:
			draw_circle(point,node_radius,node_color)
