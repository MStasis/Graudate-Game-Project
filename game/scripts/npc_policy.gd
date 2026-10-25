class_name NPCPolicy
extends RefCounted
const PROMPT_VERSION := "companion_v1.4"
const DECISION_INSTRUCTIONS := "Choose one allowed action to help a close companion. Prioritize urgent unmet needs: critically low health calls for healing; zero or nearly empty ammunition calls for resupply. Install preventive cover after urgent recovery needs are handled. Guide the player into existing cover when useful. Do not waste resources or invent actions. Use follow or wait when support is unnecessary."
## 공통 행동/대화 목록. 판단과 실제 자원 소비는 별개입니다.
const ACTIONS := {
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

static func rule_action(state: Dictionary) -> String:
 var valid: Array = state.get("valid_actions", [])
 if state.player_hp <= 55 and "heal" in valid: return "heal"
 if state.ammo <= 4 and "resupply" in valid: return "resupply"
 if state.enemy_count > 0 and "deploy_cover" in valid: return "deploy_cover"
 if "guide_to_cover" in valid: return "guide_to_cover"
 return "follow"

static func rule_intent(question: String) -> String:
 if has_word(question, ["치료", "체력", "보급", "탄약", "총알", "전투", "보호", "싸", "도와", "도움"]): return "support"
 if has_word(question, ["임무", "목표", "퓨즈", "전력", "문", "출구", "어디", "해야", "진행", "연구", "보관"]): return "mission"
 if has_word(question, ["우리", "동료", "사이", "관계", "친구", "기억"]): return "relationship"
 if has_word(question, ["안녕", "기분", "괜찮", "고마", "밥", "먹", "수고", "피곤", "오늘", "무서", "힘들"]): return "everyday"
 return "unknown"

static func has_word(text: String, words: Array) -> bool:
 for word in words:
  if text.contains(word): return true
 return false

static func template_response(intent: String, state: Dictionary) -> String:
 match intent:
  "mission": return "내가 같이 갈게. " + str(state.current_guidance)
  "support": return "가까이에서 치료와 탄약 보급을 도울게. 보호 장비 안에서는 피해가 줄어들어. 남은 치료 키트 %d개, 보급품 %d개야." % [state.medkits, state.supply_packs]
  "relationship": return "우린 서로 믿는 친한 동료잖아. 이번에도 같이 돌아가자."
  "everyday": return "무사히 돌아와서 다행이야. 조금 쉬었다 가자." if state.fuse_collected else "나도 긴장되지만 네가 있어서 든든해. 끝나면 같이 쉬자."
 return "그건 지금 가진 정보로는 모르겠어. 임무나 우리 상황부터 이야기해 볼까?"

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
 var perception := state.duplicate(true)
 perception.erase("scenario_config")
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
