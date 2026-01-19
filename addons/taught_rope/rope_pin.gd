class_name RopePin
extends Marker2D


@export var enabled: bool = false:
	set(value):
		enabled = value
		if value:
			_register()
		else:
			_deregister()

@export var rope: SoftRope
@export_range(0,1) var rope_position: float = 1
@export var apply_rotation: bool = true
@export var can_slide: bool = false

func _ready() -> void:
	if enabled:
		_register()
	else:
		_deregister()

func _register()->void:
	if rope != null:
		rope.pins.append(self)

func _deregister()->void:
	if rope != null:
		rope.pins.erase(self)
