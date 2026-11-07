# 离线合成审核

这份 GIF 使用真实 GameEngine 命令导出的 PublicPlayFrame、相同注册分层与动作 JSON 合成，普通速度 3 秒循环。它是离线资源/时间轴预览，不是原生 UIKit、模拟器或外接屏截图；辉光的 Pillow 合成与 SwiftUI plusLighter 会有差异。完整画面联系表用于检查整体比例。

教师端保留原控制台；公开端的新呈现只读取已过滤的公开结果。教师端的选人、目标选择、备注和资源编辑不进入这些 fixture。

复现：先 swift test --package-path native/Packages/GameCore；用 swiftc -I .build/.../Modules 将 native/tools/meadow_fixture_export.swift 与 ClassroomGameCore.build/*.o 链接为离线命令行工具，保存 stdout 为 meadow-fixtures.json；再运行 python3 native/tools/render_meadow_bridge.py fixtures.json output-dir。
