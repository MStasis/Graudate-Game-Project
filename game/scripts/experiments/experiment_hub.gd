extends ColorRect
signal title_requested

const Runner := preload("res://scripts/experiments/experiment_runner.gd")
const Summary := preload("res://scripts/experiments/experiment_summary.gd")
const PORTRAIT := preload("res://resources/MikaPortrait.tres")
const DISPLAY := preload("res://assets/ui/bulkhead/BarlowCondensed-Black.ttf")
const ACCENT := Color("#72dbcc")
const NAMES := {"dialogue":"대화 성능 비교","decision":"전투 지원 판단 비교","combat":"전투 재현 실험","results":"실험 기록 확인"}
const TITLES := {"home":"NPC PERFORMANCE LAB","dialogue":"DIALOGUE COMPARISON","decision":"SUPPORT DECISIONS","combat":"COMBAT REPLAY","results":"EXPERIMENT RECORDS"}
const STATUS := {"appropriate":"적절","inappropriate":"부적절","success":"응답 성공","timeout":"시간초과","invalid_action":"후보 밖 행동","cancelled":"취소","request_failed":"요청 실패","rejected":"거절"}
const CRITERIA := ["질문 관련성","게임 사실 정확성","캐릭터 일관성","대화 자연스러움"]
var runner := Runner.new()
var mode := "home"
var body := VBoxContainer.new()
var heading := Label.new()
var back := Button.new()
var notice := Label.new()
var scenario: OptionButton
var preset: OptionButton
var question: LineEdit
var repeat: OptionButton
var scenario_info: Label
var progress_bar: ProgressBar
var controls: Array = []
var stop_button: Button
var cards := {}
var last_cases := []
var last_count := 1
var history_rows := []
var session_picker: OptionButton
var row_picker: OptionButton
var details: VBoxContainer
var scores := []
var bad_fact: CheckBox
var last_mode_session := ""
var results_split: BoxContainer
var batch_summary: Label
var provider_filter: OptionButton
var scenario_filter: OptionButton
var session_rows := []

func _ready() -> void:
	add_child(runner)
	runner.progress.connect(_progress)
	runner.recorded.connect(_recorded)
	runner.finished.connect(_finished)
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26 if side in ["left","right"] else 16)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation",9)
	margin.add_child(page)
	var header := HBoxContainer.new()
	page.add_child(header)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_font_override("font", DISPLAY)
	heading.add_theme_font_size_override("font_size",38)
	heading.modulate = ACCENT
	header.add_child(heading)
	header.add_child(back)
	back.pressed.connect(_back)
	page.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",10)
	scroll.add_child(body)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(notice)
	resized.connect(_adapt)
	open_mode("home")

