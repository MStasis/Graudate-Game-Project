# 2026-11-07 본편 수정 검증

격리 복사본 `runtime/mission_mechanics_20261107/check/`에서 실행한 이번 검사 결과다. 기존 `evidence/`와 사용자 저장을 덮어쓰지 않았다. 최종 결과·생성 시각·원본 파일 보존 감사는 `summary.json`과 `preservation_audit.json`을 따른다.

- `verification_render.log`: 기존 기본 검사 251개 + 당시 기믹 53개, 전체 Render 실행. 이후 안내 말풍선 검사를 추가했고, `mechanics_final.log`의 54개와 `mechanics_final_render_stdout.log`의 GPU 56개가 최종 기믹 결과다.
- `mission_mechanics/`: 최종 헤드리스·GPU·실제 Qwen3 기믹 JSON, 실제 GPU 이미지 4장. CPU 계산만이 아니라 GPU 픽셀 방향·거리 감쇠도 확인했다.
- `local_integration_final.log`, `live_save_load_test_final.log`, `mechanics_local_ai_test_final.log`: 준비된 기존 Ollama/Qwen3의 실제 추론. 각각 5·7·9개 통과. 기믹 결과의 대화 원문과 측정도 보존한다. 정식 성능 비교 실험은 아니다.
- `coop_probe/`, `coop_final.log`: 같은 PC 두 프로세스의 별도 검증장 회귀 43개. 본편/두 PC LAN 완료를 뜻하지 않는다.
- `development_failures/`: 개발 도중 실패와 프롬프트 조정 기록. `mixed_development_event_logs/`는 여러 개발 실행이 섞인 원문 로그다. 최종 성공만의 통계나 정식 비교 데이터로 사용하지 않는다.
- `project_import*`: 원본 프로젝트의 새 리소스/클래스 헤드리스 가져오기. 게임 실행·추가 사용자 입력은 하지 않았다.

모든 창 검사는 숨김 GPU·Dummy 오디오로 진행했다. 화면 자동 조작·실제 음향 청취·Microsoft IME 조작·사람의 처음부터 끝까지 플레이·두 PC LAN 검사는 수행하지 않았다.
