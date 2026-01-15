class_name SoftRope
extends Node2D


@export_flags_2d_physics var collision_mask: int
@export var gravity_scale: float = 1.0
var _gravity: Vector2
@export var damping: float = 1

@export var itterations: int = 10
@export var rope_length: float = 100
@export var segments: int = 10
var _segment_length: float 
@export var thickness: float = 2
@export var color: Color = Color.SADDLE_BROWN

var start_point: Vector2 = Vector2.ZERO

var _prev_positions: Array[Vector2]
var positions: Array[Vector2]
var velocities: Array[Vector2]

func _ready() -> void:
	positions.resize(segments+1)
	_prev_positions.resize(segments+1)
	velocities.resize(segments+1)
	velocities.fill(Vector2.ZERO)
	_gravity = gravity_scale * ProjectSettings.get_setting('physics/2d/default_gravity_vector') * ProjectSettings.get_setting('physics/2d/default_gravity')
	_segment_length = rope_length/segments
	for i:int in range(positions.size()):
		positions[i] = Vector2(0,i * _segment_length)
	_prev_positions = positions.duplicate(true)

func _physics_process(delta: float) -> void:
	positions[0] = start_point
	simulate(delta)
	for i:int in range(itterations):
		constrain()
	queue_redraw()

func simulate(delta:float)->void:
	for i:int in range(positions.size()):
		velocities[i] = (positions[i] - _prev_positions[i]) / delta
		#MUST update prev position before adjusting the current one (only needed it for calculating velocity)
		_prev_positions[i] = positions[i]
		velocities[i] += _gravity * delta
		velocities[i] *= max(1-damping*delta,0)
		positions[i] = positions[i] + velocities[i] * delta

func constrain() ->void:
	for i:int in range(1,positions.size()):
		var segment: Vector2 = (positions[i] - positions[i-1])
		var length: float = max(segment.length(),0.001) #too ensure not devidign by 0
		var move: Vector2 = segment/length * (length - _segment_length) * 0.5 #normalise and multiply by half the error
		if (i == 1):
			positions[i] -= move * 2
		else:
			positions[i] -= move
			positions[i-1] += move
	
	
func _draw() -> void:
	draw_set_transform_matrix(self.transform.inverse())
	draw_polyline(positions,color,thickness,true)
	for point: Vector2 in positions:
		draw_circle(point,1,Color.GREEN)
