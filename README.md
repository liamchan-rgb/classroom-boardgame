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

GitHub 私有仓库 `liamchan-rgb/classroom-boardgame` 已创建并完成访问授权，当前开始上传工程并执行 Xcode 27 云端构建。构建与IPA结果以实际工作流记录为准。核心测试结果不能替代 iOS App 编译或真机验证。

## 开发检查

```sh
swift test --package-path native/Packages/ProbeCore
```

这是开发侧核心验证；教师不需要在 iPad 运行命令，也不增加 Windows/Linux 产品端。

Xcode 工程已包含在源码中，无需生成器或 Homebrew。修改工程文件清单后，可通过 `python3 native/tools/generate_xcode_project.py` 重建工程；云端直接使用已提交的工程。

旧 Swift Playground 样例保留在 `stage0/ipad/` 作为历史记录。教师设备上新建空白 Playground App 也会预启动失败，本次实施已改为独立原生 App。
