extends SceneTree

const MissionScript := preload("res://main.gd")
const SAVED_QUESTION := "비품실에서 뭘 찾아야 해?"
var checks := {}
var title: Control
var rendered := false
var evidence := ""

func _initialize() -> void:
 run.call_deferred()

func check(label: String, passed: bool) -> void:
 checks[label] = passed
 if not passed: push_error("TITLE_MENU_FAILED " + label)

func frames() -> void:
 for index in 3: await process_frame

func click(button: Button) -> void:
 var event := InputEventMouseButton.new()
 event.button_index = MOUSE_BUTTON_LEFT
 event.position = button.get_global_rect().get_center()
 event.global_position = event.position
 event.pressed = true
 root.push_input(event, true)
 event = event.duplicate()
 event.pressed = false
 root.push_input(event, true)
 await frames()

func move_mouse(position: Vector2) -> void:
 var event := InputEventMouseMotion.new()
 event.position = position
 event.global_position = position
 root.push_input(event, true)

func key(code: Key) -> void:
 var event := InputEventKey.new()
 event.keycode = code
 event.pressed = true
 root.push_input(event, true)
 event = event.duplicate()
 event.pressed = false
 root.push_input(event, true)
 await frames()

func capture(stem: String) -> void:
 if not rendered: return
 await RenderingServer.frame_post_draw
 var picture := root.get_texture().get_image()
 check(stem + "_gpu_capture", picture.get_width() == root.size.x and not picture.is_invisible() and picture.save_png(evidence.path_join(stem + ".png")) == OK)

