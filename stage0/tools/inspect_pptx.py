#!/usr/bin/env python3
"""Offline PPTX structure/notes inspection. Does not render slides or contact a server."""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import posixpath
import tempfile
import time
from urllib.parse import unquote
import xml.etree.ElementTree as ET
from zipfile import BadZipFile, ZipFile

MAX_PART = 32 * 1024 * 1024
MAX_TOTAL = 256 * 1024 * 1024


class InvalidDeck(ValueError):
    pass


def local(tag: str) -> str:
    return tag.rsplit('}', 1)[-1]


def attr(element, name, default=None):
    return next((value for key, value in element.attrib.items()
                 if local(key) == name), default)


def descendants(root, name):
    return (item for item in root.iter() if local(item.tag) == name)


class Package:
    def __init__(self, archive):
        self.archive = archive
        infos = archive.infolist()
        names = [info.filename for info in infos]
        if len(names) != len(set(names)):
            raise InvalidDeck('PPTX 含重复部件名，无法可靠解析。')
        if len(infos) > 20000 or sum(info.file_size for info in infos) > MAX_TOTAL:
            raise InvalidDeck('PPTX 超出阶段0检查工具的大小限制。')
        if any(info.file_size > MAX_PART for info in infos):
            raise InvalidDeck('PPTX 内单个部件超过32 MiB。')
        self.names = set(names)

    def xml(self, name):
        if name not in self.names:
            raise InvalidDeck(f'缺失部件：{name}')
        data = self.archive.read(name)
        # OOXML does not need DTDs. Reject them, including UTF-16/32 encodings.
        normalized = data.replace(b'\x00', b'').upper()
        if b'<!DOCTYPE' in normalized or b'<!ENTITY' in normalized:
            raise InvalidDeck(f'不支持含 DTD／实体的 XML：{name}')
        try:
            return ET.fromstring(data)
        except ET.ParseError as exc:
            raise InvalidDeck(f'XML 格式错误：{name}：{exc}') from exc

    def relationships(self, owner):
        relpath = posixpath.join(posixpath.dirname(owner), '_rels',
                                posixpath.basename(owner) + '.rels')
        if relpath not in self.names:
            return {}
        result = {}
        for element in self.xml(relpath):
            rel_id = element.get('Id')
            if not rel_id or rel_id in result:
                raise InvalidDeck(f'关系 ID 缺失或重复：{relpath}')
            external = element.get('TargetMode') == 'External'
            target = element.get('Target', '')
            if not target:
                raise InvalidDeck(f'关系目标为空：{relpath}')
            if not external:
                target = unquote(target)
                if '\\' in target:
                    raise InvalidDeck(f'非法部件路径：{relpath}')
                target = posixpath.normpath(posixpath.join(
                    posixpath.dirname(owner), target) if not target.startswith('/')
                    else target.lstrip('/'))
                if target == '..' or target.startswith('../'):
                    raise InvalidDeck(f'部件路径越出包根目录：{relpath}')
            result[rel_id] = {'type': element.get('Type', '').rsplit('/', 1)[-1],
                              'target': target, 'external': external}
        return result


def paragraphs(root):
    values = []
    for paragraph in descendants(root, 'p'):
        text = ''.join((node.text or '') if local(node.tag) == 't' else '\n'
                       for node in paragraph.iter() if local(node.tag) in ('t', 'br'))
        values.append(text)
    return '\n'.join(values).strip()


def notes_body(root):
    """Only speaker-note body shapes; never slide-number/date/footer placeholders."""
    values = []
    for shape in descendants(root, 'sp'):
        placeholders = list(descendants(shape, 'ph'))
        types = {item.get('type', 'obj') for item in placeholders}
        if placeholders and 'body' not in types:
            continue
        text = paragraphs(shape)
        if text:
            values.append(text)
    return '\n\n'.join(values)


