# 第一轮UI与美术设计存档

版本：2026-10-12-round1；App参考状态v0.7，非IPA更新。

- 独立分支：`design/ui-art-round1-20261012`
- 设计存档标签：`archive-design-ui-art-round1-20261012`
- 本次修改范围：仅 `design/`
- 方向状态：A晨光森林/B晴空学园待教师确认
- 完整文件：`design/ui-art-delivery/`
- 完整ZIP：[classroom-ui-art-round1-20261012.zip](archives/classroom-ui-art-round1-20261012.zip)
- 大小：26459491字节
- SHA256：`36267724f073c05001fe3e2590da8fce38ead1ae61bcc04685892ca176d8a8e5`
- 清单：ZIP内部FILE_CHECKSUMS.json；外部manifest与zip.sha256
- 检查：13张预览；7角色/10单位；12中文/24英文；两公开比例；透明PNG留边、字号和对比度；ZIP CRC与逐文件SHA通过
- 原生/真机：没有新构建，没有新IPA，尚未验原生材质、电视观看距离或实际PPTX
- 仓库基准main提交：`f43439ae212757631d03e4869e932e72b1dcd1da`
- 远端上传状态：已推送，并从GitHub新克隆回读完成；ZIP CRC、全部75个载荷文件SHA256和远端展开文件一致性通过。完整ZIP含76文件。
- 设计快照提交：`5b445c290df23e34fdc07d4b754ad8707117ad33`
- 独立标签已在远端确认指向该快照
- main回读：仍为`f43439ae212757631d03e4869e932e72b1dcd1da`，本轮未改变

大面板毛玻璃、小按钮原生液态玻璃/纯色、独立公开投影、运行文字与数字由App生成，详见交接说明。原规则/职业/技能/费用未修改。头像4张为小批风格备选，资源图标6套；其余4职业/6怪物清单中的未制作项、18物品与地图装饰仍按批次推进。

本轮按用户指定design目录保存；通用工具要求IPA及其他归档分支，与本轮边界冲突，解释与恢复步骤见ui-art-delivery/annotations/08_recovery.md。没有改main、App源码、GameCore数据或工作流；工作流只有手动触发，未触发构建。

## 新窗口审图交接 · 2026-10-12

- 提示词：[image-review-start_20261012.md](handoffs/image-review-start_20261012.md)
- 新增交接ZIP：[classroom-design-review-handoff-20261012.zip](archives/classroom-design-review-handoff-20261012.zip)
- 新增ZIP SHA256：`30885d6217419253d6a15ff01956466d54d03ee04af26d32abb401757f0b14c3`
- 标签：`archive-design-review-handoff-20261012`
- 仅新增状态总结与提示词；原13张图、原设计ZIP、原设计标签不变。

## 第一轮审核意见与第二轮UI修订 · 2026-10-12

- 审核意见：[round1-review-feedback_20261012.md](reviews/round1-review-feedback_20261012.md)
- 意见上传提交：3543a2022b477c5a951eb50db39fb7e66ab10004；标签archive-design-review-feedback-20261012。先上传并回读确认，再开始修改。
- 意见存档ZIP：[classroom-ui-art-review-feedback-20261012.zip](archives/classroom-ui-art-review-feedback-20261012.zip)；SHA256：31f592d1dccf704d0ffd9aced641b07e2996ea46a146ad2970ef6ab4a309d208
- 用户确认：B晴空学园；教师布局通过；公开战斗右区展开/地图收窄/玩家卡缩小；绘本单条状态区、队伍颜色+非颜色标识、计时仅启用时显示。
- 新版设计：[ui-art-delivery-round2/README.md](ui-art-delivery-round2/README.md)，12张新版预览，仍待教师审图。
- 新版快照提交：352afb2625cbb54102a58398beaae276d7273ef8
- 新版标签：archive-design-ui-art-round2-20261012
- 新版ZIP：[classroom-ui-art-round2-20261012.zip](archives/classroom-ui-art-round2-20261012.zip)；16816126字节；SHA256：4d2396660f0fb76012cdcfa57401d6aec61525faebfd137883143286f92d171a
- 文件数：64，载荷63，静态尺寸/实际字形/安全区/全姓名/资源字段/原素材哈希/ZIP CRC及逐文件SHA通过。
- 上传状态：已从GitHub新克隆回读核验，ZIP SHA256/CRC、全部63载荷SHA256与远端展开文件一致；回执见archives/round2-upload-receipt.json。
- 原有第一轮图、ZIP、标签不变；本轮只写design，未改App、GameCore、main或工作流，未构建IPA。
- 未验证：原生玻璃、触控效率、电视距离、运行隐私、实际PPTX及人物动画。本轮没有制作新职业/怪物头像或动画。
- 后续每次实际更新均上传、创建新版本/ZIP/唯一标签，并回读核验；旧版本保留。

