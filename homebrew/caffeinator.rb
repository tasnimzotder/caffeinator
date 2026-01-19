cask "caffeinator" do
  version "0.0.1-alpha4"
  sha256 :no_check # Update with actual SHA256 after release

  url "https://github.com/tasnimzotder/caffeinator/releases/download/v#{version}/Caffeinator_v#{version}_aarch64.dmg"
  name "Caffeinator"
  desc "Minimal macOS menu bar app to keep your Mac awake"
  homepage "https://github.com/tasnimzotder/caffeinator"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "Caffeinator.app"

  zap trash: [
    "~/Library/LaunchAgents/com.tasnimzotder.caffeinator.plist",
    "~/Library/Preferences/com.tasnimzotder.caffeinator.plist",
  ]
end
