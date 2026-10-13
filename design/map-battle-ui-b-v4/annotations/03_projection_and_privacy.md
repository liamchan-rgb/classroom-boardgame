# main真实接口核对与最小显示适配

先核对起始main 5a7910eadd66dbb492ef9641c7deca937eee30ad及原v0.9截图；制作期间main更新，已同步保留并重新读取 `1a4a6014278c5e14ff4b1527bbe91239e0a330f1` 的PublicProjection/PlayProjection/Presentation/MapPresentation、PVEMapView/PVEPublicView和v0.10说明。反馈和规则定义无变化；以下“现有”按最新main写，不将已经实现的接口误写缺项。两个时间点与设计固定基线的读取指纹见sources/reference-read-list.json。

| 视觉要求 | 现有数据 | 尚需开发的显示适配 |
|---|---|---|
| 地图全身落点 | PublicGameUnit.id/templateID/nodeID；PublicGameNode.id/x/y；公开roads；MapCamera/MapDisplayGeometry | 替换运行小图与脚底锚点/肢体帧；同节点offset和离屏提示已有，拥挤时本稿建议聚合/更大字号 |
| 阶段收起/展开 | snapshot.phase；CommittedPresentation.opensBattleAfterArrival；原生已按到达阶段显示 | 新场景/220ms侧栏表现适配；不另设UI开战逻辑 |
| 完整轨道 | queueIDs；unit.current/acted/health/canActFromRound；snapshot.round | 相邻中心连续线；每人仍逐个标状态，不能以数组索引推断资格 |
| 公开技能 | currentDetails.unitID/className；skills.id/name/cost/detail/available/unavailableReason，已由engine.preview生成 | 直接使用已有可用性；新尺寸/长技能分页，不新增allowed字段，不美术层猜测 |
| 个人物品 | items.id/name/quantity/detail/available/unavailableReason，已有frame.itemPage | 本局真实限制更完整描述和新布局；v0.10物品4项/页，本稿6项/页只是显示建议，接入时可保留4项/页、共5页以减少改动 |
| 探索查看对象 | frame.cameraFocusID/followsCurrent，原生header已有“查看”与公共角色状态 | 改布局标签为“地图查看”，只使用公共unit；currentDetails仍只在玩家战斗回合生成，不混入教师选择 |
| 已提交路径 | CommittedPresentation.mapMoves:[PublicMapMove]；points由实际move事件停点过滤；opensBattleAfterArrival | 原接口已具路径与到达展开条件，绑定行走帧和脚底锚点即可；不能另按两端寻路 |
| 一次反馈/恢复 | PresentationLedger key/absolute start/end、suppressHistory | 接续原去重、恢复终态和统一调度；不新增第二套结算、计时或随机源 |

PublicGameUnit.ap虽然存在，公开状态不绘制；技能cost可按原定义文字显示，真实规则失败原因如“行动点不足”可公开，但不主动加入AP数字状态条。

本轮没有新增Swift DTO或修改Swift文件；同步main的程序提交是保留已有开发成果，不是美术实现。若需skillPage或显示句子分行，只能在PublicPlayFrame/显示模型扩展，不借私有Archive键保存分页。原manifest模板ID按稳定ASCII映射，运行unitID做身份，不依赖数组顺序。不要从本分支App合并功能。

MapCamera.screen目前按(width-2inset)/(height-2inset)各轴映射归一化布局坐标，本稿以统一世界scale展示参考空间。接入时由开发明确地图world空间的宽高，再统一视觉等比变换，不能把这条视觉建议解释为修改道路距离/规则。无需为了本稿回退已实现相机/路径/一次播放功能。

## 未揭示隔离

节点首先选revealed ? actualKind : node_unknown；未知kind/name/monster/reward根本不进入画面构图或加载任务，不能先预加载再盖迷雾。公开道路子集保持现有投影过滤；道路两端无公开节点时不绘制，不补猜图。未知Boss/奖励用同一轮廓、同一问号（App文字），颜色/比例/粒子不暗示隐藏类别。

地图标记只用公开players；不显示未揭示怪物。教师规划道路、目标框、奖励勾选、私有备注、掉落概率/后台选择不进入公开SVG/HTML。打包有完整模板资源是离线资产库，不等于公开视图可加载未知资产。演示只嵌入已揭示节点start/combat、unknown、两种pilot、一个公开玩家和环境层，没有隐藏Boss/reward资源。

预览公开地图节点4/5只有unknown；不同隐藏种类应产出完全相同图层。浏览器/设计检查不能替代App DTO隔离测试，接入时继续使用v0.9未知Boss/奖励像素等价与断连隐私测试。

## 行动与查看分离

相机按钮改变显示状态，不调用engine.apply/endTurn/reward；查看P7仍在顶部保留当前行动者并标注镜头是手动查看，不显示P7技能冒充当前。奖励对象的勾选留教师原区，发奖不切回合。未提交选择不会影响public skills/items的可用性展示；合法性理由应是当前公有状态的一般校验，不能泄露教师已选目标。

恢复不扫描历史补播；撤销恢复的资源/轮次/队列以引擎为准，不借轨道动画重新结算。学生决策计时继续原有效时长，教师控镜头不会重启计时或解除暂停。

## 保留范围

原职业/技能费用、范围、效果、次数，装备/消耗/救援规则，NodeReward数量/自动结算、道路1点、自然20、一次提交、原存档与随机状态全部不变。绘本7人姓名与生命/最大生命、护盾、金币、积分、队伍完整保留；原native book两比例PNG只记录基线hash，不覆盖。没有PPTX实测或IPA。

商店issue#2仍未实现；只规划教师入口，不把规划按钮称已接入。完整商店、交易、仓库、换装按原阶段3另做。本分支不修改issue状态、不对外发消息。