func _clear(container: Control) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _button(parent: Control, caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 40
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _label(parent: Control, caption: String) -> Label:
	var label := Label.new()
	label.text = caption
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _panel(parent: Control) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation",8)
	panel.add_child(content)
	return content

func _back() -> void:
	if runner.running: runner.stop()
	if not runner.unsaved.is_empty() and not runner.retry_save():
		notice.text = runner.store.error
		return
	if mode == "home": title_requested.emit()
	else: open_mode("home")

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		if get_viewport().gui_get_focus_owner() is LineEdit:
			get_viewport().gui_release_focus()
		else: _back()

func open_mode(next: String) -> void:
	if runner.running: return
	mode = next
	_clear(body)
	results_split = null
	batch_summary = null
	controls.clear()
	cards.clear()
	last_cases.clear()
	last_mode_session = ""
	notice.text = ""
	heading.text = TITLES[next]
	back.text = "타이틀로 돌아가기" if mode == "home" else "실험실 메뉴"
	if mode == "home":
		var content := _panel(body)
		if "--experiment-test" not in OS.get_cmdline_user_args():
			var scope := HBoxContainer.new()
			content.add_child(scope)
			var picker := OptionButton.new()
			root_option(scope,picker,"수집 용도")
			picker.add_item("논문 수집")
			picker.add_item("예비 실험")
			picker.select(0 if runner.store.run_kind == "research" else 1)
			picker.item_selected.connect(func(i): runner.store.run_kind = "research" if i == 0 else "pilot")
		for key in NAMES:
			var b := _button(content,NAMES[key],open_mode.bind(key))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.custom_minimum_size.y = 62
			if key == "dialogue": b.grab_focus()
	elif mode == "results": _results()
	else: _lab()

func _lab() -> void:
	var config := _panel(body)
	var line := HFlowContainer.new()
	config.add_child(line)
	scenario = OptionButton.new()
	root_option(line,scenario,"진행 상황" if mode == "dialogue" else "시나리오")
	for item in runner.factory.catalog[mode]:
		scenario.add_item(item.id + "  " + item.name)
		scenario.set_item_metadata(-1,item)
	scenario.add_item("전체 시나리오")
	scenario.set_item_metadata(-1,{})
	repeat = OptionButton.new()
	root_option(line,repeat,"반복 횟수")
	for n in [1,5,10,20]: repeat.add_item("%d회" % n,n)
	scenario_info = _label(config,"")
	if mode == "dialogue":
		preset = OptionButton.new()
		config.add_child(preset)
		preset.item_selected.connect(_preset_changed)
		question = LineEdit.new()
		question.max_length = MikaDialogue.QUESTION_LIMIT
		question.placeholder_text = "미카에게 물어볼 질문을 입력하세요"
		question.custom_minimum_size.y = 42
		question.text_submitted.connect(func(_text): _start(false))
		config.add_child(question)
		controls.append_array([question,preset])
	scenario.item_selected.connect(_scenario_changed)
	var actions := HFlowContainer.new()
	body.add_child(actions)
	controls.append_array([scenario,repeat,_button(actions,"비교 실행",_start.bind(false))])
	if mode == "dialogue":
		controls.append(_button(actions,"질문 세트 실행",_start.bind(true)))
		controls.append(_button(actions,"동일 질문 재실행",_rerun))
		controls.append(_button(actions,"대화 초기화",_reset_dialogue))
	stop_button = _button(actions,"실행 중단",runner.stop)
	stop_button.disabled = true
	_button(actions,"기록 저장 · CSV",_export_current)
	progress_bar = ProgressBar.new()
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size.y = 7
	body.add_child(progress_bar)
	if mode == "combat":
		var display := TextureRect.new()
		display.texture = runner.viewport.get_texture()
		display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		display.custom_minimum_size.y = 200
		body.add_child(display)
	results_split = BoxContainer.new()
	body.add_child(results_split)
	for provider in NPCBrain.PROVIDERS.slice(0,2):
		var card := _panel(results_split)
		var header := HBoxContainer.new()
		card.add_child(header)
		if mode == "dialogue":
			var portrait := TextureRect.new()
			portrait.texture = PORTRAIT
			portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			portrait.custom_minimum_size = Vector2(48,48)
			portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			header.add_child(portrait)
		var nameplate := Label.new()
		header.add_child(nameplate)
		nameplate.text = "RULE BASED" if provider == "RuleBased" else "LOCAL LLM"
		nameplate.add_theme_font_override("font",DISPLAY)
		nameplate.add_theme_font_size_override("font_size",25)
		nameplate.modulate = ACCENT if provider == "LocalLLM" else Color("#e5d7ba")
		var text := RichTextLabel.new()
		text.selection_enabled = true
		text.scroll_following = true
		text.custom_minimum_size.y = 150
		card.add_child(text)
		cards[provider] = text
	batch_summary = _label(body,"")
	batch_summary.hide()
	_scenario_changed(0)
	if mode == "dialogue" and not runner.factory.question_error.is_empty(): notice.text = runner.factory.question_error
	_adapt()
	scenario.grab_focus()

func root_option(parent: Control, option: OptionButton, caption: String) -> void:
	var label := Label.new()
	label.text = caption
	parent.add_child(label)
	parent.add_child(option)

func _adapt() -> void:
	if is_instance_valid(results_split): results_split.vertical = size.x < 800

func _scenario_changed(index: int) -> void:
	var item: Dictionary = scenario.get_item_metadata(index)
	if mode == "dialogue":
		preset.clear()
		preset.add_item("자유 질문")
		preset.set_item_metadata(0,{})
		for q in runner.factory.questions:
			if item.is_empty() or q.scenario_id == item.id:
				preset.add_item(q.id + "  " + q.text)
				preset.set_item_metadata(-1,q)
		if preset.item_count > 1:
			preset.select(1)
			_preset_changed(1)
	if item.is_empty():
		scenario_info.text = "모든 상황을 순서대로 실행합니다."
		return
	if not runner.prepare(item,0):
		scenario_info.text = "시나리오 시작 상태 검증 실패"
		return
	var state := runner.world.game_state()
	if mode == "dialogue":
		scenario_info.text = "%s    ·    퓨즈 보유 %s    ·    전력 복구 %s    ·    복도 적 조우 %s    ·    레버 조작 %s" % [state.location,yn(state.fuse_in_inventory),yn(state.power_restored),yn(state.fleet_context["복도 적 발견"]),yn(state.fleet_context["레버 조작 가능"])]
	else:
		scenario_info.text = "%s    ·    HP %d    ·    탄약 %d / 예비 %d    ·    적 %d    ·    후보 %s" % [state.location,state.player_hp,state.ammo,state.magazines,state.enemy_count,", ".join(state.valid_actions)]
		if mode == "combat": scenario_info.text += "\n%d초 생존 · 고정 위치/사격 입력 · 회차당 지원 판단 1회 · 공통 긴급 지원 끔" % item.seconds

func yn(value: bool) -> String:
	return "예" if value else "아니오"

func _preset_changed(index: int) -> void:
	var q: Dictionary = preset.get_item_metadata(index)
	question.text = q.get("text","")
	preset.tooltip_text = "%s · %s" % [q.get("purpose",""),q.get("fact","")]

func _start(use_set: bool) -> void:
	if runner.running: return
	var selected: Dictionary = scenario.get_item_metadata(scenario.selected)
	var cases := []
	for item in runner.factory.catalog[mode]:
		if not selected.is_empty() and selected.id != item.id: continue
		if use_set:
			for q in runner.factory.questions:
				if q.scenario_id == item.id: cases.append({"item":item,"question_id":q.id,"question":q.text})
		elif mode == "dialogue":
			var text := question.text.strip_edges()
			if text.is_empty():
				notice.text = "질문을 입력하세요."
				question.grab_focus()
				return
			var q: Dictionary = preset.get_item_metadata(preset.selected)
			cases.append({"item":item,"question":text,"question_id":q.get("id","") if text == q.get("text") and q.get("scenario_id") == item.id else ""})
		else: cases.append({"item":item})
	_launch(cases,repeat.get_selected_id())

func _launch(cases: Array, count: int) -> void:
	if cases.is_empty():
		notice.text = "선택한 상황에 등록된 질문이 없습니다."
		return
	if runner.start(mode,cases,count):
		last_cases = cases.duplicate(true)
		last_count = count
		last_mode_session = runner.session
		batch_summary.hide()
		for card in cards.values(): card.clear()
		_lock(true)
		notice.text = "비교 시작"
	elif not runner.unsaved.is_empty(): notice.text = "저장되지 않은 회차가 있습니다. 기록 저장을 다시 누르세요."

func _rerun() -> void:
	if last_cases.is_empty(): _start(false)
	else: _launch(last_cases,last_count)

func _reset_dialogue() -> void:
	for card in cards.values(): card.clear()
	runner.brain.history.clear()
	runner.brain.dialogue_grounding.clear()
	batch_summary.hide()
	last_cases.clear()
	preset.select(0)
	_preset_changed(0)
	notice.text = "입력과 표시를 초기화했습니다. 저장된 회차는 실험 기록에서 확인할 수 있습니다."
	question.grab_focus()

func _lock(locked: bool) -> void:
	for control in controls:
		if control is LineEdit: control.editable = not locked
		else: control.disabled = locked
	stop_button.disabled = not locked

func _progress(done: int,total: int,message: String) -> void:
	progress_bar.max_value = total
	progress_bar.value = done
	notice.text = "%d / %d    %s" % [done,total,message]

func _finished(message: String) -> void:
	if mode in ["dialogue","decision","combat"]:
		_lock(false)
		notice.text = "%d / %d    %s" % [runner.done,runner.jobs.size(),message]
		if mode == "combat" and not runner.running and not runner.session.is_empty():
			batch_summary.text = Summary.summarize(runner.store.results(runner.session))
			batch_summary.visible = not batch_summary.text.is_empty()

func describe(row: Dictionary) -> String:
	var latency := "—" if row.elapsed_ms == null else "%.3f ms" % row.elapsed_ms
	var lines := PackedStringArray(["%s · %d회차 · %s · %s" % [row.scenario_id,row.trial,STATUS.get(row.status,row.status),latency]])
	if row.status == "unfinished": return "%s · %d회차 · 종료 기록 없음\n%s" % [row.scenario_id,row.trial,row.question]
	if row.kind == "dialogue":
		lines.append("Q. " + row.question)
		if row.response_text != null: lines.append(str(row.response_text))
		lines.append("처리  %s · 생성 %d회" % [row.actual_model if row.actual_model else row.handler,row.generation_attempts])
	else:
		lines.append("선택  %s   /   실행  %s" % [row.selected_action if row.selected_action else "—",row.action_outcome if row.action_outcome else "—"])
		if row.appropriate != null: lines.append("허용 집합 일치 %s · 시간 내 유효 %s" % [yn(row.appropriate),yn(row.timely_valid)])
	if row.rejected_reason: lines.append("사유  " + row.rejected_reason)
	if row.combat is Dictionary:
		var changes: Array = row.combat.resource_changes
		lines.append("%s · %.2f초 · 지원 완료 %s" % [row.combat.outcome,row.combat.duration_seconds,JSON.stringify(row.combat.completed)])
		if not changes.is_empty():
			lines.append("HP %d → %d · 탄약 %d → %d · 예비 %d → %d" % [changes[0].hp,changes[-1].hp,changes[0].ammo,changes[-1].ammo,changes[0].magazines,changes[-1].magazines])
	return "\n".join(lines)

func _recorded(row: Dictionary) -> void:
	if cards.has(row.provider):
		cards[row.provider].add_text(describe(row) + "\n\n")

func _export_current() -> void:
	if not runner.retry_save():
		notice.text = runner.store.error
		return
	if last_mode_session.is_empty():
		notice.text = "먼저 비교를 실행하세요."
		return
	_export(last_mode_session)

func _export(id: String) -> void:
	var path := runner.store.export_csv(id)
	notice.text = path if not path.is_empty() else runner.store.error

func _results() -> void:
	session_picker = OptionButton.new()
	body.add_child(session_picker)
	for id in runner.store.sessions(): session_picker.add_item(id)
	if session_picker.item_count == 0:
		_label(body,"저장된 실험 회차가 없습니다.")
		return
	session_picker.item_selected.connect(_load_session)
	var bar := HFlowContainer.new()
	body.add_child(bar)
	provider_filter = OptionButton.new()
	bar.add_child(provider_filter)
	for provider in ["전체 제공자","RuleBased","LocalLLM"]: provider_filter.add_item(provider)
	scenario_filter = OptionButton.new()
	bar.add_child(scenario_filter)
	for filter in [provider_filter,scenario_filter]:
		filter.item_selected.connect(func(_i): _filter_rows())
	row_picker = OptionButton.new()
	bar.add_child(row_picker)
	row_picker.item_selected.connect(_show_record)
	_button(bar,"세션 CSV 내보내기",func(): _export(session_picker.get_item_text(session_picker.selected)))
	details = VBoxContainer.new()
	body.add_child(details)
	_load_session(0)
	session_picker.grab_focus()

func _load_session(index: int) -> void:
	session_rows = runner.store.results(session_picker.get_item_text(index))
	scenario_filter.clear()
	scenario_filter.add_item("전체 상황")
	var ids := []
	for row in session_rows:
		if row.scenario_id not in ids: ids.append(row.scenario_id)
	ids.sort()
	for id in ids: scenario_filter.add_item(id)
	provider_filter.select(0)
	_filter_rows()
	if not runner.store.error.is_empty(): notice.text = runner.store.error

func _filter_rows() -> void:
	var provider := provider_filter.get_item_text(provider_filter.selected)
	var scenario_id := scenario_filter.get_item_text(scenario_filter.selected)
	history_rows = session_rows.filter(func(r): return (provider_filter.selected == 0 or r.provider == provider) and (scenario_filter.selected == 0 or r.scenario_id == scenario_id))
	row_picker.clear()
	for row in history_rows:
		row_picker.add_item("%s · %s · %d회차 · %s" % [row.scenario_id,row.provider,row.trial,STATUS.get(row.status,row.status)])
	if history_rows.is_empty():
		_clear(details)
		notice.text = "이 조건에 해당하는 완료 기록이 없습니다."
	else: _show_record(0)

func _show_record(index: int) -> void:
	_clear(details)
	scores.clear()
	var row: Dictionary = history_rows[index]
	var panel := _panel(details)
	_label(panel,describe(row))
	if row.kind == "dialogue" and row.status != "unfinished":
		for attempt in row.attempts:
			_label(panel,"생성 %d · %s" % [int(attempt.attempt)+1,attempt.get("response",attempt.get("partial_response",""))])
		var form := HFlowContainer.new()
		panel.add_child(form)
		for criterion in CRITERIA:
			var picker := OptionButton.new()
			root_option(form,picker,criterion)
			for v in ["미평가","0","1","2"]: picker.add_item(v)
			if row.rating is Dictionary: picker.select(int(row.rating.scores[criterion])+1)
			scores.append(picker)
		bad_fact = CheckBox.new()
		bad_fact.text = "잘못된 게임 사실 포함"
		bad_fact.button_pressed = row.rating is Dictionary and row.rating.wrong_fact
		form.add_child(bad_fact)
		_button(form,"평가 저장",_save_rating.bind(index))
	_label(details,Summary.summarize(history_rows))
	notice.text = "저장 경로  " + ProjectSettings.globalize_path(runner.store.directory())

func _save_rating(index: int) -> void:
	var rating := {"scores":{},"total":0,"wrong_fact":bad_fact.button_pressed}
	for i in scores.size():
		if scores[i].selected == 0:
			notice.text = "네 항목에 각각 0~2점을 선택하세요."
			return
		var score: int = scores[i].selected - 1
		rating.scores[CRITERIA[i]] = score
		rating.total += score
	var row: Dictionary = history_rows[index]
	if runner.store.append("ratings",row.session_id,{"experiment_id":row.experiment_id,"timestamp_utc":runner.store.utc(),"rating":rating}):
		row.rating = rating
		_show_record(index)
		notice.text = "평가 저장 · %d / 8" % rating.total
	else: notice.text = runner.store.error

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_instance_valid(runner) and runner.running: runner.stop("window_closed")
