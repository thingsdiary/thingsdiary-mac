#!/bin/bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:-0.0.0}"
build_dir="${BUILD_DIR:-${project_dir}/.build/release}"
derived_data="${build_dir}/DerivedData"
app_path="${derived_data}/Build/Products/Release/thingsdiary.app"
dmg_path="${build_dir}/thingsdiary.dmg"
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/thingsdiary-dmg.XXXXXX")"

if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must contain three numeric components, for example 1.2.3" >&2
  exit 2
fi

cleanup() {
  rm -rf "${staging_dir}"
}
trap cleanup EXIT

mkdir -p "${build_dir}"

xcodebuild \
  -project "${project_dir}/thingsdiary-mac.xcodeproj" \
  -scheme thingsdiary-mac \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "${derived_data}" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  MARKETING_VERSION="${version}" \
  build

# An ad-hoc signature is not a Developer ID signature. It keeps the bundle
# internally consistent, but Gatekeeper will still identify the developer as unknown.
codesign --force --deep --sign - --timestamp=none "${app_path}"

cp -R "${app_path}" "${staging_dir}/thingsdiary.app"
ln -s /Applications "${staging_dir}/Applications"

rm -f "${dmg_path}"
hdiutil create \
  -volname thingsdiary \
  -srcfolder "${staging_dir}" \
  -format UDZO \
  -ov \
  "${dmg_path}"

codesign --verify --deep --strict --verbose=2 "${app_path}"
shasum -a 256 "${dmg_path}"
echo "Created ${dmg_path}"
