extends Control

signal closed
const Recording = preload("res://replay/recording.gd")
const Board = preload("res://maze_view.gd")
const Maze = preload("res://maze.gd")
const ORIGIN := Vector2(100, 32)
const SCALE := 0.68
const COLORS := [Color("#ff565b"), Color("#ff9cc9"), Color("#55dbe1"), Color("#ffa451")]
var data := Recording.new()
var board := Board.new()
var index := 0
var level := 0
var dots := {}
var playing := false
var play_us := 0.0
var start_index := -1
var note_rows: Array[int] = []
@onready var timeline: HSlider = $Controls/Timeline
@onready var transport := $Controls/Transport
@onready var notes := $Controls/Notes

func _ready() -> void:
	board.position = ORIGIN
	board.scale = Vector2.ONE * SCALE
	board.show_behind_parent = true
	add_child(board)
	for rate in ["0.25×", "0.5×", "1×", "2×"]:
		transport.get_node("Rate").add_item(rate)
	transport.get_node("Rate").select(2)
	timeline.value_changed.connect(func(value): stop(); seek(data.times.bsearch(int(value), false) - 1))
	transport.get_node("Previous").pressed.connect(func(): step_record(-1))
	transport.get_node("Next").pressed.connect(func(): step_record(1))
	transport.get_node("Event").pressed.connect(func():
		stop()
		var n := data.events.bsearch(index, false)
		seek(data.events[n] if n < data.events.size() else data.rows.size() - 1))
	transport.get_node("Play").pressed.connect(toggle)
	transport.get_node("Close").pressed.connect(func(): closed.emit(); queue_free())
	transport.get_node("Export").pressed.connect(func():
		stop()
		var path := data.export_features()
		message("已导出 " + path.get_file() if path != "" else "无法写入特征文件。"))
	notes.get_node("Start").pressed.connect(func():
		stop()
		start_index = index if start_index < 0 else -1
		notes.get_node("Start").text = "取消起点" if start_index >= 0 else "设区间起点"
		message("起点 %.3f 秒；移动至终点后保存。" % (data.times[index] / 1e6) if start_index >= 0 else "已取消区间起点。"))
	notes.get_node("Save").pressed.connect(save_annotation)
	notes.get_node("List").item_selected.connect(func(i):
		if i > 0:
			stop()
			seek(note_rows[i - 1]))

func open_recording(path: String) -> String:
	var error := data.load_file(path)
	if error != "":
		return error
	timeline.max_value = data.times[-1]
	var mode := "轨迹回放" if data.frames.size() else "仅事件 · 无连续轨迹"
	var integrity := "" if data.manifest.get("recording", {}).get("complete", false) else " · 记录不完整"
	$Header.text = "%s  ·  %s%s" % [data.manifest.get("participant_label", "anonymous"), mode, integrity]
	reload_notes()
	seek(0)
	return ""

func reload_notes() -> void:
	var list: OptionButton = notes.get_node("List")
	list.clear()
	list.add_item("已保存的标注")
	note_rows.clear()
	if not DirAccess.dir_exists_absolute(data.annotation_dir()):
		return
	for name in DirAccess.get_files_at(data.annotation_dir()):
		if name.get_extension() != "json":
			continue
		var n = JSON.parse_string(FileAccess.get_file_as_string(data.annotation_dir().path_join(name)))
		if not n is Dictionary or n.get("session_id") != data.manifest.session_id:
			continue
		var i := data.times.bsearch(int(n.start_usec))
		while i < data.rows.size() and data.times[i] == int(n.start_usec) and data.rows[i].event_id != n.start_event_id:
			i += 1
		if i < data.rows.size() and data.rows[i].event_id == n.start_event_id:
			note_rows.append(i)
			list.add_item("%.2f–%.2fs · %s · %s" % [n.start_usec/1e6, n.end_usec/1e6, n.annotator, n.label])

func save_annotation() -> void:
	stop()
	var author: String = $Controls/Inputs/Author.text.strip_edges()
	var label_text: String = $Controls/Inputs/Label.text.strip_edges()
	if author.is_empty() or label_text.is_empty():
		message("请输入标注者代号和行为标签。")
		return
	var first := index if start_index < 0 else start_index
	if index < first:
		message("终点位于起点之前，请调整时间轴。")
		return
	if data.save_note(first, index, author, label_text).is_empty():
		message("无法写入标注文件。")
		return
	start_index = -1
	notes.get_node("Start").text = "设区间起点"
	$Controls/Inputs/Label.clear()
	reload_notes()
	message("已保存标注 · " + label_text)

func message(text: String) -> void:
	$Controls/Message.text = text

