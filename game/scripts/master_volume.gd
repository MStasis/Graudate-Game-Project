extends HSlider

const SETTINGS_PATH := "user://audio_settings.cfg"

@export var value_label: Label
var _saved_volume := 100.0

func _ready() -> void:
 value_changed.connect(_apply_volume)
 load_setting()

func load_setting() -> void:
 var config := ConfigFile.new()
 var saved: Variant = 100.0
 if config.load(SETTINGS_PATH) == OK:
  saved = config.get_value("audio", "master_volume", 100.0)
 set_value_no_signal(float(saved) if saved is int or saved is float else 100.0)
 _saved_volume = value
 _apply_volume(value)

func save_setting() -> void:
 if is_equal_approx(value, _saved_volume): return
 var config := ConfigFile.new()
 config.load(SETTINGS_PATH)
 config.set_value("audio", "master_volume", value)
 var error := config.save(SETTINGS_PATH)
 if error == OK:
  _saved_volume = value
 else:
  push_warning("Could not save audio settings: %s" % error_string(error))

func _apply_volume(percent: float) -> void:
 value_label.text = "%d%%" % roundi(percent)
 AudioServer.set_bus_volume_db(0, linear_to_db(maxf(percent / 100.0, 0.001)))
 AudioServer.set_bus_mute(0, is_zero_approx(percent))
