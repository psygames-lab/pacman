extends Node2D

const Maze = preload("res://maze.gd")
const AI = preload("res://ghost_ai.gd")
const Board = preload("res://maze_view.gd")
const Sounds = preload("res://sounds.gd")
const ORIGIN = Vector2(38, 95)
const COLORS = [Color("#ff565b"), Color("#ff9cc9"), Color("#55dbe1"), Color("#ffa451")]
const NAMES = ["Blinky", "Pinky", "Inky", "Clyde"]
const NOTES = ["锁定你所在的格子", "埋伏在前方四格", "借红鬼的位置包抄", "八格外追击，靠近就撤"]
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
		return Vector2(fposmod(tile.x + 0.5 + offset.x, Maze.WIDTH), tile.y + 0.5 + offset.y)

var player: Actor
var ghosts: Array[Actor] = []
var dots: Dictionary
var home_distance := {}
var phase := Phase.READY
var queued := Vector2i.LEFT
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
	# Eyes always take a shortest legal path to the door, including through the tunnel.
	var frontier: Array[Vector2i] = [Maze.DOOR]
	home_distance[Maze.DOOR] = 0
	var i := 0
	while i < frontier.size():
		var tile := frontier[i]
		i += 1
		for d: Vector2i in Maze.ORDER:
			var next := Maze.next(tile, d)
			if Maze.walkable(next) and not home_distance.has(next):
				frontier.append(next)
				home_distance[next] = home_distance[tile] + 1
	new_game()

func new_game() -> void:
	score = 0
	lives = 3
	level = 1
	dots = Maze.collectibles()
	reset_round()

func reset_round() -> void:
	player = Actor.new(Maze.START)
	queued = Vector2i.LEFT
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
	queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key: int = event.keycode
	if key in [KEY_ENTER, KEY_SPACE] and phase == Phase.OVER:
		new_game()
		return
	if key in [KEY_P, KEY_ESCAPE, KEY_SPACE] and phase == Phase.PLAY:
		paused = not paused
		queue_redraw()
		return
	var keys := {KEY_LEFT: Vector2i.LEFT, KEY_A: Vector2i.LEFT, KEY_UP: Vector2i.UP, KEY_W: Vector2i.UP,
		KEY_RIGHT: Vector2i.RIGHT, KEY_D: Vector2i.RIGHT, KEY_DOWN: Vector2i.DOWN, KEY_S: Vector2i.DOWN}
	if phase == Phase.READY and (keys.has(key) or key in [KEY_ENTER, KEY_SPACE]):
		phase = Phase.PLAY
	if phase == Phase.PLAY and not paused and keys.has(key):
		queued = keys[key]
		if queued == -player.direction and player.tile != player.dest:
			player.reverse()

func _physics_process(delta: float) -> void:
	if paused:
		return
	clock += delta
	phase_time += delta
	if phase == Phase.DYING and phase_time >= 1.0:
		if lives > 0:
			reset_round()
		else:
			phase = Phase.OVER
	elif phase == Phase.CLEAR and phase_time >= 1.3:
		level += 1
		dots = Maze.collectibles()
		reset_round()
	elif phase == Phase.PLAY:
		round_time += delta
		update_modes(delta)
		var speed := 8.0 + minf(level - 1, 5) * 0.3
		advance(player, -1, speed * delta)
		if phase == Phase.PLAY:
			for i in ghosts.size():
				var ghost := ghosts[i]
				var rate := speed * 0.92
				if ghost.state in [GhostState.EYES, GhostState.ENTER]:
					rate = 16.0
				elif ghost.scared or (ghost.tile.y == 14 and (ghost.tile.x < 6 or ghost.tile.x > 21)):
					rate = speed * 0.58
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
		if Maze.walkable(back):
			ghost.reverse()
			ghost.dest = back
	else:
		ghost.reverse()

func advance(actor: Actor, kind: int, distance: float) -> void:
	while distance > 0.00001:
		if actor.tile == actor.dest:
			var step := Vector2i.ZERO
			if kind == -1:
				if Maze.walkable(Maze.next(actor.tile, queued)):
					step = queued
				elif Maze.walkable(Maze.next(actor.tile, actor.direction)):
					step = actor.direction
			else:
				step = ghost_step(actor, kind)
			if step == Vector2i.ZERO:
				return
			actor.direction = step
			actor.dest = Maze.next(actor.tile, step)
		var moved := minf(distance, 1.0 - actor.progress)
		distance -= moved
		actor.progress += moved
		if actor.progress >= 0.99999:
			actor.tile = actor.dest
			actor.progress = 0
			if kind == -1:
				eat_dot()
				if phase != Phase.PLAY:
					return

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
	return AI.turn(ghost.tile, ghost.direction, target, ghost.scared)

