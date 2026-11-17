extends "res://addons/psygodot/psych_runtime.gd"

const MARKERS = preload("res://telemetry/marker_config.json")
var mock_markers := false

func begin(game) -> void:
	var args := OS.get_cmdline_user_args()
	mock_markers = "--psygodot-markers" in args
	var config := {
		"game_name": "pacman", "study_id": "pacman", "marker_config": MARKERS.data,
		"metadata": {"marker_driver": "mock" if mock_markers else "off",
			"runtime_revision": "c91ead6f67b397e5f7c5fdb098f446acbed68ef5",
			"physics_ticks_per_second": Engine.physics_ticks_per_second}
	}
	for arg in args:
		if arg.begins_with("--participant="):
			config["participant_label"] = arg.trim_prefix("--participant=")
		elif arg.begins_with("--output-dir="):
			config["output_dir"] = arg.trim_prefix("--output-dir=")
	if start_session(config).is_empty():
		push_error("PsyGodot could not start the Pac-Man recording.")
		return
	if "--psygodot-frames" in args:
		register_frame_sampler(game.capture_state, 6)
	print("PsyGodot recording: ", ProjectSettings.globalize_path(get_raw_events_path()))

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
