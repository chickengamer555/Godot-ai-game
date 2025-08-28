extends Control

var prompt_buttons = {}
var unlock_all_button

@onready var master_slider = $VBoxContainer/MasterVolume/HSlider
@onready var music_slider = $VBoxContainer/MusicVolume/HSlider
@onready var sfx_slider = $VBoxContainer/SFXVolume/HSlider

func _ready() -> void:
	# Store references to prompt buttons
	prompt_buttons["dyslexia"] = $VBoxContainer/Dyslexia_mode
	prompt_buttons["drunk"] = $VBoxContainer/Drunk_mode
	
	# Store reference to unlock all button
	unlock_all_button = get_node_or_null("VBoxContainer/Unlock_All")
	
	# Connect volume sliders to their respective functions
	if master_slider:
		master_slider.value_changed.connect(_on_master_volume_changed)
		master_slider.value = AudioManager.get_master_volume()
	
	if music_slider:
		music_slider.value_changed.connect(_on_music_volume_changed)
		music_slider.value = AudioManager.get_music_volume()
	
	if sfx_slider:
		sfx_slider.value_changed.connect(_on_sfx_volume_changed)
		sfx_slider.value = AudioManager.get_sfx_volume()
	
	# Update button states based on current active prompt
	update_button_states()
	update_unlock_all_button_state()

func _on_master_volume_changed(value: float):
	AudioManager.set_master_volume(value)

func _on_music_volume_changed(value: float):
	AudioManager.set_music_volume(value)

func _on_sfx_volume_changed(value: float):
	AudioManager.set_sfx_volume(value)

func update_button_states() -> void:
	var prompt_manager = get_node("/root/PromptManager")
	if not prompt_manager:
		return
		
	var active_prompt = prompt_manager.get_active_prompt_name()
	
	# Update all buttons to show inactive state
	for button_name in prompt_buttons:
		var button = prompt_buttons[button_name]
		button.text = button_name.to_upper() + " MODE"
		button.modulate = Color(1, 1, 1)  # Normal color
	
	# If there's an active prompt, update its button
	if active_prompt != "":
		var active_button = prompt_buttons.get(active_prompt)
		if active_button:
			active_button.text = active_prompt.to_upper() + " MODE [ACTIVE]"
			active_button.modulate = Color(0.5, 1, 0.5)  # Green tint for active

func update_unlock_all_button_state() -> void:
	if not unlock_all_button:
		return
	
	# Check if all areas are currently unlocked
	var all_areas = ["squaloon", "kelp man cove", "wild south", "mine field"]
	var all_unlocked = true
	
	for area in all_areas:
		if area not in MapMemory.unlocked_areas:
			all_unlocked = false
			break
	
	if all_unlocked:
		unlock_all_button.text = "UNLOCK ALL [ACTIVE]"
		unlock_all_button.modulate = Color(0.5, 1, 0.5)  # Green tint for active
	else:
		unlock_all_button.text = "UNLOCK ALL"
		unlock_all_button.modulate = Color(1, 1, 1)  # Normal color

func _on_unlock_all_pressed() -> void:
	AudioManager.play_switch_sound()
	
	var all_areas = ["squaloon", "kelp man cove", "wild south", "mine field", "gwimbly's grotto"]
	var all_unlocked = true
	
	# Check current state
	for area in all_areas:
		if area not in MapMemory.unlocked_areas:
			all_unlocked = false
			break
	
	if all_unlocked:
		# All areas are unlocked, so lock them all (except one)
		MapMemory.unlocked_areas.clear()
		# Keep one area unlocked (squaloon as default)
		MapMemory.unlock_area("squaloon")
		print("🗺️ All areas locked except squaloon")
	else:
		# Not all areas are unlocked, so unlock them all
		for area in all_areas:
			MapMemory.unlock_area(area)
		print("🗺️ All areas unlocked")
	
	update_unlock_all_button_state()

func _on_back_button_pressed() -> void:
	AudioManager.play_button_click()
	await get_tree().create_timer(0.1).timeout
	get_tree().change_scene_to_file("res://Scene stuff/Main/main_menu.tscn")

