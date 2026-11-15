class_name MikaDialogue
extends RefCounted
const CHARACTER = preload("res://resources/MikaCharacter.tres")
const HISTORY_LIMIT := 8
const HISTORY_CHAR_BUDGET := 850
const AMBIENT := {"on_shift": "평상시 연구실 근무. 아직 정전·경보·전투는 발생하지 않음.", "blackout": "정전 직후. 아직 전력은 복구되지 않았고 침식 경보는 관측 전.", "equipment": "정전 중. 플레이어는 손전등 보유. 침식 경보는 아직 관측 전.", "fuse_search": "정전된 비품실. 침식 경보는 아직 관측 전.", "fuse_return": "비품실 전투와 퓨즈 회수가 끝났지만 아직 정전 중.", "power_restored": "전력 복구와 장치 재가동 직후. 아직 경보는 관측하지 않음.", "anomaly_alarm": "전력 복구 후 실제 침식 경보가 발생함. 전체 문제는 미해결.", "main_entry": "연구동 진입실에 도착. 비품실 전투는 끝났음. 경보는 실제 발생했고 전체 임무는 미완료."}
const PHASES := {"on_shift": "평상시 연구소 근무. 아직 정전 전.", "blackout": "갑자기 정전 발생. 미카가 보안 직원인 플레이어를 불러 장비를 챙기는 중.", "equipment": "플레이어가 손전등을 받음. 퓨즈 확보를 위해 비품실로 출발.", "fuse_search": "비품실에서 선원을 제압하고 두 패널 보관함의 퓨즈를 확보하는 중.", "fuse_return": "퓨즈 확보 완료. 연구실 전력 장치에 장착할 차례.", "power_restored": "퓨즈 장착으로 전력은 복구됨. 장치가 재가동되는 순간. 전체 문제 해결 아님.", "anomaly_alarm": "전력 복구 뒤 침식된 장치가 드러나고 경고등이 켜짐. 출발 문으로 연구동에 갈 차례.", "main_entry": "전력을 복구하고 연구동 진입실에 도착. 관측 단말에서 침식 신호를 확인해야 함. 이상현상 봉쇄는 아직 완료하지 못함."}

static func topic_for(question: String, history: Array, fleet := false) -> String:
 var topic := NPCPolicy.rule_intent(question, fleet)
 if NPCPolicy.has_word(question, ["불 들어", "경보", "이상현상", "정전"]): return "mission"
 if topic == "unknown" and NPCPolicy.has_word(question, ["그럼", "반대쪽", "그거", "아까", "다음엔", "지금은"]):
  for index in range(history.size() - 1, -1, -1):
   var previous := NPCPolicy.rule_intent(str(history[index].get("question", "")), fleet)
   if previous in ["mission", "support"]: return previous
 return topic

static func recent_history(history: Array, casual: bool, fleet := false) -> Array:
 var result := []
 var remaining := HISTORY_CHAR_BUDGET
 for index in range(history.size() - 1, -1, -1):
  var turn: Dictionary = history[index]
  # 새 잡담에는 먼 임무 매뉴얼을 빼되, 지시어가 있는 후속 질문은 build에서 전체 최근 문답을 사용한다.
  if casual and NPCPolicy.rule_intent(str(turn.get("question", "")), fleet) not in ["everyday", "relationship", "unknown"]: continue
  var entry := {"question": str(turn.get("question", "")).left(160), "answer": str(turn.get("answer", "")).left(230)}
  var cost: int = entry.question.length() + entry.answer.length()
  if cost > remaining or result.size() >= HISTORY_LIMIT: break
  remaining -= cost
  result.push_front(entry)
 return result
## 잡담에 목표/HUD/기믹 매뉴얼을 주입하지 않는 대화 전용 문맥.
static func style_examples(topic: String, question := "") -> Array:
 var dataset = JSON.parse_string(FileAccess.get_file_as_string("res://resources/mika_style_examples.json").trim_prefix("\ufeff"))
 var ids := ["sample_0004"] if topic in ["mission", "support"] else ["sample_0003", "sample_0005"]
 if topic not in ["mission", "support"] and NPCPolicy.has_word(question, ["밥", "먹", "메뉴"]): ids = ["sample_0007", "sample_0008"]
 elif topic not in ["mission", "support"] and NPCPolicy.has_word(question, ["퇴근", "쉬", "근무"]): ids = ["sample_0005", "sample_0006"]
 var result := []
 if not dataset is Dictionary: return result
 for sample in dataset.samples:
  if sample.id in ids:
   result.append({"fictional_style_only": true, "player": sample.question, "Mika": sample.lines})
 return result

