class_name MessageJournal
extends RefCounted
## 사용자 통합 기록. NPCBrain.history와 별개이며 모델 입력으로 사용하지 않는다.
const LIMIT := 200
var entries: Array[Dictionary] = []
var sequence := 0

func append(sender: String, channel: String, body: String, room: String, trial: String, message_id := "") -> bool:
 body = body.left(2000)
 if body.strip_edges().is_empty(): return false
 if not message_id.is_empty() and entries.any(func(item): return item.id == message_id): return false
 var now := Time.get_ticks_msec()
 if channel == "system" and not entries.is_empty():
  var last: Dictionary = entries.back()
  if last.channel == channel and last.body == body and last.room == room and now - int(last.get("tick", -10000)) < 4000:
   last.repeat = int(last.get("repeat", 1)) + 1
   last.tick = now
   return false
 sequence += 1
 entries.append({"id": message_id if not message_id.is_empty() else trial + ":" + str(sequence), "sequence": sequence, "sender": sender, "channel": channel, "body": body, "room": room, "trial": trial, "time": Time.get_datetime_string_from_system(), "tick": now, "repeat": 1})
 if entries.size() > LIMIT: entries.pop_front()
 return true

func restore(data: Array) -> void:
 entries.clear()
 sequence = 0
 for item in data.slice(-LIMIT):
  entries.append(item.duplicate(true))
  sequence = maxi(sequence, int(item.sequence))
  entries.back()["tick"] = -10000 # 前セッションの時計で重複抑制しない。

