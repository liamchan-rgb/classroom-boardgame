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