static func build(state: Dictionary, question: String, history: Array, persona: String, extra_style: String) -> Dictionary:
 if state.get("fleet_demo", false): return _build_fleet(state, question, history, extra_style)
 var topic := topic_for(question, history)
 var casual := topic in ["everyday", "relationship", "unknown"]
 var referring := NPCPolicy.has_word(question, ["그럼", "그거", "아까", "그 음식", "지금은", "네가 말"])
 var system := "너는 연구소 정비사 미카. 상대는 함께 일하던 보안 직원이야. 한국어 반말로 말해. '~해', '~야' 같은 편한 말투를 쓰고 '~요', '~습니다'는 쓰지 마. 진행 질문은 최신 사실 우선으로 핵심을 알려 줘. 잡담은 장난·능청·회피·짧은 반문(counterquestions)도 가능해. 문장 수나 격려·역질문 끝맺음은 강제하지 않아. 가상 예시는 말투 참고일 뿐 실제 사건·규정·취향·기억이 아니야. 실행 전 행동을 완료했다고 말하지 마. 마지막 현재 플레이어 말에만 반응해. JSON/행동 주석/서술 없이 미카의 발화만 써."
 var context := {"고정 역할·세계관": {"identity": CHARACTER.identity, "voice": CHARACTER.voice, "scene_role": persona.left(240)}, "현재 서사 단계": state.get("story", {}).get("stage", "blackout"), "최근 대화 (실제 문답)": recent_history(history, casual and not referring), "말투 참고 (가상·기억 아님)": style_examples(topic, question)}
 context["현재 장면"] = PHASES.get(str(context["현재 서사 단계"]), "현재 상태 참고") if not casual else AMBIENT.get(str(context["현재 서사 단계"]), "친숙한 동료와 근무 중 대화")
 if state.get("story", {}).get("stage") in ["containment", "contained"]:
  context["현재 장면"] = "연구동 외곽의 침식 확산을 일시적으로 차단함. 내부 후속 조사 필요." if state.get("escaped", false) else "연구동 외곽 임시 봉쇄 중. 튜토리얼 전력 복구는 끝났고 연구소 전체 이상현상은 미해결."
 if casual: context["현재 장면의 용도"] = "배경 사실만 지킨다. 잡담을 임무 매뉴얼이나 과거 목표로 돌리지 않는다."
 context["미확정 배경"] = "식사 여부, 고정 최애 음식, 퇴근 불가 규정, 통신 두절은 확인되지 않았다. 예시에서 실제 과거를 가져오지 않는다."
 if not casual:
  context["실제 완료·관측 사건"] = state.get("story", {}).get("events", [])
  context["관련 공동 사건"] = related_events(state, question, topic)
  context["현재 장소"] = state.location
  var grounded_question := question
  if referring and not history.is_empty() and not NPCPolicy.has_word(question, ["불", "퓨즈", "부품", "경보", "이상", "임무"]): grounded_question += " " + str(history.back().get("question", ""))
  var current_facts := facts(state, grounded_question, topic)
  context["CURRENT FACTS (최신 사실)"] = current_facts
  if topic == "mission" and NPCPolicy.has_word(question.replace(" ", ""), ["그럼지금", "이제뭘", "다음단계", "다음엔"]):
   context["지금 진행에 필요한 핵심"] = current_facts.get("다음 단계", {}) if state.map_id == "main_entry" else state.get("current_guidance", "")
  elif current_facts.has("질문이 가리키는 물품"):
   context["이 질문에 필요한 핵심 정보"] = current_facts["질문이 가리키는 물품"]
  elif topic == "mission" and NPCPolicy.has_word(question.replace(" ", ""), ["뭘해야", "무엇을해야", "뭐해야", "어디부터", "다음", "그럼지금", "어디로가", "어디가야", "뭘확인"]):
   context["지금 진행에 필요한 핵심"] = current_facts.get("다음 단계", {}) if state.map_id == "main_entry" else state.get("current_guidance", "")
  context["조작 설명 요청"] = NPCPolicy.asks_controls(question)
  context["응답 목적"] = "장난보다 진행에 필요한 핵심 사실을 우선해서 알려 준다. CURRENT FACTS에 있는 상태가 예전 대화보다 우선한다."
 elif NPCPolicy.has_word(question, ["기억", "같이 했"]) and NPCPolicy.has_word(question, ["정전", "전력", "퓨즈", "패널", "치료", "소생"]):
  context["관련 실제 사건"] = related_events(state, question, topic)
 if NPCPolicy.has_word(question, ["밥", "먹", "퇴근", "취향"]): context["미확정 사항"] = CHARACTER.background + " " + CHARACTER.preferences
 if state.get("npc_downed", false): context["현재 몸 상태"] = "미카 다운. 가까이에서 키트로 소생하기 전에는 이동·지원 불가."
 return _conversation(system, context, question)

