# 패널 비프음

`panel_beep.wav`는 이 프로젝트를 위해 직접 합성한 880Hz 단음이다. 22,050Hz / mono / PCM 16-bit / 약 75ms이며 시작과 끝에 짧은 음량 경사를 둔다. 외부 음원 샘플은 사용하지 않았다.

재생성: 저장소 루트에서 `scripts/generate_panel_beep.ps1` 실행.

보관함은 1초 유지 성공 후 이 파일을 `0, 0.12, 0.36, 0.48, 0.72, 0.84`초에 재생해 세 쌍의 비프음을 만든다. 다른 임시 효과음 출처는 `game/assets/temporary/kenney/README.md`를 따른다.
