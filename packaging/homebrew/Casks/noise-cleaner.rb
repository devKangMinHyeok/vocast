# Homebrew Cask — 노이즈 클리너
#
# 배포법: 별도 탭 리포(예: devKangMinHyeok/homebrew-tap)에 이 파일을 두면
#   brew install --cask devKangMinHyeok/tap/noise-cleaner
# 로 설치된다. Homebrew는 curl로 받으므로 quarantine이 붙지 않아
# 코드 서명·공증 없이도 Gatekeeper 경고 없이 실행된다.
#
# ⚠️ url/sha256은 실제 릴리스 값으로 채울 것 (scripts/make_release.sh가 출력).
#    번들이 2GB를 넘으면 GitHub Releases 대신 R2/B2/S3 URL을 쓴다.
cask "noise-cleaner" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/devKangMinHyeok/denoise-app/releases/download/v#{version}/NoiseCleaner-macos-arm64.tar.gz"
  name "Noise Cleaner"
  desc "크리에이터를 위한 로컬 음성 스튜디오 — 노이즈 제거 + 보이스 클로닝"
  homepage "https://github.com/devKangMinHyeok/denoise-app"

  depends_on arch: :arm64
  depends_on macos: ">= :sonoma"

  # 압축 해제 시 최상위 NoiseCleaner/ 폴더가 나온다. 앱 지원 폴더에 스테이징하고
  # CLI 런처를 PATH에 심링크한다 (전통적 .app 아님 → app 대신 artifact+binary).
  artifact "NoiseCleaner", target: "#{appdir}/NoiseCleaner"
  binary "#{appdir}/NoiseCleaner/bin/noise-cleaner"

  # 사용자 데이터(프로필·작업 기록)는 ~/.noisecleaner에 있어 앱 제거와 무관.
  # 완전 삭제를 원할 때만 지운다.
  zap trash: [
    "~/.noisecleaner",
  ]

  caveats <<~EOS
    실행:  noise-cleaner
      또는 더블클릭:  #{appdir}/NoiseCleaner/노이즈클리너 실행.command
    브라우저에서 http://127.0.0.1:8756 이 열립니다.

    · Apple Silicon(M1 이상) 전용입니다.
    · 모델 미포함 빌드는 최초 실행 시 음성 모델을 내려받습니다(온라인).
    · 프로필·작업 기록은 ~/.noisecleaner 에 저장되어 업데이트해도 유지됩니다.
  EOS
end
