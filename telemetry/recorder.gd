extends "res://addons/psygodot/psych_runtime.gd"

const MARKERS = preload("res://telemetry/marker_config.json")
var mock_markers := false
var participant_label := ""

static func output_directory() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output-dir="):
			return arg.trim_prefix("--output-dir=")
	return SessionManagerScript.DEFAULT_OUTPUT_DIR

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
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory())) != OK or start_session(config).is_empty():
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
