#!/bin/bash
set -euo pipefail
prototype_root="$(cd "$(dirname "$0")/.." && pwd)"
prototype_results="${PROTOTYPE_REVIEW_OUTPUT_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/spritekit-review.XXXXXX")}"
mkdir -p "$prototype_results"
prototype_build_dir="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/spritekit-build.XXXXXX")"
xcodebuild -version > "$prototype_results/xcode-version.txt"
xcrun simctl list devices available --json > "$prototype_results/simulators.json"
prototype_udid="$(python3 - "$prototype_results/simulators.json" "$prototype_results/device.json" <<'PY'
import json,re,sys
data=json.load(open(sys.argv[1])); choices=[]
for runtime, devices in data['devices'].items():
    match=re.search(r'SimRuntime\.iOS-(\d+)-(\d+)', runtime)
    if not match or tuple(map(int,match.groups()))<(17,0): continue
    for device in devices:
        if device.get('isAvailable') and device['name'].startswith('iPad'):
            choices.append((tuple(map(int,match.groups())), '13-inch' in device['name'] or '12.9' in device['name'], device['name'], runtime, device))
if not choices: raise SystemExit('No compatible iPad simulator installed for this iOS17+ sample')
_,_,_,runtime,device=max(choices,key=lambda row:row[:3])
json.dump(dict(runtime=runtime,device=device),open(sys.argv[2],'w'),indent=2)
print(device['udid'])
PY
)"
if xcodebuild test -project "$prototype_root/Native/GrassLightingPrototype.xcodeproj" \
  -scheme GrassLightingPrototype -destination "platform=iOS Simulator,id=$prototype_udid" \
  -parallel-testing-enabled NO -derivedDataPath "$prototype_build_dir" \
  -resultBundlePath "$prototype_results/NativeTests.xcresult" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  2>&1 | tee "$prototype_results/build-test.log"; then
  prototype_test_status=0
else
  prototype_test_status=$?
fi
if [ -d "$prototype_results/NativeTests.xcresult" ]; then
  xcrun xcresulttool export attachments --path "$prototype_results/NativeTests.xcresult" \
    --output-path "$prototype_results/attachments" \
    2>&1 | tee "$prototype_results/attachments-export.log"
fi
if [ "$prototype_test_status" -ne 0 ]; then exit "$prototype_test_status"; fi
prototype_app="$prototype_build_dir/Build/Products/Debug-iphonesimulator/GrassLightingPrototype.app"
prototype_bundle='com.classroomboardgame.design.grasslightingreviewv2'
xcrun simctl bootstatus "$prototype_udid" -b
xcrun simctl install "$prototype_udid" "$prototype_app"
prototype_video_pid=''
cleanup() {
  if [ -n "$prototype_video_pid" ]; then
    kill -INT "$prototype_video_pid" 2>/dev/null || true
    wait "$prototype_video_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT
for prototype_ratio in 16x9 4x3; do
  xcrun simctl io "$prototype_udid" recordVideo --codec=h264 "$prototype_results/replay-$prototype_ratio.mp4" \
    > "$prototype_results/video-$prototype_ratio.log" 2>&1 &
  prototype_video_pid=$!
  SIMCTL_CHILD_PROTOTYPE_RATIO="$prototype_ratio" SIMCTL_CHILD_PROTOTYPE_SOURCE_COMMIT="${GITHUB_SHA:-local}" \
    xcrun simctl launch --terminate-running-process "$prototype_udid" "$prototype_bundle" --review-replay \
    2>&1 | tee "$prototype_results/replay-launch-$prototype_ratio.log"
  sleep 20
  kill -INT "$prototype_video_pid"
  wait "$prototype_video_pid" || test -s "$prototype_results/replay-$prototype_ratio.mp4"
  prototype_video_pid=''
  prototype_data="$(xcrun simctl get_app_container "$prototype_udid" "$prototype_bundle" data)"
  cp "$prototype_data/Documents/review-replay.json" "$prototype_results/replay-$prototype_ratio.json"
  python3 - "$prototype_results/replay-$prototype_ratio.json" <<'PY'
import json,sys
events=json.load(open(sys.argv[1])); assert events[-1]['phase']=='complete',events[-1]
middle=next(e for e in events if e['phase']=='movement-middle'); assert middle['moving'] is True
arrival=next(e for e in events if e['phase']=='arrival'); assert arrival['moving'] is False
assert middle['heroX']!=arrival['heroX']
print('Replay trace verified:',sys.argv[1])
PY
done
echo "Native review artifacts: $prototype_results"
