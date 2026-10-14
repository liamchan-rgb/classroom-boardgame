#!/usr/bin/env python3
"""Use the repository milestone tool, adapting only its legacy recovery prose for this sample."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile


def sha(data): return hashlib.sha256(data).hexdigest()


def main():
    args=sys.argv[1:]
    if '--source-only' in args: raise ValueError('This delivery must include the actual device IPA')
    index=args.index('--output')+1
    output=Path(args[index]).resolve()
    targets=[output,output.with_suffix('.manifest.json'),output.with_suffix(output.suffix+'.sha256'),output.with_suffix('.恢复说明.md')]
    if any(p.exists() for p in targets): raise FileExistsError('Refusing to overwrite a checkpoint')
    repo=Path(__file__).resolve().parents[3]
    if subprocess.check_output(['git','-C',str(repo),'rev-parse','--is-shallow-repository'],text=True).strip() != 'false':
        raise ValueError('Full source history required. Fetch --unshallow before archiving.')
    output.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='hd2d-source-archive-') as directory:
        staged=Path(directory)/'canonical.zip';forward=args.copy();forward[index]=str(staged)
        subprocess.run([sys.executable,str(repo/'tools/archive_milestone.py'),*forward],check=True)
        with zipfile.ZipFile(staged) as archive:
            payload={row.filename:archive.read(row.filename) for row in archive.infolist() if not row.is_dir()}
        # Canonical bundle verification within the source repository can miss shallow
        # boundaries. Independently import into an empty repository before publication.
        history=Path(directory)/'history.bundle';history.write_bytes(payload['git-history.bundle'])
        restored=Path(directory)/'history-verify.git'
        subprocess.run(['git','clone','--mirror',str(history),str(restored)],check=True)
        subprocess.run(['git','-C',str(restored),'fsck','--full','--no-dangling'],check=True)
        manifest=json.loads(payload.pop('manifest.json'))
        recovery=f'''# {manifest['milestone']} 独立草原小样恢复说明

本存档保存本轮完整源码、Git历史、实际设备IPA和完整Actions诊断ZIP，范围以manifest.json为准。使用仓库tools/archive_milestone.py进行源码/历史/交付采集和校验；此包装脚本仅更正旧通用恢复说明中的正式App名称、系统版本和默认分支文字，未改变采集范围或证据。

- 源码快照：{manifest['sourceSnapshotCommit']}；唯一标签：{manifest['snapshotTag']}。
- 实际IPA编译提交（PR合成merge）：{manifest['compiledCommit']}；源head与工具链记录见{manifest['buildEvidence']}。
- 安装包：{manifest['currentIPA']}；GrassHD2D 0.4(4)，iPadOS17及以上，arm64设备包，需使用已有SideStore方式个人签名。
- 与正式课堂App使用不同bundle ID，不包含账号、证书、配对材料或教师设备资料。
- Xcode编译/数学检查已完成；本轮没有中间画面审核，视觉与帧率等待用户真机验证。

## 还原

若ZIP按48MiB分片保存，先在transport目录下载全部part文件并运行restore_zip.py，再核对完整ZIP SHA256。解压后的manifest.json逐一列出每个载荷SHA256及字节数。

```sh
git clone git-history.bundle classroom-boardgame-restored
cd classroom-boardgame-restored
git checkout {manifest['sourceSnapshotCommit']}
```

也可以直接读取source/。独立项目在source/design/hd2d-terrain-foreground-v4/Native/GrassLightingPrototype.xcodeproj；共享scheme为GrassLightingPrototype。参数和尺寸/动画注解见同目录TECHNICAL_NOTES.md；安装查看说明见DEVICE_GUIDE.md。archive-assets不在源码Git bundle中，也不得合并到main。
'''.encode()
        payload['恢复说明.md']=recovery
        manifest['entries']=[dict(path=name,bytes=len(data),sha256=sha(data)) for name,data in sorted(payload.items())]
        manifest['archiveKind']='independent-design-device-ipa'
        manifest['deviceMinimumOS']='17.0'
        manifest['visualReviewPerformed']=False
        metadata=(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode()
        with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED) as archive:
            for name,data in sorted(payload.items()):archive.writestr(name,data)
            archive.writestr('manifest.json',metadata)
        with zipfile.ZipFile(output) as archive:
            if archive.testzip() is not None:raise ValueError('Final ZIP CRC failure')
            for row in manifest['entries']:
                data=archive.read(row['path'])
                if len(data)!=row['bytes'] or sha(data)!=row['sha256']:raise ValueError('Final payload checksum failure')
        digest=sha(output.read_bytes())
        targets[1].write_bytes(metadata);targets[2].write_text(digest+'  '+output.name+'\n');targets[3].write_bytes(recovery)
        print(json.dumps(dict(archive=str(output),bytes=output.stat().st_size,sha256=digest,payloadFiles=len(payload),checks='canonical collection plus final ZIP/all payload checksums passed'),indent=2))

if __name__=='__main__':main()
