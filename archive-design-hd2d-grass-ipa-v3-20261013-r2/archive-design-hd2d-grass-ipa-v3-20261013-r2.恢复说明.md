# archive-design-hd2d-grass-ipa-v3-20261013-r2 独立草原小样恢复说明

本存档保存本轮完整源码、Git历史、实际设备IPA和完整Actions诊断ZIP，范围以manifest.json为准。使用仓库tools/archive_milestone.py进行源码/历史/交付采集和校验；此包装脚本仅更正旧通用恢复说明中的正式App名称、系统版本和默认分支文字，未改变采集范围或证据。

- 源码快照：b1ffe63e51ecc29e96943f855abfa6b7e7e6ba11；唯一标签：archive-design-hd2d-grass-ipa-v3-20261013-r2。
- 实际IPA编译提交（PR合成merge）：a5078546fd4386d4dd37ca2bbf48269b8661be0e；源head与工具链记录见source/design/hd2d-grass-four-stages-ipa-v3/evidence/device-build.json。
- 安装包：deliveries/GrassHD2D-v0.3-unsigned.ipa；GrassHD2D 0.3(3)，iPadOS17及以上，arm64设备包，需使用已有SideStore方式个人签名。
- 与正式课堂App使用不同bundle ID，不包含账号、证书、配对材料或教师设备资料。
- Xcode编译/数学检查已完成；本轮没有中间画面审核，视觉与帧率等待用户真机验证。

## 还原

若ZIP按48MiB分片保存，先在transport目录下载全部part文件并运行restore_zip.py，再核对完整ZIP SHA256。解压后的manifest.json逐一列出每个载荷SHA256及字节数。

```sh
git clone git-history.bundle classroom-boardgame-restored
cd classroom-boardgame-restored
git checkout b1ffe63e51ecc29e96943f855abfa6b7e7e6ba11
```

也可以直接读取source/。独立项目在source/design/hd2d-grass-four-stages-ipa-v3/Native/GrassLightingPrototype.xcodeproj；共享scheme为GrassLightingPrototype。参数和尺寸/动画注解见同目录TECHNICAL_NOTES.md；安装查看说明见DEVICE_GUIDE.md。archive-assets不在源码Git bundle中，也不得合并到main。
