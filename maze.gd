extends RefCounted

# X is exterior space. The pen and its gate are reserved for scripted movement.
const ROWS = [
	"############################",
	"#............##............#",
	"#.####.#####.##.#####.####.#",
	"#o####.#####.##.#####.####o#",
	"#.####.#####.##.#####.####.#",
	"#..........................#",
	"#.####.##.########.##.####.#",
	"#.####.##.########.##.####.#",
	"#......##....##....##......#",
	"######.##### ## #####.######",
	"XXXXX#.##### ## #####.#XXXXX",
	"XXXXX#.##          ##.#XXXXX",
	"XXXXX#.## ###--### ##.#XXXXX",
	"######.## #hhhhhh# ##.######",
	"      .   #hhhhhh#   .      ",
	"######.## #hhhhhh# ##.######",
	"XXXXX#.## ######## ##.#XXXXX",
	"XXXXX#.##          ##.#XXXXX",
	"XXXXX#.## ######## ##.#XXXXX",
	"######.## ######## ##.######",
	"#............##............#",
	"#.####.#####.##.#####.####.#",
	"#.####.#####.##.#####.####.#",
	"#o..##.......  .......##..o#",
	"###.##.##.########.##.##.###",
	"###.##.##.########.##.##.###",
	"#......##....##....##......#",
	"#.##########.##.##########.#",
	"#.##########.##.##########.#",
	"#..........................#",
	"############################",
]
const WIDTH = 28
const HEIGHT = 31
const DOOR = Vector2i(13, 11)
const HOME = Vector2i(13, 14)
const START = Vector2i(14, 23)
const ORDER = [Vector2i.UP, Vector2i.LEFT, Vector2i.DOWN, Vector2i.RIGHT]
var rows: Array

func _init(layout: Array = ROWS) -> void:
	rows = layout

static func next(tile: Vector2i, direction: Vector2i) -> Vector2i:
	var dest := tile + direction
	if dest.y == 14:
		dest.x = posmod(dest.x, WIDTH)
	return dest

func walkable(tile: Vector2i) -> bool:
	return Rect2i(0, 0, WIDTH, HEIGHT).has_point(tile) and rows[tile.y][tile.x] in [" ", ".", "o", "*"]

func collectibles() -> Dictionary:
	var dots := {}
	for y in HEIGHT:
		for x in WIDTH:
			if rows[y][x] in [".", "o"]:
				dots[Vector2i(x, y)] = rows[y][x] == "o"
	return dots
