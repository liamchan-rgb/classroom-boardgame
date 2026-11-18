#!/usr/bin/env bash
# Local equivalent of .github/workflows/visual-refactor-classroom-ipa.yml (plus a simulator run).
#
# Usage:
#   scripts/local-build.sh            # test + ipa + sim
#   scripts/local-build.sh test       # validators, tool unit tests, ProbeCore/GameCore swift tests
#   scripts/local-build.sh ipa        # unsigned Release archive -> artifacts/*.ipa (for SideStore)
#   scripts/local-build.sh sim        # Debug build, install and launch on an iPad simulator, screenshot
#   scripts/local-build.sh mac        # Mac Catalyst Release app -> artifacts/ClassroomProbe.app, then open it
#   scripts/local-build.sh test ipa   # any combination, run in the order given
#
# Environment:
#   SIM_DEVICE="iPad Pro 13-inch (M5)"   simulator name or UDID (default: first available iPad)
#
# Logs and outputs go to artifacts/ (git-ignored). Nothing is published or pushed.
# `mac` is not part of the default run; ask for it explicitly.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
mkdir -p artifacts
project=native/ClassroomProbe.xcodeproj
scheme=ClassroomProbe
bundle_id=org.personal.classroom.stage0
packages_dir="$root/native/build/packages"

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }

# run_logged <log name> <command...>: full output to artifacts/<log>, errors shown on failure.
run_logged() {
  local log="artifacts/$1"; shift
  local start=$SECONDS status=0
  "$@" > "$log" 2>&1 || status=$?
  if (( status != 0 )); then
    printf '\033[1;31m✗ failed (exit %d) — %s\033[0m\n' "$status" "$log"
    grep -E "^error:|: error:|fatal error|FAIL|Traceback|\*\* .* FAILED" "$log" | grep -v "serialized diagnostics" | sort -u | head -40 || true
    echo "--- last lines of $log ---"; tail -20 "$log"
    exit "$status"
  fi
  ok "$(basename "$log") ($((SECONDS - start))s)"
}

select_xcode() {
  [[ -n "${_xcode_selected:-}" ]] && return
  step "Selecting Xcode"
  run_logged xcode-selection.log python3 native/tools/select_ci_xcode.py
  DEVELOPER_DIR="$(sed -n 's/^Selected DEVELOPER_DIR=//p' artifacts/xcode-selection.log)"
  export DEVELOPER_DIR
  echo "$(xcodebuild -version | head -1) at $DEVELOPER_DIR"
  _xcode_selected=1
}

# The app has .metal shaders; Xcode 26+ ships the Metal toolchain as a separate download.
require_metal() {
  if xcodebuild -showComponent MetalToolchain 2>/dev/null | grep -q "Status: uninstalled"; then
    printf '\033[1;31m✗ Metal Toolchain is not installed (needed for the .metal shaders).\033[0m\n'
    echo "  Install once with:  xcodebuild -downloadComponent MetalToolchain"
    exit 1
  fi
}

do_test() {
  select_xcode
  step "Validating project configuration"
  run_logged configuration.log python3 native/tools/validate_xcode_project.py
  run_logged custom-appearance.log python3 native/tools/check_custom_appearance.py
  run_logged configuration-tests.log python3 -m unittest discover -s native/tools/tests
  step "Swift tests"
  run_logged core-tests.log swift test --package-path native/Packages/ProbeCore
  run_logged game-core-tests.log swift test --package-path native/Packages/GameCore
  for log in core-tests game-core-tests; do
    printf '%s: %s\n' "$log" "$(grep -E "Executed [0-9]+ tests" "artifacts/$log.log" | tail -1 | sed 's/^[[:space:]]*//')"
  done
}

resolve_packages() {
  run_logged dependencies.log xcodebuild -resolvePackageDependencies \
    -project "$project" -scheme "$scheme" -clonedSourcePackagesDirPath "$packages_dir"
}

