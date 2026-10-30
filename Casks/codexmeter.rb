cask "codexmeter" do
  version "0.4.1"
  sha256 "8712690936304c388d601013284fde3d89dd6fecb052207d2281d419e429796f"

  url "https://raw.githubusercontent.com/spider-man-peter-park/CodexMeter/de01e8370c0a25a566dac4d33a4a90625b40511f/dist/CodexMeter-#{version}-macOS-arm64.zip"
  name "CodexMeter"
  desc "Codex Desktop quota, token usage and response speed in the menu bar"
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
