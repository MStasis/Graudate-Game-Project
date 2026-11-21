class_name LocalNPCSettings
extends Resource
## 로컬 AI 실행 설정입니다. 게임 속 이름과 역할은 World의 NPC와 물체에서 읽습니다.

@export_group("로컬 모델")
@export var model: String = "qwen3:4b"
@export var host: String = "127.0.0.1"
@export_range(1, 65535) var port: int = 11434
@export var thinking: bool = true
@export_range(5.0, 300.0, 1.0) var timeout_seconds: float = 90.0

@export_group("대사 생성")
@export_enum("A", "B", "C", "B512", "C512", "C4096", "C_ON", "C_FAST", "D") var campaign_dialogue_profile := "A"
@export_range(0.0, 2.0, 0.05) var temperature: float = 0.55
@export_range(512, 32768, 512) var context_size: int = 8192
@export_range(32, 8192, 32) var max_tokens: int = 4096
@export var seed: int = 42
@export_multiline var system_prompt: String = "친숙한 반말. 상황에 맞는 장난·반문·회피를 허용한다. 임무 핵심 사실과 실제 자원은 정확하게 지킨다."

# Applied only to the dialogue client's private resource. A uses the original exported values.
const PROFILE_VERSION := "qwen4b-dialogue-1"
const PROFILES := ["A", "B", "C", "B512", "C512", "C4096", "C_ON", "C_FAST", "D"]
var dialogue_profile := "A"
var _original_generation := {}

func apply_dialogue_profile(id: String) -> bool:
	if id not in PROFILES or (id != "A" and model != "qwen3:4b"): return false
	if _original_generation.is_empty():
		_original_generation = {"thinking":thinking, "max_tokens":max_tokens, "context_size":context_size, "temperature":temperature}
	dialogue_profile = id
	if id in ["A","C_ON","C_FAST"]:
		for key in _original_generation: set(key, _original_generation[key])
		if id != "A": thinking = true
	else:
		thinking = false
		max_tokens = 512 if id.ends_with("512") else 256
		context_size = 4096 if id == "C4096" else 8192
		temperature = 0.55
	return true

func uses_character_prompt() -> bool:
	return dialogue_profile.begins_with("C") or dialogue_profile == "D"

func generation_options() -> Dictionary:
	return {"temperature": temperature, "num_ctx": context_size, "num_predict": max_tokens, "seed": seed}

func effective_thinking() -> bool:
	return thinking and not model.to_lower().begins_with("qwen2.5")
