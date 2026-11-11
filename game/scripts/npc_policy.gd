class_name NPCPolicy
extends RefCounted
const CHARACTER = preload("res://resources/HarinCharacter.tres")
const PROMPT_VERSION := "story_style_v3_plain_thinking_20261110"
const DECISION_INSTRUCTIONS := "Choose one allowed action to help a close companion. Prioritize urgent unmet needs: critically low health calls for healing; zero or nearly empty ammunition calls for resupply. If player_ammo_empty is true and resupply is allowed, resupply takes priority over preventive cover. Install preventive cover after urgent recovery needs are handled. Guide the player into existing cover when useful. Do not waste resources or invent actions. Use follow or wait when support is unnecessary. If locker.player_holding is true and assist_panel is allowed, choose assist_panel."
## 공통 행동/대화 목록. 판단과 실제 자원 소비는 별개입니다.
const ACTIONS := {
 "assist_panel": "플레이어가 한쪽 패널을 유지하는 동안 반대 패널로 이동해 함께 1초 유지, 보관함 잠금 해제",
 "heal": "접근하여 치료 키트 한 개로 체력 35 회복",
 "resupply": "접근하여 보급품 한 개로 탄약 10발 보충",
 "deploy_cover": "남쪽 안전 지점에 보호 장비 설치, 내부 피해 50% 감소",
 "guide_to_cover": "보호 장비 쪽의 실제 방향을 알려 플레이어 유도",
 "follow": "동료를 따라가며 지원 대기",
 "wait": "자원을 사용하지 않고 잠시 관찰"}
const INTENTS := {
 "mission": "임무, 다음 목표, 퓨즈, 발전기, 문, 장소, 진행 상황에 관한 질문",
 "support": "전투 방법, 치료, 탄약, 보호 장비, 지원 요청",
 "relationship": "친한 동료인 하린과 플레이어의 관계에 관한 질문",
 "everyday": "안부, 기분, 식사, 일상, 격려, 잡담",
 "unknown": "주어진 정보로 답할 수 없는 질문"}

static func requested_action(question: String) -> String:
 var text := question.replace(" ", "")
 if has_word(text, ["하지마", "하지말", "안해도", "말아줘", "말자", "오지마", "따라오지", "기다리지", "라고말", "라고하면", "라는말", "명령어"]): return ""
 if has_word(text, ["따라와", "따라와줘", "따라오", "같이와", "동행해"]): return "follow"
 if has_word(text, ["기다려", "대기해", "여기있어", "여기서있어", "여기지켜"]): return "wait"
 if has_word(text, ["도와줘", "도와줄래", "도움좀"]): return "clarify"
 if has_word(text, ["문열어줘", "문을열어줘", "주워줘", "춤춰줘", "공격해줘"]): return "unsupported"
 var request := has_word(text, ["해줘", "해줄", "해줄래", "해줄수", "해주라", "부탁", "누르자", "맡아줘", "좀줘", "보충해", "치료해", "엄호해"])
 if not request: return ""
 if has_word(text, ["치료", "회복"]): return "heal"
 if has_word(text, ["탄약", "총알", "보급"]): return "resupply"
 if has_word(text, ["패널", "반대쪽"]): return "assist_panel"
 if has_word(text, ["엄호", "보호장비"]): return "deploy_cover"
 if has_word(text, ["도와", "도움"]): return "clarify"
 return ""

static func rule_action(state: Dictionary) -> String:
 var valid: Array = state.get("valid_actions", [])
 if "assist_panel" in valid: return "assist_panel"
 if state.player_hp <= 55 and "heal" in valid: return "heal"
 if state.ammo <= 4 and "resupply" in valid: return "resupply"
 if state.enemy_count > 0 and "deploy_cover" in valid: return "deploy_cover"
 if "guide_to_cover" in valid: return "guide_to_cover"
 return "follow" if "follow" in valid else "wait"

