extends Node2D

const Maze = preload("res://maze.gd")
const CELL = 20
const EDGE = Color("#4869ff")
const FILL = Color("#141e55")

func wall(x: int, y: int) -> bool:
	return Rect2i(0, 0, Maze.WIDTH, Maze.HEIGHT).has_point(Vector2i(x, y)) and Maze.ROWS[y][x] == "#"

func _draw() -> void:
	# Clip the exposed corners of each wall tile. Internal seams are left open.
	for y in Maze.HEIGHT:
		for x in Maze.WIDTH:
			if not wall(x, y):
				continue
			var exposed := [not wall(x, y - 1), not wall(x + 1, y), not wall(x, y + 1), not wall(x - 1, y)]
			var origin := Vector2(x, y) * CELL
			var corners := [origin, origin + Vector2(CELL, 0), origin + Vector2(CELL, CELL), origin + Vector2(0, CELL)]
			var outline := PackedVector2Array()
			for i in 4:
				var corner: Vector2 = corners[i]
				var previous: Vector2 = corners[(i + 3) % 4]
				var after: Vector2 = corners[(i + 1) % 4]
				var bevel := 4.0 if exposed[i] and exposed[(i + 3) % 4] else 0.0
				outline.append(corner.move_toward(previous, bevel))
				outline.append(corner.move_toward(after, bevel))
			var polygon := PackedVector2Array()
			for point in outline:
				if polygon.is_empty() or polygon[-1] != point:
					polygon.append(point)
			draw_colored_polygon(polygon, FILL)
			for i in 4:
				if outline[2*i] != outline[2*i+1]:
					draw_line(outline[2*i], outline[2*i+1], EDGE, 1.6, true)
				if exposed[i]:
					draw_line(outline[2*i+1], outline[(2*i+2) % 8], EDGE, 1.6, true)
	draw_line(Vector2(13, 12.5) * CELL, Vector2(15, 12.5) * CELL, Color("#ffacda"), 3)
