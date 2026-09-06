# 패치 범위

## 콘텐츠

- 로컬라이제이션 StringTable 41개
- 원본 대비 번역 문자열 변경 34,746개
- 번역 대상 중 의도적으로 원문 유지 179개
- 보호 항목 원문 유지 102개
- 직원 이름 413칸: 여성 이름 110, 남성 이름 110, 성씨 193
- 한글 폰트 4종: 각 현대 한글 완성형 11,172자 포함
- 영어 로케일의 표시 이름을 `한국어`로 변경하되 내부 식별자 `en`은 유지
- 온라인 소식 고정 문구와 기존 저장의 영문 직원 이름 표시 변환을 위한 어셈블리 수정

이미지 리소스와 `News Tower` 제호는 변경하지 않았습니다. BepInEx도 포함하지 않습니다.

## 변경 파일

원본 게임 253개 파일 중 다음 6개만 변경됩니다.

1. `News Tower_Data/Managed/NewsTower.dll`
2. `News Tower_Data/StreamingAssets/aa/catalog.json`
3. `News Tower_Data/StreamingAssets/aa/StandaloneWindows64/employees_assets_all_7358c2e7a2d3a41713a98574bf4ae475.bundle`
4. `News Tower_Data/StreamingAssets/aa/StandaloneWindows64/fonts_assets_all_f0fb231c54bba8ba2b9e2497806f8eb5.bundle`
5. `News Tower_Data/StreamingAssets/aa/StandaloneWindows64/localization-locales_assets_all.bundle`
6. `News Tower_Data/StreamingAssets/aa/StandaloneWindows64/localization-string-tables-english(en)_assets_all.bundle`

파일별 순정/패치 SHA-256과 델타 SHA-256은 `package/.patch_data/manifest.json`을 기준으로 합니다.

## 설치 안전장치

- 순정 파일 SHA-256 사전 검사
- 델타 파일 SHA-256 검사
- 임시 폴더에서 패치 결과를 먼저 생성하고 목표 SHA-256 검증
- 덮어쓰기 전 순정 파일 자동 백업
- 설치 중 실패하면 백업으로 자동 롤백
- BAT 메뉴를 통한 원본 복원
