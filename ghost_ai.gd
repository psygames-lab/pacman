extends RefCounted

const Maze = preload("res://maze.gd")
enum Kind { BLINKY, PINKY, INKY, CLYDE }
const CORNERS = [Vector2i(25, -3), Vector2i(2, -3), Vector2i(27, 32), Vector2i(0, 32)]

static func chase_target(kind: int, tile: Vector2i, player: Vector2i, facing: Vector2i, blinky: Vector2i) -> Vector2i:
	# The arcade's upward look-ahead also offsets left.
	var ahead := Vector2i(-1, -1) if facing == Vector2i.UP else facing
	match kind:
		Kind.PINKY:
			return player + 4 * ahead
		Kind.INKY:
			var pivot := player + 2 * ahead
			return 2 * pivot - blinky
		Kind.CLYDE:
			if tile.distance_squared_to(player) < 64:
				return CORNERS[Kind.CLYDE]
	return player

static func turn(tile: Vector2i, facing: Vector2i, target: Vector2i, frightened: bool) -> Vector2i:
	var choices: Array[Vector2i] = []
	for direction: Vector2i in Maze.ORDER:
		if direction == -facing or not Maze.walkable(Maze.next(tile, direction)):
			continue
		if not frightened and direction == Vector2i.UP and tile.y in [11, 23] and tile.x in [12, 15]:
			continue
		choices.append(direction)
	if choices.is_empty():
		return -facing
	if frightened:
		return choices.pick_random()
	var best := choices[0]
	for direction in choices:
		if (tile + direction).distance_squared_to(target) < (tile + best).distance_squared_to(target):
			best = direction
	return best
