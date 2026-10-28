cask "codexmeter" do
  version "0.3.5"
  sha256 "a97fd9d88d09ade3ed9c3c3a95797283376f2afdafec87d48a532914b95b9cde"

  url "https://raw.githubusercontent.com/spider-man-peter-park/CodexMeter/1e147b4c19c9d34a9d439bb74464cf53856d3688/dist/CodexMeter-#{version}-macOS-arm64.zip"
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
