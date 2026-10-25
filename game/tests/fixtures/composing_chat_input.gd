extends ChatInput
## 실제 OS 입력기 대신 조합 확정·전송 순서를 검사하는 합성 버퍼입니다.
var composition := ""
var block_commit := false
var commit_count := 0
func is_composing() -> bool:
 return not composition.is_empty()
func commit_composition() -> void:
 commit_count += 1
 if block_commit: return
 insert_text_at_caret(composition)
 composition = ""
