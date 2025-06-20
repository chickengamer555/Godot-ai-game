extends Window
class_name ChatLog

@onready var chat_log_label = $ChatLogPanel/VBoxContainer/ScrollContainer/ChatLogLabel
@onready var chat_log_status_label = $ChatLogPanel/VBoxContainer/StatusLabel
@onready var chat_log_title_label = $ChatLogPanel/VBoxContainer/TitleLabel

# Simple font size control
var chat_font_size := 12

# Chat window fullscreen state
var chat_window_is_fullscreen := false
var chat_window_normal_size := Vector2i(600, 400)
var chat_window_normal_position := Vector2i(200, 100)

# Chat log data
var chat_log: Array = []
var character_name: String = "Kelp Man"  # Default name, will be updated by the character script

func _ready():
	# Connect window signals
	size_changed.connect(_on_window_resized)
	close_requested.connect(_on_window_close_requested)

func show_chat_log():
	update_chat_log_display()
	
	# Only popup if not already visible to avoid resetting styling
	if not visible:
		popup_centered()
		
		# Apply initial scaling and constraints
		var tree = get_tree()
		if tree:
			await tree.process_frame
		update_text_scaling()
		constrain_window_position()
	else:
		# Just bring to front if already visible
		move_to_foreground()

func add_message(role: String, content: String, character_name_at_time: String = ""):
	var message_data = { "role": role, "content": content }
	
	# Store the character name that was used at the time this message was sent
	if role == "assistant":
		message_data["character_name"] = character_name_at_time if character_name_at_time != "" else character_name
	
	chat_log.append(message_data)
	
	# Update display if window is visible
	if visible:
		update_chat_log_display()

func clear_chat_log():
	chat_log.clear()
	update_chat_log_display()

func update_chat_log_display():
	var log := ""
	var message_count := 0
	
	for entry in chat_log:
		message_count += 1
		if entry["role"] == "user":
			log += "[color=#4A90E2][b]🧑 You:[/b][/color]\n"
			log += "[color=#FFFFFF]" + entry["content"] + "[/color]\n\n"
		else:
			# Use the historical character name for this specific message
			var display_name = entry.get("character_name", character_name)
			log += "[color=#2ECC71][b]🌿 " + display_name + ":[/b][/color]\n"
			log += "[color=#E8E8E8]" + entry["content"] + "[/color]\n\n"
	
	if log.is_empty():
		log = "[center][color=#888888][i]No conversation history yet...[/i][/color][/center]"
		message_count = 0
	
	chat_log_label.text = log.strip_edges()
	chat_log_status_label.text = str(message_count) + " messages"

func _on_window_close_requested():
	hide()

func _on_window_resized():
	update_text_scaling()
	constrain_window_position()

func update_text_scaling():
	var window_size = size
	var base_size = Vector2(600, 400)  # Reference size
	var scale_factor = min(window_size.x / base_size.x, window_size.y / base_size.y)
	scale_factor = clamp(scale_factor, 0.7, 2.0)  # Limit scaling range
	
	# Scale title font
	chat_log_title_label.add_theme_font_size_override("font_size", int(16 * scale_factor))
	
	# Scale chat content font using the user's preferred size
	chat_log_label.add_theme_font_size_override("normal_font_size", int(chat_font_size * scale_factor))
	
	# Scale status label font
	chat_log_status_label.add_theme_font_size_override("font_size", int(10 * scale_factor))

func constrain_window_position():
	var screen_size = DisplayServer.screen_get_size()
	var window_size = size
	var window_pos = position
	
	# Constrain to screen bounds
	window_pos.x = clamp(window_pos.x, 0, screen_size.x - window_size.x)
	window_pos.y = clamp(window_pos.y, 0, screen_size.y - window_size.y)
	
	position = window_pos

# Font size button handlers
func _on_increase_font_button_pressed():
	chat_font_size = min(chat_font_size + 2, 24)  # Max size 24
	chat_log_label.add_theme_font_size_override("normal_font_size", chat_font_size)

func _on_decrease_font_button_pressed():
	chat_font_size = max(chat_font_size - 2, 8)   # Min size 8
	chat_log_label.add_theme_font_size_override("normal_font_size", chat_font_size)

func _on_close_button_pressed():
	hide()

func set_character_name(new_name: String):
	character_name = new_name
	# Update window title if needed
	title = "Chat Log - " + character_name
	# Refresh display if window is visible
	if visible:
		update_chat_log_display()
