#!/usr/bin/env python3
"""Make an immutable project milestone backup from a committed source snapshot."""
import argparse
from datetime import datetime, timezone
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import tempfile
import zipfile


def git(repo, *args, binary=False):
    result = subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True)
    return result.stdout if binary else result.stdout.decode("utf-8").strip()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def safe_relative(name):
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts or not path.parts or "\\" in name:
        raise ValueError(f"Invalid relative path: {name}")
    return path


def is_sensitive(name):
    path = PurePosixPath(name)
    return any(part == ".env" or part.startswith(".env.") for part in path.parts) or path.suffix.lower() in {
        ".p12", ".p8", ".pem", ".mobileprovision", ".pairing", ".mobiledevicepairing"
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--milestone", required=True)
    parser.add_argument("--snapshot", required=True)
    parser.add_argument("--build-record", required=True)
    parser.add_argument("--deliveries-root", type=Path, required=True)
    parser.add_argument("--delivery-list", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9._-]+", args.milestone):
        raise ValueError("Milestone ID must use ASCII letters, digits, '.', '_' or '-'.")
    repo = Path(__file__).resolve().parents[1]
    snapshot = git(repo, "rev-parse", "--verify", args.snapshot + "^{commit}")
    if git(repo, "status", "--porcelain", "--untracked-files=no"):
        raise ValueError("Commit tracked-file changes before taking a milestone snapshot.")
    output = args.output.resolve()
    manifest_path = output.with_suffix(".manifest.json")
    sha_path = output.with_suffix(output.suffix + ".sha256")
    guide_path = output.with_suffix(".恢复说明.md")
    for target in (output, manifest_path, sha_path, guide_path):
        if target.exists():
            raise FileExistsError(f"Refusing to overwrite an existing checkpoint: {target.name}")
    record_name = safe_relative(args.build_record).as_posix()
    record = json.loads(git(repo, "show", snapshot + ":" + record_name))
    tested = record["testedCommit"]
    git(repo, "merge-base", "--is-ancestor", tested, snapshot)
    selected = json.loads(args.delivery_list.read_text(encoding="utf-8"))
    if not isinstance(selected, list) or not selected or not all(isinstance(x, str) for x in selected) or len(set(selected)) != len(selected):
        raise ValueError("Delivery list must contain unique, explicit relative file names.")
    root = args.deliveries_root.resolve()
    payload = {}
    raw_source = git(repo, "archive", "--format=zip", snapshot, binary=True)
    with zipfile.ZipFile(io.BytesIO(raw_source)) as source:
        for item in source.infolist():
            if item.is_dir():
                continue
            name = safe_relative(item.filename).as_posix()
            if is_sensitive(name):
                raise ValueError(f"Signing/credential material must not be archived: {name}")
            if name.startswith("archives/") and Path(name).suffix.lower() in {".zip", ".ipa", ".bundle"}:
                raise ValueError("Binary milestone archives must remain outside Git history.")
            payload["source/" + name] = source.read(item)
    delivery_rows = []
    for name in sorted(selected):
        relative = safe_relative(name)
        if is_sensitive(name):
            raise ValueError(f"Signing/credential material selected: {name}")
        file = (root / relative).resolve()
        if not file.is_relative_to(root) or not file.is_file():
            raise ValueError(f"Missing or out-of-scope delivery: {name}")
        data = file.read_bytes()
        if file.suffix.lower() in {".zip", ".ipa"}:
            with zipfile.ZipFile(io.BytesIO(data)) as check:
                if check.testzip() is not None:
                    raise ValueError(f"Corrupt delivery ZIP: {name}")
        payload["deliveries/" + relative.as_posix()] = data
        delivery_rows.append(dict(file=relative.as_posix(), bytes=len(data), sha256=digest(data)))
    matching_ipa = [row for row in delivery_rows if row["file"].endswith(".ipa") and row["sha256"] == record["ipaSha256"]]
    if len(matching_ipa) != 1:
        raise ValueError("The current build's verified IPA must be included exactly once.")
    matching_artifact = [row for row in delivery_rows if row["file"].endswith(".zip") and row["sha256"] == record["artifactArchiveSha256"]]
    if len(matching_artifact) != 1:
        raise ValueError("The current build's complete diagnostics ZIP must be included exactly once.")
    current_ipa = matching_ipa[0]["file"]
    guide = f'''# {args.milestone} 恢复说明

这份存档包含阶段0—2现存成果的源码、资料、设计、测试及交付文件。后续版本按各自清单记录范围。

- 源码快照提交：{snapshot}
- 本存档标签：{args.milestone}
- 当前IPA实际编译提交：{tested}
- 当前推荐安装包：deliveries/{current_ipa}
- 当前App版本：{record['appVersion']}；设备：iPadOS27；需SideStore个人签名。
- 云端编译/检查通过不代替新增功能真机反馈；状态以源码中的验收和证据为准。

## 核对文件

外部 `.zip.sha256` 校验整个ZIP。解压后 `manifest.json` 列出所有载荷文件的字节数和SHA256；清单自身由整个ZIP校验覆盖。

## 恢复源码和版本历史

直接使用 `source/` 可查看完整源码、原需求、计划、设计和测试。需要Git版本历史时：

```sh
git clone -b main git-history.bundle classroom-boardgame-restored
cd classroom-boardgame-restored
git checkout {snapshot}
```

Git bundle保存生成时的项目refs和历史；本存档提交包含归档规则/工具。若继续与原私有仓库协作，将origin改为 https://github.com/liamchan-rgb/classroom-boardgame.git，再使用自己的GitHub授权。

构建设备版使用Xcode27工程；不用重新解析源码也可直接把当前IPA交给SideStore。历史安装包/Playground样例保留用于追溯，不能把其中失败版本当作当前推荐包。

本存档不是教师iPad本机课堂进度备份；尚未取得的真实PPTX、游戏存档和设备签名材料不在包内。
'''
    payload["恢复说明.md"] = guide.encode("utf-8")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="classroom-milestone-") as temporary:
        bundle = Path(temporary) / "git-history.bundle"
        source_refs = [ref for ref in git(repo, "for-each-ref", "--format=%(refname)").splitlines()
                       if ref.rsplit("/", 1)[-1] != "archive-assets"]
        if not source_refs:
            raise ValueError("No source refs are available to preserve.")
        # An isolated binary-backup branch must never enter later source bundles.
        git(repo, "bundle", "create", str(bundle), *source_refs)
        git(repo, "bundle", "verify", str(bundle))
        payload["git-history.bundle"] = bundle.read_bytes()
        refs = git(repo, "bundle", "list-heads", str(bundle)).splitlines()
        if any(line.endswith("/archive-assets") for line in refs):
            raise ValueError("Binary archive refs leaked into the source history bundle.")
    entries = [dict(path=name, bytes=len(data), sha256=digest(data)) for name, data in sorted(payload.items())]
    manifest = dict(formatVersion=1, milestone=args.milestone, createdAt=datetime.now(timezone.utc).isoformat(),
                    repository="https://github.com/liamchan-rgb/classroom-boardgame", sourceSnapshotCommit=snapshot,
                    snapshotTag=args.milestone, currentAppVersion=record["appVersion"], compiledCommit=tested,
                    currentIPA="deliveries/" + current_ipa, buildEvidence="source/" + record_name,
                    coreTests=record["coreTests"], currentDeviceVerified=record.get("newPVEDeviceVerified", False),
                    gitBundleRefs=refs, deliveries=delivery_rows, manifestSelfExcluded=True, entries=entries)
    manifest_data = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    partial = output.with_suffix(output.suffix + ".partial")
    try:
        with zipfile.ZipFile(partial, "w", zipfile.ZIP_DEFLATED) as archive:
            for name, data in sorted(payload.items()):
                archive.writestr(name, data)
            archive.writestr("manifest.json", manifest_data)
        with zipfile.ZipFile(partial) as archive:
            if archive.testzip() is not None:
                raise ValueError("The assembled archive failed ZIP integrity validation.")
            for entry in entries:
                data = archive.read(entry["path"])
                if len(data) != entry["bytes"] or digest(data) != entry["sha256"]:
                    raise ValueError("A file failed post-assembly checksum verification.")
        partial.rename(output)
    finally:
        if partial.exists():
            partial.unlink()
    archive_sha = digest(output.read_bytes())
    manifest_path.write_bytes(manifest_data)
    guide_path.write_text(guide, encoding="utf-8")
    sha_path.write_text(archive_sha + "  " + output.name + "\n", encoding="utf-8")
    print(json.dumps(dict(archive=str(output), bytes=output.stat().st_size, sha256=archive_sha,
                          sourceCommit=snapshot, compiledCommit=tested, payloadFiles=len(entries),
                          deliveryFiles=len(delivery_rows), checks="ZIP and all payload checksums passed"),
                     ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
