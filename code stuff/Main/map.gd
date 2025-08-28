extends Node2D
@onready var background = $Background
@onready var background_south = $wild_south2
@onready var background_field = $mine_field2
@onready var background_squaloon = $sqauloon2
@onready var background_grotto = $grotto2
@onready var background_cove = $Kelp_man_cove2


func _on_bar_pressed() -> void:
	AudioManager.play_button_click()
	await get_tree().create_timer(0.1).timeout
	get_tree().change_scene_to_file("res://Scene stuff/Charcters/Squilleta.tscn")
	MapMemory.set_location("squaloon")
func _on_kelp_man_pressed() -> void:
	AudioManager.play_button_click()
	await get_tree().create_timer(0.1).timeout
	get_tree().change_scene_to_file("res://Scene stuff/Charcters/kelp_man.tscn")
	MapMemory.set_location("kelp man cove")

func _ready():
	print("🗓️ Days: %d, Actions: %d" % [GameState.days_left, GameState.actions_left])
	
	# Debug: Print all child node names
	print("🔍 Map child nodes:")
	for child in get_children():
		print("  - ", child.name)
	
	# Initialize random starting location if no areas are unlocked
	print("🎲 Current unlocked areas before init: ", MapMemory.unlocked_areas)
	if MapMemory.unlocked_areas.is_empty():
		print("🎲 No areas unlocked, initializing random location...")
		MapMemory.initialize_random_starting_location()
	
	# Update visibility based on unlocked areas
	update_location_visibility()
	
	# Safety check: ensure at least one location is visible
	ensure_at_least_one_location_visible()
	
	# Print current unlocked areas for debugging
	print("🗺️ Final unlocked areas: ", MapMemory.unlocked_areas)
	background.visible = true
	background_south.visible = true
	background_field.visible = true
	background_squaloon.visible = true
	background_grotto.visible = true
	background_cove.visible = true

func update_location_visibility():
	# Map the node names to their corresponding area names
	var location_mapping = {
		"kelp_man_cove": "kelp man cove",
		"sqauloon": "squaloon",
		"wild_south": "wild south",
		"mine_field": "mine field"
	}
	
	# Set visibility based on unlocked areas
	for child in get_children():
		var node_name = child.name.to_lower()
		print("🔍 Checking node: ", node_name)
		
		if node_name in location_mapping:
			var area_name = location_mapping[node_name]
			var is_unlocked = area_name in MapMemory.unlocked_areas
			child.visible = is_unlocked
			print("  - Mapped to area: ", area_name, " | Unlocked: ", is_unlocked, " | Visible: ", child.visible)
		else:
			# For other nodes, try direct name matching
			var area_name = node_name
			var is_unlocked = area_name in MapMemory.unlocked_areas
			child.visible = is_unlocked
			print("  - Direct mapping: ", area_name, " | Unlocked: ", is_unlocked, " | Visible: ", child.visible)

func ensure_at_least_one_location_visible():
	# Check if any location nodes are currently visible
	var visible_locations = []
	var location_nodes = []
	
	for child in get_children():
		var node_name = child.name.to_lower()
		if node_name in ["kelp_man_cove", "sqauloon", "wild_south", "mine field"]:
			location_nodes.append(child)
			if child.visible:
				visible_locations.append(child)
	
	print("🔍 Visible locations: ", visible_locations.size(), " / ", location_nodes.size())
	
	# If no locations are visible, force one to be visible
	if visible_locations.size() == 0 and location_nodes.size() > 0:
		print("🚨 No locations visible! Forcing one to be visible...")
		
		# Randomly pick one location to make visible
		var random_index = randi() % location_nodes.size()
		var chosen_location = location_nodes[random_index]
		chosen_location.visible = true
		
		# Also unlock the corresponding area
		var location_mapping = {
			"kelp_man_cove": "kelp man cove",
			"sqauloon": "squaloon",
			"wild_south": "wild south",
			"mine_field": "mine field"
		}
		
		var node_name = chosen_location.name.to_lower()
		if node_name in location_mapping:
			var area_name = location_mapping[node_name]
			MapMemory.unlock_area(area_name)
			print("🎲 Forced location visible: ", chosen_location.name, " (", area_name, ")")
	
	# Final check
	for child in get_children():
		if child.name.to_lower() in ["kelp_man_cove", "sqauloon", "wild_south", "mine field"]:
			print("🗺️ Final: ", child.name, " visible: ", child.visible)



func _on_wild_south_pressed() -> void:
	AudioManager.play_button_click()
	await get_tree().create_timer(0.1).timeout
	get_tree().change_scene_to_file("res://Scene stuff/Charcters/shrimp_no_name.tscn")
	MapMemory.set_location("wild south")


func _on_mine_feild_pressed() -> void:
	AudioManager.play_button_click()
	await get_tree().create_timer(0.1).timeout
	get_tree().change_scene_to_file("res://Scene stuff/Charcters/sea_mine.tscn")
	MapMemory.set_location("mine field")


func _on_grotto_pressed() -> void:
	pass
