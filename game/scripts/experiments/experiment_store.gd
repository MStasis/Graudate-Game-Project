extends RefCounted

const FIELDS := [
	"experiment_id","session_id","scenario_id","scenario_version","provider","trial","kind","question",
	"response_text","selected_action","acceptable_actions","accepted","rejected_reason","elapsed_ms",
	"display_ready_ms","generation_attempts","snapshot_hash","project_fingerprint","actual_model",
	"model_options","timestamp_utc","run_kind","question_id","dialogue_method","common_executor",
	"status","appropriate","timely_valid","valid_action","timed_out","discarded_stale","allowed","rating",
	"model_readiness","attempts","combat","initial_state","pair_id","requested_model","model_thinking",
	"timeout_seconds","max_decision_age","prompt_version","validation_errors","handler","observation",
	"session_order","fixture_hash","common_emergency_enabled","action_outcome","action_accepted","action_status",
	"request_id","decision_started_msec","decision_finished_msec","snapshot_matches","regeneration_count"
]
var run_kind := "pilot"
var profile_study := false
const PROFILE_FIELDS := ["profile_id","profile_version","blind_id","keep_alive","model_thinking_values","first_dialogue_ms","final_attempt_first_dialogue_ms","first_validation_error","screen_display_ms","server_totals"]
var error := ""

func directory() -> String:
	var root := "user://dialogue_optimization" if profile_study else "user://experiments"
	return root.path_join(run_kind)

static func uid() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

static func utc() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"

func append(folder: String, session: String, data: Dictionary) -> bool:
	error = ""
	var base := directory().path_join(folder)
	var code := DirAccess.make_dir_recursive_absolute(base)
	if code != OK:
		error = "기록 폴더 생성 실패 · " + error_string(code)
		return false
	var path := base.path_join(session + ".jsonl")
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f:
		f.seek_end()
		if f.store_line(JSON.stringify(data)):
			f.flush()
			if f.get_error() == OK: return true
	error = "기록 저장 실패 · " + ProjectSettings.globalize_path(path)
	return false

func sessions() -> PackedStringArray:
	var path := directory().path_join("sessions")
	var names := PackedStringArray()
	if DirAccess.dir_exists_absolute(path):
		for file in DirAccess.get_files_at(path):
			if file.ends_with(".jsonl"): names.append(file.get_basename())
	names.sort()
	names.reverse()
	return names

func read_rows(kind: String, session: String) -> Array:
	var path := directory().path_join(kind).path_join(session + ".jsonl")
	var rows := []
	if not FileAccess.file_exists(path): return rows
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		error = "기록 읽기 실패 · " + path
		return rows
	while f.get_position() < f.get_length():
		var line := f.get_line()
		var record = JSON.parse_string(line)
		if record is Dictionary: rows.append(record)
		elif not line.strip_edges().is_empty(): error = "손상된 기록 행 · " + path
	return rows

func results(session: String) -> Array:
	error = ""
	var rows := []
	var ratings := {}
	var presentations := {}
	if profile_study:
		for entry in read_rows("presentation", session):
			presentations[entry.experiment_id] = entry.screen_display_ms
	var completed := {}
	for record in read_rows("ratings", session):
		ratings[record.experiment_id] = record.rating
	for kind in ["dialogue", "decision", "combat"]:
		for row in read_rows(kind, session):
			row.rating = ratings.get(row.experiment_id)
			if profile_study: row.screen_display_ms = presentations.get(row.experiment_id)
			rows.append(row)
			completed[row.experiment_id] = true
	# A power loss can leave a durable start and no terminal row. Keep it in the denominator.
	for event in read_rows("sessions", session):
		if event.event != "request_started" or completed.has(event.experiment_id) or not event.has("initial"): continue
		var row: Dictionary = event.initial
		for field in FIELDS:
			if not row.has(field): row[field] = null
		row.status = "unfinished"
		row.attempts = []
		rows.append(row)
	return rows

func export_csv(session: String) -> String:
	var rows := results(session)
	if not error.is_empty(): return ""
	if rows.is_empty():
		error = "내보낼 완료 기록이 없습니다."
		return ""
	var path := directory().path_join("sessions").path_join(session + "-" + uid().left(8) + ".csv")
	var f := FileAccess.open(path, FileAccess.WRITE)
	var fields: Array = FIELDS + PROFILE_FIELDS if profile_study else FIELDS
	if f and f.store_buffer(PackedByteArray([239,187,191])) and f.store_csv_line(PackedStringArray(fields)):
		for row in rows:
			var cells := PackedStringArray()
			for key in fields:
				var value = row.get(key)
				if value is Dictionary or value is Array: cells.append(JSON.stringify(value))
				else: cells.append("" if value == null else str(value))
			if not f.store_csv_line(cells):
				error = "CSV 행 저장 실패 · " + path
				return ""
		f.flush()
		if f.get_error() == OK: return ProjectSettings.globalize_path(path)
	error = "CSV 저장 실패 · " + path
	return ""
