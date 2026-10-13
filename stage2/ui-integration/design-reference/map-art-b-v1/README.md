# B 晴空学园 · 节点与地图分层素材 v1

日期：2026-10-13。接续设计工作区最新存档，补齐地图视觉，不重做已通过战斗布局。只写独立设计分支design，不改App、GameCore、数值、规则、main或工作流，无新IPA。

交付6个原nodeVisual ID：start/combat/boss/reward/empty/unknown。前五类参考原B头像原创生成HD像素插画，unknown是统一中性轮廓；全套512×512、sRGB、透明PNG，至少10%安全留边。另交6个节点状态层、中性迷雾层、3道路表现和两比例地面／装饰独立层，共20张运行PNG，几何层另有SVG。

previews有7张PNG：地点总览、状态板、两比例适配说明、两个地图模块、未知隐私检查；index.html可离线打开。sources含5张生成原图、提示词、5份标准导出SVG、制作脚本、原设计节点／道路样例与校验。

asset-manifest中的6个nodeVisual沿用原ID与ASCII文件名；其他visualLayer只是视觉文件，不能新增GameCore状态。运行姓名、数字、问号、节点名称、人数和结果由App叠加。PNG整页不能作为App背景接入。

只有已揭示地点加载类型插画。所有未知类型统一使用node_unknown，不能在其下加载Boss／奖励图，迷雾不能作为隐私屏障。未公开道路亦不绘制。普通战斗遗迹、树／长椅和门户是类型象征，不改变实际节点名称或增加休息／传送规则；奖励箱的币图样不代表数量或概率。

本批新素材仍待最终审美确认。旧职业／怪物／物品、基础动画、三轮UI与存档保持原样。本批适配沿用原设计五节点拓扑，不修改游戏地图。

已核对尺寸、RGBA透明、留边、ID、来源拓扑、未知类型公开像素一致及预览。未在App、SwiftUI、用户iPad或实际电视验证。ZIP／远端回读状态以design/archives上传回执为准；索引在design/ARCHIVE_INDEX.md。详细状态、尺寸、交互、适配、授权及恢复说明见annotations。
