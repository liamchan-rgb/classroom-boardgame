# iOS Pull Request 编译检查

`.github/workflows/ios-pr-build.yml`在每个PR的打开、更新和重新打开时自动运行，包括草稿PR；不设分支或路径过滤。使用本仓库已经成功构建正式App的macOS/Xcode27 Runner标签`xcode-27`，也支持在合并后从Actions手动运行。本配置位于独立CI分支，合并PR后成为后续PR的默认检查。

## 实际工程

- Xcode项目：`native/ClassroomProbe.xcodeproj`。
- 共享scheme：`ClassroomProbe`。
- 本地Swift包：`native/Packages/GameCore`和`native/Packages/ProbeCore`，绘本包依赖固定版本ZIPFoundation。
- 正式App目前最低iOS版本为27.0，Swift语言模式为5.0；两个包的Swift tools版本为5.9。CI保留这些要求。
- `design/`独立美术小样与`stage0/ipad/`旧Playground不作为正式App的构建入口。

## 检查顺序

1. 验证已提交工程与生成器一致，Swift源文件、资源、Info.plist、本地包和共享scheme存在；不会在CI自动重写工程掩盖漏提交。
2. 检查Runner已安装的Xcode；选择设备和模拟器SDK都不低于工程最低系统版本的工具链，通过`DEVELOPER_DIR`用于后续步骤，不写死Xcode安装目录或修改全机Xcode选择。
3. 解析依赖，`xcodebuild`编译Debug iPad App，使用`generic/platform=iOS Simulator`，无需启动模拟器或选择可能不存在的机型。不请求签名，不生成IPA。
4. 分别执行两个核心Swift包的测试。即使App编译或一个包测试失败，另一个包仍可检查；任一步失败都会使整个任务失败。
5. `always()`上传诊断Artifact，保留14天，包括源码提交、Runner信息、工具链、包解析、编译日志、两个包测试日志以及实际生成的`Build.xcresult`。失败前尚未执行的步骤没有对应日志；Runner未能启动时无法生成Artifact。

日志管道启用`set -euo pipefail`并合并stderr，编译失败不会被`tee`误报为成功。最小权限为`contents: read`，不使用Apple账号、证书或仓库签名Secret，不执行`pull_request_target`。

## 静态配置修正

- 首次PR验证实际发现`macos-latest`最高仅含iOS26.5 SDK，选择器明确失败且日志Artifact成功上传，因此最终保留本仓库已验证的macOS/Xcode27标签`xcode-27`。这是仓库特定标签，不宣称所有GitHub仓库均可使用；`.github/actionlint.yaml`允许静态检查此标签。
- 两条workflow共同使用工具链选择器，按工程实际最低系统版本选择SDK；原来仅接受`27.*`的判断已移除，支持更高兼容SDK。
- 手动截图构建不再强制模拟器`ARCHS=arm64`，由Runner与目的地决定架构；补齐`CODE_SIGNING_REQUIRED=NO`和模拟器构建缓存忽略规则。
- 不修改App源代码、规则或最低部署版本。Runner必须具备iOS27及以上设备/模拟器SDK；复制到其他仓库时需选择提供相应SDK的macOS Runner，不能把工具链缺失描述为Swift编译错误。

## 查看结果和本地复现

打开PR的Checks → **iOS PR Build / Build ClassroomProbe**，在相应Actions运行页面下载`ios-pr-build-运行ID-尝试次数` Artifact。`Build.xcresult`可在Mac的Xcode中打开。该共享scheme没有App测试target，所以App步骤是`build`，核心测试用`swift test`；不假称已运行App UI测试或真机验收。

Mac终端可执行：

```bash
python3 native/tools/validate_xcode_project.py
python3 native/tools/select_ci_xcode.py
# 将上一步输出的路径设为 DEVELOPER_DIR，或在 Xcode 设置中选同一工具链。
xcodebuild -project native/ClassroomProbe.xcodeproj -scheme ClassroomProbe \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
swift test --package-path native/Packages/GameCore
swift test --package-path native/Packages/ProbeCore
```

原`build-native-ipa.yml`仍为手动打包/视觉检查流程。PR诊断Artifact是限期日志，长期恢复存档另见`archives/README.md`。

## 本轮实际验证

