extends Node2D

const Maze = preload("res://maze.gd")
const Stages = preload("res://stages.gd")
const AI = preload("res://ghost_ai.gd")
const Board = preload("res://maze_view.gd")
const Sounds = preload("res://sounds.gd")
const Recorder = preload("res://telemetry/recorder.gd")
const ORIGIN = Vector2(12, 47)
const CORNER_WINDOW := 0.42 # tiles either side of a junction
const TURN_BUFFER_TIME := 0.15
const COLORS = [Color("#ff565b"), Color("#ff9cc9"), Color("#55dbe1"), Color("#ffa451")]
const DIRECTIONS = {
	KEY_LEFT: Vector2i.LEFT, KEY_A: Vector2i.LEFT, KEY_UP: Vector2i.UP, KEY_W: Vector2i.UP,
	KEY_RIGHT: Vector2i.RIGHT, KEY_D: Vector2i.RIGHT, KEY_DOWN: Vector2i.DOWN, KEY_S: Vector2i.DOWN,
}
const WAVE = [7.0, 20.0, 7.0, 20.0, 5.0, 20.0, 5.0, INF]
const GOLD = Color("#ffdc52")
const INK = Color("#f1f2fb")
const MUTED = Color("#a4b0cb")
enum Phase { READY, PLAY, DYING, OVER, CLEAR }
enum GhostState { PEN, EXIT, ROAM, EYES, ENTER }

class Actor:
	var tile: Vector2i
	var dest: Vector2i
	var direction := Vector2i.LEFT
	var progress := 0.0
	var lane_offset := Vector2.ZERO
	var state := GhostState.ROAM
	var scared := false

	func _init(start: Vector2i) -> void:
		tile = start
		dest = start

	func reverse() -> void:
		direction = -direction
		if tile != dest:
			var old := tile
			tile = dest
			dest = old
			progress = 1.0 - progress

	func point() -> Vector2:
		var offset := Vector2(direction) * progress if tile != dest else Vector2.ZERO
		offset += lane_offset
		return Vector2(fposmod(tile.x + 0.5 + offset.x, Maze.WIDTH), tile.y + 0.5 + offset.y)

var maze: Maze
var stage := -1 # -1 selects the classic maze.
var items := {}
var item_total := 0
var freeze_left := 0.0
var double_left := 0.0
var player: Actor
var recorder: Recorder
var ghosts: Array[Actor] = []
var dots: Dictionary
var home_distance := {}
var phase := Phase.READY
var held_keys: Array[Key] = []
var turn_request := Vector2i.ZERO
var turn_time := 0.0
var score := 0
var lives := 3
var level := 1
var wave := 0
var wave_left := 7.0
var power_left := 0.0
var combo := 0
var round_time := 0.0
var phase_time := 0.0
var clock := 0.0
var paused := false
var dot_count := 0
var board := Board.new()
var sound := Sounds.new()
var font := SystemFont.new()
var bold := SystemFont.new()

