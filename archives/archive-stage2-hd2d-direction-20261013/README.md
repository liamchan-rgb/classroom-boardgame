# 战斗风格补充存档：近似八方旅人

2026-10-13。状态：长期存档已推送、远端重新读取和独立恢复验证通过。用户明确不做3D战斗演出，近似八方旅人的战斗氛围按原创分层2D提案记录；新美术和实现尚未验收。

- [长期存档目录](https://github.com/liamchan-rgb/classroom-boardgame/tree/be7b1bbe85617536c8b1037ec36f8d28329563ae/archive-stage2-hd2d-direction-20261013)：六个ZIP分片、transport.json、restore_zip.py、清单/校验/恢复说明和3份本次更新交付MD。
- [源码快照标签](https://github.com/liamchan-rgb/classroom-boardgame/tree/archive-stage2-hd2d-direction-20261013)：1e8a74e93cca45611791c4ca3f50f309fa7801bb。
- 当前安装包仍为v0.9，IPA编译提交1379bd2e174d88c582bb19fa8ea1f64c180a74da；[原IPA存档](../archive-stage2-ui-art-v0.9-20261013/README.md)。本次不改App或重新构建。
- 完整ZIP：classroom-stage2-hd2d-direction-20261013.zip，291,000,687字节，SHA256 `a2ea07d350760016e9be4749d2e5b7d2cef858b264a7229ca1c8428380cbb78d`。

286项载荷包含279份源码/资料、5份选定交付、完整Git历史包和恢复说明。5份交付包括更新反馈/美术提示词/效果预期，以及原v0.9 IPA/完整诊断ZIP。下载全部part、transport.json、restore_zip.py，执行 `python3 restore_zip.py` 无损还原原ZIP。目录内MD可直接阅读。

[远端恢复验证](verification.json)：六段SHA256、整ZIP/CRC及全部载荷校验通过，Git历史包完整且排除archive-assets，恢复源码提交与279份源码SHA256全部正确，App源文件与既有实际编译提交相同。此前3个存档目录未修改，旧设计/ZIP/标签保留。

[反馈补充](../../stage2/ui-feedback-round1-20261013/feedback.md)、[更新美术提示词](../../stage2/ui-feedback-round1-20261013/art-direction-prompt.md)、[可行性/效果预期](../../stage2/ui-feedback-round1-20261013/visual-expectations.md)；[GitHub界面待办 #1](https://github.com/liamchan-rgb/classroom-boardgame/issues/1)已追加方向，仍为待办。原作有3D场景/光照，本提案用2D层次与光效近似氛围，不承诺复刻原作完整渲染、不加入其战斗规则。

本次检查为资料链接、远端文档/Issue读回和存档恢复，不宣称新执行App测试、真机或审美通过；不含教师未交付的课堂进度/文件或签名材料。本目录属于同一步索引收尾，不递归归档。
