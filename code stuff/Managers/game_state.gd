extends Node

signal day_or_action_changed
signal day_completed
signal final_turn_started
var just_started_new_day := false
var days_left := 5
var actions_left := 10
var final_turn_triggered := false
var day_complete_available := false
var ai_scores := {}
var should_reset_ai := false
var ai_responses := {}  # Character-specific last responses
var ai_emotions := {}   # Character-specific last emotions
var ai_genie_used := {}  # Character-specific genie mode usage tracking
var ai_get_out_states := {}  # Character-specific get out button visibility states

func use_action():
	if final_turn_triggered:
		return


	actions_left -= 1

	# ✅ Day complete - don't transition immediately, just flag it
	if actions_left <= 0:
		day_complete_available = true
		emit_signal("day_completed")
	else:
		emit_signal("day_or_action_changed")

func transition_to_next_day():
	day_complete_available = false
	var tree = get_tree()
	if tree:
		tree.change_scene_to_file("res://Scene stuff/Main/day_transition.tscn")

func end_game():
	var tree = get_tree()
	if tree:
		tree.change_scene_to_file("res://Scene stuff/Main/game_end.tscn")

func _input(event):
	# Handle F11 for window maximize toggle
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F11:
			toggle_window_size()

func toggle_window_size():
	var current_mode = DisplayServer.window_get_mode()
	if current_mode == DisplayServer.WINDOW_MODE_MAXIMIZED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
