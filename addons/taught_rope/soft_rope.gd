class_name SoftRope
extends Node2D


@export var rope_length: float = 100
@export var segments: int = 10
@export var itterations: int = 10

@export_group('Physics')
@export_flags_2d_physics var collision_mask: int = 1
@export_range(-10,10,0.5,'or_greater',"or_less") var gravity_scale: float = 1.0

@export_subgroup('Friction')
@export var damping: float = 1
@export_range(0,1,0.01) var k_fp: float = 0.5
@export var k_fc: float = 0.5

@export_subgroup('Bending')
@export_range(0,1,0.01) var bending_stiffness: float = 0.5
@export var free_bending_radius: float = 50

@export_subgroup('Collisions')
@export var collision_itterations: int = 1
@export var resolve_collisions_while_constraining: bool = false

@export_group('Rendering')
@export var draw_rope: bool = true
@export var rope_width: float = 2
@export var rope_color: Color = Color.SADDLE_BROWN
@export var draw_nodes: bool = false
@export var node_radius: float = 1
@export var node_color: Color = Color.ORANGE

var _gravity: Vector2

var _segment_length: float 

var start_point: Vector2 = Vector2.ZERO

var _prev_positions: Array[Vector2]
var positions: Array[Vector2]
var velocities: Array[Vector2]
var collision_normals: Array[Vector2]

var space: PhysicsDirectSpaceState2D
var node_query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()

func _ready() -> void:
	space = get_world_2d().direct_space_state
	positions.resize(segments+1)
	_prev_positions.resize(segments+1)
	velocities.resize(segments+1)
	velocities.fill(Vector2.ZERO)
	collision_normals.resize(segments + 1)
	collision_normals.fill(Vector2.ZERO)
	_gravity = gravity_scale * ProjectSettings.get_setting('physics/2d/default_gravity_vector') * ProjectSettings.get_setting('physics/2d/default_gravity')
	_segment_length = rope_length/segments
	for i:int in range(positions.size()):
		positions[i] = Vector2(0,i * _segment_length)
	_prev_positions = positions.duplicate(true)
	
	node_query.collision_mask = collision_mask
	var circle = CircleShape2D.new()
	circle.radius = rope_width/2
	node_query.shape = circle
	

func _physics_process(delta: float) -> void:
	
	simulate(delta)
	var col_period: int
	if resolve_collisions_while_constraining:
		col_period = 1
	else:
		col_period = round(itterations / collision_itterations)
	
	for i:int in range(itterations):
		#points being keyframed should be set here
		positions[0] = start_point
		constrain()
		resolve_bending()
		if (i + 1) % col_period == 0:
			resolve_collisions()
	
	
	calc_velocities()
	collision_normals.fill(Vector2.ZERO)
	
	queue_redraw()

func simulate(delta:float)->void:
	for i:int in range(positions.size()):
		velocities[i] += _gravity * delta
		velocities[i] *= max(1-damping*delta,0)
		positions[i] = positions[i] + velocities[i] * delta

func constrain() ->void:
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
	

func resolve_bending()->void:
	if not bending_stiffness == 0:
		# ef describes the distance from the i to the midpoint between i-1 and i+1 when they are respectively equistance from i
		# in the condition that the segments lie on a circle of radius free_bending_radius
		# e2/2 + e1 describes this same distance for any placement of the three points
		var ef: float = (_segment_length ** 2) / 2 / free_bending_radius
		for i:int in range(1,positions.size()-1):
			var span: Vector2 = positions[i+1] - positions[i-1]
			var norm: Vector2 = (positions[i] - (positions[i-1] + span/2)).normalized()
			#var s: float = abs(norm.orthogonal().dot(span))
			var segment: Vector2 = positions[i] - positions[i-1]
			var e1: float = abs(segment.dot(norm))
			var e2: float = abs(span.dot(norm))
			#max displacement of middle point from span before free bending angle is breached
			var h: float = (1.0/3.0) * max((e2/2 + e1) - ef,0) * bending_stiffness
			if not h == 0:
				positions[i-1] += norm * h
				positions[i] += - norm * 2 * h
				positions[i+1] += norm * h

func resolve_collisions()->void:
	for i:int in range(positions.size()):
		#having no motion currently means the impact absorbs all energy
		#I can't really work out how this paramater is supposed to be used correctly
		#node_query.motion = (positions[i] - _prev_positions[i])
		node_query.transform = Transform2D(0,positions[i])
		var result: Dictionary = space.get_rest_info(node_query)
		if result != {}:
			positions[i] = result.point + result.normal * (rope_width / 2 + 0.01)
			collision_normals[i] = result.normal

func calc_velocities()->void:
	for i:int in range(positions.size()):
		velocities[i] = (positions[i] - _prev_positions[i]) / self.get_physics_process_delta_time()
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
