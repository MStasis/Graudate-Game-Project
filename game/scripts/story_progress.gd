class_name StoryProgress
extends RefCounted
## 게임에서 발생한 사건만 기록한다. 스타일 표본의 가상 사건은 들어오지 않는다.
const STAGES := ["on_shift", "blackout", "equipment", "fuse_search", "fuse_return", "power_restored", "anomaly_alarm", "main_entry"]
var stage := "on_shift"
var events: Array[String] = []
var tutorial_completed := false
var elapsed := 0.0

func advance(next: String, event: String) -> bool:
 if next not in STAGES: return false
 if event in events: return false
 events.append(event)
 if STAGES.find(next) > STAGES.find(stage): stage = next
 elapsed = 0
 return true

func snapshot() -> Dictionary:
 return {"stage": stage, "events": events.duplicate(), "tutorial_completed": tutorial_completed, "elapsed": elapsed}

func restore(data: Dictionary) -> void:
 stage = data.stage
 events.assign(data.events)
 tutorial_completed = data.tutorial_completed
 elapsed = float(data.elapsed)

static func legacy(state: Dictionary) -> Dictionary:
 var phase := "anomaly_alarm" if state.power_restored else "fuse_return" if state.fuse_collected else "fuse_search" if state.map_id == "storage" else "equipment" if state.flashlight_owned else "blackout"
 var observed := ["blackout"]
 if state.flashlight_owned: observed.append("flashlight_collected")
 if state.fuse_collected: observed.append("fuse_collected")
 if state.power_restored: observed.append_array(["power_restored", "anomaly_alarm"])
 return {"stage": phase, "events": observed, "tutorial_completed": false, "elapsed": 0.0}
