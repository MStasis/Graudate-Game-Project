class_name LocalNPCSettings
extends Resource
## 로컬 AI 실행 설정입니다. 게임 속 이름과 역할은 World의 NPC와 물체에서 읽습니다.

@export_group("로컬 모델")
@export var model: String = "qwen3:4b"
@export var host: String = "127.0.0.1"
@export_range(1, 65535) var port: int = 11434
@export var thinking: bool = false
@export_range(5.0, 300.0, 1.0) var timeout_seconds: float = 90.0

@export_group("대사 생성")
@export_range(0.0, 2.0, 0.05) var temperature: float = 0.3
@export_range(512, 32768, 512) var context_size: int = 2048
@export_range(32, 2048, 32) var max_tokens: int = 192
@export var seed: int = 42
@export_multiline var system_prompt: String = "함께 있는 친구에게 말하듯 한국어 반말로 답한다. 상대의 말과 감정에 먼저 반응하고 짧게 주고받는다. 묻지 않은 목표나 조작법은 덧붙이지 않는다. 실제 상태에 없는 과거 사건이나 완료 행동은 만들지 않는다."

func generation_options() -> Dictionary:
	return {"temperature": temperature, "num_ctx": context_size, "num_predict": max_tokens, "seed": seed}

