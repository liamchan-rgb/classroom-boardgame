# 首次安装：SideStore与课堂验证App

2026-10-12核查。教师已确认有电脑，系统待确认。以下按Windows准备；macOS使用[iloader的DMG](https://github.com/nab138/iloader/releases/download/v2.3.6/iloader-darwin-universal.dmg)。

1. Windows安装[苹果iTunes](https://www.apple.com/itunes/download/win64)，再安装[iloader 2.3.6 MSI](https://github.com/nab138/iloader/releases/download/v2.3.6/iloader-windows-x64.msi)。
2. iPad安装[LocalDevVPN](https://apps.apple.com/app/localdevvpn/id6755608044)。
3. USB连接iPad与电脑，在iPad选择“信任此电脑”。
4. 打开iloader，登录免费Apple ID、选择iPad，点击“Install SideStore (Stable)”。
5. iPad“设置→通用→VPN与设备管理”允许个人开发者；“隐私与安全性”开启开发者模式，按系统提示重启。
6. LocalDevVPN点击Connect；打开SideStore，用同一Apple ID登录，在My Apps点击SideStore旁的“7 DAYS”完成首次刷新。
7. 将已编译的 `ClassroomStage0_v0.5_unsigned.ipa` 保存到iPad“文件”；SideStore的My Apps点“＋”，选择此IPA安装。
8. 启动“课堂双画面验证”，先确认教师控制台正常，再测试电视连接和内置绘本。

安装／刷新时需要Wi-Fi及LocalDevVPN。免费签名7天，需要刷新SideStore自身和课堂App。首次安装及iPadOS27行为仍待教师实测。

当前SideStore发布页最新为0.7.0-alpha，修复旧版503登录问题；遇到错误时保留工具版本和错误原文，不将安装成功当作续签或投屏已通过。

来源：[官方前置条件](https://docs.sidestore.io/docs/installation/prerequisites)、[官方安装流程](https://docs.sidestore.io/docs/installation/install)、[iloader](https://iloader.app/)、[SideStore发布页](https://github.com/SideStore/SideStore/releases/tag/0.7.0-alpha)。
