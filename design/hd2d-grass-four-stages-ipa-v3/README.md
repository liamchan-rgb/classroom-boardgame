# 草原 HD-2D 四阶段设备小样 v3

[完整提示词](art-direction-prompt.md) · [执行计划](EXECUTION_PLAN.md) · [参数/尺寸/动画技术注解](TECHNICAL_NOTES.md) · [IPA安装查看](DEVICE_GUIDE.md) · [实际构建证据](evidence/device-build.json)

已实现前四阶段：统一左上暖阳及投影/AO，低噪声自然草地群落，树石营地明暗与前后层次，克制的局部Bloom/空气透视/边缘景深/微动。新增效果均可调节和关闭，主画面保持简洁。角色/UI整体统一留到第五步。

Xcode 27.2设备Release arm64编译通过，18项效果/几何检查通过；正式项目72+6项回归检查通过。GrassHD2D 0.3(3)独立bundle ID，最低iPadOS17，未签名IPA供已有SideStore流程安装。本轮没有中间截图/录屏/视觉审核，真机画面与性能等待用户测试。

原始图集、用户理想效果参考及旧版本保留，正式App/规则不改。IPA长期下载及完整存档见稍后补齐的交付回执。
