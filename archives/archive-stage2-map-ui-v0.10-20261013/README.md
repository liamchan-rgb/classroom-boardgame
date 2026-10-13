# 阶段2地图与战斗结构 v0.10 · 可恢复存档

状态：已推送私有archive-assets长期分支，从GitHub独立重新读取并恢复验证通过。

- [直接下载IPA](https://github.com/liamchan-rgb/classroom-boardgame/blob/4e27caff67a4c85c6ad064598fe5ab61c2704421/archive-stage2-map-ui-v0.10-20261013/ClassroomStage2-v0.10-unsigned.ipa)：ClassroomStage2-v0.10-unsigned.ipa，10,562,079字节（约10.6MB），无需下载完整备份。登录仓库账号，打开文件页点Download raw file；用SideStore个人签名安装。包内核对0.10/10、arm64/iPadOS27，保留原Bundle ID。
- [完整长期存档目录](https://github.com/liamchan-rgb/classroom-boardgame/tree/4e27caff67a4c85c6ad064598fe5ab61c2704421/archive-stage2-map-ui-v0.10-20261013)：七个ZIP分片、transport.json、restore_zip.py、清单/校验/恢复说明、单独IPA、美术提示词及真机检查步骤。
- [源码快照标签](https://github.com/liamchan-rgb/classroom-boardgame/tree/archive-stage2-map-ui-v0.10-20261013)：eef7171d23e2402923bf9f35fe462b21356ae968；IPA实际编译提交：a94ad1cfb70104b8d6e980b86b0625c0829f65d9。
- [云端构建](https://github.com/liamchan-rgb/classroom-boardgame/actions/runs/38397057874)：GameCore72项、ProbeCore6项共78通过，22张原生截图检查，66本地素材全部解码/包内哈希正确。

继续最新程序与固定f43设计素材，未用设计分支旧App覆盖源码。已实现探索全地图、角色真实落点/已提交道路移动、教师镜头与边缘头像箭头/聚合、到达后右侧战斗展开、连续混合回合轨道、当前玩家实际技能/物品费用和不可用原因。镜头不改变行动者/独立奖励/引擎；未知节点不加载隐藏插画；公开状态无AP；原规则和存档格式字节不变。具体[接入/未接入与证据](../../stage2/map-ui-v0.10/README.md)、[22张原生截图](../../stage2/map-ui-v0.10/evidence/native-previews/README.md)、[真机步骤](../../stage2/map-ui-v0.10/验收与真机检查.md)。

完整ZIP 350,352,160字节，SHA256 `58822250b8cf5af4e242ae8229c14edc26dad73cdf52f5892990d65d3c677432`。含332项载荷：326份源码/资料、4份交付、Git历史包与恢复说明。远端七分片/整包哈希、ZIP CRC、全部载荷哈希通过；Git bundle完整且排除archive-assets；从bundle恢复出的源码提交与全部326份文件一致。实际编译后仅更新资料/证据，原生源码未变；直接IPA远端哈希也正确。见[恢复验证回执](verification.json)。

下载七个part文件、transport.json及restore_zip.py到同一目录，执行 `python3 restore_zip.py` 无损恢复ZIP，再按恢复说明读取源码或恢复Git历史。原设计、旧ZIP/存档目录与旧标签保留。

IPA SHA256：`8b7af9f4967828e629c45310cd1fdb2f38486cfd31571f186c5d44aa7cd08d76`。Actions短期产物到期不影响本长期分支。此前版本标识错误与失败构建均记录在[构建过程](../../stage2/map-ui-v0.10/evidence/build-attempts.json)，不作为推荐安装包。

当前角色仍是已有独立图片沿道路平移；新行走动作、HD-2D场景与候选素材最终审美尚待独立美术交付/审核。商店继续原阶段3待办，未增加购买/交易/换装。真机触控、电视阅读、无线重连、硬件键盘及真实PPTX尚待本版反馈；云端/模拟器通过不代替真机。未包含教师未交付的本机资料、游戏进度与签名材料。

本目录为同一步索引/上传回执收尾，不递归另建存档。
