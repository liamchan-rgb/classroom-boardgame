# 恢复、来源与状态

本轮交付差异只在design/map-battle-ui-b-v4新增，旧design目录、旧ZIP、旧标签及main不被本轮写入。制作时main有并行v0.10程序更新，已合入本设计分支以保留最新成果；相对最新main没有App/GameCore/工作流差异，源App不作为设计提取对象。按用户明确隔离范围和设计AGENTS采用本目录独立ZIP、SHA256、唯一标签、固定提交与回读回执；不修改main/archives或archive-assets分支，不构建IPA。

ZIP包含本轮资料、PNG/SVG、脚本、manifest、预览与验证记录；SHA256/逐文件清单随包。ZIP不包含自身、上传回执或源码固定提交的循环引用。先验证CRC和所有FILE_CHECKSUMS项，再解压，打开previews/index.html或PNG；独立资产按asset-manifest提取。完整恢复也可git checkout唯一标签，原App基线仍用最新main。

原素材来自main本地Art，它们来自固定旧设计提交；sources/reuse-manifest记录每张原文件SHA与整画布等比缩小方法。原生成素材适用OpenAI服务条款，无第三方游戏拷贝；本轮原创SVG/像素/几何可随项目本地使用和修改。只参考经典战棋的空间组织和分层2D观感，没有复制火焰纹章/八方旅人的角色、地形、地图、图标或界面资产。

预览Noto Sans CJK SC为环境本地字体，只交渲染结果、不打包字体；运行系统字体。本轮PNG全离线，源SVG嵌入本地画布导出的图像；HTML示例嵌入允许的公开资源，没有远程资源依赖。

状态分别记录：制作候选已交；静态/离线浏览器检查见evidence；**新审美待审、SwiftUI接入未做、真机效果未验**。像素pilot的造型一致性/方向自然度未最终确认，其余8模板方向肢体帧明确待制作。原详细造型仍保留，新小样不覆盖原稿。

未测iPad Material/液态玻璃、实际电视最远距离、无线断连、系统无障碍/焦点行为、移动到达调度、原生解码峰值或帧率、真实PPTX。资产解码估算是RGBA字节计数，不是运行内存实测；App按场景加载所需小图，禁止每回合解码整库。

存档成功只在远端回读ZIP SHA、CRC、逐文件与git树一致，并确认标签指向设计源码快照后报告。恢复回执与ARCHIVE_INDEX收尾属于同一步，不再归档一次。
