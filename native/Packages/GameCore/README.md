## 当前集成状态（2026-11-06）

下方是最初引入时的历史快照说明。当前experiment已扩展GameCore与Meadow支持，源码不再与UPSTREAM.json的原始指纹逐字节相同；该文件保留最初来源。原桌游库未被本轮修改。当前差异与对接边界见docs/integration/tabletop-demo-audit.json及tabletop-demo-bridge-plan.md（experiment仓库根目录）。

# Pinned tabletop rules and Meadow support adapter

Original ClassroomGameCore Sources and tests are copied byte-for-byte from liamchan-rgb/classroom-boardgame@1e9100c4c18364ea64b3ec974fe957ba4ef42f6f/native/Packages/GameCore. Source/catalog digests in UPSTREAM.json. The original repository is unchanged.

Manifest uses iOS15 for the existing pure Foundation implementation and adds separate MeadowBattleSupport and an offline exporter. The new scene calls the original engine preview/apply once at contact, with session/operation IDs. All19 skill definitions and18 items remain exact. Only a local training deer template is added to the in-memory demo catalog; this does not complete the six formal monster art assets.

Two players, two enemy targets; adventurer and ranger roles, reused existing P1 body art; hurt training start6/12 and12/18, not imported classroom saves. Supports support/rally, original adventurer effects, ordinary attacks and four existing consumables/rescue. No new female/class appearance claim, no source tabletop data/logic edit, no original archive mutation.
