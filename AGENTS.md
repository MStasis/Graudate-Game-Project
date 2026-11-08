# 프로젝트 작업 규칙

## 기준과 범위

- 현재 로컬 파일을 기준으로 판단한다. 원격 GitHub나 과거 계획의 완료 표기를 현재 구현의 근거로 삼지 않는다.
- 작업 전 `git status --short --branch`와 해당 경로의 `AGENTS.md`를 읽는다. 기존 미커밋·미추적 파일을 보존하고, 요청 없이 reset/clean/checkout·커밋·푸시하지 않는다.
- 구조 조사 → 작은 단계 구현 → 관련 검증 → 실행 방법과 남은 한계 보고 순서로 진행한다. 이번 2026-10-31 준비 작업에서는 게임 기능을 구현하지 않았다.
- 목표와 우선순위는 `DEVELOPMENT_PLAN.md`를 따른다. 대규모 리팩터링, 엔진 변경, 기존 기능·테스트·과거 증거 삭제는 별도 요청 없이 하지 않는다.
- 참고 게임에서는 조작·전투 구조를 참고한다. 최종 그래픽·음향의 출처와 이용 조건을 기록한다.
- 사용자 작업을 방해하지 않도록 화면 조작은 중단한 상태다(2026-11-06 요청). 이후 검증은 헤드리스·숨김 창·생성 파일 검사로 진행한다. 사용자가 다시 요청하기 전에는 화면 자동 조작이나 새 보이는 창을 시작하지 않는다.
- 2026-11-07 사용자가 노란 캡처 테두리 때문에 컴퓨터 유즈 중단을 다시 요청했다. 이전의 일시 허용보다 이 요청을 우선한다.

## 구조와 실행

- Windows x64 / 로컬 확인 버전 Godot `4.7.2.stable.official.ed1daf0bf`, GDScript, GL Compatibility.
- 프로젝트는 저장소 루트가 아닌 `game/project.godot`이다. 시작 씬은 `res://main.tscn`이다.
- `game/main.gd`·`main.tscn`: UI, 입력, 제공자 설정, 일시정지, 저장 연결.
- `game/scenes/World.tscn`·`game/world.gd`: 임무, 전투, 동료 이동·사격, 지원 실행, 상태.
- `game/scripts/player.gd`, `mission_drone.gd`, `mission_projectile.gd`: 플레이어 이동, 적, 탄환.
- `game/scripts/npc_brain.gd`, `npc_policy.gd`, `local_ai_client.gd`: 판단, 규칙 정책, 비동기 Ollama 통신.
- `game/scenes/ui/`, `game/scripts/chat_input.gd`, `noncombat_dialogue_panel.gd`, `combat_interface.gd`, `mission_save_store.gd`: UI·입력·저장.
- `START_DEMO.cmd`: 규칙 기반 실행. `OPEN_PROJECT.cmd` → F5: 전체 게임 실행. F6의 World 단독 실행에는 전체 UI·NPC 판단 연결이 없다.
- `START_LOCAL_AI.cmd`: 로컬 AI 실행. 설정은 `game/resources/NPCSettings.tres`, 비교 조건은 `ExperimentSettings.tres`와 해당 Resource 스크립트의 기본값이다.
- 런처는 `APPDATA`를 `runtime/appdata`로 지정한다. 기존 사용자 저장을 검사용 데이터로 덮어쓰지 않는다. 런타임 준비는 `SETUP_RUNTIME.md` 참조.
- 별도 협동 검증은 `START_COOP_TEST.cmd`, `game/scenes/CoopProbe.tscn`, `game/scripts/coop_probe.gd`다. 메인 임무 전체의 협동 완료로 간주하지 않는다. 자동 검사는 `scripts/verify_coop.ps1`이며 `-Render`도 창을 숨겨 실행한다.
- 임시 에셋 출처·라이선스·해시는 `game/assets/temporary/kenney/`에 있다. 단순 다운로드, 게임 연결, 렌더링, 실제 청취를 구분해 보고한다.
- 본편의 이동 프로필은 `companion_motion.gd`, 재사용 협동 패널은 `CooperativeLocker.tscn`/`cooperative_locker.gd`다. 보관 구역은 전멸 후에도 말풍선 모드를 유지하고 Enter 채팅만 명시적으로 연다.
- 손전등 줍기 전 진입 금지·1초 동시 패널·비프·보관함·전력 조명을 임의로 우회하지 않는다. 회귀 테스트의 준비 상태와 실제 기믹 통합 검사를 구분한다. 새 저장은 v2이며 호환 v1 변환은 원본 파일을 보존해야 한다.
- 기본 검증에 `mission_mechanics_test.gd`, LocalAI에 `mechanics_local_ai_test.gd`가 포함된다. Render는 숨김 창/Dummy 오디오이며 실제 픽셀 검사와 PNG 확인을 수행한다.
- 빈 Enter/전송 Enter/Esc는 채팅을 닫고 이동으로 복귀한다. UI 명령은 일반 키코드를 우선하며 IME 확정·취소 경로는 보존한다. `input_aim_collision_test.gd`가 기본/Render 검증에 포함된다.
- 손전등의 CPU 시야·GPU 셰이더는 `world.gd::flashlight_direction()`의 마우스 조준 방향을 공유한다. `player.facing_direction`은 동료 대형용 이동 방향이므로 섞지 않는다.
- `rounded_obstacle.gd`는 둥근 발밑 충돌을 만든다. 레이어 값 4, 플레이어 마스크 5이며 숨겨진 방에서는 충돌을 끈다. 탄환·NPC 경로 탐색을 변경한 것으로 간주하지 않는다.
- 시스템 알림은 `system_notifications.gd`의 플레이어 우측 페이드 표시를 사용한다. `world.notice`와 `world.companion_spoke`를 구분하고, 시스템 문구를 Answer/말풍선/대화 기록에 넣지 않는다. 전송한 문장은 두 방 모두 비우며 미전송 초안은 Esc로 보존한다.
- 대화 문맥은 `harin_dialogue.gd`다. 잡담에 임무/기믹 전체를 주입하지 않고, 기믹 질문은 최신 사실과 의미 기준을 사용한다. 모델 응답을 몰래 템플릿으로 대체하지 않는다. `dialogue_notice_test.gd`는 기본/Render, `dialogue_quality_test.gd`는 LocalAI 검증에 포함된다.

