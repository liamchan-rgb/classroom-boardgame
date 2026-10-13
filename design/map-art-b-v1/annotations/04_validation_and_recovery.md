# 检查与恢复

已做：原6个nodeVisual ID／ASCII名比对；20张运行PNG尺寸／透明检查；6节点非透明像素距离四边至少51px；64/96px缩小及状态板目视；五节点／道路来源适配；未知Boss与奖励测试输入对应完全相同公开地图像素。逐项alpha边界与SHA256见sources/validation.json。

这不是App、SwiftUI、触摸、键盘、实际电视距离、无线隐私或PPTX验证。未构建IPA。7张预览不替代已通过整屏；新增素材待最终审美确认。

ZIP含完整map-art-b-v1与FILE_CHECKSUMS.json。检查ZIP CRC及逐文件SHA256后即可恢复本批；独立PNG/SVG直接交给开发对话。代码快照与远端回读见design/archives回执，旧各批不覆盖。

重建需Python3、Pillow、CairoSVG、ImageMagick和本地Noto Sans CJK SC。设置DESIGN_PREVIEW_FONT后运行sources/build_assets.py，输出由脚本目录决定；随包原图优先使用，不重新生成插画。sources/export_node_*.svg记录完整原图与标准画布。

当前GitHub连接未提供创建Git标签接口，本地Git无仓库认证。计划标签archive-design-b-map-v1-20261013不得写成已创建；完整ZIP、校验清单与不可变设计提交必须上传并回读。恢复不依赖标签，标签实际状态以回执为准。
