extends "res://addons/psygodot/psych_runtime.gd"

const MARKERS = preload("res://telemetry/marker_config.json")
var mock_markers := false
var participant_label := ""

static func output_directory() -> String:
	var game_dir := OS.get_executable_path().get_base_dir() if OS.has_feature("template") else ProjectSettings.globalize_path("res://")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output-dir="):
			var path := arg.trim_prefix("--output-dir=").strip_edges()
			if not path.is_empty():
				if path.is_absolute_path():
					return ProjectSettings.globalize_path(path).simplify_path()
				return game_dir.path_join(path).simplify_path()
	return game_dir.path_join("output").simplify_path()

func begin(game) -> bool:
	var args := OS.get_cmdline_user_args()
	mock_markers = "--psygodot-markers" in args
	var config := {
		"game_name": "pacman", "study_id": "pacman", "marker_config": MARKERS.data,
		"participant_label": participant_label if not participant_label.is_empty() else "anonymous",
		"output_dir": output_directory(),
		"metadata": {"marker_driver": "mock" if mock_markers else "off",
			"runtime_revision": "c91ead6f67b397e5f7c5fdb098f446acbed68ef5",
			"physics_ticks_per_second": Engine.physics_ticks_per_second}
	}
	if DirAccess.make_dir_recursive_absolute(config["output_dir"]) != OK or start_session(config).is_empty():
		push_error("PsyGodot could not start the Pac-Man recording.")
		return false
	if "--psygodot-frames" in args:
		register_frame_sampler(game.capture_state, 6)
	print("PsyGodot recording: ", ProjectSettings.globalize_path(get_raw_events_path()))
	return true

func observe(tag: String, data: Dictionary, timestamp: int) -> void:
	if mock_markers:
		log_event_with_marker("gameplay", tag, data, timestamp)
	else:
		log_event("gameplay", tag, data, timestamp)

func _exit_tree() -> void:
	super()
	var stats := get_statistics()
	if not stats.complete:
		push_error("Incomplete PsyGodot recording: " + str(stats))
