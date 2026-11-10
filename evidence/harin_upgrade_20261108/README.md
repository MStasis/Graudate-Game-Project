# 2026-11-08 하린 개선 검증 증거

`summary.json`의 `fresh_suites`는 최종 실행 시작 이후 새로 생성되고 `passed=true`인 결과만 가리킨다. 프로세스 종료 코드는 0이다. `raw/verification_final.log`가 최종 통합 실행 로그다.

- 헤드리스: 기존 373 + 신규 하린 70 = **443/443**.
- 숨김 GPU: UI 81 + 기믹 56 + 입력/충돌 35 + 대화/알림 35 + 하린 71 = **278/278**, 자동 임무 완료 마커 확인.
- 로컬 모델 관련: 새 하린 39 + 기존 지원/취소 통합 5 + 저장 취소 7 + 기믹 11 + 기존 대화 20 = **82/82**. 이 숫자는 추론 호출 수가 아니라 검사 항목 수다. 명령 영수증은 common_executor로 구분한다.
- `dialogue_examples.json`은 최종 새 하린 실행의 실제 표시 준비 대사/명령 영수증이다. 모델 원문·프롬프트·요청/시도 ID·오류/취소는 raw의 npc_sessions.jsonl/npc_events.jsonl에 있다.
- `source_manifest.json`의 게임 소스/검증 스크립트 SHA-256은 격리 검증 복사본과 일치한다. 문서와 엔진 생성 UID는 별도 표시한다.
- `raw/harin_upgrade/pose_*.png`는 숨김 Godot GPU가 만든 실제 화면이다. 이동/조준/경계/지원/장전/다운 상태를 육안으로 확인했다.

raw는 개발 도중 실패한 대화·파서 검사·프롬프트 진단도 보존한다. 오래된 개발 결과의 passed=false를 최종 통과로 바꾸지 않았다. 최종 결과는 summary.json에 명시된 파일을 기준으로 읽는다. 초기 모델 적재는 raw/model_warmup.json과 분리했다.

임무 완료는 자동 준비/입력을 포함하며 사람 플레이가 아니다. 실제 Microsoft IME·청취·LAN·export·일반적인 대사 자연스러움과 정식 성능 비교는 증명하지 않는다. 자세한 변경과 한계는 review/HARIN_UPGRADE_20261108.md를 따른다.

새 GPU 테스트 하네스 종료 때 ObjectDB/리소스 잔존 경고가 있었다. 원문을 raw/harin_render_stderr.log에 보존했다. 일반 메인 씬의 별도 헤드리스 종료 검사(raw/exit_resource_probe.log)는 종료 코드 0이고 해당 경고가 없었다. 장시간 자원 안정성을 검증한 결과로 확대하지 않는다.
