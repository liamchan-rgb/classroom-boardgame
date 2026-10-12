# 英语课堂电子桌游

当前实施路线：**独立原生 iPad App → GitHub Xcode 27 云端构建 → SideStore 免费个人签名与续签**。备用安装工具为 AltStore Classic。纯自用，不使用 TestFlight，不需要购买 Apple Developer Program。

目前只做阶段0能力验证。原始两份文档保存在 `docs/`，保持不变；更新安排见 [实施计划_v2.md](实施计划_v2.md)。完整桌游尚未实现，阶段0也未完成真机验收。

## 当前交付

- `native/ClassroomProbe.xcodeproj`：独立 App 工程，目标为 iPadOS 27，仅支持 iPad。
- `native/ClassroomProbe/`：教师控制台、电视公开画面、实体键盘、基础离线绘本和本地备份。
- `native/Packages/ProbeCore/`：Swift 核心库、PPTX 离线解析与6项自动验证。
- `.github/workflows/build-native-ipa.yml`：手动触发的云端构建，生成待个人签名的 IPA。
- [native/安装与真机验收.md](native/安装与真机验收.md)：构建、首次安装、续签和设备测试。
- [技术验证.md](技术验证.md)：已通过的检查与仍待验证的项目。

当前候选为v0.6：Xcode27、iOS27 SDK、6项核心测试与arm64设备版编译均通过，IPA已校验。安装包显示名为`ClassroomProbe`，中文教师界面保留；需SideStore个人签名后安装。

v0.5曾被Apple签名服务拒绝，截图指出中文`appIdName`无效。v0.6改用ASCII显示名与Bundle名称，并加入打包校验；教师已确认SideStore登录成功，等待新版安装及启动结果。

- [v0.6成功构建](https://github.com/liamchan-rgb/classroom-boardgame/actions/runs/38222596815)
- [v0.6构建产物](https://github.com/liamchan-rgb/classroom-boardgame/actions/runs/38222596815/artifacts/11735060890)：需登录仓库账号，包含IPA、日志及校验值，保留至2026-10-15。
- 最新证据：`native/evidence/cloud-build-result-v0.6.json`及`sidestore-name-fix.json`，对应源码提交`d78884dcfe2335373ed0918d2d83543e2a51d00e`。v0.5构建记录保留作为历史。
- 安装、启动、真实投屏、绘本视觉与续签尚未通过，阶段0仍未完成。

## 开发检查

```sh
swift test --package-path native/Packages/ProbeCore
```

这是开发侧核心验证；教师不需要在 iPad 运行命令，也不增加 Windows/Linux 产品端。

Xcode 工程已包含在源码中，无需生成器或 Homebrew。修改工程文件清单后，可通过 `python3 native/tools/generate_xcode_project.py` 重建工程；云端直接使用已提交的工程。

旧 Swift Playground 样例保留在 `stage0/ipad/` 作为历史记录。教师设备上新建空白 Playground App 也会预启动失败，本次实施已改为独立原生 App。