func stop() -> void:
	playing = false
	transport.get_node("Play").text = "播放"

func toggle() -> void:
	if playing:
		stop()
	else:
		if index == data.rows.size() - 1:
			seek(0)
		play_us = data.times[index]
		playing = true
		transport.get_node("Play").text = "暂停"

func step_record(d: int) -> void:
	stop()
	if data.frames.is_empty():
		seek(index + d)
	else:
		var pos := data.frames.bsearch(index, d < 0)
		if d < 0:
			pos -= 1
		seek(data.frames[pos] if pos >= 0 and pos < data.frames.size() else (0 if d < 0 else data.rows.size() - 1))

func _process(delta: float) -> void:
	if playing:
		var rate: float = [0.25, 0.5, 1.0, 2.0][transport.get_node("Rate").selected]
		play_us += delta * rate * 1e6
		var next := data.times.bsearch(roundi(play_us), false) - 1
		if next != index:
			seek(next)
		if index == data.rows.size() - 1:
			stop()

func seek(i: int) -> void:
	index = clampi(i, 0, data.rows.size() - 1)
	timeline.set_value_no_signal(data.times[index])
	var row := data.rows[index]
	var event := data.last_event[index]
	var tag: String = data.rows[event].event_tag if event >= 0 and row.event_tag == "frame_sample" else row.event_tag
	$Controls/Status.text = "%.3f s   ·   关 %d   ·   %s   ·   %s" % [data.times[index]/1e6, data.levels[index], row.event_id, tag]
	$Controls/Status.tooltip_text = JSON.stringify(row.payload)
	var frame := data.last_frame[index]
	if frame >= 0:
		var sample: Dictionary = data.rows[frame].payload
		var near := data.nearest_threat(sample)
		var phase_name: String = ["就位", "游玩", "掉命", "结束", "过关"][int(sample.phase)]
		var info := "暂停" if sample.paused else phase_name
		if near:
			info += "  ·  最近威胁 %s  %.2f 格" % [["红鬼","粉鬼","青鬼","橙鬼"][near[0]], near[1]]
		$Controls/Observation.text = "%s  ·  显示 %.3f s 的样本" % [info, data.times[frame] / 1e6]
	else:
		$Controls/Observation.text = "空心圆显示最近一次行为事件的格位置"
	if level != data.levels[index]:
		level = data.levels[index]
		board.maze = Maze.new(data.layouts[(level - 1) % data.layouts.size()])
		var stage := (level - 1) % data.layouts.size() - 1
		board.edge = Board.EDGE if stage < 0 else Recording.Stages.COLORS[stage].darkened(0.27)
		board.fill = Board.FILL if stage < 0 else board.edge.darkened(0.78)
		dots = board.maze.collectibles()
		for y in Maze.HEIGHT:
			for x in Maze.WIDTH:
				if board.maze.rows[y][x] == "*":
					dots[Vector2i(x, y)] = "item"
		board.queue_redraw()
	queue_redraw()

func _draw() -> void:
	if data.rows.is_empty():
		return
	var cell := Board.CELL * SCALE
	var pickups: Dictionary = data.removed.get(level, {})
	for tile: Vector2i in dots:
		if pickups.get(tile, data.rows.size()) <= index:
			continue
		var item: bool = typeof(dots[tile]) == TYPE_STRING
		draw_circle(ORIGIN + (Vector2(tile) + Vector2(0.5, 0.5)) * cell, 4 if item or dots[tile] else 1.5, Color.CYAN if item else Color.WHEAT)
	var frame := data.last_frame[index]
	if frame >= 0:
		var p: Dictionary = data.rows[frame].payload
		for k in p.ghosts.size():
			var g: Array = p.ghosts[k]
			var color: Color = COLORS[k]
			if int(g[2]) in [3, 4]:
				color = Color.WHITE
			elif g[3]:
				color = Color.ROYAL_BLUE
			elif p.get("freeze_left", 0) > 0:
				color = Color.LIGHT_BLUE
			draw_circle(ORIGIN + Vector2(g[0],g[1]) * cell, 6, color)
		var at := ORIGIN + Vector2(p.x,p.y) * cell
		draw_circle(at, 6, Color.GOLD)
		if p.has("dx"):
			draw_line(at, at + Vector2(p.dx, p.dy) * 6, Color("#282119"), 2, true)
	elif data.last_event[index] >= 0:
		var p: Dictionary = data.rows[data.last_event[index]].payload
		if p.has("tile_x"):
			draw_circle(ORIGIN + Vector2(p.tile_x + 0.5,p.tile_y + 0.5) * cell, 6, Color.GOLD, false, 2)
