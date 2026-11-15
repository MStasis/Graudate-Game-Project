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
- 프로젝트는 저장소 루트가 아닌 `game/project.godot`이다. 시작 씬 `res://scenes/ui/TitleMenu.tscn`은 새 게임 또는 저장 슬롯 선택 시 `main.tscn`을 열고, 타이틀 복귀 시 임무 씬을 해제한다.
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
- 손전등 줍기 전 진입 금지·1초 동시 패널·비프·보관함·전력 조명을 임의로 우회하지 않는다. 회귀 테스트의 준비 상태와 실제 기믹 통합 검사를 구분한다. 새 저장은 v3이며 서사·발견 지도·통합 기록을 포함한다. 호환 v1/v2 변환은 원본 파일을 보존해야 한다.
- 기본 검증에 `mission_mechanics_test.gd`, LocalAI에 `mechanics_local_ai_test.gd`가 포함된다. Render는 숨김 창/Dummy 오디오이며 실제 픽셀 검사와 PNG 확인을 수행한다.
- `title_menu_test.gd`는 기본/숨김 Render에서 시작 메뉴·저장 슬롯·일시정지/결과 복귀·새 임무 초기화를 검사한다.
- 빈 Enter/전송 Enter/Esc는 채팅을 닫고 이동으로 복귀한다. UI 명령은 일반 키코드를 우선하며 IME 확정·취소 경로는 보존한다. `input_aim_collision_test.gd`가 기본/Render 검증에 포함된다.
- 손전등의 CPU 시야·GPU 셰이더는 `world.gd::flashlight_direction()`의 마우스 조준 방향을 공유한다. `player.facing_direction`은 동료 대형용 이동 방향이므로 섞지 않는다.
- `rounded_obstacle.gd`는 둥근 발밑 충돌을 만든다. 레이어 값 4, 플레이어 마스크 5이며 숨겨진 방에서는 충돌을 끈다. 탄환·NPC 경로 탐색을 변경한 것으로 간주하지 않는다.
- 시스템 알림은 `system_notifications.gd`의 화면 고정 페이드 영역을 사용한다(2026-11-10 변경). `world.notice`와 `world.companion_spoke`를 구분하고 시스템 문구를 Answer/NPC 말풍선/모델 대화 기억에 넣지 않는다. 사용자 통합 기록(`message_journal.gd`)에는 발신자·채널을 구분해 함께 기록한다. 전송한 문장은 두 방 모두 비우며 미전송 초안은 Esc로 보존한다.
- 대화 문맥은 `mika_dialogue.gd`다. 잡담에 임무/기믹 전체를 주입하지 않고, 기믹 질문은 최신 사실과 의미 기준을 사용한다. 모델 응답을 몰래 템플릿으로 대체하지 않는다. `dialogue_notice_test.gd`는 기본/Render, `dialogue_quality_test.gd`는 LocalAI 검증에 포함된다.

## NPC와 비교 실험

- 이동·조준·사격·재장전·긴급 대응은 공통 규칙, LLM은 대화·제한된 고수준 전술을 맡긴다. 2026-11-08 미카 자동 장전/예비탄·공통 긴급 대응·명시적 follow/wait를 구현했다. 플레이어 탄창/R 재장전과 출격 전 무기 선택은 아직 없다.
- 미카는 `mika_actor.gd`/`NPC.tscn`의 CharacterBody2D이며 상호작용은 자식 Area2D다. `companion_navigation.gd`가 활성 방의 실제 가구를 반영한 A* 경로를 만들고 `move_and_slide`가 충돌을 제한한다. `armed_sprite.gd`는 공통 유지 표적의 visual_aim과 방향별 스프라이트 JSON을 읽는다.
- 미카 설정은 `MikaCharacter.tres`/`mika_character.gd`다. 명확한 행동 요청은 `request_player_order` → 공통 지원 실행기로 연결한다. 명령 영수증을 모델 생성 성공으로 기록하지 않는다. 대화/전술 상태·ID·취소는 별도이며 추론은 최대 하나, 재생성은 같은 모델 한 번까지다.
- 미카 다운은 근접 E와 키트 1개로 소생하며 키트가 없으면 명확한 임무 실패다. 예비탄/장전/대기 위치/8개 문답을 저장하고, 이전 v1/v2 저장 변환은 원본 파일을 보존한다. `harin_upgrade_test.gd`는 기본/Render, `harin_live_test.gd`는 LocalAI 검증에 포함된다.
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

## 2026-11-10 서사·지도·통합 기록