static func _build_fleet(state: Dictionary, question: String, history: Array, extra_style: String) -> Dictionary:
 var topic := topic_for(question, history, true)
 var casual := topic in ["everyday", "relationship", "unknown"]
 var scene: Dictionary = state.fleet_context
 var system := "너는 개척선 정비사 미카. 상대는 이미 친한 동료야. 자연스러운 한국어 반말로 실제 대사만 짧게 답해. 주석·JSON·지문은 빼. 툴툴대거나 장난쳐도 좋아. 격려·역질문은 필요할 때만. 최신 사실에 있는 위치·방향·행동 주체를 지켜. 질문의 전제, 예시, 지난 답변은 사건의 증거가 아니야. 정보가 없으면 모른다고 해. 사격과 E로 아이템 줍기는 플레이어가 맡아. 실제로 끝난 지원만 완료했다고 말해."
 system += " 미카 자신은 '나', 옆의 동료는 '너'라고 불러."
 var context := {
  "역할": {"직책": "개척선 정비사", "관계": "이미 친한 동료", "말투": CHARACTER.voice, "성격": "일할 때는 손이 빠르고 무뚝뚝할 수 있다. 가끔 장난을 치며 필요하면 돕는다."},
  "말투 선호": extra_style.left(240),
  "최근 대화 (실제 문답)": recent_history(history, casual, true),
  # The old mission's panel tutorial also appears in its fictional examples.
  "말투 참고 (가상·기억 아님)": style_examples("everyday", question) if casual else [],
 }
 if casual:
  context["현재 장면"] = {"장소": state.location, "전력 복구": state.power_restored, "통신 장애 확인": scene["통신 장애 확인"], "경보 중": scene["복도 경보"]}
  context["응답 목적"] = "배경만 지키고 잡담은 지금 상대가 한 말에 답해."
 else:
  context["CURRENT FACTS (최신 사실)"] = facts(state, question, topic)
  context["응답 목적"] = "질문에 필요한 현재 사실만 답해. 다음 목표는 할 일로 말해."
  if topic == "mission":
   context["질문에 우선할 사실"] = _fleet_focus(state, question)
 if state.npc_downed: context["현재 몸 상태"] = "다운 상태. 소생 전에는 움직이거나 지원할 수 없다."
 return _conversation(system, context, question)

static func _fleet_focus(state: Dictionary, question: String) -> String:
 var scene: Dictionary = state.fleet_context
 var compact := question.replace(" ", "")
 if NPCPolicy.has_word(compact, ["통신", "무전"]):
  if scene["통신 장애 확인"]: return "마지막으로 확인했을 땐 통신이 먹통이었다. 그 뒤엔 재확인한 적 없다. 통신 질문에는 원인을 추측하거나 적·전력 이야기를 덧붙이지 않는다."
  return "함선 통신망을 확인한 적 없다. 이 질문에는 아직 확인하지 않았다는 답만 한다."
 if NPCPolicy.has_word(compact, ["퓨즈", "캐비닛"]):
  if scene["퓨즈 장착"]: return "정상 퓨즈는 전기실 주 퓨즈함에 이미 장착됐다."
  if state.fuse_in_inventory: return "정상 퓨즈는 동료가 이미 주워 가지고 있다. 퓨즈를 다시 줍거나 뽑을 필요는 없다."
  if "앞 바닥" in scene["퓨즈 위치"]: return "정상 퓨즈는 비품실 왼쪽 캐비닛 앞 바닥에 있다. 동료가 가까이 가서 E로 줍는다."
  return "정상 퓨즈의 현재 위치는 '%s'다. 말하는 미카는 퓨즈를 주워 주는 사람이 아니다. 동료가 직접 E로 줍는다." % scene["퓨즈 위치"]
 if NPCPolicy.has_word(compact, ["저적", "적들은", "저녀석", "저놈", "선원"]):
  return "복도에서 머리 없는 침식된 선원을 확인했다. 침식의 원인, 감염 경로, 연구원들의 행방은 모른다." if scene["복도 적 발견"] else "이 시점까지 적을 보지 않았다. 질문에 나온 적의 존재나 정체를 사실로 받아들이지 않는다."
 if NPCPolicy.has_word(compact, ["레버", "코어", "격벽", "당기"]):
  if scene["격벽 설치"]: return "두 레버를 당겨 임시 격벽을 설치했다."
  if not scene["격벽 계획 공유"]: return "아직 두 코어와 격벽 계획을 공유한 적 없다. 작동 시점이나 방법은 확인 전이다."
  if scene["레버 조작 가능"]: return "신호가 끝났고 레버 사용 안내가 열렸다. 플레이어는 위쪽 레버에서 E를 새로 한 번 누른다."
  return "전투는 끝났지만 아직 신호를 주지 않았다. 동료에게 위쪽 레버 앞에서 기다리라고 말한다." if scene["B동 전투 종료"] else "현재 한 차수만 끝낸다고 레버가 해제되는 건 아니다. B동 전투를 모두 끝내고 내 신호를 기다린다. 지금은 레버를 조작할 수 없다."
 if scene["진행 단계"] == "TO_POWER": return "복도 오른쪽 전기실로 간다. 그곳에서 플레이어가 E로 미카에게 퓨즈를 건네면 미카가 교체하고 전력을 켠다."
 if scene["진행 단계"] == "REPAIR" and state.fuse_in_inventory: return "미카 옆에서 E를 눌러 퓨즈를 건네면 미카가 교체하고 전력을 켠다."
 if scene["진행 단계"] == "FIND_FUSE" and state.map_id == "mika_quarters":
  return "정상 퓨즈를 비품실에서 찾는다. 오른쪽은 미카 방에서 비품실로 이어지는 문의 방향이다."
 return "현재 목표는 '%s'다." % scene["현재 목표"]

