# 阶段2美术与UI接入存档 · v0.9

日期：2026-10-13。状态：已保存到私有项目；从远端重新克隆、合并分片、校验载荷及独立恢复源码全部通过。

- [新版IPA（需SideStore个人签名）](https://github.com/liamchan-rgb/classroom-boardgame/blob/33939b09476e2a36cd77cb1487c9199197bd336f/archive-stage2-ui-art-v0.9-20261013/ClassroomStage2-v0.9-unsigned.ipa)：ClassroomStage2-v0.9-unsigned.ipa，10,445,942字节；iPadOS27，版本0.9/9，沿用原Bundle ID。
- [长期存档目录](https://github.com/liamchan-rgb/classroom-boardgame/tree/33939b09476e2a36cd77cb1487c9199197bd336f/archive-stage2-ui-art-v0.9-20261013)（需登录仓库账号）：六个ZIP分片、transport.json、restore_zip.py、完整清单、校验及恢复说明；也单独保存IPA。
- [源码快照标签](https://github.com/liamchan-rgb/classroom-boardgame/tree/archive-stage2-ui-art-v0.9-20261013)：893cc3021211492c4ecce4ecd852cec9702d032f。
- IPA实际编译提交：1379bd2e174d88c582bb19fa8ea1f64c180a74da；[成功云端构建](https://github.com/liamchan-rgb/classroom-boardgame/actions/runs/38345790065)。
- 显式读取的固定设计提交：f43db0502bf3a9df9fef8bb7c699b6dce86c3425；从main v0.8继续，未覆盖为设计分支旧App。
- 完整ZIP：classroom-stage2-ui-art-v0.9-20261013.zip，290,894,459字节，SHA256 `58738f4104e7c1c08cac02cadd4d8fc3f72af766c4e9a5d4a6ba67bb1826a6d7`。
- IPA SHA256：`7d3a6e27184e5a07876ba769f8f54df8d7651d303c68f034c9e838147945a601`。

ZIP含270项载荷：266份源码/项目资料、最终IPA与云端诊断ZIP、完整源码Git历史包、恢复说明。Git历史包保留旧设计与源码标签，排除archive-assets二进制分支；历史交付仍见[原v0.8存档](../archive-stage2-v0.8-20261012-r2/README.md)。旧ZIP、旧标签及已通过设计稿保留。

GitHub单文件限制下，完整ZIP按48MiB无损分成六段保存。下载长期目录中的六个part文件、transport.json和restore_zip.py，在该目录执行 `python3 restore_zip.py`，校验后得到原ZIP；随后按恢复说明从git-history.bundle恢复源码。无需拼接代码或合并二进制分支到main。本地也保留完整可下载ZIP。

[远端回读与恢复证据](verification.json)：完整ZIP的SHA256/CRC、全部270项载荷和266份恢复源码的SHA256一致，恢复提交准确，完整Git历史验证通过；IPA在源码快照之后仅增加证据文档，App源文件与实际编译提交一致。

GameCore65项、ProbeCore6项通过；12张原生模拟器截图、66张本地PNG解码与离线IPA资源校验通过，覆盖长姓名、两种电视比例、独立奖励、未知隔离、救援资格、暂停和一次表现。[实际接入/未接入清单](../../stage2/ui-integration/README.md)、[检查与真机待验证事项](../../stage2/ui-integration/验收与真机检查.md)。道路PNG使用原生真实道路等价显示，coin/score装饰不额外播放；未扩展玩法。

新版iPad、无线电视投影、实际触控/键盘、真实PPTX和逐图最终审美仍待反馈。构建及模拟器检查不代表真机或审美验收通过。该存档不包含教师未交付的真实课堂文件、本机进度或个人签名材料。

本目录为本次存档的索引和上传回执收尾，不递归另建存档。
