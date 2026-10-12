# 项目长期存档

按教师2026-10-12要求，每个有新成果的交付步骤都建立一个可恢复存档。

长期位置为本项目的私有GitHub Releases，Git标签固定源码快照；本目录保存索引、清单和交付状态。Actions产物只用于构建诊断，不能代替长期存档。ZIP和IPA不写入Git主历史，避免历史包递归嵌套。

## 当前归档

正在建立阶段0—2完整存档：原需求/开发步骤、实施计划、源码及版本历史、测试数据和日志、美术/UI标准、历史交付包及当前v0.8 IPA。完成上传后，具体索引写入 `archive-stage2-v0.8-20261012/`。

## 后续操作

1. 提交该步源码/文档，建立唯一存档标签。
2. 准备交付物JSON清单（相对交付目录的明确文件名）。
3. 执行：

```sh
python3 tools/archive_milestone.py \
  --milestone archive-stage2-v0.8-20261012 \
  --snapshot archive-stage2-v0.8-20261012 \
  --build-record stage2/evidence/cloud-build-result-v0.8.json \
  --deliveries-root /workspace/shared \
  --delivery-list /workspace/scratch/classroom-deliveries.json \
  --output /workspace/shared/classroom-stage0-2-v0.8-20261012.zip
```

4. 对本项目私有Release上传ZIP、SHA256、清单与恢复说明；记录实际下载地址。
5. 验证文件完整性与恢复出的源码，再更新该步索引并推送。

源码快照提交可能包含编译后的文档/归档工具更新；IPA实际编译提交从原构建证据读取，二者分别记录。阶段2v0.8通过云端编译与64项核心测试，新增设备交互仍等待教师反馈。
