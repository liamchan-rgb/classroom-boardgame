# v4交付回执

已落实实机反馈后的场景结构与前景修正，原始素材和旧版本保留；正式App/规则与地图逻辑不改。前景树的缩放保护不再直接隐藏，而是连续非零透明度；与地图共用光照，景深开关只改变滤镜。自然林带、岩壁/土坡、缓坡受光、营地地面、较短投影与统一角色均已接入。

## 下载与安装

- [直接下载IPA](/workspace/hd2d-v4-delivery/GrassHD2D-v0.4-unsigned.ipa)（真实文件绝对路径）。
- [GitHub永久下载IPA](https://github.com/liamchan-rgb/classroom-boardgame/blob/16163a5a2f0cb967c591eb5991fdcafe074bba81/archive-design-hd2d-terrain-foreground-v4-20261014/GrassHD2D-v0.4-unsigned.ipa?raw=true) · [长期完整存档](https://github.com/liamchan-rgb/classroom-boardgame/tree/16163a5a2f0cb967c591eb5991fdcafe074bba81/archive-design-hd2d-terrain-foreground-v4-20261014)。
- GrassHD2D 0.4(4)，iPadOS17+，arm64未签名设备包；用已有SideStore流程个人签名导入，更新现有GrassHD2D，不额外占激活App名额。
- 正确IPA大小：16235638字节（约16.2MB）。若下载得到网页或异常大小，改用直接文件链接；包内采用stored ZIP及显式Payload/App目录。
- [安装观察说明](../../design/hd2d-terrain-foreground-v4/DEVICE_GUIDE.md) · [技术/尺寸/动画注解](../../design/hd2d-terrain-foreground-v4/TECHNICAL_NOTES.md) · [本轮计划](../../design/hd2d-terrain-foreground-v4/PLAN.md)。

## 版本、证据与恢复

|项目|记录|
|---|---|
|源码标签|archive-design-hd2d-terrain-foreground-v4-20261014|
|源码快照|4d30ecd428a43989625025d6381f9ddb95942387|
|IPA实际编译提交|8c888c062edcb9777c22fe577e315766e2cb7e5d（PR合成merge）|
|IPA对应源head|886f5780cda588d5eb909fdb81207c63d4919eaa|
|长期存档提交|16163a5a2f0cb967c591eb5991fdcafe074bba81（archive-assets）|
|设备编译|Release generic/platform=iOS，arm64，成功|
|效果/几何检查|29项通过，包含连续缩放/非零前景避让/边界连续性/地形法线/图结构与脚点|
|正式项目回归|GameCore72+ProbeCore6项通过|
|包检查|平台/arm64/CRC/stored-entry读取/目录/权限/全部Art SHA通过|
|独立恢复|4分片与完整ZIP校验、454个载荷校验、448个恢复源码校验、空仓导入/fsck/完整历史通过|

[设备编译日志Artifact](https://github.com/liamchan-rgb/classroom-boardgame/actions/runs/38499814667)保留14天；完整原诊断ZIP已永久存档。Native源码/资源/工程在快照与实际编译提交中逐字节相同。

IPA SHA256：`c647b0b08f69d187991062ff8805336f20f6fb4bfb526afcaba6b013df9dfabf`。

完整存档ZIP：179645125字节，SHA256 `4104346400755cb52d95fa5f011367c2a276a3891afb598e294420c79ceb6df7`；[本地完整ZIP](/workspace/hd2d-v4-delivery/archive-design-hd2d-terrain-foreground-v4-20261014.zip)。长期transport目录中4个分片可无损还原。

本轮没有中间场景截图/录屏/画面审核。编译和数学检查不能代替真机观感与帧率验收；v4设备反馈尚待用户提供。存档已独立验证，旧档/素材/标签不覆盖；索引与回执收尾属于同一步，不递归生成新存档。
