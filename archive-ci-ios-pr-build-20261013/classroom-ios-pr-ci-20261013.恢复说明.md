# archive-ci-ios-pr-build-20261013 源码/CI恢复说明

本次包含完整源码、选定CI诊断交付、逐文件校验与Git历史包；不包含新的IPA。

- 源码快照：b66ec36dbebc347e2fc77a509ff6a15b44e8344b；唯一标签：archive-ci-ios-pr-build-20261013。
- CI验证提交：1c1a47a89eb912daa25068c887cc71a6da66e5e8，状态以source/native/evidence/ci-pr-cloud-success.json为准；不将其当作IPA编译提交。
- Git bundle仅包含源码refs，排除archive-assets。下载全部分片后按transport目录内restore_zip.py还原ZIP。
- 核对外部ZIP SHA256及manifest.json所有载荷；源码位于source/。

```sh
git clone git-history.bundle classroom-boardgame-restored
cd classroom-boardgame-restored
git checkout b66ec36dbebc347e2fc77a509ff6a15b44e8344b
```

云端编译不能替代真机验收。原安装包及旧存档保持原样，不包含教师未交付的课堂数据、账号或签名材料。
