class_name ExperimentSettings
extends Resource

@export_group("비교 조건")
@export_enum("RuleBased", "LocalLLM", "Jev") var provider: int = 0
@export var scenario_id: String = "lab_roundtrip_v1"
## 현재 적 배치는 고정이며 난수를 사용하지 않습니다. 확장 시 사용할 시나리오 식별 값입니다.
@export var scenario_seed: int = 42
@export_range(0.5, 10.0, 0.1) var decision_interval: float = 1.5
@export_range(0.5, 15.0, 0.1) var max_decision_age: float = 3.0
@export_group("Jev 공식 API")
@export var jev_model: String = "jev-1.13.0"
@export_range(1.0, 60.0, 1.0) var request_timeout: float = 8.0
@export_range(1, 500, 1) var jev_call_limit: int = 60
## 키는 리소스에 저장하지 않습니다. 실행 프로세스의 TYPESAFE_API_KEY만 읽습니다.