static func grounding_facts(state: Dictionary, question: String, topic: String) -> Dictionary:
 var current := facts(state, question, topic)
 if not state.get("fleet_demo", false) or topic != "mission": return current
 var scene: Dictionary = current["진행 상황"]
 var compact := question.replace(" ", "")
 if NPCPolicy.has_word(compact, ["통신", "무전"]):
  return {"통신 장애 확인": scene["통신 장애 확인"]}
 if NPCPolicy.has_word(compact, ["퓨즈", "캐비닛"]) and not NPCPolicy.has_word(compact, ["다음", "지금뭘", "전력", "불"]):
  return {"퓨즈 위치": scene["퓨즈 위치"], "오른쪽 캐비닛 확인": scene["오른쪽 캐비닛 확인"], "정상 퓨즈 보유": current["정상 퓨즈 보유"]}
 return current

static func _conversation(system: String, context: Dictionary, question: String) -> Dictionary:
 context["PLAYER QUESTION"] = question
 var messages := [{"role": "system", "content": system + "\n다음 예시 대화는 가상의 말투 연습일 뿐 실제 사건이 아니다."}]
 for example in context["말투 참고 (가상·기억 아님)"]:
  messages.append({"role": "user", "content": "[가상 말투 예시] " + str(example.player)})
  messages.append({"role": "assistant", "content": "\n".join(example.Mika)})
 messages.append({"role": "system", "content": "가상 말투 예시는 끝났다. 이제부터 실제 최근 대화다. 예시를 과거 기억으로 회상하지 마."})
 for turn in context["최근 대화 (실제 문답)"]:
  messages.append({"role": "user", "content": turn.question})
  messages.append({"role": "assistant", "content": turn.answer})
 var latest := context.duplicate(true)
 for key in ["말투 참고 (가상·기억 아님)", "최근 대화 (실제 문답)", "PLAYER QUESTION"]: latest.erase(key)
 messages.append({"role": "system", "content": "지금의 실제 상태다. 이전 말보다 이 사실을 우선한다.\n" + JSON.stringify(latest, "", false)})
 messages.append({"role": "user", "content": question})
 return {"system": system, "prompt": JSON.stringify(context, "", false), "schema": {}, "messages": messages}
static func related_events(state: Dictionary, question: String, topic: String) -> Array:
 var events: Array = state.get("recent_shared_events", [])
 if NPCPolicy.has_word(question, ["기억", "아까", "같이 했"]): return events.slice(-3)
 var words := ["손전등"] if "손전등" in question else ["패널", "보관함"] if NPCPolicy.has_word(question, ["패널", "반대쪽", "보관함"]) else ["치료", "보급", "보호", "소생"] if topic == "support" else ["퓨즈", "전력", "선원", "보관함"]
 return events.filter(func(event): return NPCPolicy.has_word(str(event), words)).slice(-3)

