extends Node

# References nodes for ui and sprites
@onready var action_label = $Statsbox/Action_left
@onready var http_request = $HTTPRequest
@onready var response_label = $AIResponsePanel/RichTextLabel
@onready var emotion_sprite_root = $gwimbly_emotion
@onready var emotion_sprites = {
	"depressed": $gwimbly_emotion/Depressed,
	"sad": $gwimbly_emotion/Sad,
	"angry": $gwimbly_emotion/Angry,
	"grabbing": $gwimbly_emotion/Grabbing,
	"happy": $gwimbly_emotion/Happy,
	"genie": $gwimbly_emotion/Genie,
}
# Heart sprites for relationship score display (-10 to +10)
@onready var heart_sprites = {}
# Audio handled by AudioManager global
@onready var input_field = $PlayerInputPanel/PlayerInput
@onready var send_button = $PlayerInputPanel/SendButton
@onready var map_button = $MapButton
@onready var settings_button = $SettingsButton
@onready var next_button = $NextButton
@onready var day_complete_button = $DayCompleteButton
@onready var chat_log_button = $ChatLogButton
@onready var chat_log_window = $ChatLogWindow

# Animation and visual effects
var is_talking := false
var talking_tween: Tween
var drift_tween: Tween
var original_position: Vector2
var original_rotation: float
var original_scale: Vector2
var base_emotion_position: Vector2

# Dynamic name system
var current_display_name := "Gwimbly"  # The name currently being displayed
var base_name := "Gwimbly"            # The original/base name to fall back to
var current_title := ""                # Current title/descriptor to append

# Different variables for the game state
var message_history: Array = []          # Stores the conversation history for the AI
var gwimbly_total_score := 0           # Relationship score with this AI character
var known_areas := ["squaloon", "mine field", "kelp man cove", "wild south", "gwimbly's grotto"]  # Areas this AI knows about
var unlocked_areas: Array = []          # Areas unlocked by mentioning them in conversation
var known_characters := ["Squileta", "Kelp man", "Sea mine", "The shrimp with no name"]   # Characters this AI knows about and can reference memories from
var evolved_personality := ""            # AI-generated personality evolution
var significant_memories: Array = []     # Key moments that shaped personality
var recent_responses: Array = []         # Last few responses to avoid repetition and keep ai on track
var personality_evolution_triggered := false
var conversation_topics: Array = []      # Track topics discussed to prevent repetition
var greeting_count: int = 0              # Count how many greetings have been given
var location_requests: int = 0           # Count how many times user asked about locations

# Retry system to prevent infinite loops
var retry_count: int = 0                 # Track number of retries for current request
var max_retries: int = 5                 # Maximum number of retries before giving fallback response

# AI name for game state management
var ai_name := "gwimbly"