def inspect(path: Path):
    started = time.perf_counter()
    try:
        with ZipFile(path) as archive:
            package = Package(archive)
            presentation_path = 'ppt/presentation.xml'
            presentation = package.xml(presentation_path)
            rels = package.relationships(presentation_path)
            slide_lists = list(descendants(presentation, 'sldIdLst'))
            if len(slide_lists) != 1:
                raise InvalidDeck('找不到唯一的幻灯片顺序表。')
            slide_ids = list(slide_lists[0])
            if not slide_ids:
                raise InvalidDeck('PPTX 没有幻灯片。')
            sizes = list(descendants(presentation, 'sldSz'))
            size = {key: sizes[0].get(key) for key in ('cx', 'cy')} if sizes else None
            pages, reports = [], []
            for index, slide_id in enumerate(slide_ids, start=1):
                relationship_id = next((value for key, value in slide_id.attrib.items()
                                        if key.startswith('{') and local(key) == 'id'), None)
                page = {'number': index, 'texts': '', 'notes': ''}
                report = {'number': index, 'structure_status': 'failed',
                          'render_status': 'not_implemented', 'issues': []}
                try:
                    relation = rels.get(relationship_id)
                    if not relation or relation['type'] != 'slide' or relation['external']:
                        raise InvalidDeck(f'第{index}页的幻灯片关系无效。')
                    slide_path = relation['target']
                    slide = package.xml(slide_path)
                    slide_rels = package.relationships(slide_path)
                    page['part'] = slide_path
                    page['texts'] = paragraphs(slide)
                    count = Counter(local(item.tag) for item in slide.iter())
                    report['part'] = slide_path
                    report['objects'] = {name: count[name] for name in
                                         ('sp', 'pic', 'graphicFrame', 'grpSp', 'tbl',
                                          'chart', 'oleObj', 'videoFile', 'audioFile', 'timing')}
                    notes = [rel for rel in slide_rels.values() if rel['type'] == 'notesSlide']
                    if len(notes) > 1 or any(rel['external'] for rel in notes):
                        raise InvalidDeck('备注关系数量或类型无效。')
                    if notes:
                        page['notes'] = notes_body(package.xml(notes[0]['target']))
                        report['notes_part'] = notes[0]['target']
                    report['notes_characters'] = len(page['notes'])
                    report['external_relationships'] = sum(
                        rel['external'] for rel in slide_rels.values())
                    # Never fetch any external relationship.
                    for rel in slide_rels.values():
                        if not rel['external'] and rel['target'] not in package.names:
                            report['issues'].append(f"引用部件缺失：{rel['target']}")
                    report['structure_status'] = ('partial' if report['issues'] else 'parsed')
                    report['issues'].append('尚未渲染；文字／图片位置、样式、字体和视觉一致性未验证。')
                except (InvalidDeck, BadZipFile, RuntimeError) as exc:
                    report['issues'].append(str(exc))
                pages.append(page)
                reports.append(report)
            fonts = set()
            font_scan_errors = []
            for name in sorted(package.names):
                if name.startswith('ppt/') and name.endswith('.xml'):
                    try:
                        root = package.xml(name)
                        fonts.update(item.get('typeface') for item in root.iter()
                                     if item.get('typeface'))
                    except InvalidDeck as exc:
                        font_scan_errors.append(str(exc))
    except (BadZipFile, RuntimeError, OSError) as exc:
        raise InvalidDeck(f'不能读取 PPTX：{exc}') from exc
    private = {'format_version': 1, 'source_name': path.name, 'slide_size_emu': size,
               'pages': pages}
    # Construct public output with an explicit whitelist. Do not copy notes then hide them.
    public = {'format_version': 1, 'source_name': path.name, 'slide_size_emu': size,
              'pages': [{key: page[key] for key in ('number', 'part', 'texts') if key in page}
                        for page in pages]}
    report = {'format_version': 1, 'tool': 'stage0-pptx-inspector',
              'checked_at': datetime.now(timezone.utc).isoformat(),
              'source_name': path.name, 'source_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
              'elapsed_seconds': round(time.perf_counter() - started, 4),
              'network_requests': 0, 'page_count': len(pages), 'pages': reports,
              'declared_fonts': sorted(fonts), 'font_scan_errors': font_scan_errors,
              'iPad_font_availability': 'not_tested', 'rendering': 'not_implemented',
              'AC35': 'not_passed', 'device': 'Python host, not iPad',
              'limitations': ['仅验证包结构、页序、文字和备注读取，不是静态页渲染器。',
                              '没有在教师 iPad 上执行；真实 PPTX 与真机仍需验证。']}
    return private, public, report


def write_results(source: Path, output: Path):
    # Parse completely before touching output. Refuse to overwrite prior inspection evidence.
    private, public, report = inspect(source)
    if output.exists():
        raise InvalidDeck(f'输出目录已存在，请指定新目录以保留已有记录：{output}')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='pptx-check-', dir=output.parent) as temporary:
        staging = Path(temporary) / 'result'
        staging.mkdir()
        for name, payload in [('deck-private.json', private), ('deck-public.json', public),
                              ('import-report.json', report)]:
            (staging / name).write_text(json.dumps(payload, ensure_ascii=False, indent=2),
                                       encoding='utf-8')
        staging.rename(output)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pptx', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        report = write_results(args.pptx, args.output)
    except InvalidDeck as exc:
        parser.exit(2, f'检查失败：{exc}\n')
    # Do not print private speaker notes.
    print(f"已检查{report['page_count']}页。结果：{args.output}。静态页渲染和 iPad 导入仍未通过验证。")
    return 0 if all(page['structure_status'] == 'parsed' for page in report['pages']) else 1


if __name__ == '__main__':
    raise SystemExit(main())
