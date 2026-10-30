cask "codexmeter" do
  version "0.4.0"
  sha256 "dade6ec86a7158a873e5720ca9abe99f80c707e35d2d7ab874ab264e9d552bc4"

  url "https://raw.githubusercontent.com/spider-man-peter-park/CodexMeter/381f5847eb0936a1de632bb4fe895cd039b21eec/dist/CodexMeter-#{version}-macOS-arm64.zip"
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
