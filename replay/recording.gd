extends RefCounted

const Maze = preload("res://maze.gd")
const Stages = preload("res://stages.gd")
var rows: Array[Dictionary] = []
var times := PackedInt64Array()
var frames := PackedInt32Array()
var events := PackedInt32Array()
var last_frame := PackedInt32Array()
var last_event := PackedInt32Array()
var levels := PackedInt32Array()
var removed := {} # level -> tile -> pickup row
var layouts: Array = []
var manifest := {}
var stem := ""

func load_file(path: String) -> String:
	stem = path.trim_suffix("_raw_events.jsonl")
	var info := FileAccess.open(stem + "_session_manifest.json", FileAccess.READ)
	var raw := FileAccess.open(path, FileAccess.READ)
	if not info or not raw:
		return "请选择同一目录中有配套会话清单的原始 JSONL。"
	var header = JSON.parse_string(info.get_as_text())
	if not header is Dictionary or header.get("game_name") != "pacman" or not header.has("session_id"):
		return "无法识别这份吃豆人会话清单。"
	if header.session_id != stem.get_file():
		return "文件名与会话清单中的 session_id 不一致。"
	manifest = header
	layouts = manifest.get("metadata", {}).get("maze_layouts", [Maze.ROWS] + Stages.LAYOUTS)
	var frame := -1
	var event := -1
	var level := 1
	while raw.get_position() < raw.get_length():
		var line := raw.get_line().strip_edges()
		if line.is_empty():
			continue
		var row = JSON.parse_string(line)
		var i := rows.size()
		if not row is Dictionary or not row.has_all(["event_id", "session_elapsed_usec", "event_tag", "payload"]) or not row.payload is Dictionary:
			return "原始记录第 %d 行格式有误。" % (i + 1)
		var time := int(row.session_elapsed_usec)
		if i > 0 and time < times[-1]:
			return "第 %d 行时间早于上一条记录。" % (i + 1)
		var p: Dictionary = row.payload
		level = int(p.get("level", level))
		if row.event_tag == "round_ready":
			frame = -1
		if row.event_tag == "frame_sample":
			if not p.has_all(["x", "y", "ghosts", "phase", "paused"]) or not p.ghosts is Array or p.ghosts.size() != 4:
				return "第 %d 行缺少轨迹字段。" % (i + 1)
			if int(p.phase) < 0 or int(p.phase) > 4:
				return "第 %d 行包含未知游戏阶段。" % (i + 1)
			for g in p.ghosts:
				if not g is Array or g.size() < 4:
					return "第 %d 行的幽灵轨迹无效。" % (i + 1)
			frame = i
			frames.append(i)
		elif row.get("event_type") == "gameplay":
			event = i
			events.append(i)
			if row.event_tag in ["pellet", "power_pellet", "task_item"]:
				if not removed.has(level):
					removed[level] = {}
				removed[level][Vector2i(int(p.tile_x), int(p.tile_y))] = i
		rows.append(row)
		times.append(time)
		levels.append(level)
		last_frame.append(frame)
		last_event.append(event)
	if rows.is_empty():
		return "原始记录为空。"
	if manifest.get("recording", {}).get("complete", false) and int(manifest.recording.written_events) != rows.size():
		return "清单与原始文件的记录条数不一致。"
	return ""

# Grid-space separation, not path length or evidence that a participant saw a ghost.
func nearest_threat(p: Dictionary) -> Array:
	if p.phase != 1 or p.paused:
		return []
	var best := INF
	var kind := -1
	for i in p.ghosts.size():
		var g: Array = p.ghosts[i]
		if int(g[2]) != 2 or g[3]:
			continue
		var dx := absf(p.x - g[0])
		if floori(p.y) == 14 and floori(g[1]) == 14:
			dx = minf(dx, Maze.WIDTH - dx)
		var dist := Vector2(dx, p.y - g[1]).length()
		if dist < best:
			best = dist
			kind = i
	return [kind, best] if kind >= 0 else []

func export_features() -> String:
	var path := stem + "_features.tsv"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return ""
	var columns := PackedStringArray(["session_id","event_id","time_us","event","level","x","y","score","key","pressed","phase","paused","nearest_roaming_ghost","distance_tiles","sample_gap_us","dx","dy","tick","life_index","heading_changed","step_displacement_tiles","tile_x","tile_y","lives","wave","power_left","freeze_left","double_left"])
	for ghost_name in ["blinky","pinky","inky","clyde"]:
		for field in ["x","y","state","scared"]:
			columns.append(ghost_name + "_" + field)
	file.store_csv_line(columns, "\t")
	var prev := -1 # previous sample row
	for i in rows.size():
		var r := rows[i]
		var p: Dictionary = r.payload
		var sample: bool = r.event_tag == "frame_sample"
		var nearest := nearest_threat(p) if sample else []
		var fields := PackedStringArray([manifest.session_id, r.event_id, str(times[i]), r.event_tag, str(levels[i])])
		for k in ["x","y","score","key","pressed","phase","paused"]:
			fields.append(str(p.get(k, "")))
		fields.append(str(nearest[0]) if nearest else "")
		fields.append(str(nearest[1]) if nearest else "")
		fields.append(str(times[i] - times[prev]) if sample and prev >= 0 else "")
		for k in ["dx","dy","tick","life_index","heading_changed"]:
			fields.append(str(p.get(k, "")))
		var displacement := ""
		if sample and prev >= 0 and p.has("tick"):
			var before: Dictionary = rows[prev].payload
			if p.tick == before.get("tick", -2) + 1 and p.get("life_index") == before.get("life_index") and p.phase == 1 and before.phase == 1 and not p.paused and not before.paused:
				var dx := absf(p.x - before.x)
				displacement = str(Vector2(minf(dx, Maze.WIDTH - dx), p.y - before.y).length())
		fields.append(displacement)
		for k in ["tile_x","tile_y","lives","wave","power_left","freeze_left","double_left"]:
			fields.append(str(p.get(k, "")))
		for k in 4:
			for field in 4:
				fields.append(str(p.ghosts[k][field]) if sample else "")
		file.store_csv_line(fields, "\t")
		if sample:
			prev = i
	file.flush()
	return path if file.get_error() == OK else ""

func annotation_dir() -> String:
	return stem + "_annotations"

func save_note(first: int, last: int, author: String, label: String) -> String:
	var dir := annotation_dir()
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return ""
	var path := dir.path_join("%s.json" % Crypto.new().generate_random_bytes(12).hex_encode())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f:
		return ""
	f.store_string(JSON.stringify({"version":1, "session_id":manifest.session_id,
		"annotator":author, "label":label, "start_event_id":rows[first].event_id,
		"end_event_id":rows[last].event_id, "start_usec":times[first], "end_usec":times[last]}, "\t"))
	f.flush()
	return path if f.get_error() == OK else ""
