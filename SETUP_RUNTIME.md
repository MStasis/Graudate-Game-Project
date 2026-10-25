# 저장소를 받은 뒤 실행 준비

Windows x64 기준이다. 소스, Godot 씬·리소스, 초상화, Windows IME DLL·소스, 문서, 발표 자료, 검증 기록은 저장소에 포함한다. Godot/Ollama 실행 파일, AI 모델, 편집기 캐시, 빌드 임시 파일과 실행 중인 Ollama의 표준 출력 로그는 포함하지 않는다.

## 1. Godot

[Godot 4.7.2 Windows x64 공식 ZIP](https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip)을 받아 `runtime/godot/`에 압축을 푼다. 다음 파일 두 개가 바로 그 폴더 아래 있어야 한다.

```text
runtime/godot/Godot_v4.7.2-stable_win64.exe
runtime/godot/Godot_v4.7.2-stable_win64_console.exe
```

ZIP의 SHA-256은 `731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953`이다. 기록된 출처·버전·해시는 `runtime/tools_manifest.json`에 있다. 해당 파일의 destination은 개발 당시의 로컬 위치이므로 새 PC에서는 이 문서의 상대 경로를 따른다.

API 키·모델 없이 게임을 확인하려면 `START_DEMO.cmd`를 실행한다. 로컬 AI가 준비되지 않았다는 안내가 나와도 규칙 기반 모드와 편집기는 사용할 수 있다. `OPEN_PROJECT.cmd`로 편집하고 F5로 전체 게임을 실행한다. 원형 시야·통신창을 포함한 전체 구성의 시작 씬은 `game/main.tscn`이다.

## 2. 로컬 AI

[Ollama v0.40.11 Windows amd64 공식 ZIP](https://github.com/ollama/ollama/releases/download/v0.40.11/ollama-windows-amd64.zip)을 받아 하위 파일·폴더를 유지해 `runtime/ollama/`에 압축을 푼다. `runtime/ollama/ollama.exe`가 있어야 한다.

ZIP의 SHA-256은 `bda4a493ba8a7c24d57263cd843cd68cee84f44aed4299eeed532acad7eda12a`이다. 모델 파일은 저장소에 포함하지 않으며 첫 다운로드에 인터넷과 충분한 디스크 공간이 필요하다.

저장소 루트의 PowerShell에서 서버를 실행한다.

```powershell
$env:OLLAMA_MODELS = Join-Path (Get-Location) 'runtime\models'
$env:OLLAMA_HOST = '127.0.0.1:11434'
$env:OLLAMA_NO_CLOUD = '1'
.\runtime\ollama\ollama.exe serve
```

같은 위치에서 연 다른 PowerShell 창으로 모델을 받고, 다운로드가 끝나면 로컬 AI 모드를 실행한다.

```powershell
.\runtime\ollama\ollama.exe pull qwen3:4b
.\START_LOCAL_AI.cmd
```

이미 같은 주소에서 Ollama가 실행 중이면 서버를 중복 실행하지 않는다. 기존 서버에 모델을 받거나 서버 설정을 확인한다. 현재 모델·주소는 `game/resources/NPCSettings.tres`에 있다.

## 3. Jev

실제 호출에는 본인의 `TYPESAFE_API_KEY` 환경 변수가 필요하다. 키는 저장소나 문서에 저장하지 않는다. 준비된 실행 환경에서 `START_JEV.cmd`를 실행한다. 현재 프로젝트 기록에서 실제 Jev 추론 성공은 확인되지 않았으므로 어댑터 구현과 실제 인증·추론 성공을 구분한다.

## 4. 검사와 편집

- `VERIFY_MISSION.cmd`: 외부 AI 호출 없이 129개 자동 검사. 임무 50 / 채팅 27 / 입력 모듈 로드 6 / 입력 연결 합성 11 / UI 35.
- `GODOT_EDITING_GUIDE.md`: 씬·자원과 UI를 직접 수정하는 방법.
- `native/windows_ime/README.md`: 포함된 입력 연결 DLL의 소스·빌드·검증 범위. 일반 게임 실행에는 Visual Studio가 필요하지 않다.
- `README.md`: 현재 구현, 조작, 연구 비교 방식과 남은 작업.

기록된 자동 검사와 정적 UI 미리보기는 실제 Microsoft 한글 입력기·모든 PC의 화면·플레이 품질을 보증하지 않는다. 기존 `deliverables/` 발표 자료는 이전 단일 방 구성을 기준으로 작성되어 현재 왕복 임무·UI 개편 내용을 반영하는 작업이 남아 있다.
