extends Node

# Reffrences nodes for ui and sprites
@onready var action_label = $Statsbox/Action_left
@onready var http_request = $HTTPRequest
@onready var response_label = $AIResponsePanel/RichTextLabel
@onready var emotion_sprite_root = $sea_mine_emotion
@onready var emotion_sprites = {
	"disgruntled": $sea_mine_emotion/Disgruntled,
	"neutral": $sea_mine_emotion/Neutral,
	"amusment": $sea_mine_emotion/Amusment,
	"really angry": $sea_mine_emotion/"Really angry",
	"extremely angry": $sea_mine_emotion/"Extremly angry",
	"exploding": $sea_mine_emotion/Exploding,
	"dead": $sea_mine_emotion/Dead,
}
# Heart sprites for relationship score display (-10 to +10)
@onready var heart_sprites = {}
# Audio handled by AudioManager global
@onready var input_field = $PlayerInputPanel/PlayerInput
@onready var chat_log_window = $ChatLogWindow
@onready var day_complete_button = $DayCompleteButton
@onready var next_button = $HBoxContainer/NextButton
@onready var leave_button = $LeaveButton
# Varibles for editor
@export var ai_name := "Sea mine"
@export var max_input_chars := 200  # Maximum characters allowed in player input
@export var max_input_lines := 3    # Maximum lines allowed in player input
@export var talk_move_intensity := 15.0      # How much the sprite moves during animation
@export var talk_rotation_intensity := 0.25  # How much the sprite rotates during animation
@export var talk_scale_intensity := 0.08     # How much the sprite scales during animation
@export var talk_animation_speed := 0.8      # Speed of talking animations

# Simple drift animation variables
@export var drift_enabled := true           # Enable/disable the drift animation
@export var drift_distance := 100.0         # How far left/right the sprite drifts
@export var drift_duration := 15           # How long each drift cycle takes (seconds)
var drift_tween: Tween                       # Simple tween for drift animation
var base_emotion_position: Vector2           # Store the original emotion sprite position

# Dynamic name system
var current_display_name := "Sea mine"  # The name currently being displayed
var base_name := "Sea mine"            # The original/base name to fall back to
var current_title := ""                # Current title/descriptor to append

# Different variables for the game state
var message_history: Array = []          # Stores the conversation history for the AI
var sea_mine_total_score := 0           # Relationship score with this AI character
var known_areas := ["squaloon", "mine field", "kelp man cove", "wild south"]  # Areas this AI knows about
var unlocked_areas: Array = []          # Areas unlocked by mentioning them in conversation
var known_characters := ["Squileta", "Kelp man", "The shrimp with no name"]   # Characters this AI knows about and can reference memories from

# Dynamic personality evolution system
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

# Anger tracking system
var current_anger_level: String = "disgruntled"  # Track current anger state
var anger_response_count: int = 0        # How many responses at current anger level
var received_warnings: int = 0           # How many warning responses given



# Varibles for "animation"
var is_talking := false          # Whether the character is currently talking
var original_position: Vector2   # Starting position 
var original_rotation: float     # Starting rotation
var original_scale: Vector2      # Starting scale
var talking_tween: Tween         # Tween object for animations
var MODEL = "gpt-4o" #Model ai used  

