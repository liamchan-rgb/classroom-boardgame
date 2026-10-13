# iOS PR CI长期存档

- 源码标签：`archive-ci-ios-pr-build-20261013`；源码快照：`b66ec36dbebc347e2fc77a509ff6a15b44e8344b`。
- 本次自动PR运行38432491033通过，实际检查合成merge提交：`1c1a47a89eb912daa25068c887cc71a6da66e5e8`。Xcode27.2编译、72+6核心测试、Artifact上传/下载核对通过；没有新IPA或真机验收。
- 完整ZIP：100,852,308字节，SHA256 `cd2cef1b2e46b7fddfc8d06db3bf823a7e5ea06ae6a6a2a4f956c8cb50a61f86`，无损分为3段。
- 下载此目录的全部part、transport.json和restore_zip.py，运行`python3 restore_zip.py`还原，再核对ZIP及manifest.json的345项载荷。源码、Git bundle、成功/失败两次原始Artifact以及首次SDK失败日志全部包含。
- 源码Git bundle排除archive-assets，包含实际测试merge提交；按恢复说明克隆并检出快照。旧源码、安装包、设计存档及标签保持原样。
