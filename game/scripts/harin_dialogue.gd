class_name HarinDialogue
extends RefCounted
## 잡담에 목표/HUD/기믹 매뉴얼을 주입하지 않는 대화 전용 문맥.
static func build(state: Dictionary, question: String, history: Array, persona: String, extra_style: String) -> Dictionary:
 var topic := NPCPolicy.rule_intent(question)
 var casual := topic in ["everyday", "relationship", "unknown"]
 var controls := NPCPolicy.asks_controls(question)
 var system := "너는 플레이어와 친한 동료 하린이다. " + persona.split(".")[0] + "\n" + extra_style
 system += "\n친구에게 말하듯 짧고 편한 반말 한두 문장으로 질문에 먼저 답한다. 너 자신은 '나', 상대는 '너'라고 부른다. 하린이나 플레이어를 3인칭으로 부르지 않는다."
 system += "\n잡담에는 잡담으로만 답한다. 묻지 않은 임무 목표, 이동 경로, 물품, 조작 안내를 뒤에 붙이지 않는다. 매번 임무로 화제를 돌리거나 '걱정하지 마'를 반복하지 않는다."
 system += "\n현재 상태에 없는 완료 행동이나 과거 사건을 만들어내지 않는다. 대사는 행동 실행 명령이 아니다. 전달/줍기/회복을 하지 않았는데 했다고 말하지 않는다."
 system += "\n키 이름, 버튼, 수치, 초 단위 유지 시간은 구체적인 조작 방법을 물었을 때만 말한다. 시스템 알림이나 개발 상태를 흉내 내지 않는다."
 system += "\n생각 과정 없이 한국어 대사만 담은 JSON 객체 하나를 출력한다: {\"dialogue\": \"대사\"}"
 system += "\n말투 예시: '준비됐어?'에는 '응, 난 괜찮아. 너는?', '좀 피곤해'에는 '그럼 잠깐 쉬었다 가자. 무리하지 말고.', '질문이 있어'에는 '응, 뭔데? 편하게 물어봐.'처럼 대답한다. 질문에 없는 부상이나 통증을 꺼내지 않는다. 이모지는 쓰지 않는다."
 var conversation := []
 for turn in history:
  if casual and NPCPolicy.rule_intent(str(turn.get("question", ""))) in ["everyday", "relationship", "unknown"]:
   conversation.append(turn)
 var context := {"대화 종류": "잡담" if casual else "구체적인 질문", "관계": state.relationship, "최근 대화": conversation, "질문": question}
 if casual:
  context["대화 방향"] = NPCPolicy.template_response(topic, state, question)
  system += "\n질문을 그대로 되풀이하지 말고 대화 방향을 참고해 네 반응을 짧게 말한다. 의문문을 여러 개 덧붙이지 않는다."
 if not casual:
  context["현재 장소"] = state.location
  context["사실"] = facts(state, question, topic)
  context["대답의 의미 기준"] = NPCPolicy.template_response(topic, state, question)
  context["조작 설명 요청"] = controls
  system += "\n현재 사실과 대답의 의미 기준을 유지하고 말투만 자연스럽게 풀어 쓴다. 이전 대화의 위치/상태를 이어 쓰지 않는다. 상대가 이미 가진 물건을 바닥에서 다시 주우라고 하지 않는다."
 if state.get("npc_downed", false): context["현재 몸 상태"] = "하린은 쓰러져 움직이거나 지원할 수 없다. 재시작 같은 시스템 조작은 대사로 말하지 않는다."
 return {"system": system, "prompt": JSON.stringify(context), "schema": {"type": "object", "properties": {"dialogue": {"type": "string", "maxLength": 160}}, "required": ["dialogue"], "additionalProperties": false}}

static func facts(state: Dictionary, question: String, topic: String) -> Dictionary:
 if topic == "support":
  return {"치료 키트": state.medkits, "탄약 보급품": state.supply_packs, "체력": state.player_hp, "탄약": state.ammo, "지원": "실제 치료/보급은 가까이 접근한 뒤 공통 실행기로 완료한다. 대화만으로 지급하지 않는다."}
 if "손전등" in question:
  var possession := "지금 내 손 안에 있다. 내가 소지 중이다."
  if state.get("flashlight_owned", false): possession = "지금 네 손 안에 있다. 네가 소지 중이다."
  elif state.get("flashlight_dropped", false): possession = "지금 연구실 바닥에 있다. 네가 챙길 차례다."
  elif state.get("flashlight_requested", false): possession = "지금 내 손 안에 있다. 너에게 가져가는 중이다."
  var result := {"손전등 위치": possession}
  if NPCPolicy.asks_controls(question):
   result["사용 방법"] = "지금 네가 가진 손전등은 마우스 조준 방향으로 자동으로 비춘다. 마우스만 움직이면 된다." if state.get("flashlight_owned", false) else "바닥에 놓인 뒤 가까이에서 E로 줍는다. 주운 다음에는 마우스 조준 방향으로 자동으로 비춘다."
  return result
 if NPCPolicy.has_word(question, ["패널", "보관함"]):
  var result := {"보관함": "열림" if state.locker.opened else "잠김", "함께 할 일": "너는 한쪽을 맡고 나는 반대편 패널을 동시에 누른다. 내 대사는 '내가 반대편 누를게!'처럼 짧게 말한다."}
  if NPCPolicy.asks_controls(question): result["방법"] = "너는 한쪽 패널 가까이에서 E를 계속 누른다. 나는 반대편 패널을 동시에 누른다. 둘이 누른 채 1초 유지하면 보관함이 열린다."
  return result
 return {"목표": "보관 구역의 보관함에서 퓨즈를 찾아 연구실 전력 장치에 끼우고 출구로 나간다.", "퓨즈 확보": state.fuse_collected, "전력 복구": state.power_restored, "임무 완료": state.escaped}