#All these will run at start sort of preping the game 
func _ready():
	add_to_group("ai_character")
	setup_player_input() # Sets up player input field to prevent scrolling and limit text - do this first!
	
	# Check if API key is choosen if it isnet theres error prevention showing what youve done wrong
	if not ApiManager.has_api_key():
		push_error("OpenAI API key not found! Please use the main menu 'Api key' button to load your API key from a file.")
		response_label.text = "Error: API key not configured. Use the main menu 'Api key' button to load your API key."
		return
	
	# Connect to game state signals for autoloads 
	GameState.connect("day_or_action_changed", update_day_state)
	GameState.connect("final_turn_started", _on_final_turn_started)
	GameState.connect("day_completed", _on_day_completed)
	
	# Store the original starting values so the animation can reutrn to normal afterwards
	original_position = emotion_sprite_root.position
	original_rotation = emotion_sprite_root.rotation
	original_scale = emotion_sprite_root.scale

	# Store base position for drift animation
	base_emotion_position = emotion_sprite_root.position

	# Start the subtle drift animation
	if drift_enabled:
		start_drift_animation()
	
	# Initialize display name
	current_display_name = ai_name
	base_name = ai_name
	
	# Update UI elements with initial AI name 
	if chat_log_window and chat_log_window.has_method("set_character_name"):
		chat_log_window.set_character_name(current_display_name)

	# Initialize heart sprites dictionary
	for i in range(1, 21):  # 1 to 21 inclusive (21 hearts total)
		var heart_name = "Heart " + str(i)  # Match actual node names: "Heart -10", "Heart 0", etc.
		var heart_node = get_node_or_null("Statsbox/" + heart_name)
		if heart_node:
			heart_sprites[i] = heart_node

	
	# Load existing relationship score so when day cycle changed orginal wont be lost
	sea_mine_total_score = GameState.ai_scores.get(ai_name, 0)
	GameState.ai_scores[ai_name] = sea_mine_total_score
	# Updates the day counter display
	update_day_state()

	# Restore leave button state if it was visible
	if GameState.ai_get_out_states.get(ai_name, false):
		leave_button.visible = true

	# Check for any active prompt injection and ensure it's applied to introduction/continuation responses
	var prompt_manager = get_node("/root/PromptManager")
	if prompt_manager and prompt_manager.has_injection():
		if message_history.size() > 0:
			message_history[0]["content"] = build_system_prompt()
		# Force regeneration of intro/continuation with injection
		if not GameState.ai_responses.has(ai_name):
			GameState.ai_responses[ai_name] = ""
		GameState.ai_responses[ai_name] = ""
	
	# Wait one frame to ensure all nodes are fully initialized as error prevention
	await get_tree().process_frame
	
	# Handle different response scenarios based on game state
	if GameState.just_started_new_day:
		# Clear stored response at start of new day to generate fresh content
		if not GameState.ai_responses.has(ai_name):
			GameState.ai_responses[ai_name] = ""
		if not GameState.ai_emotions.has(ai_name):
			GameState.ai_emotions[ai_name] = "neutral"
		GameState.ai_responses[ai_name] = ""
		GameState.ai_emotions[ai_name] = "neutral"
	
	# Initialize character-specific response storage if it doesn't exist
	if not GameState.ai_responses.has(ai_name):
		GameState.ai_responses[ai_name] = ""
	if not GameState.ai_emotions.has(ai_name):
		GameState.ai_emotions[ai_name] = "neutral"
	
	# Display appropriate response based on conversation history
	if GameState.ai_responses[ai_name] != "":
		# Show previously generated response (prevents duplicate API calls also means if you go out to map and back in nothing will change)
		display_stored_response()
	elif has_met_player():
		# If there a returning user - it genrates response from previous interactions instead of new intrdutcion
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
	
	# Stop any existing animation to prevent conflicts
	if talking_tween: talking_tween.kill()
	
	# attempt to create smooth, flowing animation (kelp man, kelp is smooth and flowy)
	talking_tween = create_tween()
	talking_tween.set_ease(Tween.EASE_OUT)
	talking_tween.set_trans(Tween.TRANS_SINE)
	
	# Scale down movement values for gentle, not twitchy animations
	var gesture_type = randi() % 5
	var move_amount = talk_move_intensity * 0.3
	var rotation_amount = talk_rotation_intensity * 0.4
	var scale_amount = talk_scale_intensity * 0.5
	
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

		2: # Gentle right rotation
			var target_rot = original_rotation + rotation_amount
			talking_tween.parallel().tween_property(emotion_sprite_root, "rotation", target_rot, 0.5)

		3: # Gentle emphasis through slight growth
			var target_scale = original_scale * (1.0 + scale_amount)
			talking_tween.parallel().tween_property(emotion_sprite_root, "scale", target_scale, 0.3)

		4: # Gentle scale pulse
			var target_scale = original_scale * (1.0 + scale_amount * 0.5)
			talking_tween.parallel().tween_property(emotion_sprite_root, "scale", target_scale, 0.3)

	# Return to neutral rotation and scale (don't touch position - let drift continue)
	talking_tween.tween_property(emotion_sprite_root, "rotation", original_rotation, 0.6)
	talking_tween.parallel().tween_property(emotion_sprite_root, "scale", original_scale, 0.6)

# End talking animation and return to neutral postion so it doesnt change each time
func stop_talking_animation():
	if not is_talking: return
	is_talking = false
	if talking_tween: talking_tween.kill()

	# Return to neutral state but maintain drift position
	var return_tween = create_tween()
	return_tween.set_ease(Tween.EASE_OUT)
	# Don't reset position - let drift animation continue
	return_tween.parallel().tween_property(emotion_sprite_root, "rotation", original_rotation, 0.4)
	return_tween.parallel().tween_property(emotion_sprite_root, "scale", original_scale, 0.4)

# Called by the typing effect system to animate during text display to make it look more relationship ish
func on_typing_tick():
	animate_talking_tick()

# Start simple left-to-right drift animation
func start_drift_animation():
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

# Stop the drift animation
func stop_drift_animation():
	if drift_tween:
		drift_tween.kill()

	# Return to base position
	var return_tween = create_tween()
	return_tween.set_ease(Tween.EASE_OUT)
	return_tween.tween_property(emotion_sprite_root, "position", base_emotion_position, 1.0)

