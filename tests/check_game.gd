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

func press(key: Key, down := true) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = down
	game._unhandled_key_input(event)

func _initialize() -> void:
	call_deferred("run")

# Drive the normal movement and collection code one full tile at a time.
func walk_to(goal: Vector2i) -> void:
	var start := game.player.tile
	var queue: Array[Vector2i] = [start]
	var route := {start: Vector2i.ZERO}
	var i := 0
	while i < queue.size() and not route.has(goal):
		var tile := queue[i]
		i += 1
		for d: Vector2i in Maze.ORDER:
			var dest := Maze.next(tile, d)
			if not route.has(dest) and game.maze.walkable(dest):
				route[dest] = d
				queue.append(dest)
	if not route.has(goal):
		check(false, "unreachable target " + str(goal))
		return
	var path: Array[Vector2i] = []
	var tile := goal
	while tile != start:
		var d: Vector2i = route[tile]
		path.push_front(d)
		tile = Maze.next(tile, -d)
	for d in path:
		var key: Key = [KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT][Maze.ORDER.find(d)]
		press(key)
		game.advance(game.player, -1, 1)
		press(key, false)
	check(game.player.tile == goal, "walked to " + str(goal))

func check_campaign() -> void:
	for stage in 4:
		check(game.stage == stage and game.phase == Game.Phase.READY, "enter new maze")
		check(game.items.size() == [2, 3, 3, 3][stage], "mission item count")
		check(game.dots.values().count(true) == 4, "four reachable power pellets")
		for y in Maze.HEIGHT:
			check(game.maze.rows[y].length() == Maze.WIDTH, "stage row width")
			for x in Maze.WIDTH:
				var tile := Vector2i(x, y)
				if game.maze.walkable(tile):
					check(game.home_distance.has(tile), "ghosts can return home from " + str(tile))
		press(KEY_SPACE)
		var targets := game.items.keys()
		walk_to(targets[0])
		var remaining := game.items.size()
		game.reset_round()
		check(game.items.size() == remaining and remaining == targets.size() - 1, "collected item survives respawn")
		press(KEY_SPACE)
		# Reserve the final item to check the dots-first completion order on the last map.
		var last: Vector2i = targets.back()
		if stage == 3:
			for dot: Vector2i in game.dots.keys():
				if game.dots.has(dot):
					game.player = Game.Actor.new(dot)
					game.eat_dot()
			check(game.phase == Game.Phase.PLAY, "all dots alone do not clear a mission")
		for target in targets:
			if target != last and game.items.has(target):
				walk_to(target)
		# Test the exact reward in isolation by stepping onto the last item's tile.
		var entry := Vector2i.ZERO
		for d: Vector2i in Maze.ORDER:
			if game.maze.walkable(Maze.next(last, d)):
				entry = Maze.next(last, d)
				break
		game.player = Game.Actor.new(entry)
		var points := game.score
		var lives_before := game.lives
		walk_to(last)
		check(game.items.is_empty(), "mission completed")
		match stage:
			0: check(game.score == points + 500, "vault bonus")
			1:
				var position_before := game.ghosts[0].point()
				game._physics_process(0.1)
				check(is_equal_approx(game.freeze_left, 4.9) and game.ghosts[0].point() == position_before, "frozen ghost stays still")
			2:
				var dot: Vector2i = game.dots.keys()[0]
				var expected := 100 if game.dots[dot] else 20
				game.player = Game.Actor.new(dot)
				game.eat_dot()
				check(game.score == points + expected, "double pellet points")
			3: check(game.lives == lives_before + 1, "extra life")
		if game.phase == Game.Phase.PLAY:
			game.reset_round()
			press(KEY_SPACE)
			for dot: Vector2i in game.dots.keys():
				if game.dots.has(dot):
					walk_to(dot)
					# The real game yields every frame; let the recorder drain during this accelerated sweep.
					if game.recorder != null:
						await process_frame
		check(game.phase == Game.Phase.CLEAR, "mission and pellets clear the stage")
		game._physics_process(1.4)
	check(game.level == 6 and game.stage == -1 and game.dots.size() == 244, "next arcade cycle starts")

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
	check(AI.turn(game.maze, Vector2i(6, 5), Vector2i.LEFT, Vector2i(5, 4), false) == Vector2i.UP, "equal distance uses arcade priority")
	check(AI.turn(game.maze, Vector2i(6, 5), Vector2i.LEFT, Vector2i(7, 5), false) != Vector2i.RIGHT, "no voluntary U-turn")
	check(game.dots.size() == 244 and game.dots.values().count(true) == 4, "240 pellets and four energizers")
	for tile in game.dots:
		check(game.home_distance.has(tile), "reachable pellet " + str(tile))
	for row: String in Maze.ROWS:
		check(row.length() == Maze.WIDTH, "maze row width")
	press(KEY_SPACE)
	var start := game.player.point()
	var ghost_start := game.ghosts[0].point()
	game._physics_process(1.0 / 60)
	check(game.player.point() == start, "starting with space waits for direction")
	check(is_equal_approx(game.ghosts[0].point().distance_to(ghost_start), 5.76 / 60.0), "first-level roaming speed")
	press(KEY_LEFT)
	for i in 28:
		game._physics_process(1.0 / 60)
	check(game.phase == Game.Phase.PLAY and game.score > 0, "opening move scores")
	press(KEY_LEFT, false)
	var stopped := game.player.point()
	game._physics_process(1.0 / 60)
	check(game.player.point() == stopped, "release stops between tile centers")
	press(KEY_A)
	press(KEY_RIGHT)
	game._physics_process(1.0 / 60)
	check(game.player.point().x > stopped.x, "last held direction reverses mid-tile")
	press(KEY_RIGHT, false)
	var reversed := game.player.point()
	game._physics_process(1.0 / 60)
	check(game.player.point().x < reversed.x, "releasing right resumes held A")
	press(KEY_P)
	var before := game.player.point()
	game._physics_process(0.25)
	check(game.paused and game.player.point() == before, "pause freezes movement")
	press(KEY_P)
	game.player = Game.Actor.new(Vector2i(5, 5))
	press(KEY_A, false)
	press(KEY_RIGHT)
	press(KEY_UP)
	game.advance(game.player, -1, 2)
	check(game.player.tile == Vector2i(6, 4), "hold forward and turn at the first opening")
	game.get_window().focus_exited.emit()
	before = game.player.point()
	game.advance(game.player, -1, 1)
	check(game.player.point() == before, "focus loss clears held keys")
	# Approach the same junction slightly early, then just after passing its center.
	for travel in [0.75, 1.25]:
		game.player = Game.Actor.new(Vector2i(5, 5))
		press(KEY_RIGHT)
		game.advance(game.player, -1, travel)
		before = game.player.point()
		press(KEY_UP)
		game.advance(game.player, -1, 0.1)
		var after := game.player.point()
		check(after.y < before.y, "turn starts immediately near the junction: " + str(travel))
		check(after.distance_to(before) < 0.15, "turn does not teleport to the lane center")
		press(KEY_RIGHT, false)
		press(KEY_UP, false)
		game.advance(game.player, -1, 0.5)
		check(game.player.point() == after, "releasing keys stops during a corner")
	game.player = Game.Actor.new(Vector2i(5, 5))
	press(KEY_RIGHT)
	game.advance(game.player, -1, 0.4)
	press(KEY_UP)
	press(KEY_UP, false)
	for i in 8:
		game._physics_process(1.0 / 60)
	check(game.player.point().y < 5.5, "brief early tap turns while forward stays held")
	game.get_window().focus_exited.emit()
	game.player = Game.Actor.new(Vector2i(3, 5))
	press(KEY_RIGHT)
	press(KEY_UP)
	press(KEY_UP, false)
	for i in 26:
		game._physics_process(1.0 / 60)
	check(is_equal_approx(game.player.point().y, 5.5), "expired turn does not trigger at a distant opening")
	game.get_window().focus_exited.emit()
	game.player = Game.Actor.new(Vector2i(0, 14))
	press(KEY_LEFT)
	game.advance(game.player, -1, 1)
	check(game.player.tile == Vector2i(27, 14), "left tunnel wraps")
	press(KEY_RIGHT)
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
	check(game.level == 2 and game.items.size() == 2 and not game.dots.is_empty() and game.score == 10, "next level preserves score")
	await check_campaign()
	if failures.is_empty():
		print("PASS: ghost targeting, routing, maze, movement, power, lives and level cycle")
	game.sound.stop()
	game.queue_free()
	await create_timer(0.25).timeout
	quit(0 if failures.is_empty() else 1)
