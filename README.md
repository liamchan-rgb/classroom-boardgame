# 英语课堂电子桌游

实施路线：**独立原生iPad App → GitHub Xcode27云端构建 → SideStore免费个人签名与续签**。纯自用，不使用TestFlight，不需要购买Apple Developer Program。

教师已反馈v0.6各功能正常，并同意继续。当前进入**阶段1：规则计算、数据与完整操作结算**。原始两份文档在 `docs/`，保持不变；[实施计划](实施计划_v2.md)、[技术验证](技术验证.md)、[阶段1验收](stage1/阶段1验收.md)。完整PVE操作界面从阶段2接入。

## 当前交付

- `native/ClassroomProbe.xcodeproj`：iPadOS27原生App工程。
- `native/ClassroomProbe/`：教师控制台、电视公开场景、键盘、基础离线绘本、备份；v0.7新增规则示例与初始资料。
- `native/Packages/GameCore/`：独立规则计算、4职业/19技能/18物品/2套装/6怪物的校验数据、原子结算、版本化存档、完整历史与可控随机。
- `native/Packages/ProbeCore/`：PPTX离线解析及原阶段0核心。
- `.github/workflows/build-native-ipa.yml`：手动构建，测试两个核心库，再生成待个人签名的IPA。
- [安装与真机验收](native/安装与真机验收.md)：SideStore覆盖更新与免费7天续签。

安装名继续使用ASCII `ClassroomProbe`，保留中文界面和Bundle ID，避免v0.5中文appIdName签名失败，并用于覆盖更新。v0.7云端构建结果在完成后记录到 `stage1/evidence/`；App新增界面仍需本次真机核对。

v0.6历史成功构建：[工作流38222596815](https://github.com/liamchan-rgb/classroom-boardgame/actions/runs/38222596815)，证据见 `native/evidence/cloud-build-result-v0.6.json`。阶段0教师反馈见 `stage1/evidence/stage0-teacher-feedback.json`。复杂PPTX母版、图表、组合及字体的完整兼容仍在阶段6处理。

## 开发检查

```sh
swift test --package-path native/Packages/GameCore
swift test --package-path native/Packages/ProbeCore
```

这是开发侧验证，不增加Windows/Linux产品端，也不要求教师运行命令。修改App文件清单后用 `python3 native/tools/generate_xcode_project.py` 重建已提交工程。Xcode项目无需XcodeGen或Homebrew。

旧Swift Playground样例在 `stage0/ipad/`，仅保留历史；当前App不再依赖该宿主。
