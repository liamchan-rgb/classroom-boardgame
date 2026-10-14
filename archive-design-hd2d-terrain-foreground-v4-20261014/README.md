# 草原地形与角落前景修正 v4 · 长期交付

[下载GrassHD2D-v0.4-unsigned.ipa](GrassHD2D-v0.4-unsigned.ipa)。iPadOS17+，arm64设备包，使用已有SideStore流程个人签名，更新现有GrassHD2D，不额外占免费激活App名额；正式ClassroomProbe不变。

修复角落树缩放时直接隐藏、未接入共同光照的问题：独立树、稳定视口尺寸、连续非零透明度避让、统一材质shader。景深关闭保留树，缩放保持镜头中心。新增自然林带、缓坡法线、岩壁/土坡、营地地面过渡和统一角色图集；缩短投影，分离树根AO/树冠阴影，默认4:3，同时支持16:9。

- 源码标签：archive-design-hd2d-terrain-foreground-v4-20261014；快照4d30ecd428a43989625025d6381f9ddb95942387。
- 实际IPA编译提交：8c888c062edcb9777c22fe577e315766e2cb7e5d；源head886f5780cda588d5eb909fdb81207c63d4919eaa。Native源码/资源/工程与快照一致。
- 29项效果/几何检查和正式项目72+6项回归通过，设备Release编译成功。下载包设备平台/arm64/结构/CRC/全部Art SHA通过。
- 本轮未做中间场景截屏/录屏审核，实际观感和帧率等待用户v4设备反馈；不声称已达到理想图。
- IPA：16235638字节，SHA256 c647b0b08f69d187991062ff8805336f20f6fb4bfb526afcaba6b013df9dfabf。
- 完整存档ZIP：179645125字节，SHA256 4104346400755cb52d95fa5f011367c2a276a3891afb598e294420c79ceb6df7。

[构建证据](build-evidence.json) · [完整设备诊断ZIP](hd2d-v4-final-device-diagnostics.zip) · [清单](archive-design-hd2d-terrain-foreground-v4-20261014.manifest.json) · [恢复说明](archive-design-hd2d-terrain-foreground-v4-20261014.恢复说明.md)。

完整ZIP以4个48MiB以内分片保存在[transport](transport)。下载全部part、transport.json和restore_zip.py，运行脚本即可无损还原；包含完整源码、Git历史、IPA和诊断。旧稿/原素材/旧ZIP/旧标签保持原样。本分支仅存档，不合并main。
