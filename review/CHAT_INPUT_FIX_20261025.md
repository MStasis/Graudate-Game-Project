# 한글 입력 보완 — 2026-10-25

사용자 증상: START_LOCAL_AI.cmd / START_DEMO.cmd의 게임 창에서 '안녕하세요'를 입력할 때 이전 음절이 사라지고 새 음절만 남음.
사용자 요청에 따라 화면·키보드 자동 조작은 수행하지 않았다.

## 확인한 사실

- 게임 코드에서 타이핑 중 질문 본문을 지우거나 덮어쓰는 구문은 발견하지 못했다.
- 기존 LineEdit에도 완성된 Unicode 음절을 차례로 보내면 '안녕하세요'가 유지된다. 이 검사는 실제 Windows IME 조합을 재현하지 않는다.
- 따라서 현재 자동 검사만으로 신고된 Windows IME 오류의 정확한 원인을 확정하지 않았다.

## 적용한 보완

- 질문 입력을 TextEdit 기반 ChatInput으로 교체.
- 입력 중 본문·선택·커서를 재설정하지 않음. 글자 수 검사는 조합 중이 아닌 전송 시 수행.
- 전송 전에 apply_ime()로 마지막 조합 글자를 확정하고, 다음 프레임에 확정된 본문을 읽음.
- 포커스 해제와 읽기 전용 전환은 전송 내용 확보 이후 수행.
- Enter와 버튼을 같은 전송 경로로 통합하고, Enter 반복/같은 프레임의 중복 전송 방지.
- 조합이 남아 있으면 전송을 보류하고 입력을 유지.
- Escape는 조합 중에는 조합만 취소하고, 조합이 없을 때 입력 포커스를 해제.
- 입력창에 포커스가 있으면 게임의 전역 단축키 처리에서 제외.
- 빈 입력으로 시작하고 TextEdit 전용 테마 적용.

## 검증

- game/tests/chat_input_test.gd: 27/27 통과.
- 한글 연속 입력, 커서, 삭제, 선택 교체, 포커스 이동, Enter/버튼 전송, 중복, 길이 초과 보존을 검사.
- 마지막 음절 확정 순서는 합성 조합 버퍼로 검사. 실제 Windows IME 검사가 아님.
- 기존 왕복 임무 검사: 50/50 통과.
- 결과: evidence/chat_input_fix/chat_input_test.json.
- 기본 VERIFY_MISSION.cmd에 새 채팅 검사를 추가. 기존 검사 파일은 보존.

실제 Windows IME에서 증상이 해결되었는지는 아직 미확인이다. 현재 실행 중인 게임 창은 이전 소스를 사용하므로 닫은 뒤 START_LOCAL_AI.cmd 또는 START_DEMO.cmd로 다시 실행해 확인해야 한다.
동일 증상이 지속되면 입력창 수준을 넘어 Windows IME와 엔진의 조합 확정 이벤트 경로를 추가로 조사해야 한다.

공식 API 참고:
- https://docs.godotengine.org/en/stable/classes/class_textedit.html
- https://docs.godotengine.org/en/stable/classes/class_lineedit.html

수정 전 백업: review/chat_input_before_20261025.zip.
