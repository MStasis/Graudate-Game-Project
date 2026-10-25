# Windows 한글 확정 입력 연결 모듈

이 모듈은 현재 게임 프로세스의 입력 창에만 연결된다. 다른 프로그램, 전역 키보드 훅, 레지스트리나 Windows 입력기 설정을 변경하지 않는다.

## 동작

- Godot가 만든 창의 HWND에 SetWindowSubclass로 연결한다. 동일 프로세스·동일 스레드 창만 허용한다.
- 입력창에 포커스가 있는 동안 Windows GCS_RESULTSTR, WM_IME_CHAR, WM_CHAR의 확정 문자열을 순서대로 받는다.
- 조합 중 표시·커서는 TextEdit의 기존 IME 경로를 유지한다.
- 이미 별도로 받은 확정 결과가 기본 경로에서 다시 삽입되지 않도록 결과 플래그와 중복 문자 전달을 처리한다.
- ChatInput이 확정 결과를 insert_text_at_caret로 삽입한다. 완성형 한글을 분해하거나 자모로 추정 조립하지 않는다.
- 전송 전 Windows에 CPS_COMPLETE를 요청한 뒤 확정 결과를 읽는다.
- 입력 종료 시 비활성화하고, 창/노드 종료 시 하위 클래스 연결을 해제한다.

이 모듈은 Windows x64 / 현재 Godot 4.7 API용이다. 엔진 실행 파일을 패치하지 않는다.
게임에 포함된 DLL을 사용하므로 일반 실행에 Visual Studio가 필요하지 않다.

## 빌드

`build.cmd`는 현재 설치된 Visual Studio 2026 Community의 x64 컴파일러를 사용한다.
헤더가 없으면 프로젝트에 포함된 Godot 실행 파일로 공식 GDExtension C 헤더를 생성한다.
표준 C++와 Godot의 C API를 사용하며 godot-cpp나 추가 패키지를 내려받지 않는다.
정적 CRT로 빌드하므로 이 모듈을 위한 별도 VC 런타임 설치는 필요하지 않다.

```powershell
.\native\windows_ime\build.cmd
.\native\windows_ime\test.cmd
```

출력: `game/native/windows_ime/windows_ime.dll`.
빌드 전에 이 DLL을 사용 중인 게임·편집기를 닫아야 한다.
컴파일러 설치 경로가 다른 PC에서 재빌드한다면 build.cmd/test.cmd의 vcvars64.bat 경로를 조정한다.

## 검증 범위

- C++ 메시지 경로 검사 31개. 표시·포커스·키 입력이 없는 메시지 전용 창에서 수행.
- Godot DLL 적재·수명 검사 6개.
- 합성 확정 입력 → 실제 TextEdit → 전송 연결 검사 11개.
- 기존 채팅 검사 27개와 게임 기능 검사 50개.

메시지 전용 검사는 GCS_RESULTSTR 데이터 공급 부분을 테스트 값으로 대체한다.
실제 Microsoft 한글 입력기 드라이버를 자동 조작한 검사가 아니다.
실제 사용자 입력 문제의 해결 여부를 위 검사만으로 확정하지 않는다.

진단: 게임의 최초 연결, 첫 확정 입력, 종료 시 `evidence/native_ime_fix/bridge_status_<PID>.json`을 기록한다.
모듈 연결 여부·이벤트 수·삽입 글자 수만 저장하고 입력 문장은 기록하지 않는다.

## 자료

- [Godot GDExtension C API 예제](https://docs.godotengine.org/en/4.6/tutorials/scripting/gdextension/gdextension_c_example.html)
- [Microsoft WM_IME_COMPOSITION](https://learn.microsoft.com/en-us/windows/win32/intl/wm-ime-composition)
- [Microsoft WM_IME_CHAR](https://learn.microsoft.com/en-us/windows/win32/intl/wm-ime-char)
- [Godot TextEdit](https://docs.godotengine.org/en/stable/classes/class_textedit.html)

Godot 생성 헤더의 저작권·MIT 라이선스 고지는 해당 헤더에 포함되어 있다.