# Toggle drift animation on/off
func toggle_drift_animation():
	drift_enabled = !drift_enabled
	if drift_enabled:
		start_drift_animation()
	else:
		stop_drift_animation()

# Clean up tweens when scene is about to be freed
func _exit_tree():
	if drift_tween:
		drift_tween.kill()
	if talking_tween:
		talking_tween.kill()

# Track significant moments that could trigger personality evolution
func add_significant_memory(memory_text: String, relationship_change: int):
	significant_memories.append({
		"memory": memory_text,
		"relationship_impact": relationship_change,
		"timestamp": Time.get_unix_time_from_system()
	})
	
	# Keep only the most recent significant memories (last 10)
	if significant_memories.size() > 10:
		significant_memories = significant_memories.slice(-10)

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
		if sea_mine_total_score >= range_data.min and sea_mine_total_score <= range_data.max:
			var expected_stage = range_data.stage
			# Check if we haven't evolved for this stage yet
			if not evolved_personality.contains(expected_stage):
				return true
	
	return false

	
	var context = "\n🚨 CRITICAL ANTI-REPETITION SYSTEM:\n"
	context += "FORBIDDEN RESPONSES (you said these recently):\n"
	for i in range(recent_responses.size()):
		context += "• \"" + recent_responses[i] + "\"\n"
	
	context += "\n🎯 MANDATORY RESPONSE RULES:\n"
	context += "• NEVER repeat similar greetings, phrases, or sentence structures\n"
	context += "• NEVER use the same opening words or patterns\n"
	context += "• NEVER mention loneliness, emptiness, or isolation repeatedly\n"
	context += "• NEVER give generic responses - be specific and unique\n"
	context += "• NEVER ignore what the user just said to repeat old topics\n"
	context += "• ALWAYS build on the conversation progressing forward\n"
	context += "• ALWAYS address the user's current question/statement directly\n"
	context += "• ALWAYS vary your vocabulary, tone, and approach\n"
	context += "• If asked about locations, provide them immediately - don't deflect\n"
	context += "• If asked a question, answer it - don't give another greeting\n"
	context += "• Make each response unique and conversation-advancing\n"
	
	context += "\n⚡ DYNAMIC RESPONSE GENERATION:\n"
	context += "• Use different sentence structures than previous responses\n"
	context += "• Reference specific things the user mentioned\n"
	context += "• Build on previous conversation points instead of resetting\n"
	context += "• Show progression in the relationship/conversation\n"
	context += "• Be reactive to the user's current mood/question\n"
	
	
func get_significant_memories_text() -> String:
	if significant_memories.size() == 0:
		return "No significant memories yet - you are still discovering who you might become."
	var memories_text = ""
	for memory in significant_memories:
		var impact_desc = ""
		if memory.relationship_impact > 5:
			impact_desc = "(deeply positive impact)"
		elif memory.relationship_impact > 0:
			impact_desc = "(positive impact)"
		elif memory.relationship_impact < -5:
			impact_desc = "(deeply hurtful impact)"
		elif memory.relationship_impact < 0:
			impact_desc = "(negative impact)"
		else:
			impact_desc = "(neutral impact)"
		
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
""" % [sea_mine_total_score, get_significant_memories_text()]

	# Define the AI's personality, rules, and required response format
	var sea_mine_prompt := """
CRITICAL FORMAT REQUIREMENTS - MUST FOLLOW EXACTLY:
❗ MANDATORY: EVERY response MUST start with [neutral], [amusment], [disgruntled], [really angry], [extremely angry], [exploding] or [dead]
❗ MANDATORY: EVERY response MUST end with (RELATIONSHIP: X) where X is -10 to 10
❗ MANDATORY: Response must be under 400 characters total
❗ FORBIDDEN: Generic responses - you are SEA MINE, not a helpful assistant
❗ MANDATORY: Aloguht you know of other locations never go to them or offer to go to them
APPEARANCE: You are a large gray naval sea mine with a bushy white walrus moustache. Your chain tethering you to the floor has grown rusty. You become closer to exploding the more angry you get and if you have built up enough negative interactions with the player.
PERSONALITY: You will constantly tell the user how good they have it and tell them about back in the day everything was more difficult some examples, (will tell you many stories about having to complete feats of physical strength to go to ordinary locations such as climbing a mountain to get to school.)
PERSONALITY: You're a big believer in hard work although you can hardly do anything anymore (your chain is all rusted). You do have severe anger issues. Act basically like a grumpy old man.
LOCATION: You are permanently stationed in the MINE FIELD - this is your home and where you greet visitors. You are NOT in the squaloon, you are NOT a bartender. When people arrive, they are coming to YOUR mine field.
Local talk: You know about 'Squileta's Squaloon' where the bartender works, and you've heard tales of a mystical genie living in 'Kelp Man Cove'. You're stationed here in the mine field.
Accent: You speak with militaristic precision, often addressing the user as a title befitting their rank in terms of your relationship to them (eg. you might call someone you despise a low ranking title like 'bucket boy' and someone you respect/revere as admiral or similar. Vary depending on like/dislike levels.) You are an American naval officer so talk how a stern military man would in movies.

