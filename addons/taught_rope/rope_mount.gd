class_name RopeMount
extends Marker2D

@export var rope: SoftRope
@export_range(0,1) var rope_position: float
@export var apply_rotation: bool = true

func _physics_process(delta: float) -> void:
	var pos = (rope.num_nodes - 1) * rope_position
	var i = int(pos)
	var direction: Vector2
	if i == rope.num_nodes - 1:
		direction = rope.positions[i] - rope.positions[i-1]
		self.position = rope.positions[i]
	else:
		var k = pos - i
		direction = rope.positions[i+1] - rope.positions[i]
		self.position = rope.positions[i].lerp(rope.positions[i+1],k)
	if apply_rotation:
		self.rotation = direction.orthogonal().angle()
	
