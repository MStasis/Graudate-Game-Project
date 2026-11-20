extends RefCounted
## Current blackout objective in world.gd: get Mika's flashlight in the left passage.
static func matches(text: String) -> bool:
	var compact := text.replace(" ", "")
	if NPCPolicy.has_word(compact, ["오른쪽","보관함","빌려줘","이미받","받지마"]): return false
	return "손전등" in compact and "왼쪽" in compact and NPCPolicy.has_word(compact, ["받","수령","챙","빌려야","빌리러","빌려줄게"])