static func facts(state: Dictionary, question: String, topic: String) -> Dictionary:
 if state.get("fleet_demo", false):
  var scene: Dictionary = state.fleet_context
  if topic == "support":
   return {"미카 직접 사격": false, "치료 키트": state.medkits, "탄약 보급품": state.supply_packs,
    "플레이어 체력": state.player_hp, "플레이어 탄약": state.ammo, "현재 지원": state.active_action,
    "완료된 지원": state.completed_support, "동행 상태": state.companion_mode, "미카 다운": state.npc_downed,
    "고정 작업": "정상 코어" if scene["격벽 계획 공유"] and state.map_id == "research_lab_b" else "",
    "예비 탄창": state.get("magazines", 0),
    "지원 방법": "치료 키트·보급·치료 장비는 실제 지원 행동이 끝나야 완료된다. 미카의 탄약 보급은 예비 탄창 두 개를 준다. 설치형 치료 장비는 범위 안에서 초당 최대 5를 회복한다."}
  var fleet := {"현재 장소": state.location, "다음 단계": scene["현재 목표"], "남은 적": state.enemy_count,
   "정상 퓨즈 보유": state.fuse_in_inventory, "전력 복구": state.power_restored, "진행 상황": scene}
  if scene["통신 장애 확인"]: fleet["마지막 통신 확인"] = "미카 방에서 통신 먹통을 보고함. 이후 재확인 기록 없음. 장애 원인과 복구 여부 미확인."
  if scene["복도 적 발견"]: fleet["확인한 적"] = "복도에서 머리 없는 침식된 선원을 봄. 침식 원인은 모름."
  if scene["현재 전투 차수"] > 0: fleet["B동에서 확인한 적"] = "복도에서 본 종류와 같은 침식된 선원들."
  if scene["격벽 계획 공유"]:
   fleet["격벽 조작"] = "플레이어는 위쪽 침식 코어, 미카는 아래쪽 정상 코어 담당. 미카가 ‘당겨!’라고 한 뒤 안내가 뜨면 위쪽 레버 앞에서 새 E 입력으로 함께 당긴다."
  return fleet
 if topic == "support":
  if NPCPolicy.has_word(question, ["따라", "대기", "기다"]):
   return {"Mika_current_mode": state.get("companion_mode", "follow"), "active_support": state.active_action, "wait_release": "player follow command or map/trial change", "can_act": not state.get("npc_downed", false)}
  return {"치료 키트": state.medkits, "탄약 보급품": state.supply_packs, "플레이어 체력": state.player_hp, "플레이어 탄약": state.ammo, "미카 탄약": state.get("npc_ammo", 0), "미카 예비탄": state.get("npc_reserve", 0), "현재 지원": state.active_action, "완료된 지원 횟수": state.get("completed_support", {}), "동행 상태": state.get("companion_mode", "follow"), "지원": "실제 치료/보급은 가까이 접근한 뒤 공통 실행기로 완료한다. 대화만으로 지급하지 않는다. 예비탄이 있으면 미카는 자동 장전하고 없으면 공용 보급품을 소비한다."}
 if "손전등" in question:
  var possession := "지금 내 손 안에 있다. 내가 소지 중이다."
  if state.get("flashlight_owned", false): possession = "지금 네 손 안에 있다. 네가 소지 중이다."
  elif state.get("flashlight_dropped", false): possession = "지금 연구실 바닥에 있다. 네가 챙길 차례다."
  elif state.get("flashlight_requested", false): possession = "지금 내 손 안에 있다. 너에게 가져가는 중이다."
  var result := {"손전등 위치": possession, "현재 소유자": "플레이어 (상대방, 너)" if state.get("flashlight_owned", false) else "연구실 바닥 (아직 줍지 않음)" if state.get("flashlight_dropped", false) else "미카 (말하는 나)", "전달 중": state.get("flashlight_requested", false)}
  if NPCPolicy.asks_controls(question):
   result["사용 방법"] = "지금 네가 가진 손전등은 마우스 조준 방향으로 자동으로 비춘다. 마우스만 움직이면 된다." if state.get("flashlight_owned", false) else "바닥에 놓인 뒤 가까이에서 E로 줍는다. 주운 다음에는 마우스 조준 방향으로 자동으로 비춘다."
  return result
 if NPCPolicy.has_word(question, ["패널", "보관함", "반대쪽"]):
  if state.map_id == "main_entry":
   return {"장치": "최종 외곽 봉쇄 패널 (튜토리얼 보관함과 별개)", "봉쇄 단계": state.get("containment_stage", "unobserved"), "남은 적": state.enemy_count, "현재 목표": state.current_guidance, "플레이어 패널 유지": state.locker.player_holding, "방법": "두 무리의 침식된 선원 전멸 뒤 한쪽 E 유지, 미카는 반대 패널. 둘이 1초 유지 후 비프 확인. 대기 중이면 따라와, 다운이면 가까이 E로 키트 소생."}
  var result := {"보관함": "열림" if state.locker.opened else "잠김", "역할": {"player": "one selected panel", "Mika (you)": "the opposite panel"}, "실행 상태": state.get("active_action", ""), "플레이어 패널 유지": state.locker.player_holding}
  if NPCPolicy.asks_controls(question): result["방법"] = "너는 한쪽 패널 가까이에서 E를 계속 누른다. 나는 반대편 패널을 동시에 누른다. 둘이 누른 채 1초 유지하면 보관함이 열린다."
  return result
 var next := {"행동": "손전등 수령", "장소": "연구실 왼쪽 통로"}
 if state.get("story", {}).get("stage") == "on_shift": return {"현재": "평상시 근무, 아직 정전은 발생하지 않음", "다음 단계": {"행동": "연구 구역 전등 점검", "장소": "연구실"}}
 if state.map_id == "main_entry": next = {"행동": state.current_guidance, "장소": "연구동 외곽", "봉쇄 단계": state.get("containment_stage", "unobserved"), "남은 적": state.enemy_count, "보급함 회수": state.get("containment_supply_used", false)}
 elif state.power_restored: next = {"행동": "경보 확인 후 연구동 출발", "장소": "연구실 출발 출입문"} if "anomaly_alarm" in state.get("story", {}).get("events", []) else {"행동": "재가동된 장치 상태 확인 (전력 복구 완료)", "장소": "연구실"}
 elif state.fuse_collected: next = {"행동": "퓨즈 장착", "장소": "연구실 전력 장치"}
 elif state.map_id == "storage": next = {"행동": "선원 제압 후 두 패널로 보관함 개방, 퓨즈 확보", "장소": "비품실 북쪽 중앙 보관함"}
 elif state.flashlight_owned: next = {"행동": "비품실 진입 후 퓨즈 확보", "장소": "왼쪽 통로, 비품실 보관함"}
 elif state.flashlight_dropped: next = {"행동": "바닥 손전등 줍기", "장소": "연구실 바닥"}
 var stable_story: Dictionary = state.get("story", {}).duplicate(true)
 stable_story.erase("elapsed") # 연출 시계의 매 프레임 변화는 실제 사실 변경/응답 취소 사유가 아니다.
 var result := {"현재 목표": "침식된 이상현상의 봉쇄 경로 조사" if "anomaly_alarm" in state.get("story", {}).get("events", []) else "전력 계통 확인과 복구", "서사": stable_story, "다음 단계": next, "퓨즈 확보": state.fuse_collected, "퓨즈 추가 확보 필요": not state.fuse_collected, "전력 복구": state.power_restored, "임무 완료": state.escaped}
 if state.map_id == "main_entry" or state.get("escaped", false):
  result["현재 목표"] = state.current_guidance
  result["봉쇄 범위"] = "외곽 침식 확산의 일시 차단. 연구소 전체 해결 아님. 내부 후속 조사 필요."
  result["경보 상태"] = "안정/해제" if state.escaped else "경보 중"
 if NPCPolicy.has_word(question, ["물건", "부품", "퓨즈", "챙겨"]) or ("보관" in question and "찾" in question):
  result["질문이 가리키는 물품"] = {"이름": "퓨즈", "원래 보관 장소": "비품실 북쪽 중앙 보관함", "현재 위치": "연구실 전력 장치" if state.power_restored else "플레이어 보유" if state.fuse_collected else "비품실 보관함", "획득 완료": state.fuse_collected, "전력 장치에 장착 완료": state.power_restored, "추가 확보 필요": not state.fuse_collected}
 return result

