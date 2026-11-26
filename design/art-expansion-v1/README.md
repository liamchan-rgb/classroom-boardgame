# 《林间行旅》主游戏拓展美术与像素特效资源包（v1.0 — 已打包待安装）

> **当前状态**：已完成全部美术资源、角色穿戴件与 8 组 PixelFX 特效制作、视觉审核、自动化校验及归档打包；**尚未安装至主工程**（现有 `Assets.xcassets/`、`pixel-baker.js`、`initial-content.json` 及 837 项锁定原文件均保持 100% 零改动），等待确认后一键安装。

## 1. 交付清单一览（100% 对齐 `design/主游戏拓展企划_职业装备怪物_美术交接_v1.txt`）

| 模块 | 路径 | 数量 | 硬性规格 |
|---|---|---:|---|
| **职业徽章** | `class-badges/ClassBadge*.png` | **14 枚**（新增 10 + 统一既有 4） | `256×256` RGBA 透明像素绘本徽章，零白边 |
| **物品静态图标** | `item-icons/PixelIcon*.png` | **53 张**（武器 17 / 护甲 14 / 饰品 14 / 补给 8） | `512×512` RGBA（严格 `32×32` 逻辑像素 16× 最近邻放大） |
| **物品动态流光条** | `item-icon-fx/PixelIconFX*.png` | **41 条**（稀有蓝 13 / 史诗紫 13 / 传说橙金 15） | `4608×192` RGBA（24 帧 × `192×192`，12 FPS 无缝循环） |
| **角色上身装备件** | `pixel-baker/pixel_equipment_expansion.js` | **31 件**（武器 17 + 护甲 14） | `42×62` 逻辑像素 5 方向，复用 `down/shoulder/bow/up` 骨架；9 把史诗/传说武器 + 7 套史诗/传说护甲均附 4 相位 `bakeFx` 流光 |
| **怪物双序列帧图集** | `monsters/MeadowMonster*Motion.png` + `Death.png` | **16 只 = 32 张图集** + `motion_expansion.json` | Motion `3072×1792`（8×7=56 帧，朝左，锚点 `[178.5, 240]`）；Death `4096×1600`（8×5=40 帧，无血腥星光退场，末帧全透明）；`mode=P` 索引透明 PNG |
| **远程怪物弹道** | `monsters/projectiles/Proj*.png` | **8 张** | `64×64` / `128×64` 朝左硬像素 PNG |
| **像素战斗特效包** | `pixel-fx/PixelFX_*.png` + `recipes_expansion.json` | **8 组包（23 片段）+ 70 条配方** | 20 FPS、`1 fx px = 1 hero px`、`back+front` 双层图集，覆盖全部 30 新职业技 + 6 套装技 + 26 怪物技 + 8 远程攻击 |
| **视觉验收总览图** | `previews/qa_*.png` | **9 张** | 全部资产拼图（含暗/浅双底、动作抽帧、角色实穿 5 向与特效抽帧） |
| **归档压缩包** | `artifacts/meadow-expansion-art-v1.zip` | **1 包** | 自包含压缩归档 + `asset-manifest.json`（全量 SHA-256 校验） |

## 2. 校验与后续一键安装命令

- **独立校验（只读，不改动主工程）**：
  ```bash
  python3 design/art-expansion-v1/tools/verify_expansion_pack.py --zip artifacts/meadow-expansion-art-v1.zip
  ```
- **预演安装（Dry-Run，只打印变更清单）**：
  ```bash
  python3 design/art-expansion-v1/tools/install_expansion_pack.py
  ```
- **正式一键安装（待你通知后再执行）**：
  ```bash
  python3 design/art-expansion-v1/tools/install_expansion_pack.py --apply
  ```
