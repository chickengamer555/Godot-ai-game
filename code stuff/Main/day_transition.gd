extends Control

@onready var transition_panel = $TransitionPanel
@onready var day_complete_label = $TransitionPanel/VBoxContainer/DayCompleteLabel
@onready var summary_label = $TransitionPanel/VBoxContainer/SummaryLabel
@onready var next_day_button = $TransitionPanel/VBoxContainer/NextDayButton
@onready var animation_player = $AnimationPlayer

var current_day: int
var is_final_day: bool = false

func _ready():
	setup_transition()
	animate_in()

func setup_transition():
	# Calculate current day for display - fixed for 10 day system
	current_day = 6 - GameState.days_left
	is_final_day = GameState.days_left <= 1
	
	# Update labels based on day
	if is_final_day:
		day_complete_label.text = "Final Day Complete!"
		summary_label.text = "Your underwater journey has come to an end.\nTime to surface and see what you've accomplished."
		next_day_button.text = "View Results"
	else:
		day_complete_label.text = "Day %d Complete!" % current_day
		summary_label.text = "You've finished all your actions for today.\nThe deep ocean grows quiet as you rest.\nTime to prepare for tomorrow's adventures."
		next_day_button.text = "Continue to Day %d" % (current_day + 1)

func animate_in():
	# Start with panel off-screen and fade in
	transition_panel.modulate.a = 0.0
	transition_panel.scale = Vector2(0.8, 0.8)
	
	# Create smooth fade-in animation
	var tween = create_tween()
	tween.set_parallel(true)
	
	tween.tween_property(transition_panel, "modulate:a", 1.0, 0.5)
	tween.tween_property(transition_panel, "scale", Vector2(1.0, 1.0), 0.5)
	tween.tween_property(transition_panel, "position:y", transition_panel.position.y + 20, 0.5)
	
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)

func animate_out():
	# Animate panel out
	var tween = create_tween()
	tween.set_parallel(true)
	
	tween.tween_property(transition_panel, "modulate:a", 0.0, 0.3)
	tween.tween_property(transition_panel, "scale", Vector2(0.8, 0.8), 0.3)
	
	tween.set_ease(Tween.EASE_IN)
	
	await tween.finished

func _on_next_day_pressed():
	AudioManager.play_button_click()
	next_day_button.disabled = true
	
	await animate_out()
	
	if is_final_day:
		# Go to end game scene
		GameState.end_game()
	else:
		# Proceed to next day
		GameState.days_left -= 1
		GameState.actions_left = 10
		GameState.just_started_new_day = true
		
		# Transition to map
		get_tree().change_scene_to_file("res://Scene stuff/Main/map.tscn")

# Handle escape key to continue (optional)
func _input(event):
	if event.is_action_pressed("ui_cancel") and next_day_button.visible and not next_day_button.disabled:
		_on_next_day_pressed() 
