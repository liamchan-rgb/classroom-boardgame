# 四阶段小样交付回执

已自主执行优化顺序第1—4步：光照/色彩、草地群落、地形层次、克制HD-2D氛围。第五步角色/UI整体统一留待后续。完整提示词于计划提交914ae8c先于实现发布。

- [GitHub下载IPA](https://github.com/liamchan-rgb/classroom-boardgame/blob/18c9f33d4ec3ae5538efe38126ac1bc47f8d0aca/archive-design-hd2d-grass-ipa-v3-20261013-r2/GrassHD2D-v0.3-unsigned.ipa?raw=true)：GrassHD2D 0.3(3)，独立草原小样，iPadOS17+，真实arm64设备包，需使用现有SideStore方式个人签名安装。
- [长期存档及完整诊断](https://github.com/liamchan-rgb/classroom-boardgame/tree/18c9f33d4ec3ae5538efe38126ac1bc47f8d0aca/archive-design-hd2d-grass-ipa-v3-20261013-r2)：使用完整历史修正版r2，原首次存档留存但其历史包不完整，详情见[修正说明](ARCHIVE_CORRECTION.md)。
- [本地IPA](/workspace/hd2d-grass-v3-delivery/GrassHD2D-v0.3-unsigned.ipa) · [本地完整存档ZIP](/workspace/hd2d-grass-v3-delivery/archive-design-hd2d-grass-ipa-v3-20261013-r2.zip)。这些是当前真实绝对路径文件，不通过临时图片呈现机制。
- [构建日志Artifact](https://github.com/liamchan-rgb/classroom-boardgame/actions/runs/38446814120)：设备工作流成功，Artifact ID11838930568，完整ZIP已长期存档。
- [技术及参数注解](TECHNICAL_NOTES.md) · [设备查看说明](DEVICE_GUIDE.md)。

## 版本与检查

|项目|结果|
|---|---|
|源码标签|archive-design-hd2d-grass-ipa-v3-20261013-r2|
|源码快照|b1ffe63e51ecc29e96943f855abfa6b7e7e6ba11|
|IPA实际编译提交|a5078546fd4386d4dd37ca2bbf48269b8661be0e（PR合成merge）|
|IPA对应源head|218c2161476bd0217b18d885e30a1160fd4ae0a2|
|长期交付提交|18c9f33d4ec3ae5538efe38126ac1bc47f8d0aca（archive-assets）|
|工具链|Xcode27.2，Apple Swift6.4；Release generic/platform=iOS|
|检查|18项效果/几何检查通过；正式项目GameCore72+ProbeCore6项通过；无失败|
|资源与包|原图集/理想参考SHA保持一致；下载IPA CRC/平台/arm64/可执行权限/资源SHA通过|
|存档恢复|3分片、ZIP及396个载荷校验通过；空仓导入/fsck与390个恢复源码文件SHA通过；旧存档树不变|

IPA：10020952字节，SHA256 `64d72f559dde68515197dd2bcf8edb4adb803c66d05cd20a1f2629e085859f9d`。

完整存档ZIP：141753697字节，SHA256 `2065cd9349517b9d2aaccf8442856a7d631df38d40b815f49d6286f998de7f18`，长期传输目录中3分片可无损还原。

本轮按要求没有中间画面审核、截图、录屏，也没有声称真机视觉/性能已验收。源快照与实际编译提交的Native源码、资源、工程逐字节一致。索引/回执收尾更新属于同一步，按仓库规定不再递归生成另一份存档。