static func claims_valid(text: String, state: Dictionary) -> bool:
 var compact := text.replace(" ", "")
 var observed: Array = state.get("story", {}).get("events", [])
 var fleet: bool = state.get("fleet_demo", false)
 if NPCPolicy.has_word(compact, ["연구소전체가해결", "전부해결됐", "모든이상현상이사라", "모두해결됐"]): return false
 if "anomaly_alarm" not in observed and NPCPolicy.has_word(compact, ["경보가켜졌", "경고등이켜졌", "침식된장치가드러났"]): return false
 if int(state.get("enemy_count", 0)) == 0 and NPCPolicy.has_word(compact, ["선원먼저잡아", "선원을먼저잡아", "선원잡아야", "선원을제압해야"]): return false
 if not state.get("escaped", false) and NPCPolicy.has_word(compact, ["임무끝났", "임무완료했", "모두해결됐", "이상현상닫았"]): return false
 if state.get("power_restored", false) and NPCPolicy.has_word(compact, ["퓨즈찾아야", "퓨즈를찾아야", "전력부터복구해야", "전력을복구해야"]): return false
 var completed: Dictionary = state.get("completed_support", {})
 if NPCPolicy.has_word(compact, ["치료했어", "치료해줬", "치료끝났", "회복시켰"]) and int(completed.get("heal", 0)) == 0: return false
 if NPCPolicy.has_word(compact, ["보급했어", "탄약줬어", "탄약건넸", "탄약채워줬"]) and int(completed.get("resupply", 0)) == 0: return false
 if NPCPolicy.has_word(compact, ["퓨즈챙겼어", "퓨즈찾았어", "퓨즈얻었어"]) and not state.fuse_collected: return false
 if fleet: return _fleet_issue(text, state).is_empty()
 if NPCPolicy.has_word(compact, ["보관함열었어", "보관함열렸어"]) and not state.locker.opened: return false
 if NPCPolicy.has_word(compact, ["네가주웠", "네가챙겼잖"]) and "손전등" in compact and not state.flashlight_owned: return false
 if "손전등" in compact and state.flashlight_owned and NPCPolicy.has_word(compact, ["내손에있", "내가갖고있", "내가가지고있", "바닥에있"]): return false
 return true