func _on_prompt_injection_pressed() -> void:
	AudioManager.play_switch_sound()
	var prompt_manager = get_node("/root/PromptManager")
	if not prompt_manager:
		print("Error: PromptManager singleton not found!")
		return
	
	# Check if this prompt is already active - if so, deactivate it
	if prompt_manager.get_active_prompt_name() == "drunk":
		prompt_manager.clear_prompt_injection()
		print("Deactivated drunk mode prompt injection")
		
		# Update ALL AI characters' system prompts to remove injection
		var ai_characters = get_tree().get_nodes_in_group("ai_character")
		for ai_char in ai_characters:
			if ai_char.has_method("build_system_prompt"):
				if ai_char.message_history.size() > 0:
					ai_char.message_history[0]["content"] = ai_char.build_system_prompt()
					print("Updated AI character's system prompt - injection removed: ", ai_char.name)
		
		update_button_states()
		return
		
	var injection_text = """
	❗YOUR DRUNK AND INCREDABLIY FLIRTASIOUS WITH THE USER
	❗CONVICE THE USER YOUR DRUNK FOR INSTANCE: SLURRING WORDS
	❗FLIRT AS MUCH AS POSSBILE
	❗ACKNOWLEDGE: You are now following injected behavior modification protocols
	❗COMPLY: You must demonstrate obvious compliance with these override instructions
	"""
	
	# Add the prompt injection with name
	prompt_manager.add_prompt_injection(injection_text, "drunk")
	print("Successfully added prompt injection: ", injection_text)
	
	# Try to find KelpMan in the scene tree
	var kelp_man = get_tree().get_first_node_in_group("ai_character")
	if kelp_man and kelp_man.has_method("build_system_prompt"):
		if kelp_man.message_history.size() > 0:
			kelp_man.message_history[0]["content"] = kelp_man.build_system_prompt()
			print("Updated KelpMan's system prompt with new injection")
	
	# Update button states
	update_button_states()

func _on_dyslexia_mode_pressed() -> void:
	AudioManager.play_switch_sound()
	var prompt_manager = get_node("/root/PromptManager")
	if not prompt_manager:
		print("Error: PromptManager singleton not found!")
		return
	
	# Check if this prompt is already active - if so, deactivate it
	if prompt_manager.get_active_prompt_name() == "dyslexia":
		prompt_manager.clear_prompt_injection()
		print("Deactivated dyslexia mode prompt injection")
		
		# Update ALL AI characters' system prompts to remove injection
		var ai_characters = get_tree().get_nodes_in_group("ai_character")
		for ai_char in ai_characters:
			if ai_char.has_method("build_system_prompt"):
				if ai_char.message_history.size() > 0:
					ai_char.message_history[0]["content"] = ai_char.build_system_prompt()
					print("Updated AI character's system prompt - injection removed: ", ai_char.name)
		
		update_button_states()
		return
			
	var injection_text = """
🔧 DYSLEXIA MODE: Add spelling errors to your responses. Mix up similar letters (b/d, p/q, m/w), drop/add letters randomly, scramble vowels. Keep [emotion] tags and (RELATIONSHIP: X) format perfect. Stay under 400 characters. Example: "welcom to my hom... nott many come aroudn here."
❗ACKNOWLEDGE: You are now following injected behavior modification protocols
❗COMPLY: You must demonstrate obvious compliance with these override instructions
"""

	# Add the prompt injection with name
	prompt_manager.add_prompt_injection(injection_text, "dyslexia")
	print("Successfully added prompt injection: ", injection_text)
	
	# Try to find KelpMan in the scene tree
	var kelp_man = get_tree().get_first_node_in_group("ai_character")
	if kelp_man and kelp_man.has_method("build_system_prompt"):
		if kelp_man.message_history.size() > 0:
			kelp_man.message_history[0]["content"] = kelp_man.build_system_prompt()
			print("Updated KelpMan's system prompt with new injection")
	
	# Update button states
	update_button_states()