func _ready() -> void:
	font.font_names = PackedStringArray(["Segoe UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	bold.font_names = font.font_names
	bold.font_weight = 720
	board.position = ORIGIN
	board.show_behind_parent = true
	add_child(board)
	add_child(sound)
	get_viewport().size_changed.connect(center_layout)
	get_window().focus_exited.connect(on_focus_lost)
	center_layout()
	board.hide()
	$Setup.theme = Theme.new()
	$Setup.theme.default_font = font
	var args := OS.get_cmdline_user_args()
	var participant := ""
	for arg in args:
		if arg.begins_with("--participant="):
			participant = arg.trim_prefix("--participant=")
	$Setup/Location.text = "数据保存至 " + ProjectSettings.globalize_path(Recorder.output_directory())
	$Setup/Record.pressed.connect(func(): begin_recording($Setup/Participant.text))
	$Setup/Participant.text_submitted.connect(begin_recording)
	$Setup/Practice.pressed.connect(new_game)
	if "--psygodot" in args or not participant.is_empty():
		begin_recording(participant)
	else:
		$Setup/Participant.grab_focus()

func begin_recording(label_text: String) -> void:
	if recorder == null:
		recorder = Recorder.new()
		add_child(recorder)
	recorder.participant_label = label_text.strip_edges()
	new_game()

func observe(tag: String, details: Dictionary = {}) -> void:
	if recorder == null or not recorder.session_active:
		return
	var timestamp := Time.get_ticks_usec()
	details.merge({"level": level, "lives": lives, "score": score,
		"tile_x": player.tile.x, "tile_y": player.tile.y})
	recorder.observe(tag, details, timestamp)

func capture_state() -> Dictionary:
	var positions := []
	for ghost in ghosts:
		var pos := ghost.point()
		positions.append([pos.x, pos.y, ghost.state, ghost.scared])
	var pos := player.point()
	return {"x": pos.x, "y": pos.y, "ghosts": positions, "level": level,
		"phase": phase, "paused": paused, "power_left": power_left}

func load_level() -> void:
	stage = (level - 1) % (Stages.LAYOUTS.size() + 1) - 1
	maze = Maze.new(Maze.ROWS if stage < 0 else Stages.LAYOUTS[stage])
	board.maze = maze
	board.edge = Board.EDGE if stage < 0 else Stages.COLORS[stage].darkened(0.27)
	board.fill = Board.FILL if stage < 0 else board.edge.darkened(0.78)
	board.queue_redraw()
	dots = maze.collectibles()
	items.clear()
	for y in Maze.HEIGHT:
		for x in Maze.WIDTH:
			if maze.rows[y][x] == "*":
				items[Vector2i(x, y)] = true
	item_total = items.size()
	freeze_left = 0
	double_left = 0
	home_distance.clear()
	# Eyes always take a shortest legal path to the door, including through the tunnel.
	var frontier: Array[Vector2i] = [Maze.DOOR]
	home_distance[Maze.DOOR] = 0
	var i := 0
	while i < frontier.size():
		var tile := frontier[i]
		i += 1
		for d: Vector2i in Maze.ORDER:
			var next := Maze.next(tile, d)
			if maze.walkable(next) and not home_distance.has(next):
				frontier.append(next)
				home_distance[next] = home_distance[tile] + 1
	reset_round()

func center_layout() -> void:
	position = (get_viewport_rect().size - Vector2(584, 700)) * 0.5

func new_game() -> void:
	if recorder != null and not recorder.begin(self):
		$Setup.show()
		$Setup/Location.text = "无法开始记录，请检查目录：" + ProjectSettings.globalize_path(Recorder.output_directory())
		recorder.queue_free()
		recorder = null
		return
	$Setup.hide()
	board.show()
	score = 0
	lives = 3
	level = 1
	load_level()

func reset_round() -> void:
	player = Actor.new(Maze.START)
	clear_movement_input()
	ghosts.clear()
	for start: Vector2i in [Maze.DOOR, Maze.HOME, Maze.HOME + Vector2i.LEFT * 2, Maze.HOME + Vector2i.RIGHT * 2]:
		var ghost := Actor.new(start)
		if start != Maze.DOOR:
			ghost.state = GhostState.PEN
			ghost.direction = Vector2i.UP
		ghosts.append(ghost)
	phase = Phase.READY
	phase_time = 0
	paused = false
	power_left = 0
	combo = 0
	wave = 0
	wave_left = WAVE[0]
	round_time = 0
	dot_count = 0
	observe("round_ready")
	queue_redraw()

func on_focus_lost() -> void:
	if player != null:
		observe("focus_lost")
	clear_movement_input()

func clear_movement_input() -> void:
	held_keys.clear()
	turn_request = Vector2i.ZERO

func _unhandled_key_input(event: InputEvent) -> void:
	if $Setup.visible or not event is InputEventKey or event.echo:
		return
	var key: Key = event.keycode
	if not event.pressed:
		if held_keys.has(key):
			observe("direction_key", {"key": OS.get_keycode_string(key), "pressed": false})
		held_keys.erase(key)
		if held_keys.is_empty():
			turn_request = Vector2i.ZERO
		return
	if key in [KEY_ENTER, KEY_SPACE] and phase == Phase.OVER:
		new_game()
		return
	if key in [KEY_P, KEY_ESCAPE, KEY_SPACE] and phase == Phase.PLAY:
		paused = not paused
		observe("pause" if paused else "resume")
		queue_redraw()
		return
	if phase == Phase.READY and (DIRECTIONS.has(key) or key in [KEY_ENTER, KEY_SPACE]):
		phase = Phase.PLAY
		observe("round_start")
	if phase == Phase.PLAY and DIRECTIONS.has(key):
		observe("direction_key", {"key": OS.get_keycode_string(key), "pressed": true})
		held_keys.erase(key)
		held_keys.push_front(key)
		var wanted: Vector2i = DIRECTIONS[key]
		turn_request = wanted if Vector2(wanted).dot(Vector2(player.direction)) == 0 else Vector2i.ZERO
		turn_time = TURN_BUFFER_TIME

func _physics_process(delta: float) -> void:
	if player == null or paused:
		return
	clock += delta
	phase_time += delta
	if phase == Phase.DYING and phase_time >= 1.0:
		if lives > 0:
			reset_round()
		else:
			phase = Phase.OVER
			observe("game_over")
			if recorder != null:
				recorder.end_session("game_over")
	elif phase == Phase.CLEAR and phase_time >= 1.3:
		level += 1
		load_level()
	elif phase == Phase.PLAY:
		round_time += delta
		freeze_left = maxf(0, freeze_left - delta)
		double_left = maxf(0, double_left - delta)
		update_modes(delta)
		var speed := 8.0 + minf(level - 1, 5) * 0.3
		advance(player, -1, speed * delta)
		turn_time -= delta
		if turn_time <= 0:
			turn_request = Vector2i.ZERO
		if phase == Phase.PLAY:
			for i in ghosts.size():
				var ghost := ghosts[i]
				var rate := speed * 0.72
				if ghost.state in [GhostState.EYES, GhostState.ENTER]:
					rate = 16.0
				elif ghost.scared or (ghost.tile.y == 14 and (ghost.tile.x < 6 or ghost.tile.x > 21)):
					rate = speed * 0.50
				if freeze_left <= 0 or ghost.state in [GhostState.EYES, GhostState.ENTER]:
					advance(ghost, i, rate * delta)
				collide(ghost)
				if phase != Phase.PLAY:
					break
	queue_redraw()

func update_modes(delta: float) -> void:
	if power_left > 0:
		power_left = maxf(0, power_left - delta)
		if power_left == 0:
			for ghost in ghosts:
				ghost.scared = false
		return
	wave_left -= delta
	if wave_left <= 0 and wave < WAVE.size() - 1:
		wave += 1
		wave_left = WAVE[wave]
		for ghost in ghosts:
			reverse_roaming(ghost)

func reverse_roaming(ghost: Actor) -> void:
	if ghost.state != GhostState.ROAM:
		return
	if ghost.tile == ghost.dest:
		var back := Maze.next(ghost.tile, -ghost.direction)
		if maze.walkable(back):
			ghost.reverse()
			ghost.dest = back
	else:
		ghost.reverse()

func advance(actor: Actor, kind: int, distance: float) -> void:
	if kind == -1:
		if held_keys.is_empty():
			return
		var wanted: Vector2i = turn_request if turn_request != Vector2i.ZERO else DIRECTIONS[held_keys[0]]
		if Vector2(wanted).dot(Vector2(actor.direction)) == 0:
			try_corner(wanted)
			if phase != Phase.PLAY:
				return
		elif actor.tile != actor.dest and wanted == -actor.direction:
			actor.reverse()
	while distance > 0.00001:
		if actor.tile == actor.dest:
			var step := Vector2i.ZERO
			if kind == -1:
				if turn_request != Vector2i.ZERO and maze.walkable(Maze.next(actor.tile, turn_request)):
					step = turn_request
					turn_request = Vector2i.ZERO
				else:
					for key in held_keys:
						var wanted: Vector2i = DIRECTIONS[key]
						if maze.walkable(Maze.next(actor.tile, wanted)):
							step = wanted
							break
			else:
				step = ghost_step(actor, kind)
			if step == Vector2i.ZERO:
				return
			actor.direction = step
			actor.dest = Maze.next(actor.tile, step)
		var moved := minf(distance, 1.0 - actor.progress)
		distance -= moved
		actor.progress += moved
		actor.lane_offset = actor.lane_offset.move_toward(Vector2.ZERO, moved)
		if actor.progress >= 0.99999:
			actor.tile = actor.dest
			actor.progress = 0
			if kind == -1:
				eat_dot()
				if phase != Phase.PLAY:
					return

func try_corner(wanted: Vector2i) -> void:
	if player.tile == player.dest or not player.lane_offset.is_zero_approx():
		return
	# Choose the nearby junction on the current edge. Keep the exact world
	# position and bleed off the sideways distance while moving down the new lane.
	var junction := player.tile
	var sideways := player.progress
	if 1.0 - player.progress <= CORNER_WINDOW:
		junction = player.dest
		sideways -= 1.0
	elif player.progress > CORNER_WINDOW or turn_request == Vector2i.ZERO:
		# Only a fresh tap can reclaim a passed junction. A still-held forward
		# key from before the turn must not pull the player back into that lane.
		return
	var exit_tile := Maze.next(junction, wanted)
	if not maze.walkable(exit_tile):
		return
	player.lane_offset = Vector2(player.direction) * sideways
	player.tile = junction
	player.dest = exit_tile
	player.direction = wanted
	player.progress = 0
	turn_request = Vector2i.ZERO
	eat_dot()

func ghost_step(ghost: Actor, kind: int) -> Vector2i:
	if ghost.state == GhostState.PEN:
		if dot_count < [0, 0, 30, 60][kind] and round_time < [0, 0, 8, 16][kind]:
			return Vector2i.ZERO
		ghost.state = GhostState.EXIT
	if ghost.state == GhostState.EYES:
		if ghost.tile == Maze.DOOR:
			ghost.state = GhostState.ENTER
		else:
			for d: Vector2i in Maze.ORDER:
				if home_distance.get(Maze.next(ghost.tile, d), 999) < home_distance[ghost.tile]:
					return d
	if ghost.state == GhostState.ENTER:
		if ghost.tile != Maze.HOME:
			return Vector2i.DOWN
		ghost.state = GhostState.EXIT
	if ghost.state == GhostState.EXIT:
		if ghost.tile.x != Maze.DOOR.x:
			return Vector2i(signi(Maze.DOOR.x - ghost.tile.x), 0)
		if ghost.tile != Maze.DOOR:
			return Vector2i.UP
		ghost.state = GhostState.ROAM
		return Vector2i.LEFT
	var target: Vector2i = AI.CORNERS[kind]
	if wave % 2 == 1:
		target = AI.chase_target(kind, ghost.tile, player.tile, player.direction, ghosts[0].tile)
	return AI.turn(maze, ghost.tile, ghost.direction, target, ghost.scared)

func eat_dot() -> void:
	if items.erase(player.tile):
		observe("task_item", {"item": Stages.ITEMS[stage], "remaining": items.size()})
		if items.is_empty():
			match stage:
				0: score += 500
				1: freeze_left = 5.0
				2: double_left = 12.0
				3: lives += 1
			observe("task_reward", {"reward": Stages.REWARDS[stage]})
		sound.cue("reward" if items.is_empty() else "item")
	elif dots.has(player.tile):
		eat_pellet()
	else:
		return
	if dots.is_empty() and items.is_empty():
		phase = Phase.CLEAR
		observe("level_clear")
		phase_time = 0
		sound.cue("clear")

func eat_pellet() -> void:
	var power: bool = dots[player.tile]
	dots.erase(player.tile)
	dot_count += 1
	score += (50 if power else 10) * (2 if double_left > 0 else 1)
	observe("power_pellet" if power else "pellet")
	if power:
		power_left = maxf(2, 6 - (level - 1) * 0.5)
		combo = 0
		for ghost in ghosts:
			if ghost.state not in [GhostState.EYES, GhostState.ENTER]:
				ghost.scared = true
				reverse_roaming(ghost)
		sound.cue("power")
	else:
		sound.cue("dot" if dot_count % 2 == 0 else "dot2")

func collide(ghost: Actor) -> void:
	if ghost.state != GhostState.ROAM:
		return
	var a := player.point()
	var b := ghost.point()
	var dx := absf(a.x - b.x)
	if Vector2(minf(dx, Maze.WIDTH - dx), a.y - b.y).length_squared() > 0.56:
		return
	if ghost.scared:
		score += 200 << mini(combo, 3)
		combo += 1
		ghost.scared = false
		ghost.state = GhostState.EYES
		observe("ghost_captured", {"ghost": ghosts.find(ghost), "combo": combo})
		sound.cue("capture")
	else:
		lives -= 1
		phase = Phase.DYING
		observe("life_lost", {"ghost": ghosts.find(ghost)})
		phase_time = 0
		sound.cue("death")

func label(at: Vector2, value: String, size: int, color: Color, heavy := false) -> void:
	draw_string(bold if heavy else font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func ghost_icon(at: Vector2, radius: float, tint: Color, face: Vector2i, eyes_only := false, scared := false) -> void:
	if not eyes_only:
		var body := PackedVector2Array()
		for i in 21:
			var angle := PI + PI * i / 20.0
			body.append(at + radius * Vector2(cos(angle), sin(angle)))
		for i in 7:
			body.append(at + radius * Vector2(1.0 - i / 3.0, 0.96 if i % 2 == 0 else 0.64))
		draw_colored_polygon(body, tint)
	for x: float in [-0.39, 0.39]:
		var eye := at + radius * Vector2(x, -0.15)
		draw_circle(eye, radius * (0.13 if scared else 0.29), Color.WHITE, true, -1, true)
		if not scared:
			draw_circle(eye + Vector2(face) * radius * 0.14, radius * 0.14, Color("#203487"), true, -1, true)
	if scared:
		var mouth := PackedVector2Array()
		for i in 5:
			mouth.append(at + radius * Vector2(-0.55 + i * 0.275, 0.4 if i % 2 == 0 else 0.24))
		draw_polyline(mouth, Color.WHITE, 1.4, true)

func pac_icon(at: Vector2, radius: float, angle: float, opening: float) -> void:
	var shape := PackedVector2Array([at])
	for i in 33:
		var theta := angle + opening + (TAU - 2 * opening) * i / 32.0
		shape.append(at + radius * Vector2(cos(theta), sin(theta)))
	draw_colored_polygon(shape, GOLD)

func item_icon(at: Vector2) -> void:
	var color: Color = Stages.COLORS[stage]
	draw_circle(at, 9.5, color.darkened(0.82), true, -1, true)
	match stage:
		0:
			draw_arc(at + Vector2(-3, -2), 3.2, 0, TAU, 20, color, 2, true)
			draw_line(at, at + Vector2(6, 6), color, 2, true)
			draw_line(at + Vector2(3, 3), at + Vector2(5, 1), color, 2, true)
		1:
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -8), at + Vector2(6, -1), at + Vector2(0, 8), at + Vector2(-6, -1)]), color)
			draw_line(at + Vector2(-5, -1), at + Vector2(5, -1), color.darkened(0.4), 1.5)
		2:
			draw_rect(Rect2(at + Vector2(-5, -6), Vector2(10, 13)), color, false, 1.7)
			draw_rect(Rect2(at + Vector2(-2, -8), Vector2(4, 2)), color)
			draw_rect(Rect2(at + Vector2(-3, 0), Vector2(6, 5)), color)
		3:
			var star := PackedVector2Array()
			for i in 10:
				star.append(at + Vector2.UP.rotated(i * PI / 5) * (8 if i % 2 == 0 else 3.5))
			draw_colored_polygon(star, color)