static func rule_intent(question: String) -> String:
 var text := question.to_lower().replace(" ", "")
 if has_word(text, ["치료", "체력", "보급", "탄약", "총알", "전투", "보호장비", "싸우", "엄호", "도와", "도움", "따라", "기다", "대기"]): return "support"
 if has_word(text, ["봉쇄", "침식", "단말", "외곽", "정전", "어디부터", "뭘챙", "부품", "불들어", "경고등", "경보", "이상현상", "해결", "장치", "임무", "목표", "퓨즈", "전력", "발전기", "출구", "뭘해야", "무엇을해야", "뭐해야", "어디로가", "어디가야", "진행", "보관", "패널", "손전등", "문열", "문닫", "출입문", "그문", "저문"]) or text.begins_with("문"): return "mission"
 if has_word(text, ["우리사이", "우린", "동료", "관계", "친구", "기억"]): return "relationship"
 if has_word(text, ["안녕", "반가", "하이", "ㅎㅇ", "기분", "괜찮", "고마", "밥", "먹", "배고", "수고", "피곤", "오늘", "무서", "힘들", "좋아", "싫", "심심", "쉬", "긴장", "뭐해", "너는", "하린", "잘잤", "가자", "hello", "hi", "thanks"]): return "everyday"
 return "unknown"

static func has_word(text: String, words: Array) -> bool:
 for word in words:
  if text.contains(word): return true
 return false

static func opening_line(state: Dictionary) -> String:
 return "미안, 아직 움직이기 힘들어." if state.get("npc_downed", false) else "잠깐, 전등 상태가 이상한데. 여기 좀 봐."

static func asks_controls(question: String) -> bool:
 return has_word(question.replace(" ", ""), ["어떻게", "방법", "조작", "무슨키", "어느키", "뭘눌러", "뭐눌러", "몇초", "얼마나", "버튼", "방향", "비추", "비춰"])

static func template_response(intent: String, state: Dictionary, question := "") -> String:
 if state.get("npc_downed", false): return "미안… 아직 움직이기 힘들어."
 match intent:
  "mission":
   if state.get("escaped", false): return "외곽은 일단 봉쇄됐어. 안쪽은 더 조사해야 해. 보고서는… 네가 좀 써 줘."
   if state.map_id == "main_entry" and "손전등" not in question:
    match state.get("containment_stage", "unobserved"):
     "unobserved": return "저 관측 단말부터 보자. 가까이 가서 E로 확인해 봐."
     "ready": return "왼쪽 보급함부터 챙기자. 그다음 중앙 봉쇄 장치를 켜면 돼."
     "wave_one", "wave_two": return "오는 드론부터 막자. 두 무리 다 정리해야 마지막 패널을 쓸 수 있어."
     "panel_ready": return "드론은 다 정리됐어. 한쪽 봉쇄 패널에서 E를 누르고 있어. 반대편은 내가 맡을게."
     "complete": return "일단 외곽은 잠잠해졌어. 안쪽은 후속 조사가 필요해."
   if "손전등" in question:
    if state.get("flashlight_owned", false): return "보고 싶은 쪽으로 마우스를 움직여 봐. 그쪽을 비춰 줄 거야." if asks_controls(question) else "네가 챙겨서 들고 있어. 앞이 어두우면 그걸 쓰면 돼."
    if state.get("flashlight_dropped", false): return "바닥에 놓아뒀어. 가까이 가서 E로 집으면 돼." if asks_controls(question) else "바닥에 놓아뒀어. 챙겨 가."
    return "내가 갖고 있어. 어두운 데 들어가기 전에 건네줄게."
   if has_word(question, ["패널", "보관함", "반대쪽"]):
    if state.locker.opened: return "보관함은 열렸어. 물건을 챙기면 돼."
    return "한쪽 패널에서 E를 누르고 있어. 반대편도 동시에 눌러야 해. 1초 동안 같이 유지해야 열려." if asks_controls(question) else "너는 한쪽 패널, 나는 반대편이야. 먼저 한쪽을 잡아 줘."
   if state.get("power_restored", false): return "불은 들어왔는데 경보까지 켜졌어. 출발 문으로 연구동에 가 보자."
   if state.get("fuse_collected", false): return "퓨즈는 챙겼으니까 연구실 전력 장치에 끼우면 돼. 같이 돌아가자."
   return "보관 구역에서 퓨즈를 찾아야 해. 내가 같이 갈게."
  "support": return "치료랑 탄약은 내가 챙길게. 필요하면 가까이 와." if state.medkits > 0 or state.supply_packs > 0 else "지금은 나도 남은 물자가 없어. 조심해서 움직이자."
  "relationship": return "너랑 같이 있으면 좀 든든하지. 우리 둘 다 무사히 돌아가자."
  "everyday":
   if has_word(question, ["밥", "먹", "배고"]):
    if has_word(question, ["싶", "좋아", "취향"]): return "네가 사는 거야? 메뉴부터 봐야겠는데."
    return CHARACTER.meal_reply()
   if has_word(question, ["고마", "수고", "thanks"]): return "뭘, 서로 챙겨야지. 너도 고생했어."
   if has_word(question, ["긴장", "무서", "힘들", "피곤"]): return "나도 좀 그래. 괜찮아, 나 여기 있잖아."
   if has_word(question, ["어때", "기분", "잘지내"]): return "조금 긴장되긴 하는데, 네가 있으니까 괜찮아."
   if has_word(question, ["안녕", "반가", "하이", "ㅎㅇ", "hello", "hi"]): return "왔네! 오늘은 좀 어때?"
   if "쉬" in question: return "좋아, 잠깐 숨 돌리자. 서두를 거 없잖아."
   return "네가 있어서 좀 든든해. 너는 어때?"
 return "응? 어떤 얘기인지 조금만 더 말해 줄래?"

