# MeadowJourney 编译检查（快照）

这是 [liamchan-rgb/experiment](https://github.com/liamchan-rgb/experiment) 中 MeadowJourney iPad 工程的快照，只用来在本仓库已验证可用的 macOS/Xcode 运行器（`xcode-27`）上编译、跑单元测试。原工程的 `macos-15` 构建目前起不来。

- 来源：experiment 分支 `claude/hd2d-pixel-character-walk-s2pdwi`，提交见 `SOURCE_COMMIT`。
- 流水线：`.github/workflows/meadowjourney-character-check.yml`，只在本分支、且改动了本目录或该流水线文件时运行，也可手动运行。
- 检查内容：工程静态校验、模拟器编译、全部单元测试（其中 `CharacterSpriteTests.testBakedAtlasesMatchWebExport` 比对 Swift 现场烘焙与网页工具导出的人物图集，日志里搜 `[character-parity]`），以及一张模拟器截图。
- 不改动桌游 App（`native/`）的任何文件，不生成 IPA，不使用签名。

更新快照：在 experiment 工程根目录执行

```bash
git archive --format=tar HEAD MeadowJourney.xcodeproj Sources Tests UITests scripts | tar -x -C <本目录>
git rev-parse HEAD > <本目录>/SOURCE_COMMIT
```

修好的问题要改回 experiment 仓库（这里只是检查用的副本）。
