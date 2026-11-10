class_name HarinDialogue
extends RefCounted
const CHARACTER = preload("res://resources/HarinCharacter.tres")
const HISTORY_LIMIT := 8
const HISTORY_CHAR_BUDGET := 850
const AMBIENT := {"on_shift": "평상시 연구실 근무. 아직 정전·경보·전투는 발생하지 않음.", "blackout": "정전 직후. 아직 전력은 복구되지 않았고 침식 경보는 관측 전.", "equipment": "정전 중. 플레이어는 손전등 보유. 침식 경보는 아직 관측 전.", "fuse_search": "정전된 보관 구역. 침식 경보는 아직 관측 전.", "fuse_return": "보관 구역 전투와 퓨즈 회수가 끝났지만 아직 정전 중.", "power_restored": "전력 복구와 장치 재가동 직후. 아직 경보는 관측하지 않음.", "anomaly_alarm": "전력 복구 후 실제 침식 경보가 발생함. 전체 문제는 미해결.", "main_entry": "연구동 진입실에 도착. 보관 구역 전투는 끝났음. 경보는 실제 발생했고 전체 임무는 미완료."}
const PHASES := {"on_shift": "평상시 연구소 근무. 아직 정전 전.", "blackout": "갑자기 정전 발생. 하린이 보안 직원인 플레이어를 불러 장비를 챙기는 중.", "equipment": "플레이어가 손전등을 받음. 퓨즈 확보를 위해 보관 구역으로 출발.", "fuse_search": "보관 구역에서 드론을 제압하고 두 패널 보관함의 퓨즈를 확보하는 중.", "fuse_return": "퓨즈 확보 완료. 연구실 전력 장치에 장착할 차례.", "power_restored": "퓨즈 장착으로 전력은 복구됨. 장치가 재가동되는 순간. 전체 문제 해결 아님.", "anomaly_alarm": "전력 복구 뒤 침식된 장치가 드러나고 경고등이 켜짐. 출발 문으로 연구동에 갈 차례.", "main_entry": "전력을 복구하고 연구동 진입실에 도착. 관측 단말에서 침식 신호를 확인해야 함. 이상현상 봉쇄는 아직 완료하지 못함."}

static func topic_for(question: String, history: Array) -> String:
 var topic := NPCPolicy.rule_intent(question)
 if NPCPolicy.has_word(question, ["불 들어", "경보", "이상현상", "정전"]): return "mission"
 if topic == "unknown" and NPCPolicy.has_word(question, ["그럼", "반대쪽", "그거", "아까", "다음엔", "지금은"]):
  for index in range(history.size() - 1, -1, -1):
   var previous := NPCPolicy.rule_intent(str(history[index].get("question", "")))
   if previous in ["mission", "support"]: return previous
 return topic

static func recent_history(history: Array, casual: bool) -> Array:
 var result := []
 var remaining := HISTORY_CHAR_BUDGET
 for index in range(history.size() - 1, -1, -1):
  var turn: Dictionary = history[index]
  # 새 잡담에는 먼 임무 매뉴얼을 빼되, 지시어가 있는 후속 질문은 build에서 전체 최근 문답을 사용한다.
  if casual and NPCPolicy.rule_intent(str(turn.get("question", ""))) not in ["everyday", "relationship", "unknown"]: continue
  var entry := {"question": str(turn.get("question", "")).left(160), "answer": str(turn.get("answer", "")).left(230)}
  var cost: int = entry.question.length() + entry.answer.length()
  if cost > remaining or result.size() >= HISTORY_LIMIT: break
  remaining -= cost
  result.push_front(entry)
 return result