do_ipa() {
  select_xcode
  require_metal
  step "Archiving unsigned Release build"
  resolve_packages
  rm -rf native/build/ClassroomProbe.xcarchive
  run_logged xcode-build.log xcodebuild -project "$project" -scheme "$scheme" \
    -configuration Release -destination 'generic/platform=iOS' \
    -derivedDataPath native/build -clonedSourcePackagesDirPath "$packages_dir" \
    -archivePath native/build/ClassroomProbe.xcarchive \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO archive
  local app=native/build/ClassroomProbe.xcarchive/Products/Applications/ClassroomProbe.app
  test -d "$app"
  test "$(lipo -archs "$app/ClassroomProbe")" = arm64

  step "Packaging IPA"
  local version build short ipa
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Info.plist")"
  build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Info.plist")"
  short="$(git rev-parse --short=8 HEAD)"
  git diff --quiet HEAD -- native || short="$short-dirty"
  echo "version=$version build=$build" | tee artifacts/version.txt
  rm -f artifacts/*.ipa
  ipa="artifacts/ClassroomStage2-v$version-$short-unsigned.ipa"
  run_logged package.log python3 native/tools/package_ipa.py "$app" "$ipa"
  shasum -a 256 "$ipa" | tee artifacts/ipa.sha256
  ok "IPA: $root/$ipa"
}

pick_simulator() {
  if [[ -n "${SIM_DEVICE:-}" ]]; then
    xcrun simctl list devices available -j | python3 -c '
import json, sys
want = sys.argv[1]
for runtime in json.load(sys.stdin)["devices"].values():
    for d in runtime:
        if want in (d["name"], d["udid"]):
            print(d["udid"]); sys.exit()
sys.exit(f"No available simulator named {want!r}")' "$SIM_DEVICE"
  else
    xcrun simctl list devices available -j | python3 -c '
import json, sys
ipads = [d for r in json.load(sys.stdin)["devices"].values() for d in r if "iPad" in d["name"]]
if not ipads: sys.exit("No iPad simulator available; add one in Xcode > Settings > Components")
booted = [d for d in ipads if d["state"] == "Booted"]
print((booted or ipads)[0]["udid"])'
  fi
}

do_sim() {
  select_xcode
  require_metal
  step "Building for iPad simulator"
  local device
  device="$(pick_simulator)"
  echo "Simulator: $(xcrun simctl list devices | grep "$device" | sed 's/^ *//')"
  xcrun simctl boot "$device" 2>/dev/null || true
  open "$DEVELOPER_DIR/Applications/Simulator.app" --args -CurrentDeviceUDID "$device" 2>/dev/null \
    || echo "(Simulator window not opened; the app still runs headless)"
  resolve_packages
  run_logged simulator-build.log xcodebuild -project "$project" -scheme "$scheme" \
    -configuration Debug -destination "id=$device" \
    -derivedDataPath native/simulator-build -clonedSourcePackagesDirPath "$packages_dir" \
    ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

  step "Installing and launching"
  xcrun simctl bootstatus "$device" -b > /dev/null
  xcrun simctl install "$device" native/simulator-build/Build/Products/Debug-iphonesimulator/ClassroomProbe.app
  xcrun simctl terminate "$device" "$bundle_id" 2>/dev/null || true
  xcrun simctl launch "$device" "$bundle_id"
  sleep 5
  xcrun simctl io "$device" screenshot artifacts/simulator-launch.png > /dev/null 2>&1
  ok "Running in Simulator; screenshot: $root/artifacts/simulator-launch.png"
}

do_mac() {
  select_xcode
  require_metal
  step "Building Mac Catalyst app"
  resolve_packages
  run_logged mac-build.log xcodebuild -project "$project" -scheme "$scheme" \
    -configuration Release -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' \
    -derivedDataPath native/catalyst-build -clonedSourcePackagesDirPath "$packages_dir" build
  local app=native/catalyst-build/Build/Products/Release-maccatalyst/ClassroomProbe.app
  test -d "$app"
  osascript -e 'tell application id "org.personal.classroom.stage0" to quit' 2>/dev/null || true
  rm -rf artifacts/ClassroomProbe.app
  ditto "$app" artifacts/ClassroomProbe.app
  codesign --verify artifacts/ClassroomProbe.app
  open artifacts/ClassroomProbe.app
  ok "Mac app: $root/artifacts/ClassroomProbe.app (opened; use 公开窗口 for the student screen)"
}

steps=("$@")
(( ${#steps[@]} )) || steps=(test ipa sim)
for s in "${steps[@]}"; do
  case "$s" in
    test|ipa|sim|mac) "do_$s" ;;
    all) do_test; do_ipa; do_sim ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "Unknown step: $s (use test, ipa, sim, mac or all)" >&2; exit 2 ;;
  esac
done
printf '\n\033[1;32mDone in %ss.\033[0m Logs: %s/artifacts\n' "$SECONDS" "$root"
