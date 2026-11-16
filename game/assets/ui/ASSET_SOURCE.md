# 하린 통신 UI 에셋

- harin_canva.png: Canva 연결 플러그인 이미지 생성 결과. 미디어 ID MAHZCKfYM1s, 2026-10-26. 도구가 반환한 200×200 PNG를 그대로 저장했다. 외부 게임의 캐릭터·스크린샷은 참조하지 않았다.
- Canva: https://www.canva.com/M/MAHZCKfYM1s?utm_source=OC-AaBlKrqBJJNF&utm_campaign=agent_connector_create_image_asset_opened
- 요청: 어두운 SF 인디 게임의 친한 동료 하린. 한국인 성인 여성 정비사, 짧은 어두운 머리, 청록 머리핀, 연구복과 이어피스, 제한된 색상의 픽셀 초상화, 글자 없는 먹색 배경.
- station_mark.svg, reticle.svg: 이 프로젝트 UI를 위해 작성한 단순 벡터 도형.

초상화는 정적인 통신용 이미지다. 이동 캐릭터의 스프라이트·애니메이션은 아니다.

## 격벽 너머 타이틀 에셋

- `title_background.png`는 이 프로젝트의 타이틀을 위해 ChatGPT 이미지 생성으로 만든 일러스트입니다. 원본 시안의 구도와 크기를 사용합니다.
- `bulkhead_mark.svg`는 격벽과 잠금등을 본뜬 신규 아이콘입니다. 같은 원본을 PNG 시동 화면과 Windows 다중 크기 ICO로 변환했습니다.
- `lock_light.gdshader`는 PNG의 잠금등과 주변 반사광을 실시간으로 조절합니다. Inspector의 `cycle_seconds` 기본값은 4초입니다. `preview_phase`는 -1로 두면 반복하고, 0과 0.5로 어두운 상태와 밝은 상태를 비교할 수 있습니다.
- `BarlowCondensed-Black.ttf`은 Jeremy Tribby의 Barlow Condensed Black으로 타이틀 영문에 사용합니다. [Google Fonts 배포 원본](https://github.com/google/fonts/tree/main/ofl/barlowcondensed)과 동일한 파일이며 SIL Open Font License 1.1 원문을 `bulkhead/BarlowCondensed-OFL.txt`에 포함했습니다.
- `IBMPlexSansKR-Medium.ttf`은 IBM Plex Sans KR Medium으로 타이틀 메뉴, 저장 슬롯, 설정의 한글에 사용합니다. [Google Fonts 배포 원본](https://github.com/google/fonts/tree/main/ofl/ibmplexsanskr)과 동일한 파일이며 SIL Open Font License 1.1 원문을 `bulkhead/IBMPlexSansKR-OFL.txt`에 포함했습니다.

## 격벽 너머 인게임 HUD 에셋

- `bulkhead/hud_health.png`는 이 프로젝트를 위해 제작한 투명 배경의 심박 아이콘입니다.
- 장탄 아이콘은 기존 `pulse_pistol.svg`를 사용합니다. 예비 탄창은 기존 `ActorStatus.tscn`과 동일한 `fleet_demo/art/ammo_crate/pulse_magazine.png`의 영역을 사용합니다.
- `BulkheadHUDTheme.tres`는 위의 타이틀 폰트 두 종을 참조합니다. 미니맵은 기존 `ExplorationMap`으로 그립니다.
- `bulkhead/pause_gear.svg`는 일시정지 창을 위해 이 프로젝트에서 작성한 톱니 아이콘입니다.
