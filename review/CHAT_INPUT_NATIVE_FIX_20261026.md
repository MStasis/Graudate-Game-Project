# 한글 입력 후속 수정 — 2026-10-26

## 문제와 결정

사용자가 입력창 교체 뒤에도 같은 음절 소실을 확인했다.
이전 코드 검사 27개는 완성된 Unicode/합성 조합 검사였으므로 실제 Windows 입력기 오류의 해결 증거가 아니었다.

확인한 엔진 소스에서 LineEdit와 TextEdit는 같은 Windows DisplayServer 입력 경로를 사용한다.
이번에는 입력창 종류만 바꾸는 대신 Windows의 확정 문자열을 직접 받는 GDExtension을 추가했다.
원래 오류의 드라이버별 정확한 발생 조건은 화면·키보드 자동 조작 없이 확정하지 못했다.

## 변경

- game/native/windows_ime/windows_ime.dll과 .gdextension: Windows x64 확정 문자 연결.
- native/windows_ime/: 전체 C++ 소스, 공식 런타임에서 생성한 C API 헤더, 빌드·검사 명령.
- ChatInput: 확정 문자 버퍼 삽입, 전송 전 Windows 조합 완료, 포커스 해제 전 확정.
- SendButton은 클릭 시 먼저 입력 포커스를 빼앗지 않게 변경.
- 게임 프로세스의 같은 스레드 창만 연결. Windows 전역 설정·다른 앱에 대한 자동 조작은 없음.
- 원문을 저장하지 않는 모듈 상태 기록 추가.
- VERIFY_MISSION.cmd에 모듈 적재와 채팅 연결 검사 포함.

## 결과

| 검사 | 결과 | 실제 Microsoft IME 여부 |
|---|---:|---|
| C++ Windows 메시지 전달·중복·해제·혼합 문자열 | 31/31 | 결과 문자열 공급은 합성 |
| Godot DLL 적재·수명 | 6/6 | 입력기 사용 안 함 |
| Native 버퍼 → TextEdit → 전송 | 11/11 | Native 공급자는 합성 |
| 기존 채팅 | 27/27 | 합성 Unicode/조합 |
| 게임 기능 | 50/50 | 입력기 사용 안 함 |

결과 파일은 evidence/native_ime_fix/와 evidence/chat_input_fix/에 있다.
현재 DLL SHA-256은 native_load_test.json에 기록한다.
실제 Microsoft IME를 이용한 한글 입력 성공은 아직 미확인이다. 사용자가 현재 게임을 닫고 다시 실행해야 새 연결 모듈이 적용된다.

## 다음 확인 방법

START_LOCAL_AI.cmd 또는 START_DEMO.cmd 재실행 후:
1. 안녕하세요
2. 가나 까까 하하
3. 한글 English 123
4. 삭제·커서 이동·Enter와 버튼 전송

동일 증상이 남으면 bridge_status_<PID>.json에서 연결 성공·확정 이벤트 수를 먼저 확인한다.
그 결과를 이용해 모듈이 연결되지 않은 경우와 Windows에서 받는 문자 경로 문제를 구분한다.
현재 27개 코드 검사가 통과했다고만 판단하여 같은 수정으로 해결되었다고 반복 주장하지 않는다.
