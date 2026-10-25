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
@export_multiline var system_prompt: String = "한국어 한두 문장으로, 친한 동료에게 자연스러운 반말로 답한다. 임무 질문은 현재 안내를 정확히 설명하고 일상 질문은 질문 내용에 맞게 대화한다. 제공되지 않은 과거와 세계 설정을 만들지 않는다. 실제로 완료하지 않은 치료, 보급, 이동을 했다고 말하지 않는다."

func generation_options() -> Dictionary:
	return {"temperature": temperature, "num_ctx": context_size, "num_predict": max_tokens, "seed": seed}

