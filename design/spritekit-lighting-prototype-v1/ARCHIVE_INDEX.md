# SpriteKit独立光影小样v1存档

- 设计分支：`design/map-battle-ui-round4-20261013`；正式App、GameCore、main、工作流未改。
- 源码快照：`24778c3a317cae21cae03dcdf928c065dc2e946b`。
- 唯一标签：`archive-design-spritekit-lighting-prototype-v1-20261013`；标签对应源码快照，旧标签保持不变。
- [完整版本ZIP](archives/spritekit-lighting-prototype-v1-20261013.zip)，28,414,346字节，41个交付文件及FILE_CHECKSUMS，共42个ZIP条目。
- SHA256：`e420931af57f6568e1573c7d85b1c183ff4f682c5e81b78ca1f316f43897ba6a`，见[校验文件](archives/spritekit-lighting-prototype-v1-20261013.zip.sha256)及[清单](archives/spritekit-lighting-prototype-v1-20261013.manifest.json)。
- 恢复：解压ZIP，保留目录结构，按[Mac运行步骤](RUN_ON_MAC.md)打开独立Xcode工程；也可检出上述标签，再进入本目录。此工程没有外部Swift包依赖。
- [计划](PLAN.md)、[接入文档](INTEGRATION.md)、[原始理想图](reference/ideal-effect-user.jpg)和两比例设计参考均已包含。

## 检查与限制

本地ZIP CRC、逐文件SHA通过；Swift语法、工程结构、资源矩形、原图字节与浏览器离线设计参考检查通过。远端ZIP/标签/逐文件回读核对中，完成后回执补入本目录。

当前Linux无Xcode/Apple SDK：未进行SDK类型检查、Xcode编译、原生测试、SpriteKit截图或iPad性能测量。原生编译提交为空，未生成IPA；PNG为浏览器设计参考，不能标记为原生截图。美术仍待用户审美确认。
