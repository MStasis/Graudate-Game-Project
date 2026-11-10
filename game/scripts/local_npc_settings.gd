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
@export_range(0.0, 2.0, 0.05) var temperature: float = 0.55
@export_range(512, 32768, 512) var context_size: int = 8192
@export_range(32, 8192, 32) var max_tokens: int = 4096
@export var seed: int = 42
@export_multiline var system_prompt: String = "친숙한 반말. 상황에 맞는 장난·반문·회피를 허용한다. 임무 핵심 사실과 실제 자원은 정확하게 지킨다."

func generation_options() -> Dictionary:
	return {"temperature": temperature, "num_ctx": context_size, "num_predict": max_tokens, "seed": seed}

func effective_thinking() -> bool:
	return thinking and not model.to_lower().begins_with("qwen2.5")
