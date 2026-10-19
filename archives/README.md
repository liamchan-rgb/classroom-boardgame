# 项目长期存档

按教师2026-10-12要求，每个有新成果的交付步骤都建立一个可恢复存档。

长期位置为本项目私有仓库的archive-assets专用分支（或可用的私有GitHub Releases），Git标签固定源码快照；本目录保存索引、清单和交付状态。Actions产物只用于构建诊断，不能代替长期存档。ZIP只放独立的archive-assets分支，不写入源码main历史；源码Git bundle排除该分支，避免历史包递归嵌套。

## 当前归档

| 存档 | 状态 | 长期位置 |
|---|---|---|
| [侧视战斗场景实验 / v0.11 / 2026-10-19](archive-stage2-battle-prototype-v0.11-20261019/README.md) | Xcode27.2、78项核心测试、66项素材校验、24张原生截图通过；远端14分片、354项载荷、Git历史与IPA哈希恢复验证通过；实体iPad待验 | [私有长期存档](https://github.com/liamchan-rgb/classroom-boardgame/tree/83a0c1ca02badf0534ef7208084b11e90cb30e5d/archive-stage2-battle-prototype-v0.11-20261019) |
| [iOS PR自动编译 / 2026-10-13](archive-ci-ios-pr-build-20261013/README.md) | Xcode27.2编译、78核心测试及失败日志上传通过；345载荷/340源码恢复通过，无新IPA | [私有长期存档](https://github.com/liamchan-rgb/classroom-boardgame/tree/c1d444d161bbb6ec76a9c43378e5991a14e5cf26/archive-ci-ios-pr-build-20261013) |
| [地图与战斗程序结构 / v0.10 / 2026-10-13](archive-stage2-map-ui-v0.10-20261013/README.md) | 78测试、22原生截图；332载荷及326份源码远端恢复通过，真机/审美待验 | [私有长期存档](https://github.com/liamchan-rgb/classroom-boardgame/tree/4e27caff67a4c85c6ad064598fe5ab61c2704421/archive-stage2-map-ui-v0.10-20261013) |
| [战斗风格补充 / 近似八方旅人 / 2026-10-13](archive-stage2-hd2d-direction-20261013/README.md) | 仅资料更新；286项载荷及279份源码远端恢复通过 | [私有项目存档](https://github.com/liamchan-rgb/classroom-boardgame/tree/be7b1bbe85617536c8b1037ec36f8d28329563ae/archive-stage2-hd2d-direction-20261013) |
| [v0.9查看反馈与设计交接 / 2026-10-13](archive-stage2-ui-feedback-r1-20261013/README.md) | 仅资料/待办更新；281项载荷、远端六分片和274份源码恢复通过 | [私有项目存档](https://github.com/liamchan-rgb/classroom-boardgame/tree/456fc816e2d1b1e5bbbaebef1f1c6cbb1003f742/archive-stage2-ui-feedback-r1-20261013) |
| [阶段2美术/UI接入 / v0.9 / 2026-10-13](archive-stage2-ui-art-v0.9-20261013/README.md) | 270项载荷、71项核心测试、12张原生截图；远端六分片及266份源码恢复通过 | [私有项目存档](https://github.com/liamchan-rgb/classroom-boardgame/tree/33939b09476e2a36cd77cb1487c9199197bd336f/archive-stage2-ui-art-v0.9-20261013) |
| [阶段0—2 / v0.8 / 2026-10-12](archive-stage2-v0.8-20261012-r2/README.md) | 153项载荷、35份交付；远端SHA256和116份源码恢复通过 | [私有项目存档](https://github.com/liamchan-rgb/classroom-boardgame/tree/bfa1c745821b255ff0ef6a65ae305b8614dcfbaa/archive-stage2-v0.8-20261012-r2) |

当前推荐IPA为[v0.11的ClassroomStage2-v0.11-unsigned.ipa](https://github.com/liamchan-rgb/classroom-boardgame/blob/83a0c1ca02badf0534ef7208084b11e90cb30e5d/archive-stage2-battle-prototype-v0.11-20261019/ClassroomStage2-v0.11-unsigned.ipa)（约11.0MB，需SideStore个人签名），可独立下载。侧视战斗画面目前是静态接触姿势样片；本版尚待实体iPad反馈。v0.10、v0.9、v0.8及原设计/存档均继续保留。

## 后续操作

1. 提交该步源码/文档，建立唯一存档标签。
2. 准备交付物JSON清单（相对交付目录的明确文件名）。
3. 执行：

```sh
python3 tools/archive_milestone.py \
  --milestone archive-stage2-v0.8-20261012-r2 \
  --snapshot archive-stage2-v0.8-20261012-r2 \
  --build-record stage2/evidence/cloud-build-result-v0.8.json \
  --deliveries-root /workspace/shared \
  --delivery-list /workspace/scratch/classroom-deliveries.json \
  --output /workspace/shared/classroom-stage0-2-v0.8-20261012-r2.zip
```

4. 在archive-assets孤立分支新增该标签目录，保存ZIP（超过单文件限制时使用tools/split_milestone.py无损分片）、SHA256、清单与恢复说明并推送；记录实际GitHub文件地址。后续追加目录，不覆盖旧目录，不将此分支合并到main。也可在附件接口可用时改用私有Release。
5. 验证文件完整性与恢复出的源码，再更新该步索引并推送。

源码快照提交可能包含编译后的文档/归档工具更新；IPA实际编译提交从原构建证据读取，二者分别记录。阶段2v0.8通过云端编译与64项核心测试，新增设备交互仍等待教师反馈。

仅源码/CI交付可向同一归档工具增加`--source-only`：仍包含完整源码、Git历史、真实验证记录和明确选定的诊断ZIP，跳过新IPA要求。CI验证提交与IPA编译提交分开，清单的`compiledCommit`及`currentIPA`为空；不把PR模拟器编译当作新安装包交付。原IPA归档路径保持原样。

## 本次存储路线

初次尝试私有Release：草稿创建成功，但uploads.github.com附件接口返回HTTP401；未把空草稿当作已存档。按已授权项目备份范围改为archive-assets专用分支，无需教师重新配置账号。最终存档标签加r2，初次源码标签仍保留追溯，不覆盖。
