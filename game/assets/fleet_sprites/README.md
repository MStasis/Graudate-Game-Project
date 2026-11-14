# 연구 구역 스프라이트

출처는 사용자가 프로젝트에 전달한 `art_import/` 묶음입니다. PNG와 JSON을 같은 상대 경로로 복사해 Godot에서 사용합니다. 방 전체 미리보기는 `art_import/environment/fleet_lab/rooms/`에 있습니다. 게임의 방은 타일과 개별 소품을 배치 데이터로 조립합니다.

묶음에 별도 이용 조건 문서는 포함되어 있지 않습니다.

게임용 `assets.json`의 `collision_rect_px`는 각 소품 PNG 좌상단 기준의 `[x, y, 너비, 높이]`입니다. 바닥에 닿는 부분을 지정하며, 방 배치의 `blocked_tiles`는 어떤 소품에 충돌을 붙일지 판단하는 데 사용합니다.