- 기존 퓨즈/손전등/드론/2인 패널 흐름을 튜토리얼로 보존한다. `story_progress.gd`가 근무→정전→장비→퓨즈 탐색/복귀→전력 복구→침식 경보→연구동 진입→외곽 봉쇄를 관리한다. 연구실 출발 문 E는 `main_entry`로 이동하며 전체 임무 완료가 아니다. 관측 단말 이후 `containment_mission.gd`의 두 무리(기본 2/3)와 별도 2인 패널을 마쳐야 데모 완료다. 외곽 확산의 임시 봉쇄이며 내부 구역은 후속 범위다.
- 원문 말투 자료는 수정하지 않는다. `mika_style_examples.json`에 출처 해시·9개 문답·10개 발화·문맥/발화/행동 순서를 분리 보관한다. 모델에는 1~2개 가상 말투 예시만 선별한다. 예시를 실제 기억·고정 취향·퇴근 불가 규정으로 쓰지 않는다.
- 현재 로컬 `qwen3:4b` 메타데이터는 Thinking-2507이다. 대화는 native thinking과 충분한 생성 예산으로 최종 발화만 받으며 전술 후보 JSON과 분리한다. 실패 원문·재생성·실제 제공자를 기록하고 템플릿으로 대체하지 않는다. 실모델 지연/자연스러움은 별도 검토 대상이다.
- `exploration_map.gd`는 실제 방 범위와 활성 `RoundedObstacle.footprint`를 읽는다. 둥근 충돌의 외접 범위로 CPU/GPU 시야를 보수적으로 공유한다. 전력 조명과 시야 가림은 별개다. 지형은 관측 후 유지하고 물품/문/장치는 관측해야 표식이 생긴다. 미카는 현재 시야에서만 지도에 표시한다.
- M은 발견 전체 지도, H/통합 기록 버튼은 스크롤 기록이다. 채팅 포커스/IME 조합 중에는 M/H로 모달을 열지 않는다. 모달 중 월드 이동·사격·E를 막고 Esc는 모달부터 닫는다. Enter/빈 Enter/Esc의 초안 정책은 보존한다.
- 통합 기록은 최대 200개, 본문 2,000자/개다. ID·순서·발신자·채널·본문·회차·방·시각을 저장하며 같은 시스템 알림은 인접 4초 이내 합친다. 방 이동에는 유지하고 새 회차에 초기화한다. 사용자가 위를 읽으면 새 메시지 버튼만 표시하고 스크롤을 유지한다. 모델 기억(최대 8문답/프롬프트 850자)과 분리한다.
- 상태바는 플레이어 화면 기준 (-60,+38), 미카 (-60,-102), 적 (-60,+27)의 일정한 오프셋이다. 점유 영역 회피를 적용하지 않는다. 완전히 화면 안에 들어오지 않으면 숨기며, 미카는 시야 밖에서도 숨긴다. 실제 이동·충돌은 변경하지 않는다.
- 새 회귀는 `story_ui_test.gd`(기본/숨김 Render), 실제 대화 원문 수집은 `story_dialogue_live_test.gd`(-LocalAI)다. 통신/제공자 검사와 의미·자연스러움 수동 검토를 구분한다. 최신 결과와 남은 한계는 `review/STORY_UI_20261110.md`를 따른다.
- 대화는 `/api/chat`의 역할로 가상 예시/실제 문답/최신 사실/현재 질문을 구분한다. 서사 elapsed는 연출/저장에만 쓰고 stale 사실 비교에 넣지 않는다. 물품의 원래 위치와 현재 위치를 구분하며 다음 단계 후속 질문을 물품 질문으로 고정하지 않는다.
- 사용자 요청으로 설치된 qwen2.5:1.5b도 비교했다. 빠르지만 의미/말투가 더 불안정해 기본 Qwen3를 유지한다. 일반적인 대화 자연스러움과 전체 -LocalAI 최종 통과는 별도로 검증해야 한다.

## 2026-11-10 봉쇄 데모

- `containment_mission.gd`/`ContainmentMission.tscn`은 관측 전→준비→첫 무리→둘째 무리→패널 대기→완료를 관리한다. 튜토리얼 `Enemies`/`Locker`와 별도 적 풀/패널/보급을 저장한다. 무리 수는 각 1~6으로 조절하며 시나리오 해시에 포함한다.
- 전투 구역은 `world.is_combat_area()`로 판별한다. 연구실은 전투하지 않는다. 연구동 드론만 실제 가구 A* 우회/마스크 5, 연구동 탄환은 마스크 7을 사용한다. 기존 보관 구역 전투 규칙은 보존한다.
- 봉쇄 보급함은 기존 최대치까지 양쪽 탄약/미카 예비탄/공용 자원을 한 번 보충한다. 전투 중 복귀문은 안전 격리로 잠기며 전멸 후 왕복은 상태를 유지한다. 최종 패널은 고정 공통 지원으로 움직이며 AI 응답을 기다리지 않는다.
- 완료 시 공격/탄환/AI 요청을 정리하고 경보 해제→고정 미카 대사→6초 후 `DemoResult.tscn`을 표시한다. 새 게임은 기존 취소/기억 초기화를 사용한다. 저장 v3의 선택 확장과 이전 시나리오 해시를 대조하고 원본 파일은 보존한다.
- `containment_test.gd`는 기본/숨김 Render, `containment_live_test.gd`는 LocalAI에 포함된다. 새 게임→결과 자동 흐름은 위치/경계 fixtures를 사용하며 사람 완주가 아니다. 최신 증거·수치·한계는 `review/CONTAINMENT_DEMO_20261110.md`를 따른다.
