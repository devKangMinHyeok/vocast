# 배포 (서명 없이 — curl · Homebrew)

우리 제품은 전통적 `.app`이 아니라 **스크립트가 띄우는 로컬 웹서버**다.
그래서 **브라우저 다운로드 대신 curl/Homebrew로 배포**하면 macOS의
quarantine 딱지가 붙지 않아 **코드 서명·공증 없이도 Gatekeeper 경고 없이
실행**된다. (검증: 설치 후 번들에 `com.apple.quarantine` 없음 → 실행 차단 안 됨)

## 두 가지 설치 경로

### 1) curl 한 줄

```bash
curl -fsSL https://raw.githubusercontent.com/devKangMinHyeok/vocast/main/scripts/install.sh | bash
```

`scripts/install.sh`가: 플랫폼 확인(arm64 macOS) → 번들 tar.gz 다운로드 →
sha256 검증 → `~/Applications/Vocast`에 설치 → `~/.local/bin/vocast`
심링크 → 방어적 quarantine 제거. 이후 `vocast`로 실행.

환경변수로 소스/위치 조정: `NC_URL`, `NC_SHA256`, `NC_PREFIX`, `NC_BIN`, `NC_RELEASE`.

### 2) Homebrew cask

별도 탭(`devKangMinHyeok/homebrew-tap`)에 `packaging/homebrew/Casks/vocast.rb`
를 두면:

```bash
brew install --cask devKangMinHyeok/tap/vocast
```

Homebrew도 curl로 받으므로 서명 불필요. 앱은 `~/Applications`에 스테이징되고
`vocast` CLI가 PATH에 심링크된다.

## 릴리스 만들기

```bash
bash scripts/make_release.sh [--with-models] [VERSION]
```

번들 빌드 → `dist/release/Vocast-macos-arm64.tar.gz` → **sha256 출력**.
이 값을 install.sh의 `NC_SHA256`와 cask의 `sha256`/`url`에 채운다.

### ⚠️ 호스팅: GitHub Releases 2GB 제한

우리 번들은 **3.7GB(모델 없음)~11GB(--with-models)**라 GitHub Releases의
**파일당 2GB 제한**을 넘는다. 두 방법 중 택1:

| 방법 | 방식 |
|---|---|
| **오브젝트 스토리지 (권장)** | Cloudflare R2 / Backblaze B2 / S3에 tar.gz 업로드 → 그 URL을 `NC_URL`·cask `url`로. R2는 이그레스(다운로드 대역폭) 무료라 대용량 배포에 유리 |
| **분할** | `split -b 1900m`로 2GB 미만 파트로 나눠 GitHub Releases에 올리고 install.sh가 재조립 |

모델 미포함(3.7GB)이라도 2GB를 넘으므로, 온라인-첫실행 빌드도 외부 호스팅이
필요하다. 완전 오프라인(11GB)은 더더욱.

## 검증 완료

- install.sh: 다운로드·sha256 검증·설치·심링크·PATH 안내 (로컬 file:// 로 실측)
- `vocast` CLI: 심링크가 어느 위치에서든 번들 런처를 정확히 실행,
  인자 전달, 경로 독립 (실측)
- quarantine 미부착 → Gatekeeper 통과 (실측)
- cask Ruby 문법 검사 통과

## 남은 것

- 실제 릴리스 아티팩트 빌드 + 호스팅(R2/B2) 후 url·sha256 채우기
- 서명·공증은 선택 — 나중에 매끈한 브라우저 다운로드(.dmg)까지 원하면 $99
  Apple Developer 계정으로 추가 (curl/Homebrew 경로에는 불필요)

Windows 배포는 [CROSS-PLATFORM.md](CROSS-PLATFORM.md) 참고.
