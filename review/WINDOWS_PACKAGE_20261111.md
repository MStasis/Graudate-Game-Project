# Windows x64 배포 검증 (2026-11-11)

`build/ContainmentDemo-Windows-x64.zip` (40,800,850바이트)을 압축 해제한 뒤 `ContainmentDemo/ContainmentDemo.exe`를 실행한다. 같은 폴더의 PCK와 한글 입력 DLL을 함께 옮긴다. 규칙 기반 모드가 기본이다. 사용법과 라이선스 고지를 ZIP에 동봉했다.

SHA-256 `880a6979f013948c8ee0400c97978056aadf44c5019d35f01ac291d8acd077dd`

`scripts/package_windows.ps1 -TemplatesArchive <공식 4.7.2 템플릿 TPZ 경로>`로 다시 빌드할 수 있다. 스크립트는 공식 TPZ의 해시를 확인하고 격리된 복사본에서 릴리스 EXE와 PCK를 내보낸다. 배포 EXE는 `user://`에 진단을 기록하고 PCK의 SHA-256을 실행 기록에 남긴다. [Godot 4.7.2 공식 릴리스](https://github.com/godotengine/godot/releases/tag/4.7.2-stable).

- 같은 PC에서 ZIP을 공백과 한글이 포함된 새 경로에 풀었다. Windows 시스템 경로만 지정한 상태로 헤드리스 기본 실행과 숨김 GPU 튜토리얼 시연이 각각 종료 코드 0으로 완료됐다.
- 실제 배포 EXE에서 기본 RuleBased 시작, 사용자 데이터 폴더에 기록 생성, PCK 해시 일치, 한글 입력 DLL의 창 연결을 확인했다. 1280×800 GPU 캡처를 확인했다. 시연은 전력 복구와 연구동 진입까지 자동으로 진행했다.
- 새로 가져온 빌드 소스의 봉쇄 통합 114/114, IME DLL 적재 6/6, 합성 채팅 입력 11/11이 통과했다. 실제 다른 PC, 사람 완주, 실제 Microsoft IME 조합·청취는 이번에 직접 확인하지 못했다.

로그, 검사 JSON, 화면은 [배포 검증 기록](../evidence/windows_package_20261111/)에 있다. 이전 봉쇄 검증과 실모델 표현 검사 결과는 [봉쇄 데모 보고서](CONTAINMENT_DEMO_20261110.md)를 참조한다.
