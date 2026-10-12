#!/usr/bin/env python3
"""Package an unsigned device .app. Signing happens later in SideStore/AltStore."""
import argparse
import hashlib
import json
import plistlib
import stat
import struct
import zipfile
from pathlib import Path


def package(app, output):
    info = plistlib.loads((app / "Info.plist").read_bytes())
    executable = app / info["CFBundleExecutable"]
    if not executable.is_file() or not (app / "sample.pptx").is_file():
        raise ValueError("The executable or built-in test deck is missing.")
    with executable.open("rb") as binary:
        header = binary.read(8)
    if len(header) != 8 or header[:4] != b"\xcf\xfa\xed\xfe" or struct.unpack("<I", header[4:])[0] != 0x0100000C:
        raise ValueError("The executable must be a compiled 64-bit arm64 Mach-O.")
    if info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
        raise ValueError("Only a device iPhoneOS build can be packaged.")
    if (app / "embedded.mobileprovision").exists():
        raise ValueError("This workflow must package an unsigned app without personal credentials.")
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(app.rglob("*")):
            name = "Payload/" + app.name + "/" + path.relative_to(app).as_posix()
            item = zipfile.ZipInfo(name + "/" if path.is_dir() and not path.is_symlink() else name)
            item.create_system = 3
            item.compress_type = zipfile.ZIP_DEFLATED
            if path.is_symlink():
                item.external_attr = (stat.S_IFLNK | 0o777) << 16
                import os
                archive.writestr(item, os.readlink(path))
            elif path.is_dir():
                item.external_attr = (stat.S_IFDIR | 0o755) << 16
                archive.writestr(item, b"")
            else:
                item.external_attr = (stat.S_IFREG | (0o755 if path.stat().st_mode & 0o111 else 0o644)) << 16
                archive.writestr(item, path.read_bytes())
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix(".ipa.sha256").write_text(digest + "  " + output.name + "\n")
    output.with_suffix(".build.json").write_text(json.dumps(dict(
        bundleIdentifier=info["CFBundleIdentifier"], version=info["CFBundleShortVersionString"],
        minimumOS=info.get("MinimumOSVersion"), platform=info["CFBundleSupportedPlatforms"],
        signedForDevice=False, requiresPersonalSigning=True, sha256=digest), indent=2) + "\n")
    print("Created unsigned IPA; personal signing is required before installation.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    package(args.app, args.output)
