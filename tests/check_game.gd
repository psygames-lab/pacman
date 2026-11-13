extends SceneTree

const Game = preload("res://game.gd")
const AI = preload("res://ghost_ai.gd")
const Maze = preload("res://maze.gd")
var failures: Array[String] = []
var game: Game

func check(ok: bool, note: String) -> void:
	if not ok:
		failures.append(note)
		printerr("FAIL ", note)

func press(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	game._unhandled_key_input(event)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	game = preload("res://game.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	var p := Vector2i(10, 10)
	var red := Vector2i(3, 8)
	check(AI.chase_target(0, red, p, Vector2i.UP, red) == p, "Blinky targets player")
	check(AI.chase_target(1, red, p, Vector2i.RIGHT, red) == Vector2i(14, 10), "Pinky looks ahead")
	check(AI.chase_target(1, red, p, Vector2i.UP, red) == Vector2i(6, 6), "Pinky up-left offset")
	check(AI.chase_target(2, red, p, Vector2i.UP, red) == Vector2i(13, 8), "Inky up-left pivot")
	check(AI.chase_target(2, red, p, Vector2i.RIGHT, red) == Vector2i(21, 12), "Inky reflects Blinky")
	check(AI.chase_target(2, red, p, Vector2i.RIGHT, red + Vector2i.RIGHT) == Vector2i(20, 12), "Moving Blinky changes Inky target")
	check(AI.chase_target(3, Vector2i(2, 10), p, Vector2i.LEFT, red) == p, "Clyde chases at eight")
	check(AI.chase_target(3, Vector2i(5, 5), p, Vector2i.LEFT, red) == AI.CORNERS[3], "Clyde uses Euclidean distance")
	check(AI.turn(Vector2i(6, 5), Vector2i.LEFT, Vector2i(5, 4), false) == Vector2i.UP, "equal distance uses arcade priority")
	check(AI.turn(Vector2i(6, 5), Vector2i.LEFT, Vector2i(7, 5), false) != Vector2i.RIGHT, "no voluntary U-turn")
	check(game.dots.size() == 244 and game.dots.values().count(true) == 4, "240 pellets and four energizers")
	for tile in game.dots:
		check(game.home_distance.has(tile), "reachable pellet " + str(tile))
	for row: String in Maze.ROWS:
		check(row.length() == Maze.WIDTH, "maze row width")
	press(KEY_LEFT)
	for i in 28:
		game._physics_process(1.0 / 60)
	check(game.phase == Game.Phase.PLAY and game.score > 0, "opening move scores")
	press(KEY_P)
	var before := game.player.point()
	game._physics_process(0.25)
	check(game.paused and game.player.point() == before, "pause freezes movement")
	press(KEY_P)
	game.player = Game.Actor.new(Vector2i(0, 14))
	game.queued = Vector2i.LEFT
	game.advance(game.player, -1, 1)
	check(game.player.tile == Vector2i(27, 14), "left tunnel wraps")
	game.queued = Vector2i.RIGHT
	game.advance(game.player, -1, 1)
	check(game.player.tile == Vector2i(0, 14), "right tunnel wraps")
	game.player = Game.Actor.new(Vector2i(1, 3))
	var initial_direction := game.ghosts[0].direction
	game.eat_dot()
	check(game.ghosts[0].direction == -initial_direction, "power reverses roaming ghost")
	var timer := game.wave_left
	game.update_modes(0.5)
	check(game.wave_left == timer and game.ghosts[0].scared, "power suspends wave timer")
	var score_before := game.score
	var ghost := game.ghosts[0]
	ghost.tile = game.player.tile
	ghost.dest = ghost.tile
	ghost.progress = 0
	game.collide(ghost)
	check(game.score == score_before + 200 and ghost.state == Game.GhostState.EYES, "capture awards points")
	for i in 120:
		game.advance(ghost, 0, 1)
		if ghost.state == Game.GhostState.ROAM:
			break
	check(ghost.state == Game.GhostState.ROAM and not ghost.scared and ghost.tile == Maze.DOOR + Vector2i.LEFT, "eyes return and re-emerge")
	game.update_modes(10)
	game.update_modes(7)
	check(game.wave == 1 and not game.ghosts[1].scared, "chase resumes after power")
	# At the same four-way junction, the red, pink and cyan ghosts take
	# three different exits. The nearby orange ghost retreats to the left.
	game.player = Game.Actor.new(Vector2i(8, 5))
	game.player.direction = Vector2i.LEFT
	var expected := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.LEFT]
	for i in 4:
		game.ghosts[i] = Game.Actor.new(Vector2i(6, 5))
		game.ghosts[i].direction = Vector2i.UP
		check(game.ghost_step(game.ghosts[i], i) == expected[i], "junction exit for ghost " + str(i))
	var remaining := game.dots.size()
	for i in 3:
		game.phase = Game.Phase.PLAY
		game.player = Game.Actor.new(game.ghosts[0].tile)
		game.collide(game.ghosts[0])
		game._physics_process(1.1)
		check(game.lives == 2 - i and game.dots.size() == remaining, "life loss preserves dots")
	check(game.phase == Game.Phase.OVER, "game over on third loss")
	press(KEY_ENTER)
	check(game.phase == Game.Phase.READY and game.score == 0 and game.dots.size() == 244 and game.lives == 3, "restart resets game")
	game.phase = Game.Phase.PLAY
	game.player = Game.Actor.new(Vector2i(1, 1))
	game.dots = {game.player.tile: false}
	game.eat_dot()
	check(game.phase == Game.Phase.CLEAR, "last pellet clears level")
	game._physics_process(1.4)
	check(game.level == 2 and game.dots.size() == 244 and game.score == 10, "next level preserves score")
	if failures.is_empty():
		print("PASS: ghost targeting, routing, maze, movement, power, lives and level cycle")
	game.sound.stop()
	game.queue_free()
	await create_timer(0.25).timeout
	quit(0 if failures.is_empty() else 1)
