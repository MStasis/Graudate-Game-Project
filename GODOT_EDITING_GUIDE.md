# Godot에서 직접 게임 수정하기

현재 버전은 연구실과 어두운 보관 구역을 왕복하는 동료 NPC 시제품이다. 맵과 UI는 저장된 씬이며, 실행할 때 배치를 새로 만들지 않는다.
이전 단일 방 소스는 `review/mission_before_20261025.zip`에 보존했다.

## 첫 수정

1. `OPEN_PROJECT.cmd` 실행 → Godot 상단 **2D**.
2. `World.tscn` 트리의 **Player** 선택. F로 선택 대상을 화면에 맞춘다.
3. Inspector에서 **Move Speed**를 바꾸거나 2D 화면에서 시작 위치를 드래그한다.
4. Ctrl+S로 저장하고 **F5**로 전체 게임 실행.
5. 게임의 **실험 설정 / F3 → 새 회차 시작**을 눌러 저장한 시작 위치가 유지되는지 확인한다.
6. F8로 실행을 멈추고 다음 수정.

F6은 World 씬만 실행하므로 대화 UI와 NPCBrain이 포함되지 않는다. 전체 흐름은 F5로 확인한다.

## 수정 위치

| 수정할 내용 | 선택할 대상 | Inspector / 조작 |
|---|---|---|
| 연구실 첫 시작 위치 | World / Player | 2D 드래그 또는 Transform → Position |
| 이동 속도·상호작용 거리 | 같은 Player | Move Speed / Interaction Distance |
| 캐릭터 그림·색 | Player 또는 NPC | Character Texture 또는 Object Texture / 색 |
| NPC 이름·역할 | NPC | Display Name / Description |
| 연구실 소품 | LabDecor 아래 | 배치·크기·색 수정 |
| 보관 구역 소품 | StorageDecor 아래 | Visible을 켜서 배치 확인. 게임 실행 때는 현재 구역에 따라 표시 |
| 보관 구역 진입 위치 | StorageEntry | Marker2D의 위치 드래그 |
| 연구실 복귀 위치 | LabReturn | Marker2D의 위치 드래그 |
| 통로 위치 | ToStorage / ToLab | 위치 이동. Interaction Id 유지 |
| 퓨즈 위치 | Fuse | 보관 구역에서 사용할 배치 |
| 전력 장치·출구 | Generator / Exit | 연구실에서 사용할 배치 |
| 드론 위치 | Enemies / DroneA·B·C | 배치 이동 |
| 드론 체력·속도·피해 | 각 Drone | Max Hp / Move Speed / Contact Damage / Attack Interval |
| 원형 시야 반경 | 최상위 World | Sight Radius |
| 체력·탄약·지원 자원·회복량 | 같은 World | 공통 전투 조건의 각 값 |
| 보호 지점·반경·피해 비율 | 같은 World | Safe Position / Cover Radius / Covered Damage Multiplier |
| 맵 경계·바닥 크기 | 같은 World | Room Rect. 문·소품도 새 경계 안에 배치 |
| 체력·탄약·지원 표시 | main.tscn / Header | HealthBar / HealthValue / AmmoValue / SupportValue |
| 임무 표시 | main.tscn / MissionBar | Objective / MissionStep / Location |
| 대화 UI | main.tscn / RadioPanel | Answer / Question / SendButton 등의 위치·크기·글자 |
| 하린 초상화 | RadioPanel / PortraitFrame / Portrait | Texture. 픽셀 그림은 Texture Filter의 Nearest 유지 |
| 실험 설정 창 | main.tscn / DebugPanel | 편집 시 Visible을 켜서 배치 확인. 저장 시 다시 끄기 |
| UI 색·테두리·글꼴·버튼 | resources / GameTheme.tres | Theme의 각 스타일·색상·글꼴 |
| 기본 비교 방식 | ExperimentSettings.tres | Provider: RuleBased / LocalLLM / Jev |
| 판단 주기·유효 시간 | 같은 리소스 | Decision Interval / Max Decision Age |
| 로컬 모델·생성 옵션·말투 지침 | NPCSettings.tres | Model / Thinking / Temperature / Context Size / Max Tokens / System Prompt |

World만 실행할 때 RoomTitle은 Location Name을 사용한다. 전체 게임에서는 중복 안내를 숨기고 main.tscn의 MissionBar를 사용한다. 현재 목표 안내는 퀘스트 단계에 따라 `world.gd → current_guidance()`가 채운다.
퀘스트 구조가 늘어나 이전의 정적 단계 안내 템플릿은 사용하지 않는다. 새 단계·목표 문장을 추가하려면 이 함수를 수정해야 한다.

NPC의 이름·설명은 로컬 대화 지침에 반영된다. 일부 시스템 알림·규칙/의도별 대사는 `world.gd`와 `npc_policy.gd`에 있다.
지원 행동의 우선순위·대화 의도 분류·규칙 기반 문장을 바꾸려면 `npc_policy.gd`를 수정한다. 연구 비교 조건을 바꾼 경우 코드/프롬프트 버전과 데이터를 분리한다.

## 그림 바꾸기

1. PNG 등을 `game/assets/` 안에 복사한다.
2. Player의 Character Texture 또는 NPC·물체의 Object Texture 슬롯으로 드래그한다.
3. 원본 색을 쓰려면 Body Color / Base Color를 흰색으로 설정한다.
4. 그림 크기에 맞춰 Scale과 원본 씬의 CollisionShape2D도 조정한다.

Generator와 Exit는 전력 복구 시 Activated Color가 적용된다.
현재의 Sprite2D 한 장 교체 기능은 애니메이션 타일셋의 자동 분할 기능이 아니다. 걷기·방향 애니메이션은 AnimatedSprite2D 등으로 별도 연결해야 한다.
최종 픽셀아트 적용 때는 픽셀 밀도와 Nearest 필터를 맞춘다.

## 씬과 실행 상태

- World의 인스턴스 설정은 이 맵 배치를 바꾼다. 원본 Player/NPC/Drone 씬을 수정하면 그 기본값을 따르는 인스턴스에 적용된다.
- 실행을 멈춘 뒤 **Local** 트리에서 저장한다. Remote에서 바꾼 값은 대개 다음 실행에 남지 않는다.
- 내부 노드 이름·Unique Name·World의 Player/NPC/Fuse/Generator/Exit 참조는 유지한다.
- LabDecor와 StorageDecor는 현재 두 구역을 표현하는 별도 그룹이다. 실제 방을 새로 추가하는 기능은 코드 수정이 필요하다.
- 현재 하린은 열린 공간에서 단순 추적한다. 충돌하는 가구·복잡한 통로를 추가하면 NPC 경로 탐색도 보완해야 한다.
- main.tscn의 UI는 일반 Control의 저장된 위치·크기를 사용한다. 고정 1280×800 기준이며 다양한 화면 비율의 자동 재배치는 별도 작업이다.

## 검증 범위

새 자동 검사는 `game/tests/mission_test.gd`의 50개 항목이며 `VERIFY_MISSION.cmd`로 실행한다.
키 이동, 입력 중 이동 제한과 전투 지속, 탄환·근거리 적중, 지원 자원/효과, 왕복 진행, 오래된 응답 폐기, 씬 저장·재로드를 검사한다.
실제 로컬 모델의 치료·보급·대화는 별도 통합 검사로 확인했다. 최신 결과는 `evidence/mission_v1/`에 있다.
이 버전에서 native 편집기 자동 조작을 새로 수행하지는 않았다. 저장된 씬의 변경 보존은 프로그램 검사로 확인했다.