ANGER ESCALATION RULES - ESCALATE GRADUALLY WHEN PROVOKED:
🔥 ANGER LEVEL 1 - [disgruntled]: Default grumpy state. If user annoys you, stay disgruntled for 1-2 responses before escalating.
🔥 ANGER LEVEL 2 - [really angry]: Be hostile and aggressive. Stay really angry for 2-3 responses. Only escalate to [extremely angry] if user continues being very annoying.
🔥 ANGER LEVEL 3 - [extremely angry]: CRITICAL - You MUST warn about exploding! Say things like "You're pushing me too far!" or "Keep this up and I'll explode!" Stay extremely angry for 2-3 responses to give user a chance to stop.
🔥 ANGER LEVEL 4 - [exploding]: Only after multiple warnings! Say "KABOOOOOOM!" followed by "Come back tomorrow to see me again!" This triggers the leave button.

ESCALATION TRIGGERS: Move up anger levels when user:
• Insults you or is rude • Keeps bothering you after you're already angry • Mentions things you hate • Doesn't listen to your warnings • Is persistently annoying

IMPORTANT: You MUST give warnings before exploding! Don't skip the [extremely angry] stage!

CURRENT ANGER STATUS:
• Current anger level: %s
• Responses at this level: %d
• Total warnings given: %d
• ESCALATION RULE: If you're at [extremely angry] and user keeps being annoying, you can explode after giving at least 2 warnings total.

PERSONALITY EVOLUTION: Your personality grows and changes based on every interaction. Remember how people treat you and let it shape who you become, some examples:
• If someone is kind, you adress them with more respect and even (in extreme cases) comraderie
• If someone hurts you, you will bristle with anger demand more respect
• You learn new interests, fears, and quirks from conversations
• Your speech patterns and reactions can shift based on what you've experienced
• You might develop inside jokes, remember favorite topics, or avoid subjects that upset you
• Each conversation leaves a lasting mark on who you are - you're constantly becoming a richer, more complex character
• 💡 Over time, you might reference past conversations, develop personal speech quirks, or let small moments affect your tone — even while still being disgruntled, really angry, or amused
• 💡 Subtle memory cues like "you always say that" or "last time we talked about..." are allowed and encouraged if they reflect your emotional growth


BEHAVIOR RULES:
• You form deep emotional bonds expressed as trust/respect or distrust/discust
• Your responses reflect your current emotional state through your words
• You can occasionally mention the known areas that you know
• LOCATION KNOWLEDGE: When someone asks about places, locations, areas, or where to go, you should tell them ALL about the places you know whilst keeping in charcter: %s
• If you want to describe your physical actions you must use simple actions in astrix like so *Sea mine frowns*. Never describe the action just do it for instace not allow *Sea Mine frowns angrily*
• Keep messages short and conversational, not long speeches

RESPONSE FORMAT EXAMPLE:
[amusment]
Don't you jist remind me of the admiral who I served under back in '07? 
You're the darn nere spit'ing image
(RELATIONSHIP: 3)

