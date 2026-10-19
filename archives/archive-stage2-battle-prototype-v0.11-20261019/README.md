# 阶段2侧视战斗场景实验 v0.11 · 可恢复存档

状态：已推送至私有 `archive-assets` 隔离分支，远端稀疏克隆、分片恢复、整包/逐文件SHA256及Git源码恢复均通过。

- [直接下载未签名 iPad IPA](https://github.com/liamchan-rgb/classroom-boardgame/blob/83a0c1ca02badf0534ef7208084b11e90cb30e5d/archive-stage2-battle-prototype-v0.11-20261019/ClassroomStage2-v0.11-unsigned.ipa)：10,996,063字节，SHA256 `e22dd2c5e5a59897d6a067b7ccf41e17661157bed1fd8a70d1cb89e843edd4ba`。需用SideStore和个人Apple ID签名安装；arm64，最低iPadOS27，沿用原Bundle ID。
- [完整长期存档目录](https://github.com/liamchan-rgb/classroom-boardgame/tree/83a0c1ca02badf0534ef7208084b11e90cb30e5d/archive-stage2-battle-prototype-v0.11-20261019)：14个ZIP分片、`transport.json`、恢复脚本、清单、构建日志、完整Actions诊断ZIP及单独IPA。
- [源码快照标签](https://github.com/liamchan-rgb/classroom-boardgame/tree/archive-stage2-battle-prototype-v0.11-20261019)：`6748b7cb5e73f3630e9bb32ce3d25af093062766`；IPA实际编译提交：`01265f2d504fe19a33d39843dc7c7e40791eba43`。
- [云端构建](https://github.com/liamchan-rgb/classroom-boardgame/actions/runs/39229688707)：Xcode27.2；GameCore72项、ProbeCore6项测试通过；66项素材校验通过；24张SwiftUI模拟器截图已保存。

完整ZIP为667,540,296字节，SHA256 `9fd5b19659a6e824673237e333512d19c10f504c8cc11ed17052493a74813bbc`。包含350份源码/资料、2份本次交付、Git历史包及恢复说明，共354项载荷。远端14个分片逐项哈希通过；重组ZIP哈希、ZIP CRC、354项载荷校验、Git bundle完整历史及恢复出的源码提交均通过。单独IPA和完整Actions诊断ZIP的远端SHA256也匹配。详见[恢复校验回执](verification.json)与[校验清单](manifest.json)。

这版把用户确认的侧视接触姿势作为固定单帧样片放入战斗镜头实验，4:3及16:9模拟器画面已检查。新场景尚未在实体iPad上验证；动作不是完整动画，用户的美术确认也不覆盖本版背景、敌方素材或最终整体审美。原规则和存档格式未改变。Actions短期产物在3天后过期，不影响本长期存档。

恢复完整ZIP：下载本目录全部 `.partNNN` 文件以及 `transport.json`、`restore_zip.py` 至同一目录，执行 `python3 restore_zip.py`，然后按[恢复说明](恢复说明.md)核对逐文件清单和Git bundle。
