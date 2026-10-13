#!/usr/bin/env python3
"""Check generated project drift, source/resource paths and the shared scheme."""
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET


def check(native):
    project = native / "ClassroomProbe.xcodeproj"
    with tempfile.TemporaryDirectory(prefix="classroom-project-check-") as temporary:
        copy = Path(temporary)
        (copy / "tools").mkdir()
        (copy / "ClassroomProbe.xcodeproj").mkdir()
        script = copy / "tools/generate_xcode_project.py"
        shutil.copyfile(native / "tools/generate_xcode_project.py", script)
        subprocess.run([sys.executable, str(script)], check=True)
        for relative in ("project.pbxproj", "xcshareddata/xcschemes/ClassroomProbe.xcscheme"):
            if (project / relative).read_bytes() != (copy / "ClassroomProbe.xcodeproj" / relative).read_bytes():
                raise ValueError(f"Generated configuration drift: {relative}; run native/tools/generate_xcode_project.py")
    content = (project / "project.pbxproj").read_text()
    paths = re.findall(r'"path"\s*=\s*"([^"]+)"', content)
    for name in paths:
        if name in ("ClassroomProbe", "ClassroomProbe.app"):
            continue
        if not (native / "ClassroomProbe" / name).exists():
            raise ValueError(f"Missing source/resource: {name}")
    declared_swift = {name for name in paths if name.endswith(".swift")}
    actual_swift = {p.name for p in (native / "ClassroomProbe").glob("*.swift")}
    if declared_swift != actual_swift:
        raise ValueError(f"App Swift source list differs: {declared_swift ^ actual_swift}")
    for package in re.findall(r'"relativePath"\s*=\s*"([^"]+)"', content):
        if not (native / package / "Package.swift").is_file():
            raise ValueError(f"Missing local Swift package: {package}")
    plistlib.loads((native / "ClassroomProbe/Info.plist").read_bytes())
    scheme = ET.parse(project / "xcshareddata/xcschemes/ClassroomProbe.xcscheme")
    buildable = scheme.find("./BuildAction/BuildActionEntries/BuildActionEntry/BuildableReference")
    if buildable is None or buildable.get("BlueprintName") != "ClassroomProbe":
        raise ValueError("Shared scheme is missing the ClassroomProbe build target")
    print(f"PASS: project and shared scheme match generator; {len(declared_swift)} Swift sources; resources, Info.plist and local packages exist.")


if __name__ == "__main__":
    try:
        check(Path(__file__).resolve().parents[1])
    except (OSError, ValueError, ET.ParseError, plistlib.InvalidFileException, subprocess.CalledProcessError) as error:
        print(f"Configuration validation failed: {error}", file=sys.stderr)
        sys.exit(1)