static func jev_payload(kind: String, state: Dictionary, question: String, model: String) -> Dictionary:
 var criteria := {}
 var instructions := DECISION_INSTRUCTIONS
 if kind == "decision":
  for action in state.valid_actions: criteria[action] = ACTIONS[action]
 else:
  criteria = INTENTS.duplicate()
  instructions = "플레이어 질문의 주된 의도를 하나 선택하라. 제공된 상태와 동료 관계만 사용하라."
 return {"model": model, "state": {"game": model_state(state), "player_question": question}, "questions": {"selection": {"type": "choice", "instructions": instructions, "criteria": criteria}}}

static func model_state(state: Dictionary) -> Dictionary:
 # 행동 판단에 필요한 공통 관측만 전달한다. 대화의 장소/기억 문맥은 별도 경로다.
 var perception := {}
 for key in ["player_hp", "max_hp", "ammo", "max_ammo", "enemy_count", "medkits", "supply_packs", "cover_charges", "cover_active", "inside_cover", "valid_actions", "locker", "npc_hp", "npc_downed", "active_action"]:
  if state.has(key): perception[key] = state[key]
 perception["player_ammo_empty"] = int(state.get("ammo", 0)) == 0
 perception["player_health_ratio"] = float(state.get("player_hp", 0)) / maxf(1, float(state.get("max_hp", 100)))
 return perception

static func parse_jev(body: Dictionary, allowed: Array) -> Dictionary:
 var answers = body.get("answers", {})
 if not answers is Dictionary: return {"error": "invalid_answers"}
 var result = answers.get("selection", {})
 if not result is Dictionary or result.get("type", "") != "choice": return {"error": "invalid_choice_type"}
 var selected = result.get("choice", "")
 if not selected is String or selected not in allowed: return {"error": "invalid_candidate"}
 var probabilities = result.get("probabilities", {})
 if not probabilities is Dictionary or probabilities.is_empty(): return {"error": "missing_probabilities"}
 var total := 0.0
 for key in probabilities:
  if key not in allowed or not (probabilities[key] is float or probabilities[key] is int): return {"error": "invalid_probability"}
  var value := float(probabilities[key])
  if not is_finite(value) or value < 0.0 or value > 1.0: return {"error": "invalid_probability"}
  total += value
 if absf(total - 1.0) > 0.025 or not probabilities.has(selected): return {"error": "invalid_distribution"}
 if not body.get("model", "") is String or str(body.get("model", "")).is_empty(): return {"error": "missing_actual_model"}
 return {"choice": selected, "actual_model": body.model, "probabilities": probabilities, "confidence": result.get("confidence"), "usage": body.get("usage", {})}
