# 임시 무료 에셋 — Kenney

2026-11-06 Kenney 공식 에셋 페이지에서 무료 다운로드 후 ZIP과 포함 라이선스를 확인했다. 사용한 PNG/OGG만 원본 그대로 복사했으며 실행 코드나 설치 프로그램은 받지 않았다.

| 팩 | 공식 배포 페이지 | 적용 |
|---|---|---|
| Top-down Shooter | https://kenney.nl/assets/top-down-shooter | 플레이어 `soldier1_gun.png`, 하린 `womanGreen_gun.png`, 적 `robot1_machine.png`, 바닥 `tile_11.png` |
| Sci-fi Sounds | https://kenney.nl/assets/sci-fi-sounds | 플레이어/NPC 사격, 피해, 적 격파, 구역 이동, 임무 완료 |

두 팩의 포함 라이선스는 **CC0-1.0**이다. 원문을 `licenses/`에 보존했다. 프로젝트 크레딧: **Game assets by Kenney (www.kenney.nl), CC0**. 별도 UI 초상화의 출처는 기존 `game/assets/ui/ASSET_SOURCE.md`, `HARIN_BUST_SOURCE.md`를 따른다.

- `manifest.json`: 공식 출처, 취득일, 원본 ZIP SHA-256, 사용 파일 SHA-256.
- 원본 ZIP: 개발 PC의 Git 제외 경로 `runtime/coop_stage_20261106/downloads/`. 프로젝트에는 선택한 파일만 포함한다.
- `Player.tscn`, `NPC.tscn`, `Drone.tscn`, `World.tscn`에서 연결한다. 기존 SVG는 보존했다.
- `temporary_actor_aim.gd`는 그림만 회전한다. 충돌 크기·이동 속도·총 피해·자원 규칙은 변경하지 않는다.
- `mission_audio.gd`는 공통 월드 상태·이벤트를 듣고 최대 6개 소리를 재생한다. 전체 음량은 각 voice의 `volume_db=-20`으로 시작한다.
- 최종 아트와 애니메이션은 후속 작업이다. 현재 적의 그림은 로봇이며 공격은 기존 접촉 피해 규칙을 사용한다.

Kenney의 현재 페이지는 무료 다운로드 버튼에서 새 링크를 발급한다. 예전 고정 ZIP URL은 HTML로 리다이렉트되어 그대로 재사용하지 않았다. 공개 페이지의 무료 다운로드 경로로 받은 실제 ZIP을 검증했다.
