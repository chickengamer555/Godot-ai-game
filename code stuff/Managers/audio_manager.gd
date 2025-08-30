extends Node

signal volume_changed(bus_name: String, volume: float)

# Audio buses
const MASTER_BUS = "Master"
const MUSIC_BUS = "Music"
const SFX_BUS = "SFX"

# Volume settings
var master_volume: float = 1.0
var music_volume: float = 1.0
var sfx_volume: float = 1.0

# Audio players for global sounds
@onready var button_click_player: AudioStreamPlayer
@onready var switch_sound_player: AudioStreamPlayer

# Preload sound resources
const BUTTON_CLICK_SOUND = preload("res://Sound stuff/click-233950.mp3")
const SWITCH_SOUND = preload("res://Sound stuff/switch-150130 (1).mp3")

func _ready():
	# Create audio players for global sounds
	create_audio_players()
	
	# Load saved volume settings
	load_volume_settings()
	
	# Apply volume settings to audio buses
	apply_volume_settings()

func create_audio_players():
	# Create button click player
	button_click_player = AudioStreamPlayer.new()
	button_click_player.name = "ButtonClickPlayer"
	button_click_player.stream = BUTTON_CLICK_SOUND
	button_click_player.bus = SFX_BUS
	add_child(button_click_player)
	
	# Create switch sound player
	switch_sound_player = AudioStreamPlayer.new()
	switch_sound_player.name = "SwitchSoundPlayer"
	switch_sound_player.stream = SWITCH_SOUND
	switch_sound_player.bus = SFX_BUS
	add_child(switch_sound_player)

func play_button_click():
	if button_click_player and button_click_player.stream:
		button_click_player.play()

func play_switch_sound():
	if switch_sound_player and switch_sound_player.stream:
		switch_sound_player.play()

# Volume control functions
func set_master_volume(volume: float):
	master_volume = clamp(volume, 0.0, 1.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(MASTER_BUS), linear_to_db(master_volume))
	save_volume_settings()
	emit_signal("volume_changed", MASTER_BUS, master_volume)

func set_music_volume(volume: float):
	music_volume = clamp(volume, 0.0, 1.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(MUSIC_BUS), linear_to_db(music_volume))
	save_volume_settings()
	emit_signal("volume_changed", MUSIC_BUS, music_volume)

func set_sfx_volume(volume: float):
	sfx_volume = clamp(volume, 0.0, 1.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(SFX_BUS), linear_to_db(sfx_volume))
	save_volume_settings()
	emit_signal("volume_changed", SFX_BUS, sfx_volume)

# Get current volume levels
func get_master_volume() -> float:
	return master_volume

func get_music_volume() -> float:
	return music_volume

func get_sfx_volume() -> float:
	return sfx_volume

# Apply all volume settings to audio server
func apply_volume_settings():
	var master_bus_index = AudioServer.get_bus_index(MASTER_BUS)
	var music_bus_index = AudioServer.get_bus_index(MUSIC_BUS)
	var sfx_bus_index = AudioServer.get_bus_index(SFX_BUS)
	
	if master_bus_index != -1:
		AudioServer.set_bus_volume_db(master_bus_index, linear_to_db(master_volume))
	
	if music_bus_index != -1:
		AudioServer.set_bus_volume_db(music_bus_index, linear_to_db(music_volume))
	
	if sfx_bus_index != -1:
		AudioServer.set_bus_volume_db(sfx_bus_index, linear_to_db(sfx_volume))

# Save volume settings to file
func save_volume_settings():
	var config = ConfigFile.new()
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	
	var save_result = config.save("user://audio_settings.cfg")
	if save_result != OK:
		print("Failed to save audio settings")

# Load volume settings from file
func load_volume_settings():
	var config = ConfigFile.new()
	var load_result = config.load("user://audio_settings.cfg")
	
	if load_result == OK:
		master_volume = config.get_value("audio", "master_volume", 1.0)
		music_volume = config.get_value("audio", "music_volume", 1.0)
		sfx_volume = config.get_value("audio", "sfx_volume", 1.0)
		print("Loaded audio settings - Master: ", master_volume, " Music: ", music_volume, " SFX: ", sfx_volume)
	else:
		print("No audio settings file found, using defaults")

# Utility function to convert linear volume to decibels
func linear_to_db(linear: float) -> float:
	if linear <= 0.0:
		return -80.0  # Minimum volume (mute)
	else:
		return 20.0 * log(linear) / log(10.0) 