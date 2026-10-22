# ThingsDiary for macOS

Native macOS client for ThingsDiary.

## Install with Homebrew

Add the [ThingsDiary tap](https://github.com/thingsdiary/homebrew-tap), then
install the cask:

```sh
brew tap thingsdiary/tap
brew install --cask thingsdiary/tap/thingsdiary
```

The current build does not have an Apple Developer ID signature. On first
launch, macOS may block it. Try opening `thingsdiary` once, then open
System Settings > Privacy & Security and click **Open Anyway**. Only do this
for a build you trust.

Uninstall it with:

```sh
brew uninstall --cask thingsdiary
```

## Build

Build a debug app:

```sh
make build
```

Build a Release DMG for Apple Silicon:

```sh
make dmg VERSION=1.0.0
```

The result is `.build/release/thingsdiary.dmg`. The script applies an ad-hoc
signature. This is enough to keep the app bundle internally consistent, but it
does not identify the developer and does not satisfy Gatekeeper.

## Publish a release

Push a semantic version tag. GitHub Actions builds the DMG and attaches it to
the corresponding GitHub release:

```sh
git tag v1.0.0
git push origin v1.0.0
```

The Homebrew tap downloads `thingsdiary.dmg` from the latest GitHub release.
It uses `version :latest`, so Homebrew cannot compare releases automatically.
Reinstall the cask to fetch a newer build:

```sh
brew reinstall --cask thingsdiary
```

For normal one-click launches on other Macs, join the Apple Developer Program,
sign the app with a `Developer ID Application` certificate, enable Hardened
Runtime, and notarize the DMG. The ad-hoc signing step can then be replaced by
Developer ID signing and `notarytool` submission.
