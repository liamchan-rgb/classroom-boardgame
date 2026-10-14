#!/usr/bin/env python3
"""Package and verify this independent unsigned arm64 iOS device sample."""
import argparse
import hashlib
import json
import os
import plistlib
import stat
import struct
import zipfile
from pathlib import Path


def verify_device(info, executable):
    for key in ('CFBundleDisplayName','CFBundleName'):
        if not info.get(key) or any(c not in 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 ' for c in info[key]):
            raise ValueError(key+' must be ASCII for personal App ID signing')
    if info.get('CFBundleIdentifier') != 'com.classroomboardgame.design.grasshd2dv3':
        raise ValueError('Unexpected independent sample bundle identifier')
    if info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
        raise ValueError('Device platform required; simulator output cannot be delivered as IPA')
    if executable[:4] != b'\xcf\xfa\xed\xfe' or len(executable)<32:
        raise ValueError('Expected a thin 64-bit Mach-O')
    _,cpu,_,_,commands,command_bytes,_,_=struct.unpack('<8I',executable[:32])
    if cpu!=0x0100000c: raise ValueError('Device arm64 required')
    offset=32;platform=None
    for _ in range(commands):
        if offset+8>32+command_bytes or offset+8>len(executable): raise ValueError('Malformed load commands')
        command,size=struct.unpack_from('<II',executable,offset)
        if size<8 or offset+size>len(executable) or offset+size>32+command_bytes: raise ValueError('Invalid load command size')
        if command==0x32:
            if size<24: raise ValueError('Invalid LC_BUILD_VERSION')
            platform=struct.unpack_from('<I',executable,offset+8)[0]
        offset+=size
    if platform!=2: raise ValueError('Mach-O LC_BUILD_VERSION must identify device iOS (2), not simulator (7)')
    return dict(architecture='arm64',machOPlatform=platform)


def package(app,output):
    if output.exists(): raise FileExistsError('Refusing to overwrite '+str(output))
    info=plistlib.loads((app/'Info.plist').read_bytes())
    executable=app/info['CFBundleExecutable']
    checks=verify_device(info,executable.read_bytes())
    if (app/'embedded.mobileprovision').exists(): raise ValueError('Do not package personal provisioning material')
    provenance=json.loads((Path(__file__).resolve().parents[1]/'asset-provenance.json').read_text())
    for name,digest in provenance['assets'].items():
        resource=app/'Art'/Path(name).name
        if hashlib.sha256(resource.read_bytes()).hexdigest()!=digest: raise ValueError('Built asset changed: '+name)
    for name,digest in provenance.get('newAssets',{}).items():
        resource=app/'Art'/Path(name).name
        if hashlib.sha256(resource.read_bytes()).hexdigest()!=digest:raise ValueError('New built asset changed: '+name)
    output.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(output,'w',zipfile.ZIP_STORED) as archive:
        # Explicit root directory entries plus stored data: standard, simple IPA packaging.
        for name in ('Payload/','Payload/'+app.name+'/'):
            item=zipfile.ZipInfo(name);item.create_system=3;item.compress_type=zipfile.ZIP_STORED
            item.external_attr=(stat.S_IFDIR|0o755)<<16;archive.writestr(item,b'')
        for path in sorted(app.rglob('*')):
            name='Payload/'+app.name+'/'+path.relative_to(app).as_posix()
            item=zipfile.ZipInfo(name+'/' if path.is_dir() and not path.is_symlink() else name)
            item.create_system=3;item.compress_type=zipfile.ZIP_STORED
            if path.is_symlink():
                item.external_attr=(stat.S_IFLNK|0o777)<<16;archive.writestr(item,os.readlink(path))
            elif path.is_dir():
                item.external_attr=(stat.S_IFDIR|0o755)<<16;archive.writestr(item,b'')
            else:
                item.external_attr=(stat.S_IFREG|(0o755 if path.stat().st_mode&0o111 else 0o644))<<16
                archive.writestr(item,path.read_bytes())
    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None: raise ValueError('IPA CRC check failed')
        binary=archive.getinfo('Payload/'+app.name+'/'+executable.name)
        assert archive.getinfo('Payload/').is_dir() and archive.getinfo('Payload/'+app.name+'/').is_dir()
        assert all(item.compress_type==zipfile.ZIP_STORED for item in archive.infolist())
        if not (binary.external_attr>>16)&0o111: raise ValueError('Executable mode lost in ZIP')
    digest=hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix('.ipa.sha256').write_text(digest+'  '+output.name+'\n')
    output.with_suffix('.build.json').write_text(json.dumps(dict(
        bundleIdentifier=info['CFBundleIdentifier'],version=info['CFBundleShortVersionString'],
        displayName=info['CFBundleDisplayName'],bundleName=info['CFBundleName'],minimumOS=info.get('MinimumOSVersion'),
        platform=info['CFBundleSupportedPlatforms'],**checks,zipCompression='stored',explicitPayloadDirectories=True,signedForDevice=False,requiresPersonalSigning=True,
        originalAssetsVerified=True,sha256=digest),indent=2)+'\n')
    print('PASS device arm64/platform/load commands, immutable resources and ZIP executable modes; unsigned IPA:',output.name)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('app',type=Path);parser.add_argument('output',type=Path)
    args=parser.parse_args();package(args.app,args.output)