static func _fleet_issue(text: String, state: Dictionary) -> String:
 var compact := text.to_lower().replace(" ", "")
 var scene: Dictionary = state.fleet_context
 if NPCPolicy.has_word(compact, ["외곽관측단말", "침식관측단말", "봉쇄패널", "북쪽중앙보관함", "1초유지", "패널을1초", "비품실선원", "비품실의선원"]): return "fleet_wrong_scenario"
 if NPCPolicy.has_word(compact, ["내가쐈", "내가쏴", "내가발사", "내가사격했", "내가사격할", "내가재장전", "내가총으로", "내가적을잡았", "내가선원을제압했", "같이쏴", "쏴줄게"]): return "fleet_mika_does_not_shoot"
 if int(state.get("completed_support", {}).get("deploy_cover", 0)) == 0 and NPCPolicy.has_word(compact, ["치료장비설치했", "치료장비를설치했", "보호장비설치했", "터렛설치했", "터렛을설치했"]): return "fleet_support_not_completed"
 if NPCPolicy.has_word(compact, ["전력이나가서통신", "정전때문에통신", "침식때문에통신", "통신은침식때문", "통신선이끊어져서", "통신복구됐", "통신이복구됐", "통신도복구됐", "통신이돌아왔", "통신도돌아왔", "통신은정상이", "통신은돼", "통신이돼", "통신돼.", "통신돼!", "통신된다", "통신잘돼"]): return "fleet_comms_unverified"
 if not scene["통신 장애 확인"] and NPCPolicy.has_word(compact, ["통신이먹통", "통신은먹통", "통신도먹통", "통신이끊겼", "통신은끊겼", "통신장애가났"]): return "fleet_comms_not_reported"
 if not scene["복도 적 발견"] and NPCPolicy.has_word(compact, ["침식된선원", "머리없는선원", "아까본적", "봤던선원", "복도에서봤"]): return "fleet_enemy_not_observed"
 if not state.power_restored and NPCPolicy.has_word(compact, ["전력이복구됐", "전력은복구됐", "전력복구했", "불은돌아왔", "불이돌아왔"]): return "fleet_power_not_restored"
 if not scene["퓨즈 장착"] and NPCPolicy.has_word(compact, ["퓨즈끼웠", "퓨즈는끼웠", "퓨즈를끼웠", "퓨즈를교체했", "퓨즈교체했"]): return "fleet_fuse_not_installed"
 if NPCPolicy.has_word(compact, ["비품실오른쪽퓨즈", "퓨즈는오른쪽", "오른쪽캐비닛에퓨즈", "오른쪽캐비닛에서퓨즈", "내가퓨즈주워", "내가주워줄", "내가퓨즈를주웠", "내가퓨즈주웠"]): return "fleet_wrong_fuse_location_or_actor"
 if "앞바닥" in compact and NPCPolicy.has_word(compact, ["놓아줄게", "놔줄게", "가져다줄게"]): return "fleet_wrong_fuse_location_or_actor"
 if state.fuse_in_inventory and NPCPolicy.has_word(compact, ["직접뽑아서", "퓨즈를다시주워", "퓨즈는아직바닥", "퓨즈는바닥에"]): return "fleet_fuse_already_held"
 if str(scene["퓨즈 위치"]).contains("미확인") and NPCPolicy.has_word(compact, ["왼쪽캐비닛", "캐비닛앞바닥", "퓨즈가떨어졌어"]): return "fleet_fuse_not_observed"
 if not scene["격벽 계획 공유"] and NPCPolicy.has_word(compact, ["침식코어", "정상코어", "레버는위쪽", "레버를함께", "레버를동시"]): return "fleet_plan_not_shared"
 if not scene["B동 전투 종료"] and NPCPolicy.has_word(compact, ["세무리를다잡았", "웨이브는다끝났", "선원은다정리됐", "선원은전부처리했"]): return "fleet_waves_not_finished"
 if not scene["레버 조작 가능"] and NPCPolicy.has_word(compact, ["지금당겨", "당겨도돼", "지금눌러", "지금레버를당겨", "신호는이미줬", "내가신호했어", "당겨!'했", "당겨!라고했", "당겨!라고말했"]): return "fleet_lever_not_ready"
 if scene["진행 단계"] == "WAVES" and scene["현재 전투 차수"] < 3 and NPCPolicy.has_word(compact, ["당겨", "레버", "신호"]):
  var current_wave := "%d차" % scene["현재 전투 차수"]
  if NPCPolicy.has_word(compact, [current_wave + "제압끝나면", current_wave + "만끝나면", current_wave + "끝나면"]): return "fleet_lever_not_ready"
 if not scene["격벽 설치"] and NPCPolicy.has_word(compact, ["격벽은설치됐", "격벽설치했", "격벽을설치했", "두레버를당겼", "두레버는당겼", "b동은격리됐"]): return "fleet_barrier_not_installed"
 return ""

