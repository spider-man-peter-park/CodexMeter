cask "codexmeter" do
  version "0.6.0"
  sha256 "b87594548c6b5f99a5ca58aef66c71376bbef94773f571e2669bbf83c269a47e"

  url "https://raw.githubusercontent.com/spider-man-peter-park/CodexMeter/db42d54741d4abfc81ab3c098b800b2f7d479889/dist/CodexMeter-#{version}-macOS-arm64.zip"
  name "CodexMeter"
  desc "AI assistant usage and system monitoring in the menu bar"
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
