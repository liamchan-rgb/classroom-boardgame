# 存档与恢复

本轮设计成果存放在GitHub独立分支 `design/ui-art-round1-20261012`，目录 `design/ui-art-delivery/`。版本标签 `archive-design-ui-art-round1-20261012` 不覆盖旧标签。

目录外的App源码、GameCore、原需求、main和工作流保持原样；不触发构建，也不产生IPA。本轮设计状态不是App版本升级。

同一分支 `design/archives/` 包含完整设计ZIP、SHA256、归档清单；本地保留同一ZIP下载。恢复：下载ZIP→核对外部SHA256→解压→根据FILE_CHECKSUMS.json核对逐文件SHA256→查看README和previews/index.html。文件可完全离线浏览；可编辑页面是sources/*.svg，图标是assets/icons/*.svg。生成原图已保留。

Git恢复仅需检出此设计标签；如接回开发对话，仅复制/接入所需design文件，App集成由开发负责，不整分支覆盖当前App。

说明：仓库AGENTS.md规定通常用tools/archive_milestone.py和archive-assets/archives/main留存；该脚本要求IPA、实际编译记录，并且归档目录与本次用户限定“独立分支/工作区的design目录交付，不改main”冲突。本轮遵循用户范围，使用design内完整ZIP、逐文件清单、独立标签与远端回读校验，不伪造IPA记录、不修改通用归档工具。之后每轮新成果仍按明确授权范围建立新版本，不覆盖本轮。

ChatGPT资料库未写入成功；本轮的长期存档以GitHub远端验证回执为准。没有备份教师iPad真实游戏进度、未交付PPTX或签名材料。
