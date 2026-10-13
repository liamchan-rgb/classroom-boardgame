# 草原HD-2D四阶段 · v3长期交付（完整历史修正版r2）

下载[GrassHD2D-v0.3-unsigned.ipa](GrassHD2D-v0.3-unsigned.ipa)，通过已有SideStore方式个人签名安装。独立草原小样，iPadOS17+，arm64设备包，正式App不变。

**仅使用本r2完整存档恢复历史**。首次archive-design-hd2d-grass-ipa-v3-20261013的ZIP/分片存在浅克隆导致的历史父提交缺失；其IPA和源码文件有效，但历史恢复包不完整。首次文件、素材、ZIP、标签均保留，本r2另存补齐历史的修正版。新脚本拒绝浅仓库，并从空仓导入历史包后fsck；未修改运行代码、原始图集或IPA。

本轮实现左上暖阳/统一投影与AO、自然草地群落、树石营地层次、克制局部Bloom/空气透视/边缘景深/微动。按最新指令没有中间画面审核、截图或录屏，第五步角色/UI整体统一未执行。设备编译及18项效果/几何检查通过，正式项目72+6项回归通过；真机视觉/性能等待用户测试。

- 完整源码标签：archive-design-hd2d-grass-ipa-v3-20261013-r2，源码快照b1ffe63e51ecc29e96943f855abfa6b7e7e6ba11。
- 实际IPA编译提交：a5078546fd4386d4dd37ca2bbf48269b8661be0e；原PR源码head 218c2161476bd0217b18d885e30a1160fd4ae0a2。快照Native源码/资源/工程与编译提交逐字节一致。
- [构建证据](build-evidence.json) · [完整诊断ZIP](hd2d-v3-device-diagnostics.zip) · [恢复说明](archive-design-hd2d-grass-ipa-v3-20261013-r2.恢复说明.md) · [清单](archive-design-hd2d-grass-ipa-v3-20261013-r2.manifest.json)。
- 完整ZIP：141753697字节；SHA256：2065cd9349517b9d2aaccf8442856a7d631df38d40b815f49d6286f998de7f18。
- IPA：10020952字节；SHA256：64d72f559dde68515197dd2bcf8edb4adb803c66d05cd20a1f2629e085859f9d。

完整ZIP以3个48MiB以内分片保存在[transport](transport)；下载全部part及transport.json、restore_zip.py后运行脚本还原，包含完整源码、Git历史包、IPA和完整诊断ZIP。本分支不合并main。