## 第二轮审图进度01 · 2026-10-12

- B教师战斗屏通过；其余第二轮图待审。
- 记录：[round2-review01_teacher-approved_20261012.md](reviews/round2-review01_teacher-approved_20261012.md)
- 标签：archive-design-ui-art-round2-review01-20261012
- 恢复ZIP：[classroom-ui-art-round2-review01-20261012.zip](archives/classroom-ui-art-round2-review01-20261012.zip)
- ZIP SHA256：2d0831377d992b900622f32bd60f472c5783117b9667063a5248d62efbb6ac3c
- 本次只记录审核反馈，图片与App未改。

## 第二轮审图意见02 · 2026-10-12

- 公开16:9图待修改：去图例、图形队列附玩家区、公开完整角色技能、一次淡入淡出反馈、教师专用全局明细。
- 意见：[round2-review02_public-changes_20261012.md](reviews/round2-review02_public-changes_20261012.md)
- 标签：archive-design-ui-art-round2-review02-20261012
- ZIP：[classroom-ui-art-round2-review02-20261012.zip](archives/classroom-ui-art-round2-review02-20261012.zip)
- SHA256：73796b56419cac3236e48688b88189a4aa720366244254ad64411873ac88be18
- 本意见先于第三轮图片修改上传。

## 最新审图意见03 · 2026-10-12

- 战斗优先，下方仅头像队列常驻，玩家回合展开紧凑技能/道具/资源；不重复姓名。替代前一次公开常驻七人卡布局。
- 意见：[round3-review03_compact-active-turn_20261012.md](reviews/round3-review03_compact-active-turn_20261012.md)
- 标签archive-design-ui-art-review03-20261012
- ZIP：[classroom-ui-art-review03-20261012.zip](archives/classroom-ui-art-review03-20261012.zip)；SHA256：2435f2853b5e7980141e0f299e1128297b60cf0ed0b0075146b4f5cc9d337fba
- 制作中的第三轮图尚未通过，按此意见继续修改。

## 第三轮公开端紧凑版 · 2026-10-12

- 新版：[ui-art-delivery-round3/README.md](ui-art-delivery-round3/README.md)
- 修改：战斗区优先；完整头像队列附玩家区；无下方姓名/图例；玩家回合紧凑展开技能/道具/资源，怪物回合收起；数值变化只一次淡入淡出。
- 教师整场明细和公开防重复行为记录在交接，尚未实现App功能；第二轮教师屏字节保持已通过版本。第三轮公开稿仍待审核。
- 来源：意见02、03均先上传并回读；以最新意见03覆盖常驻七人卡布局，绘本仍保留七人姓名六字段、无AP。
- 设计快照：4536362c0b77bc5def237fb6bedeb76df99807da
- 唯一标签：archive-design-ui-art-round3-20261012
- ZIP：[classroom-ui-art-round3-20261012.zip](archives/classroom-ui-art-round3-20261012.zip)
- 大小：34520140字节；SHA256：356f5933e82358de9cd446749ccdc8b88a5a328ceaa3b29a2914cfc6224febef
- 文件：81；载荷：80；预览：16张。
- 检查：字形边界/相交、5%安全区、当前全名、绘本七人全名/无AP、完整队列ID顺序、技能原JSON、教师图及独立素材哈希、ZIP CRC及逐文件SHA通过；两比例离线文字演示一次播放和同ID不重播通过。
- 上传：已从GitHub新克隆，ZIP SHA256/CRC、全部80个载荷SHA256与远端文件一致；旧两轮ZIP和已通过教师图不变。回执见archives/round3-upload-receipt.json。
- 未验证：系统玻璃、TV最远可读性、App公开技能/一次提示/全局明细、实际PPTX、人物动画。只改design，无IPA，旧版本/ZIP/标签/main不改。