[PR云端检查38432491033](https://github.com/liamchan-rgb/classroom-boardgame/actions/runs/38432491033)通过：macOS27.0.1、Xcode27.2、iOS Simulator27.2 SDK，正式App Debug编译成功，GameCore72项和ProbeCore6项测试通过。日志及Build.xcresult Artifact已下载、CRC和关键日志核对；详见`native/evidence/ci-pr-cloud-success.json`。记录中分别保留PR head与实际检查出的合成merge提交，源码快照不混作实际构建提交。

## 本地一键构建（scripts/local-build.sh，2026-11-18）

云端`xcode-27`排队与构建较慢时，可在本机Mac运行与`visual-refactor-classroom-ipa.yml`相同的步骤（另加模拟器启动）：

```bash
scripts/local-build.sh            # test + ipa + sim
scripts/local-build.sh test       # 工程/外观校验、tools单测、ProbeCore与GameCore swift test
scripts/local-build.sh ipa        # 未签名Release归档 → artifacts/ClassroomStage2-v<版本>-<提交>-unsigned.ipa（SideStore侧载）
scripts/local-build.sh sim        # Debug模拟器构建、安装、启动并截图 artifacts/simulator-launch.png
SIM_DEVICE="iPad Pro 13-inch (M5)" scripts/local-build.sh sim
scripts/local-build.sh mac        # Mac Catalyst版 → artifacts/ClassroomProbe.app并打开（不在默认三步里）
MAC_OPEN=background scripts/local-build.sh mac   # 后台打开不抢焦点；MAC_OPEN=0只编译不打开
```

- 前提：Xcode 27及以上（选择器同CI），以及一次性安装的Metal Toolchain：`xcodebuild -downloadComponent MetalToolchain`（约839MB；App含`.metal`着色器，缺失时脚本直接提示）。
- 全部日志、IPA、SHA256与截图写入`artifacts/`（已忽略）；脚本不发布Release、不推送、不打标签。提交信息不含`[ipa]`时也不会触发云端打包。
- 模拟器构建额外传`ONLY_ACTIVE_ARCH=YES`：工程未设该项，模拟器默认还会编x86_64并因本地包模块缺失失败；工程文件本身未改。
- 首次本机实测（MacBook Air，Xcode 27.2，提交c113039）：test约3分钟（ProbeCore 13、GameCore 73项零失败），ipa约105秒（v0.32.4/build48，arm64），sim约3分钟并成功启动到教师主界面。仅启动截图，未做功能、电视或性能验收。

## Mac版（Mac Catalyst，2026-11-18）

- 工程由生成器开启`SUPPORTS_MACCATALYST`（`SUPPORTED_PLATFORMS`加`macosx`），Mac用独立的`ClassroomProbe/Info-Mac.plist`（只把`UIApplicationSupportsMultipleScenes`改为true），同一Bundle ID，`[sdk=macosx*]`条件设置本机ad-hoc签名（Sign to Run Locally）。iPad/模拟器的Info.plist、签名设置和IPA流程不变。
- Mac没有iPadOS的外接显示场景（`registerSceneAccessory`在Catalyst不可用，`#if !targetEnvironment(macCatalyst)`隔开）。Mac上教师顶栏多一个“公开窗口”按钮：打开第二个窗口`MacPublicWindow`（同一`PublicSurface`、同一连接计数，不接受点击，与iPad的非交互外接场景一致），拖到投影/电视屏后全屏；再点“关闭公开”或关窗即断开。
- 首次本机结果：Mac Release编译104秒、启动正常；iPad test/ipa/sim全流程复跑通过，模拟器界面无变化。Mac公开窗口的打开/关闭、跨屏全屏、教师端实时镜像与性能尚待用户在真实屏幕上验收。
- 背包/商店（2026-11-18）：这两个界面只在教师窗口打开（需要操作）。公开屏（Mac公开窗口与iPad外接电视相同）改为实时复制教师端正在打开的`MeadowCampaignInventoryViewController`/`MeadowShopViewController`画面（`MeadowPanelMirror`，渲染服务器`snapshotView(afterScreenUpdates:false)`，30Hz，按教师画面比例居中），内容、标签页与选中项与本地一致；原先公开屏只有简化文字版行囊、看不到商店。其他教师面板（GM、档案等）不复制。待用户在Mac公开窗口与iPad电视上实测。
- 本机实测与修复（2026-11-18，computer use操控Mac版）：打开公开窗口→顶栏变绿色“TV”；继续行程走路、一场战斗（掷骰、胜利结算卡、收下回地图）、行囊切成员与选物品、商店切“抽奖”并抽一次，两窗口画面一致；“关闭公开”与关窗都能断开、顶栏变回“本机”。修了三处：①有游戏时关掉再打开公开窗口两边全黑——教师预览里将被移除的`MeadowRendererContainer`在最后一次更新时把游戏画面抢回去随即被拆掉，画面不在任何窗口（iPad游戏中插上电视同样会触发）；现`MeadowRendererHost`按`teacherPreview`分工：教师预览只在未连接公开屏时持有，公开屏只在已连接时持有。②关闭行囊时旧的简化文字行囊闪一下——已删去`PublicInventoryPanel`（镜像已取代）。③Mac重启时窗口恢复可能多出第二个教师控制台（`文件›新建窗口`同理），两者争抢画面；现只保留一个教师控制台，多出的窗口自行关闭（`TeacherHostController.primary`），并去掉SwiftUI的新建项（系统的“新建窗口”菜单仍在，点了不会多出教师窗口）。跨屏全屏与投影性能仍待用户在真实投影屏上验收。
- 随机外观与地图屏外标记（2026-11-18，Mac版实测，iPad同步改动未另跑模拟器）：①创建角色加“随机外观”：教师“形象”人物自定义页一键随机体型/发型/五官（衣装跟随护甲，每次与当前不同）；新地图设置每位学生一行多“随机外观”按钮，按钮显示所选人物头像、再点“换一个”，与已选同学不重复（`PlayerAppearance.random`，GameCore新增测试）。②地图屏外成员标记：原先头像圈是白的——头像精灵在圆形裁切节点里，用`childNode(withName:"face")`找不到，贴图从未设上；且标记挂在场景上走了HD-2D模糊/调色，看起来发白发虚。现按`.//face`查找；`MeadowPostProcess.overlayNodes`把场景上z≥overlayDepth的屏幕UI也当地图UI，在调色之后不模糊地画（同时修正`isolate`误把这些保留节点隐藏），标记z改为overlayDepth+2000；名字牌放在箭头相反一侧，底边不再被裁。③教师地图支持鼠标滚轮/双指滚动缩放（`MeadowTeacherMapInput`，Mac没有触控板也能缩放）。④`scripts/local-build.sh mac`可加`MAC_OPEN=background`后台打开、`MAC_OPEN=0`只编译。
- 节点白框、屏外头像跳转、人物自定义投屏（2026-11-18，Mac版实测，iPad同步改动未另跑模拟器）：①地图节点徽章时有白色方框（随徽章翻转变窄，公开屏也有）：同一个SKRenderer每帧对同一command buffer渲染两次（地图一遍、调色后地图UI一遍），第二遍覆盖了第一遍还要用的内部顶点/常量缓冲，徽章透明角被画成白块；地图UI那一遍改用单独的SKRenderer（`overlayRenderer`，只渲染不update）。修后公开屏与教师端多次间隔截图都无白框（修前首张常见）。同一成因可能导致用户说的“地图边缘物体闪烁”，未能稳定复现，待用户复看。另做了几处防护：徽章/漂浮光点/人物图集位图用`preferredRange = .standard`，地图MTKView的layer设opaque，图片镜像回读图`noneSkipFirst`忽略alpha。②点击镜头外的成员头像标记，镜头直接跳到该成员（`GameScene.jumpToEdgeMarker`，不改选中成员、不触发移动）。③“形象”人物自定义页也实时投到公开屏（`publicPanelSource`加入该页，与行囊/商店同一镜像）；Mac上若公开窗口与教师窗口在同一屏重叠，截图里会同时看到真实弹窗和镜像，投到另一屏时只有镜像。
- 队伍记分板、PPT动画（2026-11-18，Mac版实测，iPad同步改动未另跑模拟器）：①记分板加“队伍记分”：按队员平均积分排名（同分再比总积分、金币），显示平均积分（保留1位小数）、总积分、金币、人数与队员头标，不含老师席位、空队不显示（`GameRules.teamStandings`，GameCore新增测试）。顶栏“记分”点按仍是显示/隐藏，长按（Mac点箭头）菜单选个人/队伍；新快捷键D切换个人/队伍（并显示记分板），选择记在本机。②PPT动画：导入时读`p:timing`主序列（`PPTXAnimations`），自动开始的效果在翻到该页时播放，其余按点击分组；进入/退出效果归为出现/淡入/飞入（带方向）/浮入/擦除（带方向）/缩放/弹跳，强调为放大脉冲或旋转（动作路径按强调显示），按段落的逐条出现也支持；每页`p:transition`归为推入（带方向）或淡入。渲染时静止部分合成整页图，动画对象（或段落）各自单独成层并保留前后层次（`DeckRenderer`→`DeckPage`），公开屏与教师预览同一`DeckPageView`播放。“下页”/→先播本页下一步动画，播完才翻页；“上页”/←先撤回一步，页首再退回上一页时整页显示为已完成；翻页过渡由`DeckStage`手动让新旧两页同时移动。教师绘本栏显示“动画 n/总数”。组合、表格、图表上的动画仍跳过并在导入报告里注明。用测试课件（`artifacts/anim-test.pptx`，只在本机）在Mac版逐步验证了进入/段落擦除/缩放/弹跳/旋转/退出与推入换页、上页撤回；真实课件的效果近似程度待用户用自己的PPT核对。
- 答题扩展与答题报告（2026-11-18，Mac版实测，iPad同步改动未另跑模拟器）：①题库新增题型（`QuizKind`：选择/闪卡/填空/阅读，统一为若干`QuizItem`供老师点选）、难度1–3、限时、知识点标签；纯文本与JSON都支持，格式见`docs/question-bank-format.md`。闪卡干扰项不足时借用其他闪卡背面，填空`{{正确|错答…}}`，选项顺序按内容固定洗牌（同一题库各设备一致）。②个人作答：答题点里每位在场队友各答一题（按题库顺序发下一题），都答过才关闭；老师在私有面板`MeadowQuizAnswerPanel`点学生说的答案（或“不会”/“其他”输入），电视`MeadowQuizCard`按题型显示并倒计时，提交后揭晓（填空错答红色删除线、闪卡翻面、阅读逐题✓✗）。③奖励按难度（`QuizRewards`：15/30/60金币按答对比例、全对积分=难度并按难度掉落表从存档随机流抽一件、用时不到一半全对金币×1.5、超时只记录不发奖），新命令`recordCampaignQuiz`把作答写入`GameState.quizLog`（可撤销、随存档）；未设难度的旧题库保持原奖励。④答题报告：`QuizReport`（GameCore，有测试）汇总全班与个人；`QuizReportView`用SwiftUI排版A4页面（全班总览+每人一页，错题多时续页），导出矢量PDF或每页PNG（系统存储面板）；入口“更多→答题报告”，快捷键R。用生成的测试行程在Mac版实测了阅读/填空/闪卡三种作答、揭晓、奖励与掉落、报告预览与PDF/PNG导出（测试后已还原用户行程存档）。
- 全局答题与错词（2026-11-18）：①答题可随时调出：顶栏“答题”（游戏与绘本页）或快捷键Q（全局，行囊/商店上也生效）打开`QuizLauncherPanel`选人、按题型/难度筛选、换一题；题卡改由教师协调器的`LiveQuiz`驱动，画在`ClassroomTVOverlays`里（`QuizOverlayHost`把UIKit题卡放进720高画布按屏缩放），因此盖在地图、战斗、绘本之上，电视与教师预览同步；地图答题点也走同一流程（`GameViewController.classroomQuizRequest`）。随时答题的记录`node=-1`、`QuizRecord.free`，不改地图、可重复作答；可在启动面板“导入题库”追加到当前行程（`appendQuizBank`，追加不打乱旧记录）。`quizCandidate`按发题顺序筛选。②报告错词：`QuizReport.word`认定单词题（闪卡取拉丁字母那面为单词另一面为意思；填空取正确答案；选择/阅读带“单词/词汇/vocab”标签取正确项），个人`wrongWords`（说成了什么、次数）与全班`words`（错/问次数、常见错答、哪些同学）；PDF/PNG第一页加“易错单词”，个人页加“错词本”，报告窗“复制错词”复制成文字。GameCore新增测试。随后后台实测Mac版：绘本页按Q调出启动面板、选人开题，题卡盖在绘本上（闪卡、填空揭晓正常），游戏页“答题”按钮同样可用；报告导出图片中“易错单词”与个人“错词本”显示正确。实测后修正：错词图标`textformat.abc`在中文系统显示成“甲乙丙”，改为书本图标；闪卡揭晓时在背面上方同时显示正面单词。“复制错词”未点（避免覆盖用户剪贴板）。
- 专属题/公用题与快捷出题（2026-11-18）：题库新增`对象：`（`QuizQuestion.audience`，名字或座位号；不写/“全班”为公用题）。取题：`personalQuizQuestion`先出该生未答的专属题，再出未出过的公用题（按发题顺序，`usedQuizQuestions`排除已出过的，练习不算）；`sharedQuizQuestion`给全班题；`lastAskedQuestion`用于“再出一次”；`practiceCard`闪卡练习排序（未练→答错过→其余，不连续重复）；地图答题点`quizTurn`也走专属优先。规则：公用题奖励由老师给定（`QuizRecord.manualCoins`：答对金币或参与奖，答对记积分，不掉落、不看超时），练习`practice`只记录不发奖，全班题记录带`shared`。界面：`KeyHostingController`让面板接管键盘（⏎⎋⌫与字母数字，未用的键再交给全局快捷键，文本框结束编辑或点选项/选人后焦点回到面板）；Q个人题（回车开题，1–7换人，X/K/T/Y按题型直接开题，空格换一题，Z再出一次，作答A–H/0/⌫/⏎/Esc，公用题显示“答对/参与奖”金币栏）；⇧Q全班题`ClassQuizPanel`（1–7多选、A–H答案、回车发送并记录、可连续多组、Esc揭晓答对名单）；K闪卡练习`PracticePanel`（顶栏固定“闪卡”入口，A–H记录后1.3秒自动下一张）。快捷键token区分⇧+字母。GameCore新增测试；本轮用户在使用App，未做界面实测，只编译到`native/catalyst-build`（未覆盖artifacts里正在运行的App）。
- 打开公开窗口卡死、镜像检测、自动放到第二屏（2026-11-18）：用户实测投影只能镜像、打开公开窗口卡死。系统报告（/Library/Logs/DiagnosticReports/ClassroomProbe_…hang）显示主线程卡在`GameScene.refreshProfileFrames`↔`PixelHeroAtlas.prepare`：每次地图刷新在外观未烘好时都追加一个“烘好后刷新”回调，打开公开窗口触发大量刷新，回调堆积后一次性在主线程执行；且像素图集缓存220MB（每套外观约27MB）满了会把刚烘好的挤掉，导致反复重烘。修复：`GameScene`同一时间只排一个后台烘焙并只回调一次，烘过的外观即使被缓存挤掉也直接取用；`prepareProfileVisuals`同样只排一次、不循环；Mac图集缓存上限提到480MB（iPad不变）。镜像：当时AirPlay屏“Mirror: On”，镜像模式下公开窗口无法单独显示。新增`MacDisplays`（运行时查找CoreGraphics显示器接口，Catalyst SDK未提供）：检测镜像时教师顶栏出现“投影屏在镜像 · 改为单独显示”（一键对本次登录关闭镜像，失败则提示去系统设置），打开公开窗口时若有单独的第二屏，自动移到该屏并全屏（`requestGeometryUpdate`+按标题找AppKit窗口`toggleFullScreen:`）。只读脚本核对过显示器检测（用户已改为扩展后：主屏1440×900、第二屏1920×1080在右侧）；随后装新版后台实测：用用户行程打开公开窗口不再卡死、无新卡死报告；测试时投影屏已断开，状态检测正确返回“无第二屏”，自动移屏/全屏仍待接上投影屏验证（公开窗口开着时若第二屏出现也会自动移过去；放置诊断写在临时目录public-window.log）。用测试行程（测后已还原用户存档）点按钮实测：Q面板默认当前成员并先给专属题，专属题全对自动按难度发奖并掉落；全班题多选两人答对各+10、一人答错参与奖+2，结束揭晓“答对：小明、小刚”；闪卡练习答后自动下一张。后台无法向弹出面板发送按键，面板内键盘操作（A–H、回车、Esc、X/K/T/Y）未实测。面板背景改为铺满（原上下有空白）。
- 性能（2026-11-19，用户反馈投影后两边帧数低）：只读排查——扩展屏实为Sidecar/AirPlay（2628×1970），系统视频编码（VTEncoder+avconferenced）约55% CPU；内存16GB用到15GB、5GB压缩并换页；App约105% CPU，主线程主要在地图每帧渲染（`MeadowShadowRenderer.draw`/SpriteKit编码，地图已固定1280×720，非分辨率问题）与教师端实时镜像快照；CPU资源报告另见战斗视图被头像回调反复整体刷新并每次重缩放物品图标。按“尽量不用CPU画”的要求修改：①地图上的SKShapeNode（选中/目的地圈、路线、节点脚印与点击区、名牌、完成粒子、屏外标记箭头/圆盘/遮罩/名字底、像素标记阴影）每帧都在CPU上重新描边算包围盒，全部改为`MeadowShapeSprite`——形状只在第一次（或形状变化时，如路线、名牌宽度）画成纹理并缓存，之后每帧只用GPU画精灵；点击区改透明精灵。②头像改存普通字典（最多64个，不被内存紧张时清掉），烘不出的不再重试，避免“清掉→重烘→整体刷新”循环。③物品按钮图标缩放结果缓存（动图24帧不再每次刷新重画）。④Mac地图默认稳定30帧（`MeadowFrameRate`，“更多 › 地图 60 帧”可切回；iPad仍60），Mac教师端实时镜像20Hz。只编译，未装机实测性能。
