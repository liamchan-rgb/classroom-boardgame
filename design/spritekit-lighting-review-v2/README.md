# SpriteKit原生审核小样v2

从v1独立小样复制为新版本，旧源码、资产、ZIP和标签保持原样。原图/PNG字节复用，未更改正式App、GameCore或规则。原生测试入口仍为`Native/GrassLightingPrototype.xcodeproj` / `GrassLightingPrototype`；独立Bundle ID为`com.classroomboardgame.design.grasslightingreviewv2`。

## 本轮审核方式

1. **编译/行为检查**：PR触发macOS/Xcode云端`xcodebuild test`，执行5项几何/公开道路/事件门控测试及2项UI测试；UI测试验证加载、光照切换与减少动态抵达。
2. **原生图片审美审核**：iPad模拟器输出16:9与4:3的原始素材、太阳投影、抵达和局部光照共8张PNG。它们是真实SpriteKit运行截图，只有生成后才标记为原生证据；以真实绝对路径Markdown文件链接发送，用户逐图审核。
3. **动态审核**：两比例各一段模拟器录屏，包含原始/太阳、人物沿路移动、镜头跟随/缩放、局部光照。同步保存位置/阶段/实际构建提交记录，检查实际移动和抵达。
4. **后续回归对照**：用户确认本轮图片后才冻结为审美基准；后续可对相同seed、视角、设备、光照阶段做截图差异。像素差异用于定位变化，不自动判定哪张更美。
5. **真机验收**：iPad帧率/发热/内存、触摸手感、电视远距阅读仍需实际设备。模拟器截图和录屏审核无需用户有Mac；安装包与真机部署可单独安排，本轮不生成IPA。

## 自动化入口

`.github/workflows/spritekit-native-review.yml`在本版本及审核配置的PR更新时运行，使用仓库已验证的macOS `xcode-27`标签；正式App既有PR检查同时独立运行。旧手动IPA workflow不受小样测试影响。

素材/工程检查后，选择已安装且兼容的iPad模拟器，`xcodebuild test`生成`NativeTests.xcresult`，导出PNG附件，录制两比例MP4；即使编译/测试失败也上传已有日志和测试附件，保留14天。只上传诊断/截图/录屏，DerivedData保存在Artifact之外。

目录中的`--review-replay`是显式开启的显示夹具，只有独立小样使用；不提交游戏命令、不读正式存档，不添加常驻说明文字。16:9在iPad物理屏幕内居中显示，PNG保留真实屏幕尺寸和留边，不伪装裁切为原生截图。

本版本在独立设计分支通过PR审核，不自动把美术标为通过或将小样接入正式App。运行证据与长存档完成后放入`evidence/`和存档索引；未产生的结果不能标为已完成。
