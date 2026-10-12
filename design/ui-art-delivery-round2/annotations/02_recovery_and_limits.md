# 恢复与证据范围

分支：design/ui-art-round1-20261012。第一轮固定标签archive-design-ui-art-round1-20261012和ZIP保留。
审核意见标签：archive-design-review-feedback-20261012，指向3543a2022b477c5a951eb50db39fb7e66ab10004。
第二轮标签：archive-design-ui-art-round2-20261012。完整ZIP与上传回执位于design/archives，索引在design/ARCHIVE_INDEX.md。

下载第二轮ZIP，核对旁边.sha256；解压后按FILE_CHECKSUMS.json核对全部载荷；用PNG或previews/index.html离线查看。SVG可编辑，sources/build_round2.py与export_previews.cjs可重建，需Python3、Node/playwright、Chromium、Noto Sans CJK SC；这些是设计导出依赖，App仍只用系统字体和本地资产。参考生成脚本只在本设计包中运行，不能替换GameCore。

归档仅包含设计、审核意见、可编辑源、预览、素材与校验。不包含账号凭据、签名材料或真实课堂资料。按用户明确范围不修改main/archive-assets或构建工作流，采用与第一轮相同的design内ZIP、标签及逐文件校验，不伪造IPA或Git构建记录。

静态检查不是原生/真机验收：尚未测iPad系统毛玻璃/液态玻璃、点击效率、最远座位、无线断连隐私、实际PPTX或人物动画。12张新版仍待用户审核；历史图审核通过不代表这些新版通过。

之后每次设计更新均先记录反馈、完成修改及检查，上传独立设计分支design目录，建立新ZIP与唯一标签并回读核验。保留旧版本、旧ZIP和旧标签。索引和回执收尾属于同一步，不递归归档。
