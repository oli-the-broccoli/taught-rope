class_name RopePin
extends Node

@export var enabled: bool = true:
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

func _register()->void:
	pass

func _deregister()->void:
	pass