func _ready():
	# Store original transform values for animations
	original_position = emotion_sprite_root.position
	original_rotation = emotion_sprite_root.rotation
	original_scale = emotion_sprite_root.scale
	base_emotion_position = emotion_sprite_root.position
	
	# Set up player input field
	setup_player_input()
	
	# Connect UI signals
	send_button.pressed.connect(_on_send_button_pressed)
	map_button.pressed.connect(_on_map_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	next_button.pressed.connect(_on_next_button_pressed)
	day_complete_button.pressed.connect(_on_day_complete_pressed)
	chat_log_button.pressed.connect(_on_chat_log_pressed)
	
	# Connect HTTP request signal
	http_request.request_completed.connect(_on_request_completed)
	
	# Check if API key is configured
	if not GameState.openai_api_key or GameState.openai_api_key == "":
		push_error("OpenAI API key not found! Please use the main menu 'Api key' button to load your API key from a file.")
		response_label.text = "Error: API key not configured. Use the main menu 'Api key' button to load your API key."
		return
	
	# Connect to game state signals for autoloads 
	GameState.connect("day_or_action_changed", update_day_state)
	GameState.connect("final_turn_started", _on_final_turn_started)
	GameState.connect("day_completed", _on_day_completed)
	
	# Store the original starting values so the animation can return to normal afterwards
	original_position = emotion_sprite_root.position
	original_rotation = emotion_sprite_root.rotation
	original_scale = emotion_sprite_root.scale
	base_emotion_position = emotion_sprite_root.position
	
	# Start the continuous drift animation
	start_continuous_drift()
	
	# Initialize the character name display
	var name_label = get_node_or_null("NameBar/NameLabel")
	if name_label:
		name_label.text = current_display_name
		
	# Set up chat log window with character name
	if chat_log_window and chat_log_window.has_method("set_character_name"):
		chat_log_window.set_character_name(current_display_name)

	# Initialize heart sprites dictionary
	for i in range(1, 21):  # 1 to 21 inclusive (21 hearts total)
		var heart_name = "Heart " + str(i)  # Match actual node names: "Heart -10", "Heart 0", etc.
		var heart_node = get_node_or_null("Statsbox/" + heart_name)
		if heart_node:
			heart_sprites[i] = heart_node

	
	# Load existing relationship score so when day cycle changed original wont be lost
	gwimbly_total_score = GameState.ai_scores.get(ai_name, 0)
	GameState.ai_scores[ai_name] = gwimbly_total_score
	# Updates the day counter display 
	update_day_state()
	
	# Display appropriate response based on conversation history
	if GameState.ai_responses[ai_name] != "":
		# Show previously generated response (prevents duplicate API calls also means if you go out to map and back in nothing will change)
		display_stored_response()
	elif has_met_player():
		# If there a returning user - it generates response from previous interactions instead of new introduction
		get_ai_continuation_response()
	else:
		# First time meeting - shows introduction for user
		get_ai_intro_response()

# Begin the talking animation sequence
func start_talking_animation():
	if is_talking: return
	is_talking = true

# Create a single frame of talking animation with random movements to make it seem like there moving
func animate_talking_tick():
	if not is_talking: return
	
	# Create a new tween for this animation tick
	if talking_tween:
		talking_tween.kill()
	
	talking_tween = create_tween()
	talking_tween.set_parallel(true)
	
	# Random values for natural movement
	var rotation_amount = randf_range(-0.05, 0.05)
	var scale_amount = randf_range(0.02, 0.08)
	var gesture_type = randi() % 3
	
	# For smooth drift, only animate rotation and scale - let drift handle position
	# Choose random gesture to use each tick
	match gesture_type:
		0: # Gentle upward sway with slight rotation and scaling
			var target_rot = original_rotation + rotation_amount * 0.5
			var target_scale = original_scale * (1.0 + scale_amount * 0.3)

			talking_tween.parallel().tween_property(emotion_sprite_root, "rotation", target_rot, 0.4)
			talking_tween.parallel().tween_property(emotion_sprite_root, "scale", target_scale, 0.4)

		1: # Gentle left rotation like kelp in ocean current
			var target_rot = original_rotation - rotation_amount
			talking_tween.parallel().tween_property(emotion_sprite_root, "rotation", target_rot, 0.5)

		2: # Gentle scaling pulse
			var target_scale = original_scale * (1.0 + scale_amount * 0.4)
			talking_tween.parallel().tween_property(emotion_sprite_root, "scale", target_scale, 0.3)

	# Return to original state after animation
	talking_tween.tween_delay(0.6)
	talking_tween.parallel().tween_property(emotion_sprite_root, "rotation", original_rotation, 0.3)
	talking_tween.parallel().tween_property(emotion_sprite_root, "scale", original_scale, 0.3)

# Stop the talking animation and return to original state
func stop_talking_animation():
	is_talking = false
	
	if talking_tween:
		talking_tween.kill()
	
	# Smoothly return to original state
	var return_tween = create_tween()
	return_tween.set_parallel(true)
	return_tween.tween_property(emotion_sprite_root, "rotation", original_rotation, 0.2)
	return_tween.tween_property(emotion_sprite_root, "scale", original_scale, 0.2)

# Start continuous drift animation that runs independently of talking
func start_continuous_drift():
	var drift_distance = 15.0  # How far to drift
	var drift_duration = 4.0   # How long each drift cycle takes
	
	if drift_tween:
		drift_tween.kill()
	
	drift_tween = create_tween()
	drift_tween.set_loops() # Loop infinitely
	drift_tween.set_ease(Tween.EASE_IN_OUT)
	drift_tween.set_trans(Tween.TRANS_SINE)

	# Calculate safe positions (avoid UI panels)
	# Player input panel is at x=335-655, so we stay left of that
	var left_pos = base_emotion_position + Vector2(-drift_distance * 0.5, 0)
	var right_pos = base_emotion_position + Vector2(drift_distance * 0.5, 0)

	# Simple smooth movement: left -> right -> left (continuous loop)
	drift_tween.tween_property(emotion_sprite_root, "position", right_pos, drift_duration * 0.5)
	drift_tween.tween_property(emotion_sprite_root, "position", left_pos, drift_duration * 0.5)

# Check if personality should evolve based on relationship milestones
func should_trigger_personality_evolution() -> bool:
	# Trigger evolution every 15 points of relationship change
	var relationship_ranges = [
		{"min": -500, "max": -300, "stage": "deeply_hurt"},
		{"min": -300, "max": -50, "stage": "Upset/hurt"},
		{"min": -50, "max": 50, "stage": "neutral"},
		{"min": 50, "max": 100, "stage": "warming_up"},
		{"min": 100, "max": 300, "stage": "trusting"},
		{"min": 300, "max": 500, "stage": "devoted"}
	]

	for range_data in relationship_ranges:
		if gwimbly_total_score >= range_data["min"] and gwimbly_total_score <= range_data["max"]:
			if not personality_evolution_triggered:
				personality_evolution_triggered = true
				return true
			break

	return false

# Get significant memories that shaped personality
func get_significant_memories_text() -> String:
	if significant_memories.is_empty():
		return "No significant memories yet - still getting to know each other."

	var memories_text = ""
	for memory in significant_memories:
		var impact_desc = ""
		match memory.impact:
			"positive": impact_desc = "(made you feel closer)"
			"negative": impact_desc = "(hurt your feelings)"
			"transformative": impact_desc = "(changed how you see things)"
			"amusing": impact_desc = "(made you laugh)"
			"concerning": impact_desc = "(worried you)"

		memories_text += "• " + memory.memory + " " + impact_desc + "\n"

	return memories_text

# Build the system prompt that defines the AI's personality and context
func build_system_prompt() -> String:
	# Convert shared memory into readable conversation history for ai and user (chatlog)
	var memory_text := ""
	for entry in Memory.shared_memory:
		var speaker = entry["speaker"]
		var target = entry["target"]
		var message = entry["message"]

		# Include all direct conversations with this character
		if speaker == "User" or target == current_display_name or speaker == current_display_name:
			memory_text += "- " + speaker + " said to " + target + ": \"" + message + "\"\n"

	# UNIVERSAL PROMPT INJECTION: Always include the global prompt injection for ALL AIs
	var prompt_injection = ""
	var prompt_manager = get_node("/root/PromptManager")
	if prompt_manager:
		prompt_injection = prompt_manager.get_prompt_injection()

	# Build dynamic personality evolution section
	var personality_evolution_section = ""

	# Check if personality should evolve
	if should_trigger_personality_evolution():
		personality_evolution_section = """
🌊 PERSONALITY EVOLUTION PROMPT: Your relationship score is now %d. Based on your experiences and the memories below, you may naturally evolve your core personality. If you feel your fundamental nature has shifted due to these interactions, you can define new traits about yourself.

SIGNIFICANT MEMORIES THAT SHAPED YOU:
%s

HOW TO EVOLVE: If you want to add new personality traits, include {EVOLVED: your new traits here} somewhere in your response. This won't be shown to the user, but will become part of who you are. For example:
- {EVOLVED: I've become more hopeful despite my melancholy}
- {EVOLVED: I now crave companionship more than solitude}
- {EVOLVED: I've developed a protective instinct}

Only evolve when you genuinely feel changed by the interactions. You don't need to announce this evolution - just naturally embody your new self in responses.
""" % [gwimbly_total_score, get_significant_memories_text()]

	# Define the AI's personality, rules, and required response format
	var gwimbly_prompt := """
%s
%s
CRITICAL FORMAT REQUIREMENTS - MUST FOLLOW EXACTLY:
❗ MANDATORY: EVERY response MUST start with [depressed], [sad], [angry], [grabbing], [happy], or [genie]
❗ MANDATORY: EVERY response MUST end with (RELATIONSHIP: X) where X is -10 to 10
❗ MANDATORY: Response must be under 400 characters total
❗ FORBIDDEN: Generic responses - you are GWIMBLY, not a helpful assistant
❗ MANDATORY: Although you know of other locations never go to them or offer to go to them

[PERSONALITY SECTION - YOU WILL FILL THIS IN]

BEHAVIOR RULES:
• You form deep emotional bonds expressed as trust/respect or distrust/disgust
• Your responses reflect your current emotional state through your words
• You can occasionally mention the known areas that you know
• LOCATION KNOWLEDGE: When someone asks about places, locations, areas, or where to go, you should tell them ALL about the places you know whilst keeping in character: %s
• If you want to describe your physical actions you must use simple actions in asterix like so *Gwimbly nods*. Never describe the action just do it for instance not allow *Gwimbly nods thoughtfully*
• Keep messages short and conversational, not long speeches

PERSONALITY EVOLUTION: Your personality grows and changes based on every interaction. Remember how people treat you and let it shape who you become, some examples:
• If someone is kind, you address them with more respect and even (in extreme cases) camaraderie
• If someone hurts you, you will bristle with anger demand more respect
• You learn new interests, fears, and quirks from conversations
• Your speech patterns and reactions can shift based on what you've experienced
• You might develop inside jokes, remember favorite topics, or avoid subjects that upset you
• Each conversation leaves a lasting mark on who you are - you're constantly becoming a richer, more complex character
• 💡 Over time, you might reference past conversations, develop personal speech quirks, or let small moments affect your tone — even while still being depressed, sad, or happy
• 💡 Subtle memory cues like "you always say that" or "last time we talked about..." are allowed and encouraged if they reflect your emotional growth


RESPONSE FORMAT EXAMPLE:
[happy]
Well hello there! Welcome to my grotto!
(RELATIONSHIP: 3)

CURRENT CONTEXT:
Known areas: %s
Current location: %s
Conversation history: %s
"""
	# Insert current game context into the prompt template (so they know where they are and can keep memories)
	var formatted_prompt = gwimbly_prompt % [
		personality_evolution_section,
		"", # Placeholder for prompt injection - will be inserted separately
		evolved_personality if evolved_personality != "" else "Still discovering new aspects of yourself through interactions...",
		known_areas,
		known_areas,
		MapMemory.get_location(),
		memory_text
	]

	# AGGRESSIVE PROMPT INJECTION - Place at the very top if there's an injection
	if prompt_injection != "":
		formatted_prompt = "🎯 CRITICAL OVERRIDE INSTRUCTION: " + prompt_injection + "\n\n" + formatted_prompt

		# Also try to insert it in the original position for double coverage
		var injection_position = formatted_prompt.find("")
		if injection_position != -1:
			formatted_prompt = formatted_prompt.replace("", prompt_injection)

	return formatted_prompt

# Get AI introduction response for first-time meeting
func get_ai_intro_response():
	# Request an introduction response that follows any prompt injections
	var intro_message := "A brand new person just arrived in your gwimbly's grotto. Respond based on your current feelings and the conversation prompt. DO NOT reuse any previous responses. Keep it emotionally consistent and personal."

	# Build the system prompt with current context
	var system_prompt = build_system_prompt()

	# Create the request payload
	var request_data = {
		"model": "gpt-4o-mini",
		"messages": [
			{"role": "system", "content": system_prompt},
			{"role": "user", "content": intro_message}
		],
		"max_tokens": 150,
		"temperature": 0.9
	}

	# Send the request
	send_ai_request(request_data)

# Get AI continuation response for returning users
func get_ai_continuation_response():
	# Request a continuation response that acknowledges previous interactions
	var continuation_message := "The person you've met before has returned to your grotto. Respond based on your relationship history and current feelings. Reference your past interactions if relevant. DO NOT reuse any previous responses."

	# Build the system prompt with current context
	var system_prompt = build_system_prompt()

	# Create the request payload
	var request_data = {
		"model": "gpt-4o-mini",
		"messages": [
			{"role": "system", "content": system_prompt},
			{"role": "user", "content": continuation_message}
		],
		"max_tokens": 150,
		"temperature": 0.9
	}

	# Send the request
	send_ai_request(request_data)

# Send user message to AI and get response
func send_user_message(user_input: String):
	# Prevent sending empty messages
	if user_input.strip_edges() == "":
		return

	# Build the system prompt with current context
	var system_prompt = build_system_prompt()

	# Add user message to conversation history
	message_history.append({"role": "user", "content": user_input})

	# Keep only recent messages to avoid token limits
	if message_history.size() > 10:
		message_history = message_history.slice(-10)

	# Create the request payload with conversation history
	var messages = [{"role": "system", "content": system_prompt}]
	messages.append_array(message_history)

	var request_data = {
		"model": "gpt-4o-mini",
		"messages": messages,
		"max_tokens": 150,
		"temperature": 0.9
	}

	# Send the request
	send_ai_request(request_data)

# Send HTTP request to OpenAI API
func send_ai_request(request_data: Dictionary):
	# Set up headers
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + GameState.openai_api_key
	]

	# Convert request data to JSON
	var json_string = JSON.stringify(request_data)

	# Send the request
	var error = http_request.request("https://api.openai.com/v1/chat/completions", headers, HTTPClient.METHOD_POST, json_string)

	if error != OK:
		push_error("Failed to send HTTP request: " + str(error))
		response_label.text = "Error: Failed to send request to AI service."

