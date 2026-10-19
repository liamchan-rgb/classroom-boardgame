# 侧视战斗场景实验 · v0.11

把已确认的侧视接触姿势接入此前的 iPad 桌游 App，做成可安装的战斗场景实验。构建号为 0.11（11），地图、战斗面板、回合队列、技能物品栏和现有规则仍在同一应用内。

## 场景内容与边界

- 左侧固定显示已确认的 `heavyStrike + trainingSword` 接触姿势样片，右侧显示本局地点中已公开的敌人；背景由远景、遗迹轮廓、地面和前景组成。
- 样片在界面中标为“侧视动作样片”和“接触姿势·单帧”。顶部当前行动者姓名、回合、队列、同行/敌方生命与护盾均来自实际战斗快照；样片不代表当前行动者的职业外形或技能触发。
- 4:3 布局曾把同行生命/护盾挤成省略号，现已缩紧状态行并通过最终模拟器截图复核。16:9 与 4:3 成图中，人物与剑完整可见，队列、状态栏及下方技能/物品仍在。
- 游戏规则、伤害、骰子、技能触发、敌人选择和存档格式没有改变。接触姿势是静止原型；本版没有攻击起手、挥砍、受击或命中结算动画。

用户确认范围仅是这张接触姿势的镜头、人物侧面轮廓和向前握剑姿态；不是对本版背景、敌方素材、完整战斗构图或正式动画的美术验收。

## 模拟器预览

[16:9 横屏预览](evidence/public-side-battle-scene-16x9.png) · [4:3 横屏预览](evidence/public-side-battle-scene-4x3.png) · [24张截图检查报告](evidence/simulator-report.json)

## iPad 实验包

- IPA：`ClassroomStage2-v0.11-unsigned.ipa`，10,996,063 字节，SHA256：`e22dd2c5e5a59897d6a067b7ccf41e17661157bed1fd8a70d1cb89e843edd4ba`。
- Bundle ID：`org.personal.classroom.stage0`；arm64；最低系统 iPadOS 27；包未使用设备证书签名，需用 SideStore 和个人 Apple ID 签名后安装。
- 云构建： [GitHub Actions run 39229688707](https://github.com/liamchan-rgb/classroom-boardgame/actions/runs/39229688707)，源码编译提交 `01265f2d504fe19a33d39843dc7c7e40791eba43`。GameCore 72项、ProbeCore 6项测试通过；66个素材校验通过；模拟器生成24张原生截图。
- 完整构建证据：[cloud-build-result-v0.11.json](../../native/evidence/cloud-build-result-v0.11.json)。模拟器截图不是实体 iPad 验收；本包尚未在实体 iPad 上安装验证。

长期备份已完成：[直接下载IPA](https://github.com/liamchan-rgb/classroom-boardgame/blob/83a0c1ca02badf0534ef7208084b11e90cb30e5d/archive-stage2-battle-prototype-v0.11-20261019/ClassroomStage2-v0.11-unsigned.ipa) · [完整源码与诊断存档](../../archives/archive-stage2-battle-prototype-v0.11-20261019/README.md) · [远端恢复校验](../../archives/archive-stage2-battle-prototype-v0.11-20261019/verification.json)。

安装后恢复或新建一局，在地图中进入已有战斗，即可在地图旁看到横版场景。建议优先检查动作样片与敌人的距离、4:3/16:9下状态文字大小、场景亮暗对比，以及原有回合和技能面板是否容易操作。当前样片不播放慢动作。

接下来先用实体 iPad 确认镜头比例和构图，再固定人物脚底、武器握点和目标锚点，制作待机、起手、挥砍、受击与收势关键帧，并逐项连接到真实战斗结果。当前用户反馈仍未获得。
