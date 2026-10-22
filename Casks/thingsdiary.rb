cask "thingsdiary" do
  version :latest
  sha256 :no_check

  url "https://github.com/thingsdiary/thingsdiary-mac/releases/latest/download/thingsdiary.dmg"
  name "ThingsDiary"
  desc "Desktop client for ThingsDiary"
  homepage "https://github.com/thingsdiary/thingsdiary-mac"

  depends_on arch: :arm64
  depends_on macos: :sequoia

  app "thingsdiary.app"

  caveats <<~EOS
    This build has an ad-hoc signature rather than an Apple Developer ID.
    On first launch, macOS may block it. Try opening it once, then go to
    System Settings > Privacy & Security and click Open Anyway.
  EOS
end
