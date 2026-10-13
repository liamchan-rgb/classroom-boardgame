# 原生材质交接：用户本轮新反馈优先

本轮取消“常规小控件可选纯色”的旧理解：只有极小控件/符号采用纯色；其他常规按钮统一原生液态玻璃。毛玻璃与液态玻璃按功能分配，不能把所有透明白块都称为液态玻璃。

| 对象 | 正式原生实现 | 样稿中的视觉近似 |
|---|---|---|
| 顶部、地图、战斗外框、轨道、底部详情模块 | SwiftUI `.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26))` | backdrop-filter blur26px + 弱透色、细白边、柔影 |
| 技能信息卡、地点名称、生命/盾读数底衬 | `.thinMaterial`或`.regularMaterial`；信息卡不套交互按钮 | 较轻毛玻璃，稳定文字衬底 |
| 镜头定位/总览/缩放常规按钮 | 系统 `.glassEffect(.regular.interactive(), in: Circle())`，相邻控件在`GlassEffectContainer`内 | 通透边缘/折射高光、浅投影，52px圆形 |
| 极小当前指针、身份状态符号 | 纯色矢量；保持非颜色标记 | 12×9px实色指针、叉/勾/时钟 |

不把渐变PNG导入App作为玻璃底板；真正的模糊/折射应由系统根据实时背景绘制。资产只有完整角色/物品/环境，模块和按钮由原生组件生成。文字/数值/姓名不烘焙进运行图片。

按钮参考（仅显示层，原动作闭包仍由开发绑定；不在本轮修改App）：

```swift
GlassEffectContainer(spacing: 12) {
    HStack(spacing: 12) {
        Button(action: returnCameraToActor) {
            Image(systemName: "scope")
                .frame(width: 52, height: 52)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
    }
}
```

大模块使用Material，不在每个模块外再套交互glassEffect。按钮使用一次系统玻璃，不叠两层buttonStyle glass与glassEffect；相邻控件的合并行为由GlassEffectContainer统一。以上为iPadOS27工程的接入建议，未编译验证。

维持5%公开安全区与约24px以上必要文字；原生教师常规按钮触区至少44pt，视觉大小不等同于公开输出像素。液态玻璃不改变动作合法性、当前回合、镜头/奖励对象分离、公开只读或一次提交。技能卡不是执行按钮；电视没有触控时仍由教师iPad操控等价镜头操作。

减少透明度/增加对比度按系统无障碍设置使用稳定实色衬底；属于可访问性回退，不是默认把常规按钮改回实色。减少动态时关闭玻璃形变/弹性与场景位移，保持相同终态信息。原生毛玻璃、液态玻璃折射、外屏阅读距离与系统回退仍需接入后真机核对。
