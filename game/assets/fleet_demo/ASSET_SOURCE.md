# 개척선 데모 에셋

- 출처는 프로젝트 사용자가 제공한 `graduate_fleet_map_godot.zip`이다. ZIP SHA-256은 `A8F502BBCFEE0D4F353481C289FEC12A369D2DFF58E9D58DE97FB5EE790F89FB`다.
- `rooms/`의 씬은 텍스처 경로를 이 폴더로 바꿨다. `art/`에서 씬이 참조하는 PNG와 소품 애니메이션을 가져왔고, `layout/`에서 방 배치·소품 애니메이션 데이터를 가져왔다. 캐릭터, 사격과 효과음은 본편 리소스를 사용한다.
- 첨부의 별도 폰트 라이선스는 해당 폰트에 적용된다. 가져온 맵 스프라이트의 별도 라이선스 표기는 ZIP에 포함되어 있지 않다.
- 단독 퓨즈는 `fuse_breaker_door_animation.png`의 완전히 열린 정상·고장 상태에서 퓨즈 부분을 잘라 쓰는 AtlasTexture다.
- `art/breaker_lowered.svg`와 `art/eroded_breaker_lowered.svg`는 레버를 당긴 상태를 표시하기 위해 이 프로젝트에서 새로 그린 스프라이트다.
- 문 목표 화살표는 `art_import/ui/door_objective_arrow/`에서, 치료 장비 PNG와 프레임 JSON은 `art_import/devices/mika_healer/`에서 가져왔다. 두 묶음에 별도 이용 조건 문서는 없다.
- 보급함·탄약·탄창 픽셀 아트는 `art_import/devices/ammo_crate/`에, 상호작용 키는 `art_import/ui/interact_key/`에 있다. 모두 이 프로젝트용으로 제작했다.
- `game/assets/audio/fleet_warning_wail.wav`는 개척선용 합성 경보음이다. 합성 사양과 실제 경보 패턴 참고 자료는 [원본 폴더](../../../art_import/audio/fleet_siren/)에 있다.
