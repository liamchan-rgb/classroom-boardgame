# iPad 侧视战斗场景实验 v0.11 · 长期存档

- [直接下载未签名 iPad IPA](ClassroomStage2-v0.11-unsigned.ipa)：10,996,063 字节，SHA256 `e22dd2c5e5a59897d6a067b7ccf41e17661157bed1fd8a70d1cb89e843edd4ba`。Bundle ID `org.personal.classroom.stage0`，arm64，最低 iPadOS 27；用 SideStore 和个人 Apple ID 签名安装。
- [完整可恢复存档](archive.zip.sha256)：667,540,296 字节，SHA256 `9fd5b19659a6e824673237e333512d19c10f504c8cc11ed17052493a74813bbc`。下载14个 `.partNNN` 文件与 `transport.json`、`restore_zip.py` 到同一目录，运行 `python3 restore_zip.py` 还原ZIP；再按[恢复说明](恢复说明.md)检查清单与Git历史包。
- [完整 GitHub Actions 构建诊断](ClassroomStage2-v0.11-side-battle-build.zip)：包含IPA副本、Xcode/测试日志、66项素材验证及24张原生模拟器截图。SHA256 见 `cloud-build-result-v0.11.json`。
- [逐文件归档清单](manifest.json)包含源码、Git bundle、IPA及构建诊断的大小和SHA256；`transport.json`列出每个ZIP分片的校验值。

源码快照标签 `archive-stage2-battle-prototype-v0.11-20261019` 指向 `6748b7cb5e73f3630e9bb32ce3d25af093062766`；IPA 实际编译提交为 `01265f2d504fe19a33d39843dc7c7e40791eba43`。Xcode 27.2；GameCore 72项、ProbeCore 6项测试通过，66项素材验证通过。模拟器报告含16:9及4:3成图；战斗动作仍是用户确认的单帧静态接触姿势。

实体iPad安装和新场景的设备效果尚未验证。用户对美术资源的确认仅限于接触姿势，不代表完整动画或本版背景/敌人素材的最终审美验收。规则、骰子、技能触发及存档格式保持不变。
