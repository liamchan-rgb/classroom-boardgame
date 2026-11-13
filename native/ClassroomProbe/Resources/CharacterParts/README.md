# 人物部件数据

发型（`hair/`）和五官（`face/`）的数据文件。网页制作工具 `hd2d-walk-demo/` 和游戏里的 Swift 烘焙器读的是同一份文件：

- 新增一个发型或一套五官 = 在对应目录里加一个 JSON，`id` 全局唯一。
- 字段含义、取值范围和硬性要求见 `docs/CHARACTER_SPRITES.md` 第 6.2、6.3 节。