## 잡담에 목표/HUD/기믹 매뉴얼을 주입하지 않는 대화 전용 문맥.
static func style_examples(topic: String, question := "") -> Array:
 var dataset = JSON.parse_string(FileAccess.get_file_as_string("res://resources/harin_style_examples.json").trim_prefix("\ufeff"))
 var ids := ["sample_0004"] if topic in ["mission", "support"] else ["sample_0003", "sample_0005"]
 if topic not in ["mission", "support"] and NPCPolicy.has_word(question, ["밥", "먹", "메뉴"]): ids = ["sample_0007", "sample_0008"]
 elif topic not in ["mission", "support"] and NPCPolicy.has_word(question, ["퇴근", "쉬", "근무"]): ids = ["sample_0005", "sample_0006"]
 var result := []
 if not dataset is Dictionary: return result
 for sample in dataset.samples:
  if sample.id in ids:
   result.append({"fictional_style_only": true, "player": sample.question, "Harin": sample.lines})
 return result

static func build(state: Dictionary, question: String, history: Array, persona: String, extra_style: String) -> Dictionary:
 var topic := topic_for(question, history)
 var casual := topic in ["everyday", "relationship", "unknown"]
 var referring := NPCPolicy.has_word(question, ["그럼", "그거", "아까", "그 음식", "지금은", "네가 말"])
 var system := "너는 연구소 정비사 하린. 상대는 함께 일하던 보안 직원이야. 한국어 반말로 말해. '~해', '~야' 같은 편한 말투를 쓰고 '~요', '~습니다'는 쓰지 마. 진행 질문은 최신 사실 우선으로 핵심을 알려 줘. 잡담은 장난·능청·회피·짧은 반문(counterquestions)도 가능해. 문장 수나 격려·역질문 끝맺음은 강제하지 않아. 가상 예시는 말투 참고일 뿐 실제 사건·규정·취향·기억이 아니야. 실행 전 행동을 완료했다고 말하지 마. 마지막 현재 플레이어 말에만 반응해. JSON/행동 주석/서술 없이 하린의 발화만 써."
 var context := {"고정 역할·세계관": {"identity": CHARACTER.identity, "voice": CHARACTER.voice, "scene_role": persona.left(240)}, "현재 서사 단계": state.get("story", {}).get("stage", "blackout"), "최근 대화 (실제 문답)": recent_history(history, casual and not referring), "말투 참고 (가상·기억 아님)": style_examples(topic, question)}
 context["현재 장면"] = PHASES.get(str(context["현재 서사 단계"]), "현재 상태 참고") if not casual else AMBIENT.get(str(context["현재 서사 단계"]), "친숙한 동료와 근무 중 대화")
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
 if state.get("npc_downed", false): context["현재 몸 상태"] = "하린 다운. 가까이에서 키트로 소생하기 전에는 이동·지원 불가."
 context["PLAYER QUESTION"] = question
 var messages := [{"role": "system", "content": system + "\n다음 예시 대화는 가상의 말투 연습일 뿐 실제 사건이 아니다."}]
 for example in context["말투 참고 (가상·기억 아님)"]:
  messages.append({"role": "user", "content": "[가상 말투 예시] " + str(example.player)})
  messages.append({"role": "assistant", "content": "\n".join(example.Harin)})
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
 var words := ["손전등"] if "손전등" in question else ["패널", "보관함"] if NPCPolicy.has_word(question, ["패널", "반대쪽", "보관함"]) else ["치료", "보급", "보호", "소생"] if topic == "support" else ["퓨즈", "전력", "드론", "보관함"]
 return events.filter(func(event): return NPCPolicy.has_word(str(event), words)).slice(-3)

