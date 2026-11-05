cask "codexmeter" do
  version "0.5.1"
  sha256 "ac4b82c1c5c56f562d8db56b6ea49311b64878d3274ee845b58f09916bcd1e46"

  url "https://raw.githubusercontent.com/spider-man-peter-park/CodexMeter/c77af57cd4f6b43728b922bda39aa916c73934b1/dist/CodexMeter-#{version}-macOS-arm64.zip"
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
