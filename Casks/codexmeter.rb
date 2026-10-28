cask "codexmeter" do
  version "0.3.4"
  sha256 "3306bafab11627ed0b2f6f9a28844440e505e2e3a64cd0182f4c7b073b712c76"

  url "https://raw.githubusercontent.com/spider-man-peter-park/CodexMeter/c98c0e17672c6dec2642116361ffdf54b726269f/dist/CodexMeter-macOS-arm64.zip"
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