static func facts(state: Dictionary, question: String, topic: String) -> Dictionary:
 if topic == "support":
  if NPCPolicy.has_word(question, ["따라", "대기", "기다"]):
   return {"Harin_current_mode": state.get("companion_mode", "follow"), "active_support": state.active_action, "wait_release": "player follow command or map/trial change", "can_act": not state.get("npc_downed", false)}
  return {"치료 키트": state.medkits, "탄약 보급품": state.supply_packs, "플레이어 체력": state.player_hp, "플레이어 탄약": state.ammo, "하린 탄약": state.get("npc_ammo", 0), "하린 예비탄": state.get("npc_reserve", 0), "현재 지원": state.active_action, "완료된 지원 횟수": state.get("completed_support", {}), "동행 상태": state.get("companion_mode", "follow"), "지원": "실제 치료/보급은 가까이 접근한 뒤 공통 실행기로 완료한다. 대화만으로 지급하지 않는다. 예비탄이 있으면 하린은 자동 장전하고 없으면 공용 보급품을 소비한다."}
 if "손전등" in question:
  var possession := "지금 내 손 안에 있다. 내가 소지 중이다."
  if state.get("flashlight_owned", false): possession = "지금 네 손 안에 있다. 네가 소지 중이다."
  elif state.get("flashlight_dropped", false): possession = "지금 연구실 바닥에 있다. 네가 챙길 차례다."
  elif state.get("flashlight_requested", false): possession = "지금 내 손 안에 있다. 너에게 가져가는 중이다."
  var result := {"손전등 위치": possession, "현재 소유자": "플레이어 (상대방, 너)" if state.get("flashlight_owned", false) else "연구실 바닥 (아직 줍지 않음)" if state.get("flashlight_dropped", false) else "하린 (말하는 나)", "전달 중": state.get("flashlight_requested", false)}
  if NPCPolicy.asks_controls(question):
   result["사용 방법"] = "지금 네가 가진 손전등은 마우스 조준 방향으로 자동으로 비춘다. 마우스만 움직이면 된다." if state.get("flashlight_owned", false) else "바닥에 놓인 뒤 가까이에서 E로 줍는다. 주운 다음에는 마우스 조준 방향으로 자동으로 비춘다."
  return result
 if NPCPolicy.has_word(question, ["패널", "보관함", "반대쪽"]):
  var result := {"보관함": "열림" if state.locker.opened else "잠김", "역할": {"player": "one selected panel", "Harin (you)": "the opposite panel"}, "실행 상태": state.get("active_action", ""), "플레이어 패널 유지": state.locker.player_holding}
  if NPCPolicy.asks_controls(question): result["방법"] = "너는 한쪽 패널 가까이에서 E를 계속 누른다. 나는 반대편 패널을 동시에 누른다. 둘이 누른 채 1초 유지하면 보관함이 열린다."
  return result
 var next := {"행동": "손전등 수령", "장소": "연구실 오른쪽 통로"}
 if state.get("story", {}).get("stage") == "on_shift": return {"현재": "평상시 근무, 아직 정전은 발생하지 않음", "다음 단계": {"행동": "연구 구역 전등 점검", "장소": "연구실"}}
 if state.map_id == "main_entry": next = {"행동": "침식 관측 단말 확인·이상현상 봉쇄 경로 조사", "장소": "연구동 진입실"}
 elif state.power_restored: next = {"행동": "경보 확인 후 연구동 출발", "장소": "연구실 출발 출입문"} if "anomaly_alarm" in state.get("story", {}).get("events", []) else {"행동": "재가동된 장치 상태 확인 (전력 복구 완료)", "장소": "연구실"}
 elif state.fuse_collected: next = {"행동": "퓨즈 장착", "장소": "연구실 전력 장치"}
 elif state.map_id == "storage": next = {"행동": "드론 제압 후 두 패널로 보관함 개방, 퓨즈 확보", "장소": "보관 구역 북동쪽 보관함"}
 elif state.flashlight_owned: next = {"행동": "보관 구역 진입 후 퓨즈 확보", "장소": "오른쪽 통로, 보관 구역 보관함"}
 elif state.flashlight_dropped: next = {"행동": "바닥 손전등 줍기", "장소": "연구실 바닥"}
 var stable_story: Dictionary = state.get("story", {}).duplicate(true)
 stable_story.erase("elapsed") # 연출 시계의 매 프레임 변화는 실제 사실 변경/응답 취소 사유가 아니다.
 var result := {"현재 목표": "침식된 이상현상의 봉쇄 경로 조사" if "anomaly_alarm" in state.get("story", {}).get("events", []) else "전력 계통 확인과 복구", "서사": stable_story, "다음 단계": next, "퓨즈 확보": state.fuse_collected, "퓨즈 추가 확보 필요": not state.fuse_collected, "전력 복구": state.power_restored, "임무 완료": state.escaped}
 if NPCPolicy.has_word(question, ["물건", "부품", "퓨즈", "챙겨"]) or ("보관" in question and "찾" in question):
  result["질문이 가리키는 물품"] = {"이름": "퓨즈", "원래 보관 장소": "보관 구역 북동쪽 보관함", "현재 위치": "연구실 전력 장치" if state.power_restored else "플레이어 보유" if state.fuse_collected else "보관 구역 보관함", "획득 완료": state.fuse_collected, "전력 장치에 장착 완료": state.power_restored, "추가 확보 필요": not state.fuse_collected}
 return result

