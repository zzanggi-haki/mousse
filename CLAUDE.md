# Mousse — 작업 지침

JK(학장기)의 맥 QoL 메뉴바 앱 시리즈 4번째. 화면공유·강의 때 켜두는 커서 도구.
이름은 mouse + 무스 케이크 (Soundwich와 같은 음식 말장난 라인). 답변은 한국어로.

## 로드맵 (상태는 README 표가 정본)

1. ✅ 메뉴바 골격 + 전역 단축키 + 오버레이 + 커서 강조(⌃⌥H) + 위치 찾기(⌃⌥L)
2. ✅ 그리기 모드(⌃⌥A): 모드 안에서 R 사각형 · P 펜, Esc까지 계속 그림, Esc면 그린 것 전부 사라짐. 기본은 그린 뒤 3초 후 페이드. 선·채우기 색·투명도 설정 + 설정창(단축키 변경 포함)
3. 타이핑 표시: 영문·단축키 조합 먼저 → 한글 조합기. 화면 하단 중앙 말풍선, 입력 멈추면 사라짐
4. 돋보기: ScreenCaptureKit, 단축키 누르는 동안만 확대(설정에서 토글 방식 선택 가능)

## 결정 사항

- 스택: Swift + AppKit/SwiftUI + XcodeGen. Soundwich(`../Soundwich`) 구조와 `../Soundwich/docs/DESIGN_SYSTEM.md`를 그대로 따른다.
- 단축키는 ⌃⌥+글자. Magnet 기본키(⌃⌥ 화살표/C/D/E/F/G/T/U/I/J/K/Return)와 겹치지 않게. 현재 ⌃⌥H 강조, ⌃⌥L 찾기, ⌃⌥A 그리기. 예정: ⌃⌥Z 돋보기. 설정창에서 바꿀 수 있고 UserDefaults `mousse.hotkey.<id>`에 저장.
- 설정은 별도 설정창(⚙︎, 툴바 탭)으로. 팝오버에는 도구 on/off·실행 버튼·단축키 표시만 둔다(JK 결정, 디자인 시스템 §7.2의 팝오버 내 전환 대신). 3·4단계 설정은 새 탭으로 추가.
- 그리기 모드는 Mousse를 활성 앱으로 만든다(키 입력·커서 때문, ZoomIt과 같은 방식). 끝날 때 직전 앱을 다시 활성화. Esc는 모드 동안만 Carbon 전역 단축키로 등록 → 포커스를 못 가져와도 빠져나올 수 있고, 평소엔 다른 앱의 Esc를 뺏지 않는다. 모드 안의 R/P는 keyCode로 판별(한글 입력 소스에서도 동작).
- `HotkeyCenter`는 press/release를 모두 전달한다 → 4단계 "누르는 동안" 구현에 사용.
- 오버레이 원칙: 그릴 게 없으면 `orderOut` + 마우스 추적 중단 → 유휴 CPU 0%. 새 효과도 이 원칙을 지킨다.
- 차별점은 한글 조합 표시. KeyCastr는 키 단위 `UCKeyTranslate`라 자모로 찍힌다. JK의 입력 소스는 `com.apple.inputmethod.Korean.2SetKorean`이고 레이아웃은 `com.apple.keylayout.2SetHangul` → 자모 변환은 OS 레이아웃으로 하고 조합 오토마타만 직접 구현.
- 아이콘: 커서를 눕혀 옆에서 본 초코 무스 케이크 조각(끝 왼쪽·꼬리 오른쪽, 글레이즈 흘러내림, 카라멜 배경). `scripts/render_icons.swift`가 정본이고 메뉴바는 22×14pt 템플릿 PDF. 탐색 라운드 렌더는 `docs/icon-candidates/`(gitignore, 로컬 보관).
- 참고 오픈소스: microsoft/ZoomitForMac (MIT, Swift; `LiveCaptureSession.swift`가 돋보기 참고), keycastr/keycastr (BSD).

## 빌드·실행

```bash
./scripts/run_dev.sh      # Debug 빌드 → Apple Development 서명 → ~/Applications/Mousse.app 설치 → 재실행
./scripts/make_icons.sh   # scripts/render_icons.swift 한 곳에서 메뉴바 PDF + 앱 아이콘 생성
```

- 시스템 기본 개발 경로가 Command Line Tools라서 Xcode는 `DEVELOPER_DIR`로 지정한다(스크립트에 들어 있음). `xcode-select`는 바꾸지 않는다.
- Debug는 `ENABLE_DEBUG_DYLIB=NO`가 필요하다. 없으면 재서명 후 `Mousse.debug.dylib` Team ID 불일치로 실행 즉시 종료된다.
- 고정 개발 서명이라 3·4단계의 입력 모니터링·화면 기록 권한이 빌드마다 풀리지 않는다.

## 검증 방법 (완료 전 반드시 실제 화면으로 확인)

JK는 다른 작업(파이널컷 등) 중일 때가 많다 → 마우스·키보드를 건드리지 말고 Debug 전용 트리거와 캡처로 확인한다.

```bash
swift scripts/debug_trigger.swift highlightOn   # highlightOff | find | menuShow | menuHide
screencapture -x -C a.png b.png c.png           # 모니터 3대, 커서 포함
```

- `menuShow`는 팝오버 내용을 모든 창 뒤에 띄운다 → CGWindowList로 Mousse의 layer 0 창 ID를 찾아 `screencapture -x -o -l <id>`로 찍는다. 설정창은 `settingsShow:<탭 0~3>`으로 같은 방식.
- 그리기는 `drawDemo`로 확인한다(입력·포커스를 뺏지 않고 실제 마우스 핸들러에 합성 이벤트를 넣어 그린 뒤 페이드). `drawOn`/`drawOff`는 진짜 모드라 JK 작업 중엔 1~2초 안에 끝낸다. `dump:<파일>`로 isActive·Esc 등록 여부 등을 읽는다.
- 새 기능을 추가하면 `AppModel.installDebugTrigger()`에 명령을 같이 추가한다.
- computer-use 도구는 LSUIElement 앱을 대상으로 잡지 못한다.
- 메뉴바 아이콘이 안 보이는 건 JK의 PAC-MEN-U가 새 아이콘을 화면 밖으로 미는 것이다(버그 아님). macOS 26에서는 상태 아이템 창을 제어 센터가 소유한다.
- 모니터 3대: V28UE(메인, 1920×1080@2x), 내장 Retina(1728×1117), DR1602(1280×800).

## 릴리스

```sh
./scripts/release.sh v1.2.3 --notes-file notes.md
```

DMG 빌드 → GitHub 릴리스 생성 → [Snackbar](https://github.com/zzanggi-haki/snackbar) 사이트 갱신 신호까지 한 번에 한다.
릴리스 노트 첫 문단이 사이트 "최근 업데이트"에 요약으로 실린다. 웹에서 직접 릴리스를 만들면
신호가 안 가니 이 스크립트를 쓴다.

## 커밋

작성자는 로컬 git 설정(zzanggi-haki)을 쓴다. 커밋·푸시는 JK가 요청할 때만 한다.