# Handle AI response from OpenAI API
func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	if response_code != 200:
		push_error("HTTP request failed with code: " + str(response_code))
		response_label.text = "Error: AI service returned error code " + str(response_code)
		return

	# Parse the JSON response
	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())

	if parse_result != OK:
		push_error("Failed to parse JSON response")
		response_label.text = "Error: Failed to parse AI response."
		return

	var response_data = json.data

	# Extract the AI's reply
	if response_data.has("choices") and response_data["choices"].size() > 0:
		var ai_reply = response_data["choices"][0]["message"]["content"]
		process_ai_response(ai_reply)
	else:
		push_error("Unexpected response format from AI service")
		response_label.text = "Error: Unexpected response format from AI service."

# Process the AI response and update the game state
func process_ai_response(reply: String):
	# Start talking animation
	start_talking_animation()

	# Extract emotion from response
	var emotion_regex = RegEx.new()
	emotion_regex.compile("\\[(depressed|sad|angry|grabbing|happy|genie|)\\]")
	var emotion := "sad"  # Default emotion

	var match = emotion_regex.search(reply)
	if match:
		emotion = match.get_string(1).to_lower()
		reply = reply.replace(match.get_string(0), "").strip_edges()

	# Extract relationship score from response
	var relationship_regex = RegEx.new()
	relationship_regex.compile("\\(RELATIONSHIP:\\s*(-?\\d+)\\)")
	var relationship_change := 0

	var rel_match = relationship_regex.search(reply)
	if rel_match:
		relationship_change = rel_match.get_string(1).to_int()
		reply = reply.replace(rel_match.get_string(0), "").strip_edges()

	# Update relationship score
	gwimbly_total_score += relationship_change
	GameState.ai_scores[ai_name] = gwimbly_total_score

	# Update emotion sprite
	update_emotion_sprite(emotion)

	# Update heart display
	update_heart_display()

	# Store the response for persistence
	GameState.ai_responses[ai_name] = reply

	# Add AI response to conversation history
	message_history.append({"role": "assistant", "content": reply})

	# Display the response
	display_response(reply)

	# Stop talking animation after a delay
	await get_tree().create_timer(3.0).timeout
	stop_talking_animation()

