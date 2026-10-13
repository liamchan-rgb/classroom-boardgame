# 英语课堂电子桌游

实施路线：**独立原生iPad App → GitHub Xcode27云端构建 → SideStore免费个人签名与续签**。纯自用，不使用TestFlight，不需要购买Apple Developer Program。

教师已反馈v0.6各功能正常，阶段1已完成且v0.7正常。教师查看v0.9后反馈功能上无问题，界面仍需修改。当前继续**阶段2：地图/战斗显示结构 v0.10**，用现有素材先推进程序，不等待新美术。原始两份文档在 `docs/`，保持不变；[实施计划](实施计划_v2.md)、[技术验证](技术验证.md)、[阶段1验收](stage1/阶段1验收.md)。操作入口见 [快速开始](stage2/快速开始.md)，基础范围见 [阶段2验收](stage2/阶段2验收.md)，新版见[地图与战斗结构](stage2/map-ui-v0.10/README.md)。

## 当前交付

- `native/ClassroomProbe.xcodeproj`：iPadOS27原生App工程。
- `native/ClassroomProbe/`：教师控制台、电视公开场景、键盘、基础离线绘本、备份；v0.8新增PVE操作与本机恢复，v0.9接入B风格本地素材，v0.10增加地图镜头、人物位置/已提交移动、阶段布局、连续轨道和技能物品详情。
- `native/Packages/GameCore/`：独立规则计算、4职业/19技能/18物品/2套装/6怪物的校验数据、原子结算、版本化存档、完整历史与可控随机。
- `native/Packages/ProbeCore/`：PPTX离线解析及原阶段0核心。
- `.github/workflows/build-native-ipa.yml`：手动构建，测试两个核心库，再生成待个人签名的IPA。
- [安装与真机验收](native/安装与真机验收.md)：SideStore覆盖更新与免费7天续签。

安装名继续使用ASCII `ClassroomProbe`，保留中文界面和Bundle ID，避免v0.5中文appIdName签名失败，并用于覆盖更新。v0.7已通过Xcode27.0设备版编译及44项核心测试（游戏38、绘本6），IPA与内置规则资源已校验；教师本次已反馈v0.7“没有问题”，新增界面未提供分项测试日志。

v0.7：[成功构建](https://github.com/liamchan-rgb/classroom-boardgame/actions/runs/38231894206)、[构建产物](https://github.com/liamchan-rgb/classroom-boardgame/actions/runs/38231894206/artifacts/11738378519)（仓库账号登录后下载，保留至2026-10-15）。证据见 `stage1/evidence/cloud-build-result-v0.7.json`，编译源码提交 `26e0c62e76cda7430fce9ac20c33491a014891ee`。

v0.6历史成功构建：[工作流38222596815](https://github.com/liamchan-rgb/classroom-boardgame/actions/runs/38222596815)，证据见 `native/evidence/cloud-build-result-v0.6.json`。阶段0教师反馈见 `stage1/evidence/stage0-teacher-feedback.json`。复杂PPTX母版、图表、组合及字体的完整兼容仍在阶段6处理。

## 阶段2 v0.8

主页面点“进入PVE课堂”。用五节点森林地图探索、开战，选择移动/普攻/技能/道具/救援；当前行动者和奖励对象分开。怪物按策略和技能优先级自动行动，暂停/绘本/编辑/记录时停止。可配置1—6学生及主持人；两个独立验证剧本展示玩家/魔龙D20自然20。

配色和布局开始采用设计令牌；正式美术仍可由设计对话交付后替换。尚不提供商店、正式随机地图编辑、自定义键位和完整存档包。

本地及Xcode27云端GameCore58项、ProbeCore6项通过。v0.8设备版已编译并校验：[成功构建](https://github.com/liamchan-rgb/classroom-boardgame/actions/runs/38248744250)、[构建产物](https://github.com/liamchan-rgb/classroom-boardgame/actions/runs/38248744250/artifacts/11747620718)。编译提交 `aff02aad17fc24b6f76c6ac3e8ce3b4269934f2d`；证据在 `stage2/evidence/cloud-build-result-v0.8.json`。新PVE触摸、键盘与电视排版仍需真机反馈。

## 开发检查

```sh
swift test --package-path native/Packages/GameCore
swift test --package-path native/Packages/ProbeCore
```

这是开发侧验证，不增加Windows/Linux产品端，也不要求教师运行命令。修改App文件清单后用 `python3 native/tools/generate_xcode_project.py` 重建已提交工程。Xcode项目无需XcodeGen或Homebrew。

旧Swift Playground样例在 `stage0/ipad/`，仅保留历史；当前App不再依赖该宿主。

## 阶段2 v0.10

不等待新美术，现有素材上的地图镜头、人物落点/已提交移动、探索与战斗布局、连续回合轨道和玩家技能/物品栏已实现。最终设备构建[38397057874](https://github.com/liamchan-rgb/classroom-boardgame/actions/runs/38397057874)通过；78项核心测试、22张原生截图及IPA本地素材/实际0.10版本校验通过。具体接入、未接入和真机待验见[本轮记录](stage2/map-ui-v0.10/README.md)，长期安装包和恢复存档见[存档索引](archives/README.md)。商店、正式走路帧与新HD-2D场景仍待独立后续工作。

## 美术与UI

已选择B「晴空学园」，v0.9按固定设计提交f43db0502bf3a9df9fef8bb7c699b6dce86c3425接入66张独立本地PNG、原生玻璃面板和一次结果表现，详见[接入清单](stage2/ui-integration/README.md)。新素材是制作候选，未逐图最终审美确认。

v0.10先用现有素材完成[地图/战斗程序结构](stage2/map-ui-v0.10/README.md)，新走路动作与HD-2D场景层可随后按ID接入。[最新反馈](stage2/ui-feedback-round1-20261013/feedback.md)和[美术窗口完整提示词](stage2/ui-feedback-round1-20261013/art-direction-prompt.md)优先于旧布局；原v1[设计标准](design/美术与UI设计标准_v1.md)保留追溯，不能只读main旧设计标准。

## 逐步存档

按教师要求，每个有新成果的交付都建立完整快照、校验清单和恢复说明，保存到本项目私有archive-assets专用分支或可用的私有Release，长期保留。索引见 [archives/README.md](archives/README.md)，后续工作必须遵守 [AGENTS.md](AGENTS.md)。GitHub Actions的3天产物保留不作为长期备份。
