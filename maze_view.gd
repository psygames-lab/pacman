extends Node2D

const Maze = preload("res://maze.gd")
const CELL = 20
const INSET = 4.5
const EDGE = Color("#4869ff")
const FILL = Color("#141e55")

func wall(x: int, y: int) -> bool:
	return Rect2i(0, 0, Maze.WIDTH, Maze.HEIGHT).has_point(Vector2i(x, y)) and Maze.ROWS[y][x] == "#"

func _draw() -> void:
	# Inset the wall boundary into the solid tiles. Each quadrant joins its
	# neighbors, including the inside corner where only the diagonal is open.
	for y in Maze.HEIGHT:
		for x in Maze.WIDTH:
			if not wall(x, y):
				continue
			for dx in [-1, 1]:
				for dy in [-1, 1]:
					var open_x := not wall(x + dx, y)
					var open_y := not wall(x, y + dy)
					var half := CELL * 0.5
					var w := half - INSET if open_x else half
					var h := half - INSET if open_y else half
					var bevel := 2.5 if open_x and open_y else 0.0
					if not open_x and not open_y and not wall(x + dx, y + dy):
						bevel = INSET
					var side := Vector2(w, 0)
					var top := Vector2(0, h)
					var a := Vector2(w, h - bevel)
					var b := Vector2(w - bevel, h)
					var points := PackedVector2Array([Vector2.ZERO, side, a])
					if bevel > 0:
						points.append(b)
					points.append(top)
					draw_set_transform((Vector2(x, y) + Vector2(0.5, 0.5)) * CELL, 0, Vector2(dx, dy))
					draw_colored_polygon(points, FILL)
					if open_x:
						draw_line(side, a, EDGE, 1.6, true)
					if bevel > 0:
						draw_line(a, b, EDGE, 1.6, true)
					if open_y:
						draw_line(b, top, EDGE, 1.6, true)
	draw_set_transform(Vector2.ZERO)
	draw_line(Vector2(13 * CELL - INSET, 12.5 * CELL), Vector2(15 * CELL + INSET, 12.5 * CELL), Color("#ffacda"), 3)
