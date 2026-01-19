@tool
extends EditorPlugin


func _enable_plugin() -> void:
	# Add autoloads here.
	pass


func _disable_plugin() -> void:
	# Remove autoloads here.
	pass


func _enter_tree() -> void:
	# Initialization of the plugin goes here.
	add_custom_type('TaughtRope','Node2D',preload("taught_rope.gd"),preload("icons/taut_rope.png"))
	add_custom_type('SoftRope','Node2D',preload("soft_rope.gd"),preload("icons/soft_rope.png"))
	add_custom_type('RopeMount','Marker2D',preload("rope_mount.gd"),preload("icons/rope_mount.png"))
	add_custom_type('RopePin','Marker2D',preload("rope_pin.gd"),preload("icons/rope_mount.png"))


func _exit_tree() -> void:
	# Clean-up of the plugin goes here.
	remove_custom_type('TaughtRope')
	remove_custom_type('SoftRope')
	remove_custom_type('RopeMount')
	remove_custom_type('RopePin')