## NPC와 비교 실험

- 이동·조준·사격·재장전·긴급 대응은 공통 규칙, LLM은 대화·제한된 고수준 전술을 맡기는 목표를 유지한다. 현재 재장전과 공통 긴급 대응 우선권은 아직 없다.
- 모델 출력으로 체력·탄약·목표를 직접 바꾸지 않는다. 허용 후보·현재 자원·회차/맵 epoch·응답 나이를 검사한 뒤 공통 실행기를 사용한다.
- 두 비교 조건은 같은 무기·적·시작 자원·실행 규칙·상태 입력을 사용한다. 변경된 설정과 프롬프트 버전을 기록한다. 현재 seed는 식별 값이며 난수 재현/입력 리플레이 구현으로 간주하지 않는다.
- 모델 요청은 게임 루프를 막지 않아야 한다. 대화 대기 중에도 긴급 대응이 가능하도록 후속 구현한다. 실패를 숨겨 다른 제공자의 성공으로 기록하지 않는다.
- `accepted`는 실행 수락이고, 실제 지원 효과는 `support_completed`로 확인한다. 합성 검사·실모델 호출·사람 플레이·성능 비교 결과를 구분한다.
- 현재 Qwen3 `qwen3:4b`·Ollama `0.40.11`을 재사용한다. 키를 파일에 저장하지 않는다. Jev는 보존하되 이번 필수 범위를 확대하지 않는다.

## 검증

저장소 루트 PowerShell에서 실행한다.

```powershell
.\scripts\verify_mission.ps1          # 기본 자동 검사
.\scripts\verify_mission.ps1 -Render  # 기본 검사 + 실제 GPU 임무/UI 렌더링
.\scripts\verify_mission.ps1 -LocalAI # 기본 검사 + 준비된 Ollama의 실제 추론/취소
```

- 런타임 경로: `runtime/godot/Godot_v4.7.2-stable_win64_console.exe`. 최초 사용 시 이 실행 파일에 `--headless --editor --path game --import --quit`을 전달해 리소스를 가져온다.
- 활성 테스트는 `game/tests/`다. 루트 `tests/`는 이전 사양이므로 현재 회귀 검증 대신 실행하지 않는다.
- 기본 검사 결과 JSON의 `passed`, `check_count`, 생성 시각과 프로세스 종료 코드를 확인한다. 기존 결과 파일을 읽는 것만으로 이번 통과라고 보고하지 않는다.
- 위 명령은 `evidence/`에 덮어쓰거나 로그를 추가한다. 기존 증거가 미커밋이면 별도 `runtime/<검증명>/`에 `game/`(.godot 제외), `scripts/verify_mission.ps1`, 동일 Godot 실행 파일을 복사하고 그 복사본에서 검사한다. 격리된 `APPDATA`와 `evidence/`를 사용한다.
- UI·카메라 변경은 `-Render`와 생성 PNG 육안 확인을 추가한다. UI 클릭의 오발 방지, 입력 포커스, 실제 창 크기를 확인한다. 정적 SVG 미리보기를 GPU 증거로 부르지 않는다.
- AI·저장 취소 변경은 모델 적재를 먼저 확인하고 `-LocalAI`를 실행한다. 처음 적재한 요청과 준비 후 요청을 구분하고 오류·시간초과·stale 응답도 보존한다.
- 임무 변경 후에는 사람이 WASD·조준·사격·E·재시작으로 처음부터 끝까지 플레이한다. 자동 시연은 위치·자원을 직접 설정하므로 이 검사를 대신하지 못한다.
- 한글 입력 변경은 실제 Microsoft IME로 조합·삭제·Enter 전송·Esc를 확인한다. 현재 자동 입력 검사는 실제 IME 검증이 아니다.
- 멀티플레이 구현 후에는 두 프로세스 검사와 실제 두 PC LAN 검사를 구분한다. 싱글플레이 검사 통과로 동기화·권한·연결 해제를 완료 처리하지 않는다.
- 변경 범위에 맞는 검사를 실행하고, 수행한 명령·결과·증거 위치·미검증 항목을 보고한다. 게임 코드가 바뀌지 않은 문서 편집만으로 전체 검사를 반복하지 않는다.

2026-10-31 기준: 격리 복사본에서 기본 251/251, GPU UI 81/81 및 임무 완료, 준비된 Qwen3 실통합 5/5·불러오기 취소 7/7 통과. 상세 경계와 증거 위치는 `DEVELOPMENT_PLAN.md` 참조.
