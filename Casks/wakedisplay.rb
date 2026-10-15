# Homebrew Cask for WakeDisplay. Version and sha256 are updated automatically by the release workflow.
#   brew tap jasonhuzhensheng/wakedisplay https://github.com/jasonhuzhensheng/WakeDisplay
#   brew install --cask wakedisplay
cask "wakedisplay" do
  version "1.15"
  sha256 "565c5d6886d36e42da09b69b482bdaa79ed04438ec57338e02b546d20cae94fa"

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
