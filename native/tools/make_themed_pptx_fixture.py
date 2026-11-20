#!/usr/bin/env python3
"""Writes Packages/ProbeCore/Tests/ClassroomProbeCoreTests/Fixtures/themed.pptx: a one-slide deck whose look comes from
the theme, master and layout (background on the layout, theme colours through the master's clrMap, text styles on the
master, a decorative master shape, a group) — the things a template-made deck relies on."""
import pathlib, zipfile

NS = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"'
REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
def rels(*items):
    body = "".join(f'<Relationship Id="{i}" Type="{REL}/{t}" Target="{target}"/>' for i, t, target in items)
    return f'<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">{body}</Relationships>'
def xfrm(x, y, cx, cy): return f'<a:xfrm><a:off x="{x}" y="{y}"/><a:ext cx="{cx}" cy="{cy}"/></a:xfrm>'
TREE_HEAD = '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>'

files = {
"[Content_Types].xml": '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/><Override PartName="/ppt/slides/slide1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/><Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/><Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/><Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/></Types>',
"_rels/.rels": rels(("rId1", "officeDocument", "ppt/presentation.xml")),
"ppt/presentation.xml": f'<?xml version="1.0" encoding="UTF-8"?><p:presentation {NS}><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId2"/></p:sldMasterIdLst><p:sldIdLst><p:sldId id="256" r:id="rId1"/></p:sldIdLst><p:sldSz cx="12192000" cy="6858000"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>',
"ppt/_rels/presentation.xml.rels": rels(("rId1", "slide", "slides/slide1.xml"), ("rId2", "slideMaster", "slideMasters/slideMaster1.xml")),
"ppt/theme/theme1.xml": f'<?xml version="1.0" encoding="UTF-8"?><a:theme {NS} name="T"><a:themeElements><a:clrScheme name="T"><a:dk1><a:srgbClr val="2B2147"/></a:dk1><a:lt1><a:srgbClr val="FFFFFF"/></a:lt1><a:dk2><a:srgbClr val="3D3366"/></a:dk2><a:lt2><a:srgbClr val="F3F0FA"/></a:lt2><a:accent1><a:srgbClr val="1F7A99"/></a:accent1><a:accent2><a:srgbClr val="E0533D"/></a:accent2><a:accent3><a:srgbClr val="E0A526"/></a:accent3><a:accent4><a:srgbClr val="6B5CA5"/></a:accent4><a:accent5><a:srgbClr val="2E9E62"/></a:accent5><a:accent6><a:srgbClr val="8A8FA3"/></a:accent6><a:hlink><a:srgbClr val="1F7A99"/></a:hlink><a:folHlink><a:srgbClr val="6B5CA5"/></a:folHlink></a:clrScheme><a:fontScheme name="T"><a:majorFont><a:latin typeface="Georgia"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont><a:minorFont><a:latin typeface="Helvetica"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont></a:fontScheme><a:fmtScheme name="T"><a:fillStyleLst/><a:lnStyleLst/><a:effectStyleLst/><a:bgFillStyleLst/></a:fmtScheme></a:themeElements></a:theme>',
"ppt/slideMasters/slideMaster1.xml": f'<?xml version="1.0" encoding="UTF-8"?><p:sldMaster {NS}><p:cSld><p:bg><p:bgPr><a:solidFill><a:schemeClr val="bg1"/></a:solidFill></p:bgPr></p:bg><p:spTree>{TREE_HEAD}'
    f'<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr/><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr><p:spPr>{xfrm(600000, 300000, 11000000, 1200000)}</p:spPr><p:txBody><a:bodyPr anchor="b"/><a:lstStyle/><a:p><a:r><a:t>Master title</a:t></a:r></a:p></p:txBody></p:sp>'
    f'<p:sp><p:nvSpPr><p:cNvPr id="3" name="Band"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr>{xfrm(0, 6600000, 12192000, 258000)}<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:solidFill><a:schemeClr val="accent2"/></a:solidFill></p:spPr></p:sp>'
    '</p:spTree></p:cSld><p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/><p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>'
    '<p:txStyles><p:titleStyle><a:lvl1pPr algn="ctr"><a:defRPr sz="4400" b="1"><a:solidFill><a:schemeClr val="tx1"/></a:solidFill><a:latin typeface="+mj-lt"/></a:defRPr></a:lvl1pPr></p:titleStyle><p:bodyStyle><a:lvl1pPr><a:defRPr sz="2400"><a:solidFill><a:schemeClr val="tx1"/></a:solidFill><a:latin typeface="+mn-lt"/></a:defRPr></a:lvl1pPr></p:bodyStyle><p:otherStyle><a:lvl1pPr><a:defRPr sz="1800"><a:solidFill><a:schemeClr val="tx1"/></a:solidFill></a:defRPr></a:lvl1pPr></p:otherStyle></p:txStyles></p:sldMaster>',
"ppt/slideMasters/_rels/slideMaster1.xml.rels": rels(("rId1", "slideLayout", "../slideLayouts/slideLayout1.xml"), ("rId2", "theme", "../theme/theme1.xml")),
# The layout: dark background (tx1 → dk1) and text colours flipped by mapping tx1 to the light colour.
"ppt/slideLayouts/slideLayout1.xml": f'<?xml version="1.0" encoding="UTF-8"?><p:sldLayout {NS}><p:cSld><p:bg><p:bgPr><a:solidFill><a:schemeClr val="tx1"/></a:solidFill></p:bgPr></p:bg><p:spTree>{TREE_HEAD}'
    f'<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr/><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr><p:spPr>{xfrm(700000, 1800000, 8000000, 1400000)}</p:spPr><p:txBody><a:bodyPr/><a:lstStyle><a:lvl1pPr algn="l"><a:defRPr><a:solidFill><a:schemeClr val="bg1"/></a:solidFill></a:defRPr></a:lvl1pPr></a:lstStyle><a:p><a:r><a:t>Layout title</a:t></a:r></a:p></p:txBody></p:sp>'
    '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>',
"ppt/slideLayouts/_rels/slideLayout1.xml.rels": rels(("rId1", "slideMaster", "../slideMasters/slideMaster1.xml")),
"ppt/slides/slide1.xml": f'<?xml version="1.0" encoding="UTF-8"?><p:sld {NS}><p:cSld><p:spTree>{TREE_HEAD}'
    '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr/><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr><p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang="en-US"/><a:t>Themed title</a:t></a:r></a:p></p:txBody></p:sp>'
    f'<p:grpSp><p:nvGrpSpPr><p:cNvPr id="5" name="Group"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="1000000" y="4000000"/><a:ext cx="2000000" cy="1000000"/><a:chOff x="0" y="0"/><a:chExt cx="4000000" cy="2000000"/></a:xfrm></p:grpSpPr>'
    f'<p:sp><p:nvSpPr><p:cNvPr id="6" name="Card"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr>{xfrm(2000000, 0, 2000000, 2000000)}<a:prstGeom prst="roundRect"><a:avLst/></a:prstGeom><a:solidFill><a:schemeClr val="accent4"><a:lumMod val="50000"/></a:schemeClr></a:solidFill><a:ln w="25400"><a:solidFill><a:schemeClr val="accent3"/></a:solidFill></a:ln></p:spPr>'
    '<p:txBody><a:bodyPr anchor="ctr" lIns="0" tIns="0" rIns="0" bIns="0"/><a:lstStyle/><a:p><a:r><a:rPr lang="en-US"><a:solidFill><a:schemeClr val="bg2"/></a:solidFill></a:rPr><a:t>Card text</a:t></a:r></a:p></p:txBody></p:sp></p:grpSp>'
    '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>',
"ppt/slides/_rels/slide1.xml.rels": rels(("rId1", "slideLayout", "../slideLayouts/slideLayout1.xml")),
}
out = pathlib.Path(__file__).resolve().parent.parent / "Packages/ProbeCore/Tests/ClassroomProbeCoreTests/Fixtures/themed.pptx"
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for name, text in files.items(): z.writestr(name, text)
print(out)
