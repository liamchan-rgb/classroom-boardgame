# 阶段2美术接入 v0.9 长期存档

源码快照893cc3021211492c4ecce4ecd852cec9702d032f，源码标签archive-stage2-ui-art-v0.9-20261013；IPA编译提交1379bd2e174d88c582bb19fa8ea1f64c180a74da。设计固定提交f43db0502bf3a9df9fef8bb7c699b6dce86c3425。71项核心测试、12张原生截图、66张离线素材通过；用户新版真机和最终逐图审美待反馈。

直接下载安装包：ClassroomStage2-v0.9-unsigned.ipa，10445942字节，SHA256 7d3a6e27184e5a07876ba769f8f54df8d7651d303c68f034c9e838147945a601；沿用原SideStore账号个人签名和原Bundle ID。

完整逻辑ZIP为classroom-stage2-ui-art-v0.9-20261013.zip，290894459字节，SHA256 58738f4104e7c1c08cac02cadd4d8fc3f72af766c4e9a5d4a6ba67bb1826a6d7。包含270份载荷，完整源码、设计绑定/资产、截图/检查、Git历史包、当前IPA与完整构建诊断ZIP。源历史保留设计分支和旧ZIP/标签，排除archive-assets，避免递归备份。

GitHub普通Git拒收超过100MB的单文件，因此无损保存为6份48MiB以内分片；transport.json记录每份长度/校验及完整ZIP校验。下载本目录所有分片、transport.json和restore_zip.py，在本目录运行：

```sh
python3 restore_zip.py
```

程序逐片校验、合并并校验完整ZIP，不覆盖已有文件。解压后按恢复说明从git-history.bundle克隆并检出上述源码快照。也可从本次交付的本地完整ZIP直接恢复，无须合并。

此目录是本项目私有长期备份，不以Actions三天有效产物代替。未包含教师iPad未交付的真实课堂进度、文件或签名材料。旧存档和旧标签均保留。
