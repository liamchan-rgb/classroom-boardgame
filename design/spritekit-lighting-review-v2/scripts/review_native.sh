#!/bin/bash
set -euo pipefail
prototype_root="$(cd "$(dirname "$0")/.." && pwd)"
prototype_results="${PROTOTYPE_REVIEW_OUTPUT_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/spritekit-review.XXXXXX")}"
export PROTOTYPE_REVIEW_OUTPUT_DIR="$prototype_results"
mkdir -p "$prototype_results"
prototype_stage="${1:-all}"
if [ "$prototype_stage" = all ]; then
  for prototype_phase in prepare build test export video; do bash "$0" "$prototype_phase"; done
  exit 0
fi
if [ "$prototype_stage" = prepare ]; then
  prototype_build_dir="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/spritekit-build.XXXXXX")"
  xcodebuild -version > "$prototype_results/xcode-version.txt"
  xcrun simctl list devices available --json > "$prototype_results/simulators.json"
  python3 - "$prototype_results/simulators.json" "$prototype_results/device.json" "$prototype_results/state.json" "$prototype_build_dir" <<'PY'
import json,re,sys
data=json.load(open(sys.argv[1]));choices=[]
for runtime,devices in data['devices'].items():
    match=re.search(r'SimRuntime\.iOS-(\d+)-(\d+)',runtime)
    if not match or tuple(map(int,match.groups()))<(17,0): continue
    version=tuple(map(int,match.groups()))
    for device in devices:
        if device.get('isAvailable') and device['name'].startswith('iPad'):
            choices.append((version==(27,0),version,'13-inch' in device['name'] or '12.9' in device['name'],device['name'],runtime,device))
if not choices: raise SystemExit('No compatible iPad simulator installed')
*_,runtime,device=max(choices,key=lambda row:row[:4])
json.dump(dict(runtime=runtime,device=device),open(sys.argv[2],'w'),indent=2)
json.dump(dict(udid=device['udid'],buildDir=sys.argv[4]),open(sys.argv[3],'w'),indent=2)
PY
fi
if [ "$prototype_stage" = export ]; then
  if [ -d "$prototype_results/NativeTests.xcresult" ]; then
    xcrun xcresulttool export attachments --path "$prototype_results/NativeTests.xcresult" \
      --output-path "$prototype_results/attachments" \
      2>&1 | tee "$prototype_results/attachments-export.log"
  else
    echo 'No native test result bundle produced; existing build logs remain available.'
  fi
  exit 0
fi
prototype_udid="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["udid"])' "$prototype_results/state.json")"
prototype_build_dir="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["buildDir"])' "$prototype_results/state.json")"
case "$prototype_stage" in
  prepare)
    xcrun simctl boot "$prototype_udid" > "$prototype_results/simulator-boot.log" 2>&1 || true
    xcrun simctl bootstatus "$prototype_udid" -b 2>&1 | tee -a "$prototype_results/simulator-boot.log"
    ;;
  build)
    xcodebuild build-for-testing -project "$prototype_root/Native/GrassLightingPrototype.xcodeproj" \
      -scheme GrassLightingPrototype -destination "platform=iOS Simulator,id=$prototype_udid" \
      -derivedDataPath "$prototype_build_dir" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
      2>&1 | tee "$prototype_results/build.log"
    ;;
  test)
    xcodebuild test-without-building -project "$prototype_root/Native/GrassLightingPrototype.xcodeproj" \
      -scheme GrassLightingPrototype -destination "platform=iOS Simulator,id=$prototype_udid" \
      -parallel-testing-enabled NO -derivedDataPath "$prototype_build_dir" \
      -collect-test-diagnostics never -test-timeouts-enabled YES \
      -default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 90 \
      -resultBundlePath "$prototype_results/NativeTests.xcresult" \
      CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
      2>&1 | tee "$prototype_results/test.log"
    ;;
  video)
    python3 "$prototype_root/scripts/record_replay.py" "$prototype_results" "$prototype_udid" "$prototype_build_dir"
    ;;
  *) echo "Unknown review stage: $prototype_stage" >&2; exit 2 ;;
esac
