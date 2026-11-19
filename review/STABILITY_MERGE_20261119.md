# 저장·AI 응답 안정화 병합 검증 (2026-11-19~20)

## 범위

기준 `main`은 `24de9d02f0e5fcf8c299b8dc15c9f65dbb9e916b`, 안정화 변경은 `d654fdf60ccba3eb38b652d2dc8b02b14d2d841f`다. 현재 로컬 코드가 안정화 변경과 일치하는 것을 먼저 확인했다.

안정화 변경은 UTF-8 저장 용량과 기존 슬롯 보존, 잘못된 모델 스트림의 오류 처리, 대화 기록의 명시적 수집 옵션, 전기실 수리 동선의 실패 복구, 효과 없는 자동 전술의 기록을 다룬다. 이번 검증에서 추가한 변경은 테스트 준비 상태·판정 시점·실행 옵션·대기 조건과 이 보고서다.

## 검증 결과

원본의 미커밋 증거를 보존하기 위해 `runtime/merge_stability_20261119/`에 게임(.godot 제외), 검증 스크립트, 같은 Godot 실행 파일을 복사했다. APPDATA와 증거 경로도 복사본 안으로 격리했다. Godot 4.7.2, GL Compatibility/NVIDIA RTX 5070, 실제 Ollama `qwen3:4b`를 사용했다.

| 검사 | 결과 | 근거 |
| --- | --- | --- |
| 기본 헤드리스 17개 묶음 | 1,169/1,169 | `validation_summary.json` |
| 숨김 GPU 10개 묶음 | 817/817 | `validation_summary.json`, 각 render JSON |
| 새 안정화 회귀 | 21/21 | `evidence/stability_test.log` |
| Fleet 실제 대화 전송·제공자 | 30/30, 사례별 재검증 포함 | `evidence/fleet_dialogue/verified_case_coverage.json` |
| 실제 HTTP 새 게임·엔딩 취소 | 7/7 | `evidence/containment/live.json` |
| 실제 추론 중 저장 불러오기·취소 | 7/7 | `evidence/interface_update/live_save_load_21920.json` |
| 실제 패널 선택·이동·개방·취소·안내 | 11/11 | `evidence/mission_mechanics/local_ai_10900.json` |
| 실제 치료·보급·이동·늦은 응답 기각 | 4/4 | `evidence/mission_v1/local_integration/live_integration_8580.json` |
| 서사 실제 대화 생성 수락 | 14/15 | `evidence/story_ui/live_dialogue.json` |
| 미카 기존 종합 실모델 검사 | 36/39 | `evidence/harin_upgrade/live_22736.json` |
| 기존 대화 내용 검사 | 19/20 | `evidence/dialogue_notices/local_dialogue_25072.json` |
| 통합 검사의 임무 경로 설명 | 0/1 | 위 live integration JSON |

Fleet 최초 실모델 묶음은 GPU 검사와 진단이 겹친 실행에서 두 사례가 제한시간을 넘겼다. GPU 검사가 끝난 뒤 동일 모델·설정으로 두 사례를 순차 재검증해 각각 3/3을 확인했다. 최초 실패 결과와 재실행 결과를 모두 보존했다. 이는 안정적인 응답 지연을 입증하는 성능 평가가 아니다.

## 검증 코드 보완

- 미니맵 기억 검사의 두 번째 관측점 `(1000, 330)`은 현재 방 밖에 있었다. 이 실패는 원래 `main`에서도 숨김 GPU 실행으로 재현됐다. 두 관측점을 방 안에 두고 손전등 조준 영향을 해당 검사 동안 분리한 뒤 보유 상태를 복원했다. 방 내부 좌표 검사도 추가했다. 헤드리스 88/88, GPU 89/89를 확인했다.
- 패널 이동 검사는 보관함 개방 후 위치와 고정 35px 반경을 사용했다. 실제로 패널을 누르기 시작한 순간의 이동·거리를 기록하고 공용 사용 반경 48px으로 판정하도록 바꿨다. 실제 HTTP 재검증에서 이동 거리 222.92px, 패널 거리 47.71px와 보관함 개방을 확인했다.
- `local_integration.gd` 실행에 `--mission-test`를 지정했다. 일반 플레이의 원문 기록이 기본 비활성화된 상태에서도 검증용 증거 디렉터리가 준비되도록 한다. 최초 결과 파일 쓰기 오류와 보완 후 실제 결과 파일을 보존했다.
- 서사 검사 대기를 고정 85초에서 요청당 설정 시간(현재 90초), 허용된 재생성 1회와 짧은 여유를 반영하도록 바꿨다. 측정 기록의 질문이 현재 질문과 일치하는지도 함께 검사한다. 게임의 제한시간·모델·프롬프트는 변경하지 않았다.

## 남은 한계

전체 LocalAI 검증을 통과한 것으로 표시하지 않는다. 기존 개발 임무의 자유 대화에서 다음 6개 항목이 실패했다.

- `mission_answer_has_current_goal`: 손전등 수령 위치/다음 목표 안내.
- `mission_followup_understands_partner`: 반대 패널 역할에 대한 후속 응답.
- `no_fake_handoff`: 손전등을 아직 건네지 않은 상태의 설명.
- `before_handoff_has_no_fake_completed_delivery`: 전달 전 손전등 상태 설명.
- `real_mission_dialogue_has_current_route`: 기존 임무의 현재 경로 설명.
- `fictional_rule_actual_generation`: 근거 없는 연구소 규정을 생성해 `unsupported_world_rule`로 거부됐다. 측정 기록의 질문과 실제 제공자는 일치했으며, 해당 발화는 표시 수락되지 않았다.

기록한 대화 문맥 3개를 원래 `main`과 안정화 코드에서 재생해 모델 요청 본문·생성 설정의 SHA-256이 일치하는 것을 확인했다. 이 비교는 새 모델 추론 없이 요청을 준비하고 취소한 입력 비교다. 대화 내용 문제를 이번 안정화가 해결했다고 주장하지 않는다. 전송·취소·실제 지원 효과와 대화 의미 품질을 구분해 기록한다.

사람의 처음부터 끝까지 플레이, 실제 Microsoft IME 조합 입력, 실제 스피커 청취, 다른 PC와 내보낸 빌드의 장시간 실행은 이번에 수행하지 않았다. 자동 진행은 상태·위치 fixture를 사용한다. GPU PNG는 Fleet 시작·전기실·결과와 960×600 저장 슬롯 화면을 직접 열어 확인했다.

## 명령과 증거

모든 경로는 저장소 루트 기준이며, 아래 실행은 격리 복사본 안에서 수행했다.

```powershell
.\scripts\verify_mission.ps1 -Render
.\run_local_ai.ps1
.\run_local_ai_followup.ps1
.\run_corrected_live.ps1
```

첫 Render 실행은 기존 미니맵 검사에서 중단됐다. 보완한 인터페이스 검사와 남은 렌더링 검사를 원래 스크립트와 같은 인자로 개별 재실행했다. LocalAI 블록은 이미 통과한 기본 검사를 중복 실행하지 않도록 원래 명령을 별도 실행 파일로 추출했다. 각 프로세스 종료 코드, 결과 JSON, 현재 실행의 수정 시각과 실패 원문을 확인했다.

주요 증거는 `runtime/merge_stability_20261119/validation_summary.json`, `live_followup_results.json`, `corrected_live_results.json`, `dialogue_prompt_comparison.json`, `additional_prompt_comparisons.json`, `evidence/`에 있다. 원본 작업 폴더의 기존 로그·패치·번들은 검증 데이터로 사용하거나 덮어쓰지 않았다.
