extends Node2D

@export var soft_rope: SoftRope

func _process(delta: float) -> void:
	$RopeHandle.position = $Camera2D.get_global_mouse_position()
	var direction: Vector2 = Vector2.ZERO
	if Input.is_key_pressed(KEY_UP):
		direction.y -= 1
	if Input.is_key_pressed(KEY_DOWN):
		direction.y += 1
	if Input.is_key_pressed(KEY_LEFT):
		direction.x -= 1
	if Input.is_key_pressed(KEY_RIGHT):
		direction.x += 1
	
		#soft_rope.target_rope_length += 100
	#soft_rope.start_point += direction.normalized() * 100 * delta

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed:
			if event.keycode == KEY_1:
				soft_rope.target_rope_length += 50
			if event.keycode == KEY_2:
				soft_rope.target_rope_length -= 50
			if event.keycode == KEY_3:
				soft_rope.target_segment_length += 5
			if event.keycode == KEY_4:
				soft_rope.target_segment_length -= 5
			if event.keycode == KEY_SPACE:
				soft_rope.edit_start = not soft_rope.edit_start
