# 运行独立SpriteKit小样

本工程还未经过Xcode编译或原生运行；当前交付环境为Linux。先构建/运行，再判断画面与性能。无须把小样合并进正式游戏。

## 有Mac/Xcode

1. 下载本版本完整ZIP或检出设计分支，保留目录结构。
2. 用完整Xcode打开`Native/GrassLightingPrototype.xcodeproj`，选择`GrassLightingPrototype` scheme与iPad模拟器，点击Run。目标iOS17或以上；建议Xcode16或更新并安装iOS Simulator运行时。
3. 点击▷播放人物移动；太阳按钮循环原始素材/太阳光影/局部光照；准星回总览。设置里调整光影强度、16:9/4:3和跟随；画面支持拖动与双指缩放。
4. 用Product → Test运行几何/事件门控单元测试及两比例原生截图测试；也可在终端运行：

```bash
bash design/spritekit-lighting-prototype-v1/scripts/verify_on_mac.sh
```

脚本自动选择已安装的iPad模拟器，结果写到临时目录，输出构建日志、NativeTests.xcresult与截图附件；不生成IPA，不改正式工程。可用`PROTOTYPE_DESTINATION='platform=iOS Simulator,id=已安装设备UDID'`指定设备。

## 只有iPad

需要开发阶段的Mac/Xcode或既有Mac构建环境编译独立测试包，再沿用现有签名/安装渠道装到iPad。此源码不能直接在Safari或SideStore中编译。当前没有交付已签名安装包，不能只下载ZIP就运行原生场景。

独立Bundle ID为`com.classroomboardgame.design.grasslightingprototype`，不覆盖现有课堂游戏。设计阶段不需要用户提供账号、密码、证书或签名材料；构建/签名由原有开发渠道处理。已有正式App/GameCore和工作流本轮保持原样。

## 需要回传什么

- 首次Xcode构建/测试结果；若失败，相关错误段与Xcode版本即可。
- 同一视角的原始素材/太阳光影截图，16:9和4:3各一组；移动、拖动/缩放的小段录屏。
- 最终在实际iPad观察树下阴影、人物接地、前景遮挡、帧率/发热和远距阅读；模拟器不代表真机性能。

原生测试附件才可标记为“SpriteKit运行截图”。`previews/design_*.png`是浏览器设计参考，两者不能混用。
