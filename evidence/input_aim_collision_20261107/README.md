# 입력/마우스 조준/충돌 검증

2026-11-07 이번 요청의 격리 실행 결과다. `summary.json`이 최종 집계이고 `preservation_audit.json`은 요청 시작 시 원본 482개 파일과 비교한 보존 감사다. 기존 증거의 변경과 기존 파일 삭제는 없다. 새 소스는 검사 사본과 일치한다.

- `verification_render.log`: 최종 전체 기본 339/339, 프로세스 종료 0. 결과별 생성 시각과 JSON도 보존했다.
- GPU: UI 81/81, 기존 기믹 56/56, 새 입력/조준/충돌 35/35. `mission_render_stdout.log`의 자동 임무 완료와 각 stdout/stderr를 함께 확인한다. 새 PNG 두 장은 `input_aim_collision/`에 있다.
- 실제 Qwen3: `mission_mechanics/local_ai_31568.json`의 11/11. 패널 지원·취소·대화와 마우스 방향 손전등 설명의 원문을 포함한다. 이전 성공 결과를 이번 결과로 재사용하지 않았다. 정식 성능 비교는 아니다.
- `desktop_ui_observation.json`: 사용자 허용 후 실제 검사 창에서 Computer Use로 Enter 열기/빈 Enter 닫기/Esc 닫기를 확인한 기록. 처음 관찰한 일반/물리 키코드 차이는 `development_diagnostics/interactive_diagnostic.log`와 연결된다. 최종 창은 모두 종료했다.
- `development_diagnostics/`의 초기 실패는 최종 결과와 구분한다. 첫 자동 검사는 지연 제출을 기다리지 않고 물리 프레임만 기다린 검사 타이밍 문제였다. 최종 검사는 process/physics 프레임을 모두 기다리고 통과했다.

실제 Microsoft IME 조합·사람의 전체 플레이·실제 청취·두 PC LAN은 수행하지 않았다. 원본 프로젝트의 헤드리스 가져오기 로그는 `project_import*`다.