func run() -> void:
 rendered = "--render-title" in OS.get_cmdline_user_args()
 evidence = ProjectSettings.globalize_path("res://../evidence/title_menu")
 DirAccess.make_dir_recursive_absolute(evidence)
 root.size = Vector2i(1280, 800)
 var entry := str(ProjectSettings.get_setting("application/run/main_scene"))
 check("project_entry_loads", change_scene_to_file(entry) == OK)
 await frames()
 title = current_scene as Control
 if not title or not title.has_node("%NewGame"):
  check("project_starts_on_title", false)
  finish()
  return
 var menu := title.get_node("Menu") as Control
 var new_game := title.get_node("%NewGame") as Button
 var continue_game := title.get_node("%Continue") as Button
 var settings := title.get_node("%Settings") as Button
 var quit_game := title.get_node("%Quit") as Button
 var english_title := title.get_node("Menu/Stage/Card/EnglishTitle") as Label
 var store: MissionSaveStore = title._store
 store.directory = "user://title_menu_test_%d" % OS.get_process_id()
 title._show_actions()
 check("project_starts_on_title", menu.visible and not title.has_node("Main") and not paused)
 check("empty_slot_state_and_default_focus", continue_game.disabled and new_game.has_focus())
 check("english_title_and_bundled_font", english_title.text.replace("\n", " ") == "BEYOND THE BULKHEAD" and root.title == "BEYOND THE BULKHEAD" and english_title.get_theme_font("font").resource_path.ends_with("BarlowCondensed-Black.ttf"))
 var buttons := [new_game, continue_game, settings, quit_game]
 check("main_actions_match_labels_and_size", buttons.map(func(button): return button.text) == ["새 게임", "이어하기", "설정", "종료하기"] and buttons.all(func(button): return button.size == new_game.size))
 check("mode_gap_has_room_for_one_button", settings.position.y - continue_game.position.y - continue_game.size.y >= new_game.size.y)
 check("bundled_korean_font_covers_menu", buttons.all(func(button):
  var font: Font = button.get_theme_font("font")
  for index in button.text.length():
   if not font.has_char(button.text.unicode_at(index)): return false
  return font.resource_path.ends_with("IBMPlexSansKR-Medium.ttf")))
 await capture("01_title")
 var scan := settings.get_node("HoverScan") as ColorRect
 var scan_material := scan.material as ShaderMaterial
 move_mouse(Vector2(1, 1))
 await frames()
 move_mouse(settings.get_global_rect().get_center())
 await frames()
 var left: float = scan_material.get_shader_parameter("scan_position")
 await create_timer(0.15).timeout
 check("hover_scan_sweeps_right", scan.visible and scan_material.get_shader_parameter("scan_position") > left)
 await capture("03_hover_scan")
 await create_timer(0.5).timeout
 check("hover_scan_finishes_without_repeating", not scan.visible and settings.get_draw_mode() == BaseButton.DRAW_HOVER)
 move_mouse(Vector2(1, 1))
 move_mouse(settings.get_global_rect().get_center())
 await frames()
 check("hover_scan_restarts_when_reentering", scan.visible)
 move_mouse(continue_game.get_global_rect().get_center())
 await frames()
 check("hover_scan_cancels_on_exit_and_skips_disabled", not scan.visible and not continue_game.get_node("HoverScan").visible)
 await click(settings)
 var volume := title.get_node("%MasterVolume") as HSlider
 var initial_volume := volume.value
 check("settings_click_opens_focused_slider", volume.is_visible_in_tree() and volume.has_focus() and not new_game.is_visible_in_tree())
 volume.value = 0.0
 check("zero_master_volume_mutes_audio", AudioServer.is_bus_mute(0))
 volume.value = 50.0
 check("nonzero_volume_updates_audio_and_label", not AudioServer.is_bus_mute(0) and is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(0.5)) and title.get_node("%VolumeValue").text == "50%")
 await capture("04_settings")
 volume.value = initial_volume
 await key(KEY_ESCAPE)
 check("settings_escape_restores_action_focus", settings.has_focus() and not volume.is_visible_in_tree() and not title.has_node("Main"))
 new_game.grab_focus()
 await key(KEY_ENTER)
 var mission := title.get_node_or_null("Main") as MissionScript
 check("new_game_starts_tutorial", not menu.visible and mission != null and mission.world.story.stage == "on_shift")
 if not mission:
  finish()
  return
 var world := mission.world
 mission.brain.auto_enabled = false
 world.trigger_blackout()
 world.flashlight_owned = true
 world._change_map("storage", Vector2(180, 380))
 world.player_hp = 71
 var drone := world.get_node("Enemies/DroneA") as MissionDrone
 drone.hp = 0
 mission.combat_hud.speak("플레이어", SAVED_QUESTION)
 mission.brain.history.assign([{"question": SAVED_QUESTION, "answer": "퓨즈를 찾아야 해."}])
 mission.question.text = "저장하지 않은 초안"
 mission.brain.serial = 7
 mission.brain.pending = {"kind": "dialogue", "request_id": 7}
 var previous_trial := mission.brain.trial
 var cancellations: Array[String] = []
 mission.brain.dialogue_error.connect(func(message): cancellations.append(message))
 mission.toggle_pause()
 await click(mission.pause_menu.get_node("Window/Settings"))
 var pause_volume := mission.pause_menu.get_node("Window/AudioSettings/MasterVolume") as HSlider
 pause_volume.value = 68.0
 await click(mission.pause_menu.get_node("Window/AudioSettings/Back"))
 check("fixture_saved_in_existing_slot", mission.save_slot(2))
 var save_path := store.path_for(2)
 var backup_path := save_path + ".bak"
 check("backup_only_slot_fixture", DirAccess.rename_absolute(save_path, backup_path) == OK)
 var save_hash := FileAccess.get_sha256(backup_path)
 FileAccess.open(store.path_for(3), FileAccess.WRITE).store_string("{}")
 await click(mission.pause_menu.get_node("Window/ReturnToTitle"))
 check("pause_returns_to_title_and_unpauses", menu.visible and not paused and not is_instance_valid(mission))
 check("pending_dialogue_cancelled", cancellations.size() == 1 and "title_return" in cancellations[0])
 check("existing_save_enables_continue", not continue_game.disabled and continue_game.has_focus())
 await click(settings)
 check("pause_and_title_share_audio_settings", volume.value == 68.0 and is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(0.68)))
 volume.value = initial_volume
 await key(KEY_ESCAPE)
 continue_game.grab_focus()

 root.size = Vector2i(960, 600)
 await frames()
 await key(KEY_ENTER)
 var slot_one := title.get_node("%Slot1") as Button
 var slot_two := title.get_node("%Slot2") as Button
 var slot_three := title.get_node("%Slot3") as Button
 var card := title.get_node("Menu/Stage/Card") as Control
 check("slot_picker_fits_small_window", menu.get_global_rect().encloses(card.get_global_rect()) and card.get_global_rect().encloses(slot_three.get_global_rect()))
 check("slot_picker_lists_existing_saves", slot_one.disabled and not slot_two.disabled and "비품실" in slot_two.text and slot_two.has_focus() and "손상된 저장" in slot_three.text)
 await capture("02_continue_960")
 await key(KEY_ESCAPE)
 check("escape_returns_to_title_actions", continue_game.is_visible_in_tree() and continue_game.has_focus())
 await click(continue_game)
 await click(slot_three)
 check("corrupt_slot_keeps_picker_open", menu.visible and slot_three.is_visible_in_tree() and not title.has_node("Main") and "손상" in title.get_node("%SlotMessage").text)
 await click(slot_two)
 mission = title.get_node_or_null("Main") as MissionScript
 check("continue_loads_the_selected_slot", mission != null and not menu.visible and mission.world.map_id == "storage" and mission.world.player_hp == 71 and mission.world.get_node("Enemies/DroneA").hp == 0)
 if not mission:
  finish()
  return
 check("continue_restores_both_dialogue_histories", mission.brain.history.size() == 1 and mission.brain.history[0].question == SAVED_QUESTION and mission.combat_hud.journal.entries.any(func(entry): return entry.body == SAVED_QUESTION))
 check("continue_drops_draft_and_keeps_ids_distinct", mission.question.text.is_empty() and mission.brain.trial > previous_trial and mission.brain.serial >= 7)

 # Enter the final panel boundary. The containment suite plays the preceding mission.
 mission.world.containment.stage = "panel_ready"
 mission.world.containment.panel_completed()
 mission._ending_elapsed = mission.ENDING_SECONDS
 await frames()
 check("completion_opens_result", mission.world.finished and mission.result_screen.visible)
 await click(mission.result_screen.get_node("Center/Card/Margin/Content/Buttons/ReturnToTitle"))
 check("result_returns_to_title", menu.visible and not paused and not is_instance_valid(mission))
 await click(new_game)
 mission = title.get_node_or_null("Main") as MissionScript
 check("fresh_game_resets_mission", mission != null and mission.world.map_id == "lab" and mission.world.story.stage == "on_shift" and not mission.world.finished and mission.world.player_hp == mission.world.max_hp and not mission.world.flashlight_owned and mission.world.containment.stage == "unobserved" and not mission.result_screen.visible)
 if not mission:
  finish()
  return
 check("fresh_game_resets_enemies", mission.world.get_node("Enemies").get_children().all(func(enemy): return enemy.hp == enemy.max_hp) and mission.world.containment.remaining() == 0)
 check("fresh_game_resets_dialogue", mission.brain.history.is_empty() and mission.combat_hud.journal.entries.is_empty() and mission.question.text.is_empty() and mission.brain.pending.is_empty())
 check("saved_slot_bytes_preserved", not FileAccess.file_exists(save_path) and FileAccess.get_sha256(backup_path) == save_hash)
 mission.close_dialogue()
 mission.fleet_saves_only = true
 mission.toggle_pause()
 mission.pause_menu.show_slots(true)
 var pause_slot := mission.pause_menu.get_node("Window/Slots/Slot2") as Button
 check("fleet_pause_hides_development_slot", pause_slot.disabled and "비어 있음" in pause_slot.text)
 check("fleet_rejects_direct_development_load", not mission.load_slot(2) and "이전 개발 맵" in store.last_error and FileAccess.get_sha256(backup_path) == save_hash)
 await click(mission.pause_menu.get_node("Window/Slots/Back"))
 await click(mission.pause_menu.get_node("Window/ReturnToTitle"))
 title._fleet_saves_only = true
 title._show_slots()
 check("fleet_title_hides_development_slot", slot_two.disabled and "비어 있음" in slot_two.text and FileAccess.get_sha256(backup_path) == save_hash)
 title._show_actions()
 finish()

func finish() -> void:
 var result := {"passed": not checks.values().has(false), "check_count": checks.size(), "checks": checks, "gpu_rendered": rendered, "created_utc": Time.get_datetime_string_from_system(true)}
 FileAccess.open(evidence.path_join("render.json" if rendered else "test.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
 print("TITLE_MENU_RESULT ", JSON.stringify(result))
 if not result.passed:
  quit(1)
  return
 # A timeout fails the process if the actual title Quit button doesn't close it.
 create_timer(2).timeout.connect(func(): quit(1))
 await click(title.get_node("%Quit"))
