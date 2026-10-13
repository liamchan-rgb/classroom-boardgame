# 草原HD-2D四阶段 · v3长期交付

下载[GrassHD2D-v0.3-unsigned.ipa](GrassHD2D-v0.3-unsigned.ipa)，通过已有SideStore方式个人签名安装。独立草原小样，iPadOS17+，arm64设备包，正式App不变。

本轮实现左上暖阳/统一投影与AO、自然草地群落、树石营地层次、克制局部Bloom/空气透视/边缘景深/微动。按用户最新指令没有中间画面审核、截图或录屏，第五步角色/UI整体统一未执行。云端设备编译和18项效果/几何检查通过，正式项目72+6项回归通过；真机视觉/性能尚待用户测试。

- 完整源码标签：archive-design-hd2d-grass-ipa-v3-20261013，源码快照2c15a22f31cab699558e0e3af4f61b14fd574b09。
- 实际IPA编译提交：a5078546fd4386d4dd37ca2bbf48269b8661be0e；原PR源码head 218c2161476bd0217b18d885e30a1160fd4ae0a2。源码快照Native源码/资源/工程与编译提交逐字节相同。
- [构建证据](build-evidence.json) · [完整编译诊断ZIP](hd2d-v3-device-diagnostics.zip) · [恢复说明](archive-design-hd2d-grass-ipa-v3-20261013.恢复说明.md) · [逐文件清单](archive-design-hd2d-grass-ipa-v3-20261013.manifest.json)。
- 完整ZIP为141694985字节，SHA256 e89e81241489df2536496af38b5edd82d45eb259db0db2fd394d214370b8697e。

完整ZIP以3个48MiB以内分片保存在[transport](transport)；下载全部part及transport.json、restore_zip.py后运行脚本还原。它包含本轮完整源码、Git历史包、实际设备IPA和完整诊断ZIP；此分支仅存交付文件，不合并main。