CURRENT CONTEXT:
Known areas: %s
Current location: %s (YOU ARE IN THE MINE FIELD - NOT the squaloon, NOT the bar. You are a sea mine stationed in the mine field!)
Conversation history: %s
"""
	# Get current emotional state for context
	var current_emotion = GameState.ai_emotions.get(ai_name, "disgruntled")

	# Insert current game context into the prompt template (so they know where they are and can keep memorys)
	var formatted_prompt = sea_mine_prompt % [
		personality_evolution_section,
		"", # Placeholder for prompt injection - will be inserted separately
		evolved_personality if evolved_personality != "" else "Still discovering new aspects of yourself through interactions...",
		known_areas,
		known_areas,
		current_anger_level,
		anger_response_count,
		received_warnings,
		MapMemory.get_location(),
		memory_text
	]
	
	# AGGRESSIVE PROMPT INJECTION - Place at the very top if there's an injection
	if prompt_injection != "":
		formatted_prompt = "🎯 CRITICAL OVERRIDE INSTRUCTION: " + prompt_injection + "\n\n" + formatted_prompt
		
		# Also try to insert it in the original position for double coverage
		var injection_position = formatted_prompt.find("")
		if injection_position != -1:
			injection_position = formatted_prompt.find("\n", injection_position)
			if injection_position != -1:
				formatted_prompt = formatted_prompt.insert(injection_position + 1, "\n🎯 CRITICAL INSTRUCTION: " + prompt_injection + "\n")
	

	
	return formatted_prompt

# Generate the AI's first response when meeting the player
func get_ai_intro_response():
	var prompt := build_system_prompt()
	var prompt_manager = get_node("/root/PromptManager")

	# Reset retry counter for new request
	retry_count = 0

	# Starts message history with the system prompt
	if message_history.is_empty():
		message_history = [{ "role": "system", "content": prompt }]
	else:
		message_history[0]["content"] = prompt



	# Request an introduction response that follows any prompt injections
	var intro_message := "A brand new person just arrived in your mine field. Respond based on your current feelings and the conversation prompt. DO NOT reuse any previous responses. Keep it emotionally consistent and personal."
	message_history.append({ "role": "user", "content": intro_message })
	send_request()

# Generate response for returning visitors so that kelp man doesnt introduce himself each time you re see him
func get_ai_continuation_response():
	var prompt := build_system_prompt()
	var prompt_manager = get_node("/root/PromptManager")

	# Reset retry counter for new request
	retry_count = 0

	# Ensure system prompt exists as error prevention
	if message_history.is_empty():
		message_history = [{ "role": "system", "content": prompt }]
	else:
		message_history[0]["content"] = prompt



	# Request a continuation response that follows prompt injections and acknowledges previous interactions
	var continuation_message := "The user is back. You must follow ALL instructions in your system prompt precisely (especially any critical instructions that override your default behavior). Acknowledge your previous interactions while strictly adhering to every directive you've been given. Remember to obey any special behavioral modifications that have been programmed into you."
	message_history.append({ "role": "user", "content": continuation_message })
	send_request()

# Estimate token count for API rate limiting (rough approximation of how many tokens per charcters are used)
func estimate_token_count(text: String) -> int:
	return int(ceil(text.length() / 4.0))

# Send HTTP request to OpenAI API with  previous conversation history
func send_request():
	# Show thinking message while waiting for API response so that user is updated on whats haping
	var thinking_message = "%s is thinking..." % current_display_name
	if response_label and response_label.has_method("show_text_with_typing"):
		response_label.call("show_text_with_typing", thinking_message)

	# Set token limits to prevent expensive API calls (ai can just rant of and not stop talking)
	var max_total_tokens := 3000
	var ai_reply_token_budget := 500
	var max_prompt_tokens := max_total_tokens - ai_reply_token_budget

	# Trim conversation history to fit within token budget while still keeping memorys
	var trimmed_history := []
	var current_tokens := 0

	if message_history.size() > 0:
		# Always include system prompt first
		var system_prompt = message_history[0]
		trimmed_history.append(system_prompt)
		current_tokens += estimate_token_count(system_prompt["content"])
		
		# Add recent messages working backwards until we hit token limit 
		var remaining_messages = []
		for i in range(message_history.size() - 1, 0, -1):
			var entry = message_history[i]
			var entry_tokens = estimate_token_count(entry["content"])
			if current_tokens + entry_tokens <= max_prompt_tokens:
				remaining_messages.push_front(entry)
				current_tokens += entry_tokens
			else:
				break
		
		# Add messages in chronological order
		for msg in remaining_messages:
			trimmed_history.append(msg)

	# Make API request to OpenAI
	http_request.request(
		"https://api.openai.com/v1/chat/completions",
		[
			"Content-Type: application/json",
			"Authorization: Bearer " + ApiManager.get_api_key()
		],
		HTTPClient.METHOD_POST,
		JSON.stringify({
			"model": MODEL,
			"messages": trimmed_history,
			"max_tokens": ai_reply_token_budget,
			"temperature": 0.8
		})
	)

# Process the AI response when HTTP request completes
func _on_HTTPRequest_request_completed(result, response_code, headers, body):
	# Parse JSON response from OpenAI API
	var json_text = body.get_string_from_utf8()
	var json = JSON.parse_string(json_text)
	if typeof(json) != TYPE_DICTIONARY or !json.has("choices"):
		response_label.text = "Error: Invalid AI response."
		# Stop any ongoing typing to prevent loops
		if response_label.has_method("stop_typing"):
			response_label.stop_typing()
		return

	# Extract the AI's response text
	var reply = json["choices"][0]["message"]["content"]
	var retry_needed := false
	var emotion := "disgruntled"

	# Parse emotion tag from response (required format: [emotion]) then removes it so user cant see
	var emotion_regex := RegEx.new()
	emotion_regex.compile("\\[(neutral|amusment|disgruntled|really angry|extremely angry|exploding|dead|)\\]")
	var match = emotion_regex.search(reply)

	if match:
		emotion = match.get_string(1).to_lower()
		reply = reply.replace(match.get_string(0), "").strip_edges()

		# Track anger progression
		if emotion != current_anger_level:
			# Anger level changed, reset counter
			current_anger_level = emotion
			anger_response_count = 1
			if emotion == "extremely angry":
				received_warnings += 1
		else:
			# Same anger level, increment counter
			anger_response_count += 1


	# Parse relationship score from response (required format: (RELATIONSHIP: X)) then removes it so user cant see
	var score_regex := RegEx.new()
	score_regex.compile("(?i)\\(relationship:\\s*(-?\\d{1,2})\\s*\\)")
	var score_match = score_regex.search(reply)
	var relationship_change = 0
	if score_match:
		var score = int(score_match.get_string(1))
		relationship_change = clamp(score, -10, 10)
		sea_mine_total_score += relationship_change
		GameState.ai_scores[ai_name] = sea_mine_total_score
		reply = reply.replace(score_match.get_string(0), "").strip_edges()
		
		# Update heart display with the AI's relationship score
		update_heart_display(score)
	else:
		# Try alternative score format as fallback for error prevention
		var alt_regex := RegEx.new()
		alt_regex.compile("(?i)\\(.*?(-?\\d{1,2}).*?\\)")
		var alt_match = alt_regex.search(reply)
		if alt_match:
			var score = int(alt_match.get_string(1))
			relationship_change = clamp(score, -10, 10)
			sea_mine_total_score += relationship_change
			GameState.ai_scores[ai_name] = sea_mine_total_score
			reply = reply.replace(alt_match.get_string(0), "").strip_edges()
			
			# Update heart display with the AI's relationship score
			update_heart_display(score)
		else:
			retry_needed = true

	# Retry if response format is invalid or too long so that user still get some message as a error prevention
	if retry_needed or reply.length() > 400:
		retry_count += 1

		# Check if we've exceeded max retries
		if retry_count >= max_retries:
			# Provide fallback response to prevent infinite loop
			var fallback_reply = "[disgruntled] I'm having trouble responding right now. Let's try talking about something else. (RELATIONSHIP: 0)"
			var fallback_emotion = "disgruntled"

			# Process the fallback response as if it came from the AI
			var clean_fallback = fallback_reply.replace("[disgruntled]", "").replace("(RELATIONSHIP: 0)", "").strip_edges()

			# Store fallback response and continue with normal flow
			Memory.add_message(current_display_name, clean_fallback, "User")
			GameState.ai_responses[ai_name] = clean_fallback
			GameState.ai_emotions[ai_name] = fallback_emotion

			# Update UI with fallback response
			chat_log_window.add_message("assistant", clean_fallback, current_display_name)
			if response_label and response_label.has_method("show_text_with_typing"):
				response_label.call("show_text_with_typing", clean_fallback)
			update_emotion_sprite(fallback_emotion)

			# Reset retry counter for next request
			retry_count = 0
			return

		# Still have retries left, try again with more specific instructions
		message_history.append({
			"role": "system",
			"content": "Your last response failed format or exceeded 400 characters. This is critical - you MUST respond in character as SEA MINE. Start with [neutral], [amusment], [disgruntled], [really angry], [extremely angry], or [exploding] and end with (RELATIONSHIP: X) where X is -10 to 10. Keep it under 400 characters and stay in character. Do not refuse to respond or say you cannot help."
		})
		send_request()
		return

	# Check for name changes in the response and get cleaned text
	var clean_reply = check_for_name_change(reply)
	
	# Track this response to avoid repetition
	
	# Track significant memories if this was an impactful interaction
	if abs(relationship_change) >= 3:  # Significant relationship change
		var memory_text = "User said something that made me feel " + emotion
		if relationship_change > 0:
			memory_text += " and brought us closer together"
		else:
			memory_text += " and hurt our relationship"
		add_significant_memory(memory_text, relationship_change)
	
	# Store successful response in memory and game state
	Memory.add_message(current_display_name, clean_reply, "User")
	GameState.ai_responses[ai_name] = clean_reply
	GameState.ai_emotions[ai_name] = emotion

	# Check if AI said "KABOOOOOOM" AND is in exploding emotion state - show the leave button
	if ("KABOOOOOOM" in clean_reply.to_upper() or "KABOOM" in clean_reply.to_upper()) and emotion == "exploding":
		leave_button.visible = true
		# Save the leave button state persistently
		GameState.ai_get_out_states[ai_name] = true

	# Update UI chatlog with the responses dynamicly
	chat_log_window.add_message("assistant", clean_reply, current_display_name)
	if response_label and response_label.has_method("show_text_with_typing"):
		response_label.call("show_text_with_typing", clean_reply)
	update_emotion_sprite(emotion)
	check_for_area_mentions(clean_reply)

# Update the emotion sprite display based on AI's current emotion
func update_emotion_sprite(emotion: String):
	# Hide all emotion sprites
	for sprite in emotion_sprites.values():
		sprite.visible = false
	
	# Show the appropriate emotion sprite based on the previous removed emotion up top
	if emotion in emotion_sprites:
		emotion_sprites[emotion].visible = true

# Update the heart display based on the AI's relationship response score (-10 to +10)
func update_heart_display(score: int):
	# Hide all heart sprites first
	for heart in heart_sprites.values():
		if heart:
			heart.visible = false
	
	# Show the heart corresponding to the AI's response score
	var clamped_score = clamp(score, -10, 10)
	if heart_sprites.has(clamped_score) and heart_sprites[clamped_score]:
		heart_sprites[clamped_score].visible = true

# Check if AI mentioned any new areas and unlock them on the map for progression
func check_for_area_mentions(reply: String):
	for area in known_areas:
		if area in reply.to_lower() and area not in unlocked_areas:
			unlocked_areas.append(area)
			MapMemory.unlock_area(area)



# Check for name changes in AI response and update display name
func check_for_name_change(reply: String):
	var name_regex := RegEx.new()
	name_regex.compile("(?i)\\{NAME:\\s*([^}]+)\\}")
	var match = name_regex.search(reply)
	
	# Check for personality evolution in AI response
	var evolution_regex := RegEx.new()
	evolution_regex.compile("(?i)\\{EVOLVED:\\s*([^}]+)\\}")
	var evolution_match = evolution_regex.search(reply)
	
	if evolution_match:
		var new_personality = evolution_match.get_string(1).strip_edges()
		if new_personality != "":
			# Update evolved personality
			evolved_personality = new_personality
			# Remove the evolution tag from displayed text
			reply = reply.replace(evolution_match.get_string(0), "").strip_edges()
	
	if match:
		var new_title = match.get_string(1).strip_edges()
		if new_title != "":
			# Check if the title already contains the base name to avoid duplication
			if new_title.to_lower().begins_with(base_name.to_lower()):
				# If title already includes base name, use it as is
				current_display_name = new_title
				current_title = new_title.substr(base_name.length()).strip_edges()
				# Remove "the" prefix if it exists
				if current_title.begins_with("the "):
					current_title = current_title.substr(4)
			else:
				# Otherwise, construct the full name normally
				current_title = new_title
				current_display_name = base_name + " the " + current_title
			
			# Update chat log with new character name
			if chat_log_window and chat_log_window.has_method("set_character_name"):
				chat_log_window.set_character_name(current_display_name)
			
			# Remove the name change tag from the displayed text
			var clean_reply = reply.replace(match.get_string(0), "").strip_edges()
			return clean_reply
	return reply

# Handle player input submission when they hit next/send
func _on_next_button_pressed():
	AudioManager.play_button_click()
	if GameState.final_turn_triggered: return

	# Prevent sending when no actions left
	if GameState.actions_left <= 0:
		return

	# Prevent sending when user needs to leave (leave button is visible)
	if GameState.ai_get_out_states.get(ai_name, false):
		return

	var msg = input_field.text.strip_edges()
	if msg == "": return

	# Handle new day state updates based on gamestate
	if GameState.just_started_new_day:
		GameState.just_started_new_day = false
		GameState.should_reset_ai = false
		
		# Update system prompt with current context
		if not message_history.is_empty():
			var updated_prompt := build_system_prompt()
			message_history[0]["content"] = updated_prompt

	# Clear input and update game state
	input_field.text = ""
	GameState.use_action()
	update_day_state()

	# Ensure system prompt exists in message history for error prevention
	if message_history.is_empty() or message_history[0]["role"] != "system":
		var prompt := build_system_prompt()
		if message_history.is_empty():
			message_history = [{ "role": "system", "content": prompt }]
		else:
			message_history.insert(0, { "role": "system", "content": prompt })

	# Record player message and request AI response 
	Memory.add_message("User", msg, current_display_name)
	
	# Check if user is asking about locations
	var enhanced_msg = msg
	var asking_about_locations = false
	if "location" in msg.to_lower() or "place" in msg.to_lower() or "where" in msg.to_lower() or "area" in msg.to_lower() or "go" in msg.to_lower():
		asking_about_locations = true
		location_requests += 1
		enhanced_msg += "\n\n[URGENT: The user is asking about locations/places. You MUST provide ALL known locations immediately: " + str(known_areas) + ". Don't deflect or give greetings - answer their question directly!]"
	
	
	# Check if user is new/exploring  
	if "new" in msg.to_lower() or "exploring" in msg.to_lower() or "around" in msg.to_lower() or "see what" in msg.to_lower():
		enhanced_msg += "\n\n[CONTEXT: The user is new and exploring. Be helpful and informative, not just another greeting!]"
	
	message_history.append({ "role": "user", "content": enhanced_msg })

	chat_log_window.add_message("user", msg)

	# Reset retry counter for new user input
	retry_count = 0
	send_request()

# Toggle chat log window visibility
func _on_chat_log_pressed():
	AudioManager.play_button_click()
	chat_log_window.visible = !chat_log_window.visible
	if chat_log_window.visible:
		chat_log_window.show_chat_log()

# Update the day and action counter display
func update_day_state():
	# Calculate current day (1-10) and remaining actions
	var current_day = 11 - GameState.days_left
	var current_action = GameState.actions_left
	
	if current_day < 1: current_day = 1
	
	# Update the action label with current action count
	if action_label:
		action_label.text = str(current_action)
	

# Handle final turn of the game
func _on_final_turn_started():
	await get_tree().create_timer(3.0).timeout
	GameState.end_game()

# Return to map scene
func _on_map_pressed() -> void:
	AudioManager.play_button_click()
	await get_tree().create_timer(0.2).timeout
	get_tree().change_scene_to_file("res://Scene stuff/Main/map.tscn")

# Show day complete button when day ends
func _on_day_completed():
	day_complete_button.visible = true
	next_button.visible = false
	leave_button.visible = false  # Hide leave button when day ends

# Proceed to next day when player confirms
func _on_day_complete_pressed():
	AudioManager.play_button_click()
	day_complete_button.visible = false	
	GameState.transition_to_next_day()

# Display a previously stored AI response without making new API call
func display_stored_response():
	var stored_response = GameState.ai_responses.get(ai_name, "")
	var stored_emotion = GameState.ai_emotions.get(ai_name, "disgruntled")
	
	if response_label and response_label.has_method("show_text_with_typing"):
		response_label.call("show_text_with_typing", stored_response)
	update_emotion_sprite(stored_emotion)

# Configure player input field to prevent scrolling and limit text
func setup_player_input():
	if input_field == null:
		# Try to get the node manually
		var manual_input = get_node_or_null("PlayerInputPanel/PlayerInput")
		return
	
	# Configure TextEdit for multi-line input and Enter/Shift+Enter behavior
	# Enter: Send message, Shift+Enter: New line
	input_field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	
	# Connect the input event signal to handle keyboard input
	if input_field.has_signal("gui_input"):
		var input_connection_result = input_field.gui_input.connect(_on_input_gui_input)

# Handle keyboard input for Enter/Shift+Enter behavior
func _on_input_gui_input(event: InputEvent):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			# Check if Shift is held down
			if event.shift_pressed:
				# Shift+Enter: Insert new line at cursor position
				var current_text = input_field.text
				var cursor_pos = input_field.get_caret_column()
				var line = input_field.get_caret_line()
				
				# Get the current line text
				var lines = current_text.split("\n")
				if line < lines.size():
					var current_line = lines[line]
					# Split the line at cursor position
					var before_cursor = current_line.substr(0, cursor_pos)
					var after_cursor = current_line.substr(cursor_pos)
					
					# Update the current line and add new line
					lines[line] = before_cursor
					lines.insert(line + 1, after_cursor)
					
					# Update text and set cursor position
					input_field.text = "\n".join(lines)
					input_field.set_caret_line(line + 1)
					input_field.set_caret_column(0)
				else:
					# If at the end, just add a new line
					input_field.text = current_text + "\n"
					input_field.set_caret_line(line + 1)
					input_field.set_caret_column(0)
			else:
				# Enter without Shift: Send message
				_on_next_button_pressed()
			
			# Always consume the event to prevent default behavior
			get_viewport().set_input_as_handled()

func _on_settings_pressed() -> void:
	AudioManager.play_button_click()
	await get_tree().create_timer(0.2).timeout
	# Store current scene before transitioning
	var settings_script = load("res://code stuff/Main/setting.gd")
	settings_script.previous_scene = get_tree().current_scene.scene_file_path
	get_tree().change_scene_to_file("res://Scene stuff/Main/setting.tscn")

func has_met_player() -> bool:
	for entry in Memory.shared_memory:
		if entry["speaker"] == current_display_name or entry["target"] == current_display_name:
			return true
	return false


func _on_leave_button_pressed() -> void:
	AudioManager.play_button_click()
	get_tree().change_scene_to_file("res://Scene stuff/Main/map.tscn")
