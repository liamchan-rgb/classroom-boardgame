# iOS PR自动编译存档

本步为正式iPad工程配置PR自动编译与诊断Artifact；App源码、GameCore规则、资源、部署版本及旧设计未改，不交付新IPA。

- [长期存档](https://github.com/liamchan-rgb/classroom-boardgame/tree/c1d444d161bbb6ec76a9c43378e5991a14e5cf26/archive-ci-ios-pr-build-20261013)：完整ZIP的三段无损分片、清单、校验、恢复工具和说明。
- [源码快照标签](https://github.com/liamchan-rgb/classroom-boardgame/tree/archive-ci-ios-pr-build-20261013)：`b66ec36dbebc347e2fc77a509ff6a15b44e8344b`。
- [成功PR云端验证](https://github.com/liamchan-rgb/classroom-boardgame/actions/runs/38432491033)：macOS27.0.1/Xcode27.2，正式App模拟器编译成功、GameCore72项和ProbeCore6项测试通过，实际合成merge提交`1c1a47a89eb912daa25068c887cc71a6da66e5e8`，PR head为`a5260baafa2438363dc34dea5808d69ffcca6d5a`。后续源码快照PR运行38433141831同样成功。
- 首次macos-latest SDK缺失失败及成功运行的两个原始Artifact均包含在长期存档；失败时日志上传已实测。
- ZIP：`classroom-ios-pr-ci-20261013.zip`，100,852,308字节，SHA256 `cd2cef1b2e46b7fddfc8d06db3bf823a7e5ea06ae6a6a2a4f956c8cb50a61f86`。

[独立远端恢复验证](verification.json)：三段SHA/整ZIP CRC与345项载荷通过，340份源码从Git bundle恢复逐字节一致，实际CI合成merge提交存在，源码bundle排除archive-assets，旧archive-assets根目录条目未变。

下载存档目录全部part、transport.json和restore_zip.py，执行`python3 restore_zip.py`再解压；按恢复说明克隆Git bundle并检出源码快照。本目录是同一步索引收尾，不递归产生新ZIP。PR诊断Artifact保留14天；长期ZIP独立留存。操作见[native/CI.md](../../native/CI.md)。