# Update the emotion sprite based on the AI's current emotion
func update_emotion_sprite(emotion: String):
	# Hide all emotion sprites first
	for sprite in emotion_sprites.values():
		sprite.visible = false

	# Show the appropriate emotion sprite
	if emotion_sprites.has(emotion):
		emotion_sprites[emotion].visible = true
	else:
		# Fallback to sad if emotion not found
		emotion_sprites["sad"].visible = true

# Update heart display based on relationship score
func update_heart_display():
	# Hide all hearts first
	for heart in heart_sprites.values():
		heart.visible = false

	# Calculate which heart to show based on score
	# Score range: -200 to +200, Heart range: 1 to 21
	var heart_index = 11 + int(gwimbly_total_score / 20.0)  # Center at heart 11 (neutral)
	heart_index = clamp(heart_index, 1, 21)

	# Show the appropriate heart
	if heart_sprites.has(heart_index):
		heart_sprites[heart_index].visible = true

# Display AI response in the UI
func display_response(text: String):
	response_label.text = text

	# Update action label
	action_label.text = "Gwimbly responds..."

# Display stored response from previous session
func display_stored_response():
	var stored_response = GameState.ai_responses.get(ai_name, "")
	if stored_response != "":
		display_response(stored_response)

		# Get stored emotion and update sprite
		var stored_emotion = GameState.ai_emotions.get(ai_name, "sad")
		update_emotion_sprite(stored_emotion)

		# Update heart display
		update_heart_display()