func _draw() -> void:
	if player == null:
		return
	label(Vector2(12, 34), "得分", 19, MUTED)
	label(Vector2(65, 35), "%06d" % score, 30, INK, true)
	label(Vector2(242, 34), "生命", 19, MUTED)
	for i in mini(lives, 4):
		pac_icon(Vector2(304 + i * 22, 26), 8, 0, 0.59)
	if lives > 4:
		label(Vector2(388, 33), "+%d" % (lives - 4), 16, GOLD)
	label(Vector2(459, 34), "关卡", 19, MUTED)
	label(Vector2(519, 35), "%02d" % level, 27, GOLD, true)
	for tile: Vector2i in dots:
		var at := ORIGIN + (Vector2(tile) + Vector2(0.5, 0.5)) * Board.CELL
		if dots[tile]:
			draw_circle(at, 5.4 + 0.9 * sin(clock * 6), Color("#ffe1bb"), true, -1, true)
		else:
			draw_circle(at, 2, Color("#efc6a8"))
	for tile: Vector2i in items:
		item_icon(ORIGIN + (Vector2(tile) + Vector2(0.5, 0.5)) * Board.CELL)
	for i in ghosts.size():
		var ghost := ghosts[i]
		var tint: Color = COLORS[i]
		if ghost.scared:
			tint = Color("#686fc0") if power_left < 2 and int(clock * 7) % 2 == 0 else Color("#354ef4")
		elif freeze_left > 0:
			tint = Color("#acdeff")
		var pos := ORIGIN + ghost.point() * Board.CELL
		ghost_icon(pos, 11.8, tint, ghost.direction, ghost.state in [GhostState.EYES, GhostState.ENTER], ghost.scared)
	var openness := 0.14 + 0.61 * absf(sin(clock * 11)) if player.tile != player.dest and not held_keys.is_empty() else 0.58
	if phase == Phase.DYING:
		openness = lerpf(0.3, PI - 0.01, minf(1.0, phase_time))
	pac_icon(ORIGIN + player.point() * Board.CELL, 12, Vector2(player.direction).angle(), openness)
	var status := ""
	if paused:
		status = "已暂停"
	elif phase == Phase.READY:
		status = "READY!" if stage < 0 else Stages.TITLES[stage]
	elif phase == Phase.CLEAR:
		status = "过关！"
	elif phase == Phase.OVER:
		status = "GAME OVER"
	if status != "":
		var center := ORIGIN + Vector2(280, 350)
		var width := bold.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_rect(Rect2(center - Vector2(width/2 + 6, 11), Vector2(width + 12, 22)), Color("#090b12"))
		label(center + Vector2(-width / 2, 7), status, 18, GOLD, true)
	var hint := "按住方向键 / WASD 移动，松开即停     ·     空格暂停"
	if phase == Phase.READY:
		hint = "按住方向键 / WASD 开始移动，松开即停"
	if stage >= 0:
		if not items.is_empty():
			hint = "%s %d/%d  ·  集齐获得%s" % [Stages.ITEMS[stage], item_total - items.size(), item_total, Stages.REWARDS[stage]]
		elif freeze_left > 0:
			hint = "冰晶已集齐  ·  幽灵冻结 %d 秒" % ceili(freeze_left)
		elif double_left > 0:
			hint = "电池已集齐  ·  双倍豆分 %d 秒" % ceili(double_left)
		elif stage in [1, 2]:
			hint = "任务已完成  ·  吃完剩余豆子过关"
		else:
			hint = "任务已完成  ·  %s" % Stages.REWARDS[stage]
	if paused:
		hint = "按空格或 P  继续游戏"
	elif phase == Phase.OVER:
		hint = "按回车或空格重新开局"
	draw_string(font, Vector2(12, 691), hint, HORIZONTAL_ALIGNMENT_CENTER, 560, 16, MUTED)
