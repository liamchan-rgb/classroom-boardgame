# archive-stage2-v0.8-20261012-r2 恢复说明

本存档包含该步源码、项目资料、设计、测试和明确选定的交付文件；范围以清单为准。首次阶段0—2存档同时保存此前全部现存交付。

- 源码快照提交：39393717cffe6a082a5447426b21baccb75109e8
- 本存档标签：archive-stage2-v0.8-20261012-r2
- 当前IPA实际编译提交：aff02aad17fc24b6f76c6ac3e8ce3b4269934f2d
- 当前推荐安装包：deliveries/ClassroomStage2_v0.8_unsigned.ipa
- 当前App版本：0.8；设备：iPadOS27；需SideStore个人签名。
- 云端编译/检查通过不代替新增功能真机反馈；状态以源码中的验收和证据为准。

## 核对文件

外部 `.zip.sha256` 校验整个ZIP。解压后 `manifest.json` 列出所有载荷文件的字节数和SHA256；清单自身由整个ZIP校验覆盖。

## 恢复源码和版本历史

直接使用 `source/` 可查看完整源码、原需求、计划、设计和测试。需要Git版本历史时：

```sh
git clone -b main git-history.bundle classroom-boardgame-restored
cd classroom-boardgame-restored
git checkout 39393717cffe6a082a5447426b21baccb75109e8
```

Git bundle保存源码分支/标签和历史，排除二进制archive-assets分支；本存档提交包含归档规则/工具。若继续与原私有仓库协作，将origin改为 https://github.com/liamchan-rgb/classroom-boardgame.git，再使用自己的GitHub授权。

构建设备版使用Xcode27工程；不用重新解析源码也可直接把当前IPA交给SideStore。历史安装包/Playground样例保留用于追溯，不能把其中失败版本当作当前推荐包。

本存档不是教师iPad本机课堂进度备份；尚未取得的真实PPTX、游戏存档和设备签名材料不在包内。
