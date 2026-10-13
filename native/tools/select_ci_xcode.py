#!/usr/bin/env python3
"""Select an installed Xcode supporting the project's unchanged iOS minimum."""
import argparse
import glob
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def version(value):
    if not re.fullmatch(r"\d+(?:\.\d+)*", value):
        raise ValueError(f"Invalid SDK version: {value!r}")
    parts = tuple(map(int, value.split(".")))
    return parts + (0,) * max(0, 3 - len(parts))


def minimum_ios(project):
    values = set(re.findall(r'"?IPHONEOS_DEPLOYMENT_TARGET"?\s*=\s*"?(\d+(?:\.\d+)*)',
                            (project / "project.pbxproj").read_text()))
    if len(values) != 1:
        raise ValueError(f"Expected one consistent project iOS minimum, found {sorted(values)}")
    return values.pop()


def query(command, developer):
    env = dict(os.environ, DEVELOPER_DIR=developer)
    result = subprocess.run(command, env=env, text=True, capture_output=True, timeout=45)
    if result.returncode:
        raise ValueError((result.stderr or result.stdout).strip())
    return result.stdout.strip()


def select(project):
    minimum = minimum_ios(project)
    print(f"Project minimum iOS: {minimum}", flush=True)
    candidates = set(glob.glob("/Applications/Xcode*.app/Contents/Developer"))
    inherited = os.environ.get("DEVELOPER_DIR")
    if inherited:
        candidates.add(inherited)
    selected = subprocess.run(["xcode-select", "-p"], text=True, capture_output=True, timeout=15)
    if selected.returncode == 0:
        candidates.add(selected.stdout.strip())
    compatible = []
    for developer in sorted(candidates):
        try:
            xcode = query(["xcodebuild", "-version"], developer)
            device = query(["xcrun", "--sdk", "iphoneos", "--show-sdk-version"], developer)
            simulator = query(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], developer)
            supported = min(version(device), version(simulator)) >= version(minimum)
            print(json.dumps(dict(developer=developer, xcode=xcode, iphoneos=device,
                                  iphonesimulator=simulator, compatible=supported)), flush=True)
            if supported:
                compatible.append((min(version(device), version(simulator)), developer))
        except (ValueError, subprocess.TimeoutExpired) as error:
            print(f"Unavailable candidate {developer}: {error}", flush=True)
    if not compatible:
        raise ValueError(f"Runner has no Xcode with both iOS and simulator SDK >= {minimum}. "
                         "Use a macOS Runner image with that SDK; do not lower deployment target to hide this failure.")
    return max(compatible)[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1] / "ClassroomProbe.xcodeproj")
    parser.add_argument("--github-env", type=Path)
    args = parser.parse_args()
    developer = select(args.project)
    if "\n" in developer or "\r" in developer:
        raise ValueError("Invalid developer directory")
    if args.github_env:
        with args.github_env.open("a") as out:
            out.write(f"DEVELOPER_DIR={developer}\n")
    print(f"Selected DEVELOPER_DIR={developer}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"Xcode selection failed: {error}", file=sys.stderr)
        sys.exit(1)