static func claims_valid(text: String, state: Dictionary) -> bool:
 var compact := text.replace(" ", "")
 var observed: Array = state.get("story", {}).get("events", [])
 if "anomaly_alarm" not in observed and NPCPolicy.has_word(compact, ["경보가켜졌", "경고등이켜졌", "침식된장치가드러났"]): return false
 if int(state.get("enemy_count", 0)) == 0 and NPCPolicy.has_word(compact, ["드론먼저잡아", "드론을먼저잡아", "드론잡아야", "드론을제압해야"]): return false
 if not state.get("escaped", false) and NPCPolicy.has_word(compact, ["임무끝났", "임무완료했", "모두해결됐", "이상현상닫았"]): return false
 if state.get("power_restored", false) and NPCPolicy.has_word(compact, ["퓨즈찾아야", "퓨즈를찾아야", "전력부터복구해야", "전력을복구해야"]): return false
 var completed: Dictionary = state.get("completed_support", {})
 if NPCPolicy.has_word(compact, ["치료했어", "치료해줬", "치료끝났", "회복시켰"]) and int(completed.get("heal", 0)) == 0: return false
 if NPCPolicy.has_word(compact, ["보급했어", "탄약줬어", "탄약건넸", "탄약채워줬"]) and int(completed.get("resupply", 0)) == 0: return false
 if NPCPolicy.has_word(compact, ["퓨즈챙겼어", "퓨즈찾았어", "퓨즈얻었어"]) and not state.fuse_collected: return false
 if NPCPolicy.has_word(compact, ["보관함열었어", "보관함열렸어"]) and not state.locker.opened: return false
 if NPCPolicy.has_word(compact, ["네가주웠", "네가챙겼잖"]) and "손전등" in compact and not state.flashlight_owned: return false
 if "손전등" in compact and state.flashlight_owned and NPCPolicy.has_word(compact, ["내손에있", "내가갖고있", "내가가지고있", "바닥에있"]): return false
 return true

static func response_issue(text: String, state: Dictionary, question: String) -> String:
 var spoken := text.replace(" ", "")
 if NPCPolicy.has_word(spoken, ["주문했", "시켜먹었", "같이먹었", "먹었잖", "스파게티시켰"]): return "invented_food_event"
 if "퇴근" in question and NPCPolicy.has_word(question, ["정말", "금지", "규정"]) and NPCPolicy.has_word(spoken, ["퇴근은안돼", "퇴근금지", "퇴근못해", "퇴근을못해"]) and not NPCPolicy.has_word(spoken, ["지금은", "농담", "장난", "?"]): return "unsupported_world_rule"
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
 if "손전등" in question and not state.flashlight_owned and not state.flashlight_dropped and NPCPolicy.has_word(compact, ["네가소지", "네손에있", "너한테있"]): return "wrong_current_owner"
 return ""
