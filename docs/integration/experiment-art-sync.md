# experiment 美术更新 → classroom-boardgame 接入约定

此文在两个仓库保存，供后续生成/接入 agent 直接阅读：

- 美术源仓库：[liamchan-rgb/experiment](https://github.com/liamchan-rgb/experiment/tree/fix/build33-face-grounding-camera)，规范镜像 `docs/integration/classroom-art-sync.md`。
- 课堂运行仓库：[liamchan-rgb/classroom-boardgame](https://github.com/liamchan-rgb/classroom-boardgame/tree/feat/teacher-backend-meadow-v0.13)，本文 `docs/integration/experiment-art-sync.md` 为接入规范原件。
- experiment 制作人物/骨骼/衣装/武器/配饰/怪物/技能特效/环境光影/公开战斗UI；课堂端负责承接其已完成的视觉成果，并保留教师后台、绘本、6学生+老师P7、组队、存档与公开权限边界。

**当前不是实时链接或自动热更新。** experiment 提交素材后，课堂IPA不会自动变化。每轮同步固定完整提交SHA，按清单接入、检查、编译并发布新的课堂IPA。用户本次要求建立后续对接约定，不等于已要求接入尚未交付的未来美术。本轮不更新美术基线。

## 1. 接入基线与记录

当前课堂资源基线为 experiment `175c7dfc4a68e62cb9693da8d837b77081619a6b`，记录在 `native/ClassroomProbe/Resources/meadow-port-provenance.json`，568个源文件SHA；课堂端的七人/权限/镜像/档案适配已继续演进，不能用这个旧源提交回写覆盖课堂代码。

美术作者完成一次更新后，提交一份按 `docs/integration/classroom-art-update-template.json` 填写的变更说明；至少包含：完整sourceCommit、涉及的组件、源路径/派生资源/元数据/代码依赖、动作/方向/帧数与节奏、兼容性、正常速度GIF和仍缺失内容。草稿/工具生成/内部agent审核不等于用户认可；逐项记录真实认可范围，不擅自扩大。

课堂接入者在 `docs/integration/experiment-art-sync/<日期>-<组件>.json` 记录实际来源与去向：逐文件源提交/源路径/目标路径/SHA256、代码合并说明、旧标识迁移、检查结果、课堂编译提交/run/artifact、正常GIF、直接IPA及可恢复归档。新文件、删除、重命名必须列出；删除需确认无存档/目录引用，重命名需别名或迁移，不能直接丢弃旧角色、装备或技能ID。

资源可分批来自不同源提交。保留逐文件来源，不把未更新文件冒记为最新提交；`meadow-port-provenance.json` 的全局commit只有在整套来源一致时才整体推进，否则保留原基线并通过每轮接入记录/逐文件sourceCommit说明混合来源。更新包检脚本以验证实际分文件来源；不能为了通过旧的568文件/281名称断言而漏掉新素材或伪造旧哈希。数量随实际更新清单调整，所有发布资源逐文件校验。

## 2. 实际路径与同步单元

| experiment 源路径 | classroom-boardgame 目标 | 同步方式 |
| --- | --- | --- |
| `Sources/Resources/Assets.xcassets/<名字>.imageset/`、`.dataset/` | `native/ClassroomProbe/Resources/Assets.xcassets/` 同名目录 | 图像/数据与Contents.json成套；记录新增/删改，不混入审核图或白底说明图 |
| `Sources/Resources/hero-gait.json` | `native/ClassroomProbe/Resources/hero-gait.json` | 图集布局、八向行走、帧号/脚底/装备绑定与图集一并更新 |
| `Sources/Resources/SceneMap.json` | `native/ClassroomProbe/Resources/SceneMap.json` | 仅共享场景模板；校对节点/建筑锚点，不覆盖教师生成地图与已存行程 |
| `Sources/Game/*.swift` | `native/ClassroomProbe/Meadow/Game/` | 逐文件三方比较，合并视觉变化；保留课堂新增逻辑 |
| `Sources/GameViewController.swift` | `native/ClassroomProbe/Meadow/GameViewController.swift` | 仅移植视觉相关差异，禁止整文件覆盖教师路由/镜像/输入适配 |
| `Sources/UI/*.swift` | `native/ClassroomProbe/Meadow/UI/` | 合并公开呈现，权限表单仍走教师私有窗口 |
| `Sources/ShadowLab/*.swift`、`.metal` | `native/ClassroomProbe/Meadow/ShadowLab/` | shader、参数与调用者成套，检查固定画布/投影/镜像读回 |
| `Vendor/ClassroomGameCore/Sources/MeadowBattleSupport/` 及其 `Resources/` | `native/Packages/GameCore/Sources/MeadowBattleSupport/` | 骨架/姿态/特效阶段等呈现模型与JSON配套，合并目录/装备变化 |
| 新字体、音效或其他资源 | `native/ClassroomProbe/Resources/` 中明确目录 | 检查使用授权和加载路径；补Xcode资源phase/包资源清单后再发布 |
| `Art/`、`Media/` 的源稿与审核GIF | 课堂 `docs/integration/.../` 证据或独立交付归档 | 用于理解/检查，不当作实际帧图拷进App |

`Sources/AppDelegate.swift`、`Info.plist`、AppIcon、experiment的`project.yml`/打包脚本属于应用壳层/标识，不能随着美术批量覆盖课堂入口、Bundle ID、版本、部署设置和构建流程。AppIcon等若确有更新需求，单独评估品牌与课堂App身份。

`Vendor/ClassroomGameCore/Sources/ClassroomGameCore/`、`MeadowWorldSupport/` 不能整目录反向覆盖课堂规则/存档：课堂端已加入7人、组队独立移动条、GM、档案槽、导入导出等。若视觉确实依赖新增技能/装备字段，单独合并必要目录定义和兼容代码，运行存档迁移检查；不能把美术改动顺带变成未说明的数值改动。

## 3. 各类资源的配套要求

### 人物骨骼、衣装、武器和配饰

1. 八方向图集/动画元数据、战斗分层PNG、骨骼/姿态JSON、Swift采样/遮挡顺序要成套。重点包括 `HeroFrames.swift`、`WalkCycle.swift`、`MeadowBattleActorView.swift`，以及 `BowRig.swift`/`GreatSwordRig.swift`/`LegendaryStaffRig.swift` 和对应Resources JSON。
2. 明确画布像素、单位、根节点/脚底锚点、左右手握点、装备挂点、前后遮挡与镜像规则。改骨骼/尺寸时同步阴影轮廓、受击点、护盾中心、粒子挂点、法杖/弓/剑握持，不能只换PNG；已有衣装/配饰须跟新骨架复核。
3. 行走8方向及开始/循环/停止、攻击/受击/格挡/倒地/胜利等已有动作保持标识兼容。每种已支持装备与基础衣装/皮甲/符文甲组合，检查全身1×/2×与正常速度循环；逐侧看肩—肘—腕、髋—膝—足、衣口/裤口/腰带和剑背部遮挡。检查所有当前可用人物与P7，不能回到硬编码两名演员。
4. `GameUnit.appearance`、档案中的body/outfit及实际装备ID是持久化协议。新增外观同步选择器、白名单、HeroFrames绑定、资源预载/缓存和旧档回退；纯装扮不能赋予装备属性，实际武器仍由装备驱动。独立女性/体型/发型等缺图只登记，不自行生成。

### 技能特效、粒子、光影与怪物

1. 同步RGBA帧图、帧序/时长、特效载入、技能ID映射、空间坐标和阶段事件。使用现有近身/远程动作，按命中时刻、目标部位挂载，不擅自新增动作来规避对接问题。
2. 保留已经确定的触发规则：强度对应压暗；选定技能停止骰子并平滑摆正；命中处伤害数值；施放后地圈退场；盾/治疗在技能动画后半段生成；治疗光线随强度分档并螺旋上升；死亡粒子在HP归零与数字同时启动并向右散，血条同时隐藏。若源稿改变这些时序，须明确列出新旧差异并按用户最新要求处理，不能因换图倒退。
3. 粒子颜色/运动/地面碰撞、环境照明/高光/暗场与主特效一起同步；持续特效跟随同一人物根节点，地面残片留世界空间。怪物比例/压迫感沿用已确认要求；死亡/受击/蓄势等视觉与正式怪物回合模型共用，不再开一个训练引擎。
4. 如需改变治疗分档阈值、技能数值、AP/装备属性，作为规则变更另列，不用视觉同步悄悄改规则。测试目标帧率配置与时间采样，不把离线GIF或Release成功称作设备稳定60FPS。

### UI、字体、技能卡与公开展示

共享的是游戏美术与公开布局。课堂教师管理、GM、地图生成/节点修改、存档/导入导出、备注、系统文件窗口都仍私有；公开端只展示地图/战斗/只读行囊和怪物预览/绘本状态。不得导回experiment里可直接编辑规则的公开按钮。

保留1280×720逻辑画布、固定Metal像素/相机契约、教师同画面镜像及原技能卡命中路由。改技能卡/字体/人物站位时，同步实际卡片frame命中、教师手势的留边/坐标映射、多人血条/行动值/头像区域；测试6学生+老师P7和1—2人旧档。绘本状态总占画面9%的上限不随游戏UI美化挤占绘本主体。教师镜像30Hz/960×540与公开60Hz仍是目标，不是实测承诺。

## 4. 可执行接入流程

1. 先读两仓库AGENTS，检查分支与未提交改动；固定本轮源完整SHA和上次对应组件基线，不抓浮动HEAD或拷贝未提交工作区。源仓库工作分支`fix/build33-face-grounding-camera`，课堂分支`feat/teacher-backend-meadow-v0.13`。
2. 在课堂仓库生成只读盘点（不会同步或改文件）：

   ```bash
   python3 tools/plan_experiment_art_update.py \
     --experiment /workspace/experiment \
     --from-commit 175c7dfc4a68e62cb9693da8d837b77081619a6b \
     --to-commit <本轮experiment完整40位SHA> \
     --output /workspace/experiment-art-update-plan.json
   ```

   后续把`--from-commit`换成对应组件上次已接入基线。报告列出新增/修改/删除、实际目标路径、源旧/新SHA256、课堂当前SHA256、已与新版相同的文件和课堂本地适配差异。它不做apply，也不保证自动发现所有跨文件依赖；结合作者清单补齐未映射/新类型文件。
3. 按上表和依赖清单选择文件。纯资源可从固定提交导出候选文件；代码用“当前课堂文件 / experiment旧基线 / experiment本轮版本”做三方比较，人工合并视觉变化并处理冲突。禁止直接cherry-pick整个experiment提交、rsync整个Sources或覆盖Vendor包；这些都可能带回旧双人/公开编辑/存档版本。
4. 更改新增Swift/Metal/字体/音效或包资源时，更新 `native/tools/generate_xcode_project.py`、生成工程/资源phase及SPM Package.swift（需要时），执行工程一致性检查。处理名字/骨骼/技能数据的兼容与孤立引用，再更新准确的资源来源清单。
5. 主线程审核实际装配后的全身、正常速度GIF、关键帧和整场层次；发现问题自己修，不把agent产物或编译通过当美术认可。对缺失素材只列待补项。纯规则/姿态/特效/存档专项与全部核心回归通过；静态检查教师/公开路由及7人适配。按AGENTS仅离线审核与设备Release归档，不运行App/模拟器/实机；实际iPad/电视截图由用户反馈。
6. 归档设备Release并核对实际run/源码/artifact、CRC/经典ZIP2.0/arm64/权限/版本/Metal/资源/骨架JSON。明确本轮美术源SHA和课堂实际编译SHA，完整GET校验公开IPA字节/SHA256。直接交IPA，不把ZIP当安装包。
7. 两仓库更新AGENTS/迭代记录与该轮接入清单，附实际正常速度GIF、HTTPS动图直链、IPA、未验证事项与可恢复归档。源码/美术基线/旧版本可恢复；回退只撤回所选视觉同步，保留新课堂权限与教师设备存档，不整体重置工作分支或覆盖用户未提交改动。

## 5. 本轮状态

v0.18.0/build23只落实分类筛选、对接协议、变更模板与只读盘点工具；没有导入新的experiment美术、没有推进175c7dfc资源基线，也没有为缺失资源补画。以后由experiment产生新美术并提交清单后，按本协议接入新的课堂IPA。