func eat_dot() -> void:
	if not dots.has(player.tile):
		return
	var power: bool = dots[player.tile]
	dots.erase(player.tile)
	dot_count += 1
	score += 50 if power else 10
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
	if dots.is_empty():
		phase = Phase.CLEAR
		phase_time = 0
		sound.cue("clear")

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
		sound.cue("capture")
	else:
		lives -= 1
		phase = Phase.DYING
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

func _draw() -> void:
	if player == null:
		return
	pac_icon(Vector2(56, 49), 18, 0, 0.62)
	label(Vector2(86, 62), "PAC-MAN", 39, INK, true)
	draw_line(Vector2(38, 79), Vector2(922, 79), Color("#333e59"), 1)
	label(Vector2(776, 56), "关卡", 17, MUTED)
	label(Vector2(839, 59), "%02d" % level, 29, GOLD, true)
	for tile: Vector2i in dots:
		var at := ORIGIN + (Vector2(tile) + Vector2(0.5, 0.5)) * Board.CELL
		if dots[tile]:
			draw_circle(at, 5.4 + 0.9 * sin(clock * 6), Color("#ffe1bb"), true, -1, true)
		else:
			draw_circle(at, 2, Color("#efc6a8"))
	for i in ghosts.size():
		var ghost := ghosts[i]
		var tint: Color = COLORS[i]
		if ghost.scared:
			tint = Color("#686fc0") if power_left < 2 and int(clock * 7) % 2 == 0 else Color("#354ef4")
		var pos := ORIGIN + ghost.point() * Board.CELL
		ghost_icon(pos, 9, tint, ghost.direction, ghost.state in [GhostState.EYES, GhostState.ENTER], ghost.scared)
	var openness := 0.14 + 0.61 * absf(sin(clock * 11)) if player.tile != player.dest else 0.58
	if phase == Phase.DYING:
		openness = lerpf(0.3, PI - 0.01, minf(1.0, phase_time))
	pac_icon(ORIGIN + player.point() * Board.CELL, 9.5, Vector2(player.direction).angle(), openness)
	var status := ""
	if paused:
		status = "已暂停"
	elif phase == Phase.READY:
		status = "READY!"
	elif phase == Phase.CLEAR:
		status = "过关！"
	elif phase == Phase.OVER:
		status = "GAME OVER"
	if status != "":
		var center := ORIGIN + Vector2(280, 350)
		var width := bold.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_rect(Rect2(center - Vector2(width/2 + 6, 11), Vector2(width + 12, 22)), Color("#090b12"))
		label(center + Vector2(-width / 2, 7), status, 18, GOLD, true)
	draw_line(Vector2(627, 99), Vector2(627, 713), Color("#333e59"))
	label(Vector2(660, 125), "得分", 18, MUTED)
	label(Vector2(656, 188), "%06d" % score, 55, INK, true)
	label(Vector2(660, 236), "生命", 18, MUTED)
	for i in lives:
		pac_icon(Vector2(747 + i * 30, 230), 10, 0, 0.59)
	draw_line(Vector2(660, 269), Vector2(922, 269), Color("#333e59"))
	label(Vector2(660, 309), "追击档案", 24, INK, true)
	for i in 4:
		var y := 357 + 77 * i
		ghost_icon(Vector2(676, y + 2), 13, COLORS[i], Vector2i.LEFT)
		label(Vector2(707, y), NAMES[i], 22, COLORS[i], true)
		label(Vector2(707, y + 23), NOTES[i], 15, MUTED)
	draw_line(Vector2(660, 638), Vector2(922, 638), Color("#333e59"))
	var mode := "受惊" if power_left > 0 else ("追击" if wave % 2 else "散开")
	label(Vector2(660, 685), "幽灵状态", 17, MUTED)
	label(Vector2(790, 685), mode, 21, GOLD if power_left > 0 else INK, true)
	var hint := "方向键 / WASD  移动         空格 / P  暂停"
	if phase == Phase.READY:
		hint = "按方向键或空格开始"
	elif paused:
		hint = "按空格或 P  继续游戏"
	elif phase == Phase.OVER:
		hint = "按回车或空格重新开局"
	label(Vector2(38, 752), hint, 17, MUTED)
