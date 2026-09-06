# News Tower 한국어 패치
<img width="616" height="353" alt="image" src="https://github.com/user-attachments/assets/4bf3ee4c-b7e8-4228-b8e8-2c506e7cc718" />


## 설치

1. GitHub Releases에서 `NewsTower_Korean_Patch_v1.0.1.bat`을 내려받습니다.
2. BAT를 `News Tower.exe`가 있는 순정 게임 폴더에 넣고 실행합니다.
3. `1`을 눌러 설치합니다. BAT가 게임 폴더 밖에 있으면 정확한 게임 폴더를 직접 입력합니다.

배포본은 실행 파일 하나에 패치 데이터를 내장한 BAT 형식입니다. 실행 중에만 임시 폴더로 풀고 작업이 끝나면 자동 삭제하므로 사용자가 별도 패치 파일을 관리할 필요가 없습니다.


## 원본 복원

같은 BAT을 다시 실행해 `2`를 선택하면 설치 시 만든 백업으로 원본을 복원합니다.

## 포함 범위

- 게임 로케일 문자열 한국어화: 41개 테이블, 원본 대비 34,746개 값 변경
- 직원 이름: 413칸 한국어 표기
- 메인 화면 현재 고정 문구

정확한 변경 파일과 검증값은 [PATCH_SCOPE.md](PATCH_SCOPE.md) 및 `package/.patch_data/manifest.json`에 기록되어 있습니다.

## 주의

- 게임 업데이트 또는 다른 파일 수정이 감지되면 손상을 막기 위해 설치가 중단됩니다.
- 이 저장소에는 게임 원본 파일이 없으며, 정품 순정 파일에 적용하는 바이너리 델타만 포함합니다.


