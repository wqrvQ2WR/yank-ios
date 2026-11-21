# Yank (iOS)

`yank-android` 의 iOS 판. 유튜브 영상/음원을 앱 하나로 검색하고 내려받는다. SwiftUI, iOS 17+.

안드로이드는 yt-dlp(파이썬)+ffmpeg 바이너리를 앱에 넣어 돌리지만 iOS 는 그럴 수 없어서
**유튜브 내부(InnerTube) API 를 Swift 로 직접 호출**하고, 합치기는 **AVFoundation** 으로 한다.
서버가 필요 없다.

## 구현한 것

| 기능 | 방식 |
|---|---|
| 링크/검색어 입력 | 링크면 바로 대기열, 검색어면 유튜브 검색 결과에서 골라 받기 |
| 화질 | 최고(H.264 최대 1080p) · 1080p · 720p · 음원만 |
| 합치기 | 영상(mp4)+소리(m4a)를 샘플 단위로 옮겨 쓰기(재인코딩 없음, 빠름) |
| 저장 | 파일 앱(나의 iPhone > Yank) 항상 + 사진 앱 선택 |
| 진행 표시 | 용량 · 속도 · 남은 시간 |
| 구독 | 채널 링크/@핸들/영상 링크로 구독, 앱 열 때(1시간마다) 새 영상 자동 대기열. 구독 전 영상은 받지 않음 |
| 언어 | en · ko · ja · es · zh-Hans (안드로이드 strings.xml 에서 생성) |
| 테마 | 밝게(기본) / 시스템 / 어둡게 |

## 안드로이드와 다른 점 (알아둘 제약)

1. **MP3 대신 M4A(AAC).** iOS 에는 mp3 인코더가 없다. 유튜브의 AAC 를 그대로 m4a 로 저장한다.
2. **"최고 화질"은 1080p 까지.** 1440p/4K 는 VP9/AV1 이라 AVFoundation 이 mp4 로 못 합친다.
3. **백그라운드 다운로드 없음.** iOS 는 꺼진/백그라운드 앱을 곧 멈춘다. 받는 동안 앱을 열어 두면 화면이 꺼지지 않게 해 둔다.
   구독 자동 확인도 앱을 열 때만 돈다.
4. **자동 업데이트·엔진 업데이트 없음.** 유튜브가 클라이언트 정책을 바꿔 안 되면
   [YouTube.swift](Yank/Core/YouTube.swift) 의 `ios` / `androidVR` 클라이언트 버전·UA 를 갱신해야 한다(yt-dlp 의 같은 값을 참고).
5. 번들 파이썬이 아니라 직접 구현이라 yt-dlp 가 지원하는 1000여 개 사이트 중 **유튜브만** 된다.
   나이 제한·로그인 필요·일부 라이브 영상은 받지 못한다.
6. 유튜브 약관상 다운로더는 앱스토어에 올릴 수 없다. 사이드로딩(재서명)으로 설치한다.

## 검증 상태

- 맥에서 `./tools/test.sh` 로 **추출 → 조각 다운로드 → 합치기**를 실제 유튜브로 확인함 (검색, 채널, 1080p 합치기 / 720p / m4a, ffprobe 로 길이·코덱 확인).
- `./tools/preview-catalyst.sh` 로 같은 SwiftUI 화면을 맥(Catalyst)에서 띄워 한글 화면·검색·다운로드·대기열을 확인함.
- **진짜 iOS 시뮬레이터/기기에서는 돌려보지 못했다.** 이 맥에 Xcode 가 없다. 깃허브 액션(`.github/workflows/ios.yml`)이
  시뮬레이터 빌드·실행·스크린샷과 서명 안 된 ipa 를 만든다. 사진 앱 저장(권한 창), 파일 앱 노출, 백그라운드 전환은 실기기에서 확인 필요.

## 빌드

Xcode 가 있는 맥에서:

```bash
brew install xcodegen
xcodegen generate
open Yank.xcodeproj
```

Xcode 없이 핵심 로직만:

```bash
./tools/test.sh selftest
./tools/test.sh search "lofi"
./tools/test.sh get https://youtu.be/jNQXAC9IVRw p720      # best | p1080 | p720 | audio
./tools/preview-catalyst.sh                                # 화면 미리보기(맥 앱)
```

문구는 `python3 tools/gen_strings.py` 로 `yank-android` 의 strings.xml + iOS 전용 문구에서 다시 만든다.
기기용 ipa 는 서명이 안 된 채로 나온다. AltStore/Sideloadly 등으로 다시 서명해서 설치한다.
