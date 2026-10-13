# 晴空学园 · 大地图 / 战斗 / 连续轨道 v4

2026-10-13，**待审设计候选**。本轮最新 feedback 与 visual-expectations 覆盖旧地图、底栏布局意见；历史通过记录与旧资产保留。只新增本目录，没有App、规则、存档格式、工作流修改，没有IPA。

独立分支：`design/map-battle-ui-round4-20261013`。起始main：`5a7910eadd66dbb492ef9641c7deca937eee30ad`；制作期间同步保留最新main `1a4a6014278c5e14ff4b1527bbe91239e0a330f1` 已有v0.10程序成果。旧美术固定提交：`f43db0502bf3a9df9fef8bb7c699b6dce86c3425`。本轮固定快照、唯一标签、ZIP及回读记录见 [ARCHIVE_INDEX](ARCHIVE_INDEX.md)。相对最新main的交付差异只有本design新目录；不要合并本分支App作为开发基线，只提取本目录资产和设计资料。

## 主预览（全部待审）

| 状态 | 1920×1080 · 16:9 | 1440×1080 · 4:3 |
|---|---|---|
| 探索大地图 | [探索16:9](previews/public_exploration_16x9.png) | [探索4:3](previews/public_exploration_4x3.png) |
| 玩家战斗 | [玩家16:9](previews/public_player_16x9.png) | [玩家4:3](previews/public_player_4x3.png) |
| 怪物战斗 | [怪物16:9](previews/public_monster_16x9.png) | [怪物4:3](previews/public_monster_4x3.png) |

探索没有右侧战斗、战斗计时或虚构回合轨道；地图占据释放空间。玩家回合附加独立技能/个人物品栏；怪物回合收起，地图和战斗增高。战斗轨道为完整原混合次序7玩家+3怪物，连续连接线、已行动勾、当前指针、倒地叉和下轮时钟，不是AP条或胜率。

顶部当前全名、生命/最大生命、护盾、金币、积分、队伍保留，状态不显示AP。技能原费用仍显示。探索顶部明确为“地图查看”的公开查看对象，使用最新main的cameraFocusID，不能直接冒用教师私有选择。预览采用独立布局fixture，不是假称从GameCore提交的游戏结果。

地图是原PVEGameFactory的5节点与公开道路子集；本轮没有另造方格规则。已知地点在镜头外时保留对应公开道路方向提示，角色沿真实节点定位；同节点10单位逐个显示稳定ID，不以人数代替位置。缩放示例的离屏P7方向由实际坐标计算。

## 交接与检查页

- [教师镜头与商店入口规划](previews/teacher_camera_and_shop.png)：iPad等价控制，公开电视只读；商店未实现，本轮只规划入口。
- [空背包、18物品分页、身份与离屏聚合](previews/edge_cases.png)。
- [最长龙骑士技能与第4套装技能](previews/long_skills_and_set.png)：信息不删减，4:3采用两张/页。
- [地图尺度与全身动作小样](previews/sprite_scale_and_motion.png)：冒险者+史莱姆先行验证。
- [分层2D交接](previews/hd2d_layers.png)：背景、树冠、地面、前景、接地阴影与光晕。
- [离线总览](previews/index.html)、[镜头/移动到达/侧栏展开/攻击/恢复终态演示](previews/camera_transition_demo.html)。HTML是设计样例，未实现SwiftUI控制或游戏结算。

## 可接入独立资源

完整清单：[asset-manifest.json](asset-manifest.json)。运行PNG全部本地，ASCII文件名，文字/姓名/数字/队伍/数量/问号/按钮标签由App绘制。

| 类别 | 交付 | 状态与用途 |
|---|---|---|
| 原实体/节点/图标 | 4职业、6怪物、18物品、6节点、6图标，40 PNG | 原完整透明画布等比小尺寸导出；头像不裁成假全身。主预览使用原造型；原图不改 |
| 原特效 | 12套8帧PNG，2048×256 | 原字节复制，原manifest ID；不追加第二套伤害/资源数字 |
| 像素动作试作 | 冒险者、史莱姆，各1024×256四方向sheet；各64×64 idle | 原创可编辑SVG，16帧/方向；4职业/6怪物中的其余8模板完整方向肢体帧**待制作** |
| 分层场景 | 4张1024×640场景层，阴影128×48、光晕128×128、地面模块256×128 | 原创SVG+PNG；背景不透明，其余透明；只非语义环境可裁切 |
| UI模块 | 箭头、轨道指针/端帽、镜头定位、商店入口，各64×64 | 原创透明SVG+PNG，无文字。商店只是规划 |

复用完整画布缩小后人物可见轮廓偏小，已另交192px运行版本并给实际alpha锚点；不能把它们称为已经完成自然行走。两张像素sheet是方向/肢体节奏的试作，审美与原造型一致性仍待审，未自动替换正式素材。先审小样，再决定其余8模板制作；不虚称全套已齐。

没有弱点、破防、增幅、地形费、传送、新奖励、新怪物、经济规则或3D演出。所有动态仅表现已提交结果一次，恢复/重连直接终态，减少动态关闭位移、震屏、视差和粒子。具体时序见 [动画注解](annotations/02_animation_and_layers.md)。

## 真实接口适配

[接口及隐私注解](annotations/03_projection_and_privacy.md)已更新到最新main：nodeID/x/y/queueIDs可用于地图及轨道；currentDetails已有原费用/效果/余次及物品数量，v0.10另已增加available/unavailableReason/detail、camera/cameraFocusID/itemPage/followsCurrent、mapMoves/opensBattleAfterArrival。本轮只建议把新资产和尺寸绑定到这些既有显示接口。剩余适配包括像素帧/锚点/场景层、技能展示分页、物品更完整限制说明、拥挤边缘聚合和本轮字号；不把已有程序功能写成缺项，也不把本稿写成已原生接入。不得改GameArchive或技能规则。

场景阵位是原战斗节点上的视觉放大，只有同节点单位进入阵位；远处玩家留在地图与轨道，不被传送。这里10单位密度fixture均在node2。超过当前阵位容量需视觉分页/额外行，不能改变参战或隐藏轨道单位。

绘本沿用原通过方案：七人完整姓名和六字段、无AP、原页aspectFit不裁切，不被本轮技能栏侵占。保留奖励独立对象、暂停原因/剩余时间、键盘焦点保护；新教师镜头控件不改这些行为。

## 复建与验证

Python3/Pillow、Inkscape、Playwright/Chromium、本地Noto Sans CJK SC。依次运行 sources/build_delivery.py、export_and_check.py、build_demo.py、verify_delivery.py。运行App仍用本地系统字体和Bundle资源，无网络字体。源码和可编辑SVG都在本目录。

已核对实际v0.9原生截图、两比例与原素材来源；检查结果见 [validation.json](evidence/validation.json) 和 [文本边界](evidence/text-bounds.json)。这些是设计导出与浏览器证据，不是iPad无线投影、真实Material、电视最远阅读距离、原生动画/性能或审美通过。没有构建或安装包更新。
