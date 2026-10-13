#!/bin/bash
set -euo pipefail
prototype_root="$(cd "$(dirname "$0")/.." && pwd)"
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "需要安装并选择完整Xcode；本脚本不生成IPA、不修改正式App。" >&2
  exit 2
fi
prototype_results="$(mktemp -d "${TMPDIR:-/tmp}/classroom-spritekit.XXXXXX")"
if [ -n "${PROTOTYPE_DESTINATION:-}" ]; then
  prototype_destination="$PROTOTYPE_DESTINATION"
else
  xcrun simctl list devices available --json > "$prototype_results/simulators.json"
  prototype_udid="$(python3 - "$prototype_results/simulators.json" <<'PY'
import json,sys
data=json.load(open(sys.argv[1]));devices=[d for group in data['devices'].values() for d in group if d.get('isAvailable') and d['name'].startswith('iPad')]
if not devices:raise SystemExit('未安装iPad模拟器；请在Xcode下载iOS Simulator运行时。')
print(devices[0]['udid'])
PY
)"
  prototype_destination="platform=iOS Simulator,id=$prototype_udid"
fi
xcodebuild -version > "$prototype_results/xcode-version.txt"
xcodebuild test -project "$prototype_root/Native/GrassLightingPrototype.xcodeproj" \
  -scheme GrassLightingPrototype -destination "$prototype_destination" \
  -derivedDataPath "$prototype_results/DerivedData" -resultBundlePath "$prototype_results/NativeTests.xcresult" \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$prototype_results/build-test.log"
if xcrun xcresulttool export attachments --path "$prototype_results/NativeTests.xcresult" --output-path "$prototype_results/attachments"; then
  echo "截图附件：$prototype_results/attachments"
else
  echo "请在Xcode打开NativeTests.xcresult手动导出截图；构建/测试日志已保留。" >&2
fi
echo "原生验证结果：$prototype_results"
