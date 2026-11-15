# 게임 스프라이트 원본과 미리보기

`art_import/`에는 전달받은 원본 PNG, 프레임·배치 JSON, 미리보기와 ZIP을 보관합니다. Godot 본편은 `game/` 아래에 있으며, 게임용 사본은 [캐릭터·장비·연구 구역 에셋](../game/assets/fleet_sprites/)과 [개척선 데모 에셋](../game/assets/fleet_demo/)에서 확인할 수 있습니다.

| 위치 | 내용 | 본편 반영 |
| --- | --- | --- |
| [`characters/mika/`](characters/mika/) | 미카 클라비스 4방향 통합 시트와 프레임 설정 | 사용 중 |
| [`characters/rsc07/`](characters/rsc07/) | RSC-07 4방향 통합 시트와 프레임 설정 | 사용 중 |
| [`characters/rift_crew/`](characters/rift_crew/) | 침식된 선원 4방향 통합 시트, 탄착 스파크, 프레임 설정 | 사용 중 |
| [`devices/sentry/`](devices/sentry/) | 지원 드론 부유·스캔·설치와 터렛 연사·레일건 모션 | 사용 중 |
| [`devices/mika_healer/`](devices/mika_healer/) | 설치형 치료 장비 시트 6장, 프레임 JSON, README, 원본 ZIP | 개척선 전투 지원에 사용 |
| [`devices/ammo_crate/`](devices/ammo_crate/) | 상하좌우 보급함 열림 시트, 펄스 권총 탄약과 탄창 | 개척선 보급함과 HUD에 사용 |
| [`environment/fleet_lab/`](environment/fleet_lab/) | 연구 구역 타일·소품·배관, 애니메이션, 방 배치 PNG와 JSON | 일부 사용 중 |
| [`environment/graduate_fleet_map/`](environment/graduate_fleet_map/) | 개척선 전체 맵 이미지, Godot 미리보기 프로젝트, 원본 ZIP | 방 5개와 맵 에셋 반영 |
| [`ui/door_objective_arrow/`](ui/door_objective_arrow/) | 문 안내 화살표 PNG 시트와 문 위에 표시한 GIF 미리보기 | 개척선 목표 문에 PNG 사용 |
| [`ui/interact_key/`](ui/interact_key/) | 상호작용 E 키 4프레임 | 개척선 상호작용 안내에 사용 |
| [`audio/fleet_siren/`](audio/fleet_siren/) | 개척선 침식 경보 WAV와 참고 자료 | 전력 복구 후 경보에 사용 |

## 미리보기와 배치 자료

- 문 안내 화살표는 [PNG 시트](ui/door_objective_arrow/door_objective_arrow.png)와 [GIF 미리보기](ui/door_objective_arrow/door_objective_arrow_preview.gif)를 함께 보관합니다.
- 개척선의 방 배치와 진행 동선은 [전체 맵 이미지](environment/graduate_fleet_map/graduate_fleet_map.png)에서 볼 수 있습니다. [`godot_preview/`](environment/graduate_fleet_map/godot_preview/)에는 ZIP에서 꺼낸 독립 Godot 프로젝트가 있으며, 그 안의 `art/`, `layout/`, `rooms/`를 함께 두면 씬의 원본 경로가 유지됩니다. 본편에 적용한 경로는 [맵 에셋 출처](../game/assets/fleet_demo/ASSET_SOURCE.md)에 기록돼 있습니다.
- 기존 연구 구역의 [`rooms/`](environment/fleet_lab/rooms/)에는 [개인실](environment/fleet_lab/rooms/gunsmith_quarters.png), [비품실](environment/fleet_lab/rooms/supply_room.png), [연구실](environment/fleet_lab/rooms/research_lab.png) 배치 PNG와 같은 이름의 JSON이 있습니다. 이 파일들은 최초 전달본 `graduate_game_sprite_handoff.zip`에서 복원했습니다.

## 스프라이트 설정

미카와 RSC-07의 JSON은 각 PNG에 들어 있던 프레임 정보를 같은 이름의 별도 파일로 꺼낸 것입니다. 침식된 선원, 연구 구역, 지원 드론, 치료 장비의 세부 설정과 사용법은 각 폴더의 JSON과 README에 있습니다.

- 캐릭터 셀은 96×96px이고 발 기준점은 (48, 86)입니다.
- 지원 드론과 터렛의 셀은 128×128px이고 바닥 기준점은 (64, 108)입니다.
- 4방향 행 순서는 아래, 왼쪽, 오른쪽, 위입니다. 좌표의 원점은 셀의 왼쪽 위입니다.
- 픽셀 아트에는 최근접 필터를 적용합니다. 프레임 위치, 지속 시간, 발사 시점과 총구 좌표는 캐릭터·기기별 JSON을 사용합니다.
- 기존 연구 구역 에셋의 파일 경로와 크기, 배치 기준점은 [`assets.json`](environment/fleet_lab/assets.json)에 있습니다. 방 JSON에는 타일, 소품, 출입구 배치가 들어 있습니다.
