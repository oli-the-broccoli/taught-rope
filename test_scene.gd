extends Node2D

@export var rope: TautRope
@export var rope_speed: float = 100

func _process(delta: float) -> void:
	var direction: Vector2 = Vector2.ZERO
	if Input.is_key_pressed(KEY_UP):
		direction.y -= 1
	if Input.is_key_pressed(KEY_DOWN):
		direction.y += 1
	if Input.is_key_pressed(KEY_LEFT):
		direction.x -= 1
	if Input.is_key_pressed(KEY_RIGHT):
		direction.x += 1
	
	rope.rope_start += direction.normalized() * rope_speed * delta
	rope.rope_end = $Camera2D.get_global_mouse_position()