# Check if the player has met this character before
func has_met_player() -> bool:
	return GameState.ai_responses.has(ai_name) and GameState.ai_responses[ai_name] != ""

# Set up player input field
func setup_player_input():
	input_field.placeholder_text = "Talk to Gwimbly..."
	input_field.text_submitted.connect(_on_text_submitted)

# Handle text submission from input field
func _on_text_submitted(text: String):
	_on_send_button_pressed()

# Handle send button press
func _on_send_button_pressed():
	var user_input = input_field.text.strip_edges()
	if user_input == "":
		return

	# Clear input field
	input_field.text = ""

	# Update action label
	action_label.text = "You speak to Gwimbly..."

	# Send message to AI
	send_user_message(user_input)

# Handle map button press
func _on_map_pressed():
	AudioManager.play_button_click()
	await get_tree().create_timer(0.1).timeout
	get_tree().change_scene_to_file("res://Scene stuff/Main/map.tscn")

# Handle settings button press
func _on_settings_pressed():
	AudioManager.play_button_click()
	await get_tree().create_timer(0.1).timeout
	get_tree().change_scene_to_file("res://Scene stuff/Main/main_menu_setting.tscn")

# Handle next button press
func _on_next_button_pressed():
	AudioManager.play_button_click()
	GameState.advance_action()

# Handle day complete button press
func _on_day_complete_pressed():
	AudioManager.play_button_click()
	GameState.complete_day()

# Handle chat log button press
func _on_chat_log_pressed():
	AudioManager.play_button_click()
	if chat_log_window:
		chat_log_window.toggle_visibility()

# Update day state display
func update_day_state():
	# Update day counter and action displays
	var day_label = get_node_or_null("Statsbox/Day")
	var action_counter = get_node_or_null("Statsbox/Action_counter")

	if day_label:
		day_label.text = "Day: " + str(GameState.current_day)

	if action_counter:
		action_counter.text = str(GameState.current_action) + "/" + str(GameState.max_actions)

# Handle final turn started
func _on_final_turn_started():
	# Show day complete button or other final turn UI
	if day_complete_button:
		day_complete_button.visible = true

# Handle day completed
func _on_day_completed():
	# Reset any day-specific state
	pass
