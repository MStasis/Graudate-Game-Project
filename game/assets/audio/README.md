# 패널 비프음

`panel_beep.wav`는 이 프로젝트를 위해 직접 합성한 880Hz 단음이다. 22,050Hz / mono / PCM 16-bit / 약 75ms이며 시작과 끝에 짧은 음량 경사를 둔다. 외부 음원 샘플은 사용하지 않았다.

재생성: 저장소 루트에서 `scripts/generate_panel_beep.ps1` 실행.

보관함은 1초 유지 성공 후 이 파일을 `0, 0.12, 0.36, 0.48, 0.72, 0.84`초에 재생해 세 쌍의 비프음을 만든다. 다른 임시 효과음 출처는 `game/assets/temporary/kenney/README.md`를 따른다.

## 소총 효과음

- `rifle_shot.wav`는 The Free Firearm Sound Library의 AR-15 D_24P 실사격 녹음입니다. Ben Jaszczak 외, CC0. OpenSpades Free Assets의 `Sounds/Weapons/SMG/FireStereo.opus`에서 단발의 총구 소리와 잔향 0.52초를 잘라 44.1kHz 모노 PCM으로 변환했습니다. [원본 라이브러리](https://opengameart.org/content/the-free-firearm-sound-library) · [OpenSpades 출처 기록](https://github.com/DeathByDenim/openspades-free-pak/blob/main/License/Credits-pak001-Free.md)
- `rifle_reload.wav`는 qubodup의 Assault Rifle Reload에 기반합니다. 원 녹음은 serøutōnin이며 CC0입니다. 공개 고음질 프리뷰에서 탄창과 장전 손잡이 소리를 이어 붙이고 재장전 시간 0.95초에 맞춰 조정했습니다. [Freesound 원본](https://freesound.org/people/qubodup/sounds/815879/)

## 회피와 침식 센트리

- `dash_phase.wav`는 피치가 올라갔다 가라앉는 합성 효과음입니다. PCM 44.1kHz 모노이며 기본 회피 무적 시간인 0.22초에 맞췄습니다.
- `rift_sentry_bolt.wav`와 `rift_sentry_laser.wav`는 저음 충격과 반사음을 합성한 포탑 발사 효과음입니다. 각각 0.40초와 0.53초입니다.
- 세 효과음은 이 프로젝트를 위해 만든 원본이며 외부 샘플을 사용하지 않았습니다.
