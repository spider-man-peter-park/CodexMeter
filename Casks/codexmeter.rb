cask "codexmeter" do
  version "0.5.0"
  sha256 "abc614ad5f67b4d6801c5072561050ce8cf4cffa67262573046c1d311a200482"

  url "https://raw.githubusercontent.com/spider-man-peter-park/CodexMeter/fe0d2294eea8428791206129dd71a0d92cb94f21/dist/CodexMeter-#{version}-macOS-arm64.zip"
  name "CodexMeter"
  desc "Codex Desktop usage and system monitoring in the menu bar"
  homepage "https://github.com/spider-man-peter-park/CodexMeter"

  livecheck do
    skip "Versions and checksums are maintained in this tap"
  end

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "CodexMeter.app"

  uninstall quit: "io.github.codexmeter.app"

  zap trash: [
    "~/Library/Application Support/CodexMeter",
    "~/Library/Preferences/io.github.codexmeter.app.plist",
  ]
end
