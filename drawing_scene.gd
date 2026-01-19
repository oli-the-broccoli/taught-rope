extends Node2D

var positions: Array[Vector2]
var points: Array[Point]

class Point:
	var color: Color
	var position: Vector2
	
	func _init(_position: Vector2, _color: Color = Color.GREEN) -> void:
		color = _color
		position = _position

func add_point(pos:Vector2, col:Color = Color.DARK_RED)->void:
	points.append(Point.new(pos,col))

func _ready() -> void:
	positions.append(Vector2(-100,0))
	positions.append(Vector2(0,-0.0001))
	positions.append(Vector2(100,0))
	
	var span: Vector2 = positions[2] - positions[0]
	var norm: Vector2 = (positions[1] - (positions[0] + span/2)).normalized()
	var segment: Vector2 = positions[1] - positions[0]
	var e1: float = abs(segment.dot(norm))
	var e2: float = abs(span.dot(norm))
	#max displacement of middle point from span before free bending angle is breached
	#var ef: float = _segment_length * cos((PI - free_bending_angle * _segment_length)/2)
	print(e2/2 + e1)
	var h: float = (1.0/3.0) * (e2/2 + e1)
	add_point(positions[0] + norm * h,Color.GREEN)
	add_point(positions[1] - norm * 2 * h,Color.YELLOW)
	add_point(positions[2] + norm * h)


func _draw() -> void:
	for pos: Vector2 in positions:
		draw_circle(pos,3,Color.BLUE)
	for point: Point in points:
		draw_circle(point.position,3,point.color)
