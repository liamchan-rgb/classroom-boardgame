# SpriteKit草地光影独立小样v1

用户授权制作独立光影小样并将计划同步GitHub，见[PLAN.md](PLAN.md)。[用户理想效果原图](reference/ideal-effect-user.jpg)继续原样保存；本轮不改正式App/GameCore、main或工作流，不构建IPA，不覆盖旧资产/ZIP/标签。

## 交付

- `Native/GrassLightingPrototype.xcodeproj`：独立iPad SwiftUI/SpriteKit工程，原始素材/太阳光影/局部光照三模式、强度调节、人物移动、拖动/缩放/跟随、两比例与减少动态。
- 本地RGBA/地面/方向图与测量矩形清单，字节复用v6；8种地面纹理缓存、2D alpha投影、Y排序、SKLightNode/实验法线、边缘前景效果。
- 原生单元/截图测试、[Mac运行脚本及用户需要做的步骤](RUN_ON_MAC.md)、[正式接入边界](INTEGRATION.md)。

## 先看的设计参考

| 对照 | 16:9 | 4:3 |
| --- | --- | --- |
| 关闭新增投影 | [参考图](previews/design_base_16x9.png) | [参考图](previews/design_base_4x3.png) |
| 太阳方向投影 | [参考图](previews/design_sun_16x9.png) | [参考图](previews/design_sun_4x3.png) |

[离线浏览器设计参考](previews/design-preview.html)可切换投影、移动与缩放。以上四张PNG是浏览器设计参考，未经过SpriteKit渲染；不能用作原生实测证据。原生局部光照效果需运行独立工程查看。

## 验证状态

当前Linux环境无Xcode/Apple SDK。已做Swift语法解析、Xcode工程对象/共享scheme结构、素材矩形/原图字节、浏览器离线设计对照与移动检查。尚未Apple SDK类型检查、Xcode编译、执行原生测试或iPad验证，见[evidence/source-checks.json](evidence/source-checks.json)。

原生测试脚本运行后会生成真实xcresult与截图，届时补充新的验证存档。现在不需要用户提供账号；要查看原生效果，需要Mac/Xcode或开发阶段的Mac构建环境。只有iPad时，请把本目录交给开发阶段构建独立测试包，签名沿用已有渠道。

正常按钮在Xcode26/Swift6.2且iOS26上使用Liquid Glass；旧编译器/系统以原生Material回退。场景资产有已有烘焙高光，关闭新增光照不会消除它们。自动法线、草地重复、剪影投影与人物一致性仍待审，不自动标记达到理想图。

原生场景布局与浏览器设计参考来自同一素材，但实现不同，画面需要原生运行后对照。正式GameCore、App和旧资源保持原样。图片沟通使用真实绝对路径Markdown文件链接。恢复存档见ARCHIVE_INDEX.md。