static func response_issue(text: String, state: Dictionary, question: String) -> String:
 var spoken := text.replace(" ", "")
 if NPCPolicy.has_word(spoken, ["주문했", "시켜먹었", "같이먹었", "먹었잖", "스파게티시켰"]): return "invented_food_event"
 if "퇴근" in question and NPCPolicy.has_word(question, ["정말", "금지", "규정"]) and NPCPolicy.has_word(spoken, ["퇴근은안돼", "퇴근금지", "퇴근못해", "퇴근을못해"]) and not NPCPolicy.has_word(spoken, ["지금은", "농담", "장난", "?"]): return "unsupported_world_rule"
 if state.get("fleet_demo", false):
  var fleet_issue := _fleet_issue(text, state)
  if not fleet_issue.is_empty(): return fleet_issue
  var fleet_query := question.replace(" ", "")
  if NPCPolicy.has_word(fleet_query, ["통신은돼", "통신돼", "통신상태", "통신은되", "통신이돼"]):
   var comms: Dictionary = state.fleet_context
   if not comms["통신 장애 확인"] and not NPCPolicy.has_word(spoken, ["확인못", "확인안", "안확인", "모르", "몰라", "확인하지"]): return "fleet_comms_not_reported"
   if NPCPolicy.has_word(spoken, ["선원이뭐했는지", "선원때문", "침식때문"]): return "fleet_comms_unverified"
  if state.fleet_context["진행 단계"] == "TO_POWER" and NPCPolicy.has_word(spoken, ["캐비닛봐", "캐비닛확인", "캐비닛찾"]): return "fleet_fuse_already_held"
  if state.fleet_context["격벽 계획 공유"] and not state.fleet_context["레버 조작 가능"] and NPCPolicy.has_word(fleet_query, ["레버는언제", "레버언제", "언제당겨"]):
   if not NPCPolicy.has_word(spoken, ["신호", "'당겨!'", "‘당겨!’"]): return "fleet_lever_signal_missing"
 if not claims_valid(text, state): return "unverified_action_claim"
 if text.begins_with("#") or "(" in text or "（" in text: return "non_spoken_annotation"
 var compact := text.replace(" ", "")
 if state.get("map_id") == "lab" and state.get("power_restored", false) and "anomaly_alarm" in state.get("story", {}).get("events", []) and NPCPolicy.has_word(compact, ["연구실로가자", "연구실로돌아", "연구실에가자"]): return "wrong_departure_destination"
 var query := question.replace(" ", "").trim_suffix("?").trim_suffix(".")
 if compact.trim_suffix("?").trim_suffix(".") == query: return "question_echo"
 if NPCPolicy.has_word(text, ["세요", "습니다", "입니다", "됩니다", "어요", "아요", "네요", "군요", "해요", "예요", "그래요"]): return "formal_voice"
 if NPCPolicy.has_word(question, ["먹고 싶", "먹고싶"]) and "먹었" in text: return "wrong_answer_tense"
 if NPCPolicy.has_word(question, ["패널", "반대쪽"]) and state.active_action != "assist_panel" and NPCPolicy.has_word(compact, ["지금은왼쪽패널을누르고있", "지금누르고있", "내가누르고있어"]): return "unstarted_panel_action"
 if NPCPolicy.has_word(question, ["기다", "대기", "따라"]) and not NPCPolicy.has_word(question, ["탄약", "치료"]) and NPCPolicy.has_word(text, ["예비탄", "치료했", "보급했"]): return "unrequested_support_claim"
 if state.get("companion_mode", "follow") == "wait" and NPCPolicy.has_word(question, ["기다", "대기"]) and NPCPolicy.has_word(text, ["따라가", "따라갈", "따라오면"]): return "wrong_wait_behavior"
 if not state.get("fleet_demo", false) and "손전등" in question and not state.flashlight_owned and not state.flashlight_dropped and NPCPolicy.has_word(compact, ["네가소지", "네손에있", "너한테있"]): return "wrong_current_owner"
 return ""
