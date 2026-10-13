# 阶段2美术与UI原生接入 v0.9

开发基线：main f43439ae212757631d03e4869e932e72b1dcd1da（v0.8阶段2程序）。设计固定提交：design/ui-art-round1-20261012 的 f43db0502bf3a9df9fef8bb7c699b6dce86c3425。只通过 native/tools/import_art_delivery.py 提取设计文档和66个独立PNG，不合并设计分支App代码，不导入整页PNG。

最新审核意见03/04/05优先；公开战斗头像队列、当前全名和紧凑当前玩家详情，怪物回合收起；公开状态条无AP。技能费用仍只读显示本局原定义，不显示教师尚未提交的动作。绘本保留7人姓名、生命/最大生命、护盾、金币、积分、队伍，完整等比显示页面。

教师保留原操作，直接可达暂停、绘本、编辑、记录、撤销和奖励，独立奖励选择不切回合。原生Material大面板与纯色小控件支持减少透明度；状态用指针、勾选、叉、时钟、合法目标框和明确校验原因表达。

## 实际接入

- 4职业、6怪物：manifest模板ID绑定头像，教师玩家/敌人/当前行动者与公开队列/战斗展示。
- 18物品：全部本地打包；教师只读初始资料和公开实际背包按ID绑定。现有教师道具菜单显示真实持有数量，掉落差额只用一次文字反馈，不增加商店、交易、换装。
- 6资源图标：生命、护盾、行动点、金币、积分、倒地；公开状态不绘制行动点图标。
- 6nodeVisual：未知先选择node_unknown，隐藏Boss/奖励插画不加载；已揭示节点按真实类型和原名绘制。
- 节点current/path/enemy/claimed/crowded/target、中性迷雾与地面/通用装饰：原生地图分层，教师路径/合法目标不进入公开投影。
- 10实体6状态：从character-motion读取参数、锚点、方向和幅度；只改变独立图片的表现。
- 12套8帧表现资源本地打包：impact/shield/heal/revive/natural20/dice6/dice20/rune/flame/projectile按已提交结果展示。coin/score暂不叠加装饰，资源只一条合并淡入淡出文字。
- 整场已提交操作在现有只读记录面板展示，包含原骰子、实际资源前后值和原事件；不增加历史选择回退功能。

## 未接入及边界

道路PNG不拉伸到任意拓扑；真实锚点用原生实线/规划虚线等价绘制。coin/score贴图保留本地，不重复资源提示。装备仅已实现背包/掉落展示，不增加新经济模块。A风格、整页设计预览、在线字体不进入App；运行字体使用iPad系统本地字体。全部来源文档保存在design-reference，旧设计、ZIP、标签不改。

制作候选仍待逐图最终审美；技术接入不表示审美通过。云端编译、模拟器原生截图、结构/接口测试不能替代iPad无线投影、触控效率、玻璃材质、电视最远阅读距离或真实PPTX反馈。

## 结果与存档

[最终云端构建](https://github.com/liamchan-rgb/classroom-boardgame/actions/runs/38345790065)成功，编译提交1379bd2e174d88c582bb19fa8ea1f64c180a74da，Xcode27.0/27A266a、iphoneos27.0。GameCore65与ProbeCore6项测试全部通过。IPA 0.9/9、arm64、iPad设备族2、最低27.0，Bundle ID沿用org.personal.classroom.stage0，须SideStore个人签名；10445942字节，SHA256 7d3a6e27184e5a07876ba769f8f54df8d7651d303c68f034c9e838147945a601。

原生12张截图与66张Bundle素材解码通过，已修正4:3英文长名与小尺寸教师屏奖励栏问题，未知Boss/奖励输入的公开地图像素完全相同。详见[检查及真机步骤](验收与真机检查.md)、[原生截图](evidence/native-previews/README.md)、[构建证据](evidence/cloud-build-result-v0.9.json)、[离线包校验](evidence/asset-verification.json)。公开投影没有AP状态条，技能费用保留本局实际定义；教师未提交选人/技能/目标/路径/奖励勾选不公开。原规则JSON、职业技能数值、费用、GameState/GameArchive存档格式保持原样。

唯一存档标签archive-stage2-ui-art-v0.9-20261013固定源码快照，开发侧[存档索引](../../archives/README.md)记录长期私有archive-assets位置、ZIP与分片校验及独立恢复回执。已交付设计、旧ZIP和旧标签保留。
