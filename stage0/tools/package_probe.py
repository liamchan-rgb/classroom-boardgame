#!/usr/bin/env python3
"""Package source with explicit portable directory/file permissions; include no UID/GID metadata."""
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo
import argparse
import stat


def package(source: Path, destination: Path):
    if not source.is_dir() or source.suffix != '.swiftpm':
        raise ValueError('输入必须是存在的.swiftpm目录。')
    destination.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(destination, 'w', compression=ZIP_DEFLATED) as archive:
        for path in [source, *sorted(source.rglob('*'))]:
            if path.is_symlink():
                raise ValueError(f'不打包符号链接：{path.name}')
            name = (Path(source.name) / path.relative_to(source)).as_posix()
            is_directory = path.is_dir()
            if is_directory:
                name += '/'
            info = ZipInfo(name)
            info.create_system = 3
            info.compress_type = ZIP_DEFLATED
            mode = (stat.S_IFDIR | 0o755) if is_directory else (stat.S_IFREG | 0o644)
            info.external_attr = (mode << 16) | (0x10 if is_directory else 0)
            info.extra = b''
            archive.writestr(info, b'' if is_directory else path.read_bytes())
    with ZipFile(destination) as archive:
        if archive.testzip() is not None:
            raise ValueError('压缩包完整性校验失败。')
        for info in archive.infolist():
            actual = stat.S_IMODE(info.external_attr >> 16)
            expected = 0o755 if info.is_dir() else 0o644
            if actual != expected or info.extra:
                raise ValueError(f'压缩包权限／附加元数据不符合预期：{info.filename}')
    print(f'已打包：{destination}（{destination.stat().st_size}字节）；目录0755，文件0644。')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    arguments = parser.parse_args()
    package(arguments.source, arguments.destination)
