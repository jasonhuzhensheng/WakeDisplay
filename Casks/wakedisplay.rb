# Homebrew Cask for WakeDisplay. Version and sha256 are updated automatically by the release workflow.
#   brew tap jasonhuzhensheng/wakedisplay https://github.com/jasonhuzhensheng/WakeDisplay
#   brew install --cask wakedisplay
cask "wakedisplay" do
  version "1.28"
  sha256 "537fd09562f2ded0b1f5bc7f4f630cb6db5cabfc80a5b8005860d30c5e50b734"

  url "https://github.com/jasonhuzhensheng/WakeDisplay/releases/download/v#{version}/WakeDisplay-v#{version}.zip"
  name "WakeDisplay"
  desc "Menu-bar utility to wake dark USB-C displays and unlock hidden HiDPI scaling"
  homepage "https://github.com/jasonhuzhensheng/WakeDisplay"

  depends_on macos: ">= :monterey"
  depends_on arch: :arm64
  auto_updates true

  app "WakeDisplay.app"

  # The app is ad-hoc signed (not notarized), so clear the download quarantine flag
  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/WakeDisplay.app"]
  end

  uninstall launchctl: "com.jason.wakedisplay",
            quit:      "com.jason.wakedisplay"

  zap trash: [
    "~/Library/LaunchAgents/com.jason.wakedisplay.plist",
    "~/Library/Preferences/com.jason.wakedisplay.plist",
  ]
end
