extends SceneTree

const Recording = preload("res://replay/recording.gd")
var failures := 0

func check(ok: bool, description: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL ", description)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	# Use an isolated fixture with a tunnel crossing, a frightened ghost and an event-only pickup.
	var dir := ProjectSettings.globalize_path("user://replay-tests").path_join(Crypto.new().generate_random_bytes(8).hex_encode())
	DirAccess.make_dir_recursive_absolute(dir)
	var stem := dir.path_join("test")
	var path := stem + "_raw_events.jsonl"
	var file := FileAccess.open(path, FileAccess.WRITE)
	var events := [
		["round_ready", {"level":1, "tile_x":14, "tile_y":23}],
		["pellet", {"level":1, "tile_x":1, "tile_y":1}],
		["frame_sample", {"x":0.25, "y":14.5, "level":1, "phase":1, "paused":false,
			"ghosts":[[27.75,14.5,2,false],[0.25,14.5,2,true],[1,1,0,false],[1,1,3,false]]}],
	]
	for i in events.size():
		file.store_line(JSON.stringify({"event_id":"EV_%d" % i, "session_elapsed_usec":i * 10000,
			"event_type":"frame" if i == 2 else "gameplay", "event_tag":events[i][0], "payload":events[i][1]}))
	file.close()
	var mf := FileAccess.open(stem + "_session_manifest.json", FileAccess.WRITE)
	mf.store_string(JSON.stringify({"game_name":"pacman","session_id":"test","recording":{"complete":true,"written_events":3}}))
	mf.close()
	var source_hash := FileAccess.get_sha256(path)
	var viewer = preload("res://replay/viewer.tscn").instantiate()
	root.add_child(viewer)
	check(viewer.open_recording(path) == "", "read session")
	check(viewer.data.last_frame[1] == -1, "no invented trajectory before first sample")
	viewer.step_record(1)
	check(viewer.index == 2 and viewer.data.nearest_threat(viewer.data.rows[2].payload) == [0, 0.5], "tunnel distance excludes frightened ghost")
	viewer.get_node("Controls/Inputs/Author").text = "tester"
	viewer.get_node("Controls/Inputs/Label").text = "test interval"
	viewer.start_index = 1
	viewer.save_annotation()
	check(viewer.note_rows == [1], "reloaded annotation anchors")
	check(viewer.data.export_features() == stem + "_features.tsv", "feature export")
	check(FileAccess.get_sha256(path) == source_hash, "analysis preserves raw observations")
	viewer.queue_free()
	await process_frame
	for name in DirAccess.get_files_at(stem + "_annotations"):
		DirAccess.remove_absolute((stem + "_annotations").path_join(name))
	DirAccess.remove_absolute(stem + "_annotations")
	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(name))
	DirAccess.remove_absolute(dir)
	if failures == 0:
		print("PASS replay seek, features, annotations and raw integrity")
	quit(1 if failures else 0)
