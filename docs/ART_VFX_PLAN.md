# 羁绊视觉升级 + 打击感 美术资源计划（VFX Plan）

> 状态：设计定稿，2026-11-06。配套 prompt 已写入 [`../tools/art_prompts.yaml`](../tools/art_prompts.yaml)，可直接 `gen-art gen` 出图。
> 定位：本文回答"要让羁绊升级看得见、打击有爽感，**需要哪些美术资源、怎么生成、怎么分级**"。生成管线沿用 [`ART_PIPELINE.md`](ART_PIPELINE.md)；程序接线（粒子/击退/换形态逻辑）在 §7 列配套清单，不展开设计。
> 上游依据：现状调研（2026-11-04，见 §1）＋ [`systems/chongmei.md`](systems/chongmei.md) 进化表 ＋ 业界实践（§2）。

---

## 0. 目标（需求原文 → 设计回应）

| # | 需求 | 设计回应 | 资源量 |
|---|------|----------|--------|
| 1 | 召唤流派：宠物和人物随羁绊显示的效果升级 | 莫邪 5 形态 + 白魇魔 2 阶强化 + 主角半魔化魔人 + 第三魂宠三选一 + hero 通用法相 3 档 | 12 张（另 1 可选） |
| 2 | 其他流派：按羁绊吞噬进度显示不同特效 | 升境法阵（4 IP 系专属+1 通用）+ 境界徽章 4 档 + hero 境界光环 3 档 + 宠物光环 3 档 + 吞噬进度环 | 16 张 |
| 3 | 攻击特效随羁绊吞噬升级 | 弹道 4 元素 × 3 档 + 命中特效 2 档 × 2 类 + 击杀爆裂 2 档 + 体系终极演出 4 张 | 16 张 |
| 4 | 小怪质感、打击感、爽感 | 5 小怪受击/死亡状态帧 + Boss 狂暴形态 + Boss 半身像 + 碎屑粒子 4 张 + 血条贴图 2 张（＋程序侧击退/粒子） | 22 张 |

**新增 66 张**（另有存量复用：弹道/命中 tier1 共 6 张已在库）。全部按 Seedream 精修价 ¥0.25~0.3/张估算 **≈ ¥17~20**，半天出完。

---

## 1. 现状基线（2026-11-04 调研结论）

已有可复用的底子：

- **程序 juice 齐全**：受击闪白（`juice.gd:151`）、顿帧（击杀 40ms / Boss 120ms / 突破 150ms）、trauma 震屏、屏闪、伤害数字（普通/暴击/大招三档）、死亡 squash+金环、攻击 squash——见 `game_manager.gd:130-184`。
- **升境钩子现成**：`EventBus.bond_devoured` → `hud.gd:230` 已有大字+金闪+顿帧演出，但**零贴图参与**。
- **半魔化钩子现成**：`build.summon_unit_devoured` → `game_manager.gd:617` 暗紫 Shockwave 演出已有。
- **羁绊结构**：7 条路径（zhutian/xingchenbian/chongmei/doupo 各 9 境，generic_phys/magic/summon 各 4 境），`balance/data/bonds.yaml` 为 SSOT；`path_realm` 记录进度。

关键缺口（本计划补的）：

1. 全项目 **零粒子系统、零 shader**（`fx_hit_normal/fx_hit_crit` 有图未接线，`fx_aoe_blast/fx_transform_great_sage` 有图未接线）。
2. 敌人/召唤物全是**单张静态图**，无受击/死亡状态帧；无击退。
3. 羁绊三处 UI（底部池条 / Tab 面板 / Lobby 卡）**零贴图**，升境演出无美术。
4. 宠魅进化表（莫邪 5 形态、半魔化、第三魂宠）在 `chongmei.md` 已设计，代码只有 2 张图、无换形态逻辑。
5. `assets/` 缺目录：`skills/ debuffs/ ui/ bg/`；现有图实际 256²，与 yaml 目标尺寸不符（入库前统一缩放，见 ART_PIPELINE §7）。

---

## 2. 设计原则（业界实践 → 本项目落地）

| 原则 | 业界参照 | 落地 |
|------|----------|------|
| **视觉分 3 档，不逐级出图** | 皇室战争 14 级只有 4 档边框视觉；宝可梦只在关键节点进化 | 9 境 → 3 档（t1/t2/t3），4 境符文系 → 2 档（§4 公式） |
| **通用底图 + 程序染色** | Supercell 通用框架按稀有度 tint | 光环/徽章/粒子出中性银白版，运行时 `modulate` 染体系色（`GROUP_COLORS` 已有 7 色） |
| **换贴图 + 程序增强双轨** | Dota 2 至宝：特效升级同时粒子变密 | tier 提升时同步调拖尾密度/粒子数/震屏强度——一半表现力不花钱 |
| **AI 出静态，程序做动态** | 本仓库 ART_PIPELINE §6 已踩坑（AI 帧间抖动） | 形变动画 = 单帧 + Juice 程序变形；多状态 = Seedream 参考图链/组图保主体一致 |
| **克制，juice 传达信息** | [Game Feel 20 原则](https://www.manuelsanchezdev.com/blog/game-feel-principles-animated-godot)、[Stardock TD 设计日志](https://www.stardock.com/games/article/495008/siege-of-centauri-dev-journal-what-makes-a-good-tower-defense-game) | 顿帧只留给击杀/升境；震屏走 trauma 衰减（现状已符合）；特效档位必须能读出"变强了"（BTD6 标准：反馈传达状态而非炫技） |

---

## 3. 命名与色系映射（出图前必须遵守）

### 3.1 色系 → 路径正式映射表

`ART_PIPELINE.md` 的 8 套美术色系（遮天金紫/风云青/黑神话黑红/星陨紫/苍焰蓝/铁壁灰钢/淘金币/兽魂绿）与游戏 7 条路径此前**无正式映射**（其中 4 套无对应游戏体系）。本计划起按 `path_id` 命名，映射如下：

| path_id（SSOT） | 体系名 | 体系色 | 旧美术色系 |
|---|---|---|---|
| `zhutian` | 遮天 | 金 #FFC759 | 遮天金紫 ✅ |
| `xingchenbian` | 星辰变 | 蓝 | 星陨紫（微调为星蓝紫） |
| `chongmei` | 宠魅 | 紫 | 兽魂绿 → **改宠魅紫**（召唤=紫，与现有 `GROUP_COLORS` 一致） |
| `doupo` | 斗破 | 焰红 | 苍焰蓝 → **改焰红**（同上） |
| `generic_phys / generic_magic / generic_summon` | 符文三系 | 灰绿 | 通用（中性银白 tint） |
| —（无路径） | — | — | 风云青 / 黑神话黑红 / 铁壁灰钢 / 淘金币 → **legacy**：仅 bonds 卡面旧条目保留，不再新增 |

> 决策：体系色以 `hud/bond_pool_bar.gd:8-14 GROUP_COLORS` 为准（玩家已在看），美术向代码对齐，而非反之。

### 3.2 命名规范

沿用 `ART_PIPELINE.md` §7 前缀，新增规则：

- 特效档位后缀 `_t1/_t2/_t3`（tier1 可省略，与存量兼容：`fx_projectile_fire` = t1）。
- 状态帧后缀 `_hit`（受击形变）/`_death`（死亡爆裂前帧）/`_enraged`（Boss 狂暴）/`_portrait`（半身像）。
- 体系专属资源中段带 path_id：`aura_circle_zhutian`、`fx_ult_doupo`。

---

## 4. Tier 映射规则（数据层公式，程序接线用）

```gdscript
# realm(0-based, path_realm 值) → 视觉档位
func realm_to_tier(realms_completed: int, max_realm: int) -> int:
    if max_realm >= 9:  return clampi(realms_completed / 3, 1, 3)      # 9 境系：0-2→t1, 3-5→t2, 6-8→t3
    else:               return clampi((realms_completed + 1) / 2, 1, 2) # 4 境符文系：0-1→t1, 2-3→t2
```

**宠魅特例（形态而非档位，遵 `chongmei.md` §2.1/§5 的 `summon_upgrade` 表）**：

| 境界 | 莫邪精灵图 | 白魇魔 | 主角 |
|------|-----------|--------|------|
| 境0 魂徒 | moonfox（已有） | — | 普通剑修 |
| 境1 魂士 | sixtail_evil | — | — |
| 境2 魂师 | ninetail_fire | 登场（已有 baiyanmeng） | — |
| 境3 魂主 | — | baiyanmeng_awakened | — |
| 境5 魂宰 | sevensin | baiyanmeng_perfect | — |
| 境6 魂朽 | — | **被吞噬（消失）** | **banmo 半魔化魔人**（周期变身→境7 冷却减半→境8 常驻） |
| 境7 千年 | zidi_purple | — | 第三魂宠三选一登场 |

---

## 5. 资源清单

### 5.1 P0 打击感（22 张，收益最大先做）

> 程序侧零美术前置：**击退**（受击位移 8-12px 弹性回弹）、**GPUParticles2D 引入**（全项目目前零粒子）。这两项不依赖出图，可与生图并行。

| id | 张数 | 规格 | 要点 |
|----|------|------|------|
| `enemy_{grunt,runner,brute,shaman,frost_wraith}_hit` | 5 | 1024² | 受击形变帧：同一角色的挤压/痛苦表情版本，切帧 60ms+白色 overlay（死亡细胞式手感核心）。**图生图**：以现有 `enemy_*.png` 为参考图 |
| `enemy_{...}_death` | 5 | 1024² | 死亡爆裂前帧：崩解/碎裂中的形变，接现有金环+squash |
| `boss_{blind_eye,regen_core,immortal_body}_enraged` | 3 | 1024² | 血 <50% 换图（现有 modulate 变红保留，叠加贴图升级） |
| `boss_{...}_portrait` | 3 | 512² | 顶部 HUD 大血条旁半身像 |
| `particle_{debris_stone,blood_drop,energy_shard,soul_flame}` | 4 | 512²（入库缩 128） | 碎屑粒子贴图：石屑/血滴/能量碎片/魂火；中性色版，部分按体系 tint |
| `ui_hp_bar_{normal,boss}` | 2 | 1024×256 裁切 | 血条三件套贴图（elite 复用 normal tint 放大），替代 4px draw_rect |

### 5.2 P1 羁绊进度反馈（16 张，钩子现成接线即生效）

| id | 张数 | 规格 | 要点 |
|----|------|------|------|
| `aura_circle_{zhutian,xingchenbian,chongmei,doupo}` | 4 | 512² | 升境爆发法阵，各体系文化符号（鼎纹/星轨/魂纹/焰环），直接按体系色出图；升境瞬间英雄脚下展开 0.8s，喂给 `bond_devoured` 现有演出 |
| `aura_circle_generic` | 1 | 512² | 符文三系通用法阵，中性银白 tint |
| `badge_realm_{t1,t2,t3,t4}` | 4 | 512² | 境界徽章：石→银→金→圆满鎏金（t4 复用给"★圆满"标记）；升境大字旁盖章动画 |
| `aura_hero_{t1,t2,t3}` | 3 | 512² | 英雄脚下境界光环，中性银白，按最高体系 tint——**非召唤流派"我练到哪了"的常驻可视** |
| `aura_pet_{t1,t2,t3}` | 3 | 512² | 召唤物脚下光环，同上 |
| `ring_devour_progress` | 1 | 256² | 吞噬进度环（当前境界 x/y 填充），贴图版更精致；可先程序画圆环过渡 |

### 5.3 P2 召唤进化（12 张必出 + 1 可选，需先实装形态切换逻辑）

| id | 张数 | 规格 | 要点 |
|----|------|------|------|
| `moxie_{sixtail_evil,ninetail_fire,sevensin,zidi_purple}` | 4 | 1024² | 莫邪进化链，文件名遵 `chongmei.md` §2.1；**同一只狐**的递进（尾数↑/焰色银→橙→罪红→紫），用 Seedream 参考图链（上一形态作参考图）保证主体一致 |
| `baiyanmeng_{awakened,perfect}` | 2 | 1024² | 白魇魔境 3 觉醒（魔焰暴涨）/境 5 完全体（君主级），青焰→深紫黑焰 |
| `hero_banmo_form` | 1 | 1024² | **主角半魔化魔人**（境 6+，宠魅流派 hero 本体升级）；钩子 `summon_unit_devoured` 演出已有，换贴图+变身框架（transform_* 字段已在 chongmei.md 设计） |
| `summon_{dragonlet,flower_king,wind_binder}` | 3 | 1024² | 第三魂宠三选一起点形态（小蛰龙/善恶花王/缚风灵）；终极形态（天苍青蛰龙等）后续按需追加 |
| `hero_sword_cultivator_{v2,v3}` | 2 | 1024² | hero 通用法相：御剑境（剑随身环）/万剑归宗（背后剑阵）；按主修体系 tint 拔剑光 |
| `hero_banmo_portrait`（可选） | 1 | 512² | 半魔化变身演出立绘（预留，P2 尾） |
| （存量）`summon_moxie`/`summon_baiyanmeng`/`hero_sword_cultivator` | 3 | — | 已在库，作为进化链 t1 和参考图基底 |

### 5.4 P3 攻击特效 tier（16 张，依赖 tier 查表先建）

| id | 张数 | 规格 | 要点 |
|----|------|------|------|
| `fx_projectile_{physical,fire,ice,thunder}_t2/t3` | 8 | 512²（入库缩 256） | tier2 加尾焰/外环，tier3 加核心+双环+环绕微粒；**同时程序增强**：拖尾帧数 6→10、拉伸系数、ADD 混合亮度 |
| `fx_hit_{normal,crit}_t2` | 2 | 512² | tier1 已在库（未接线——先接线！）；t2 加层叠冲击环 |
| `fx_kill_{burst,burst_elite}` | 2 | 512² | 击杀爆裂（碎屑向心）+ 精英击杀大爆；接现有死亡金环叠加 |
| `fx_ult_{zhutian,xingchenbian,chongmei,doupo}` | 4 | 1024² | 修满整条路径（`bond_devoured_set` 联动触发）全屏终极演出：天帝临世/星辰归墟/紫帝降临/焚天炎环。（存量 `fx_transform_great_sage` 属 legacy 色系，保留不接线） |

---

## 6. 生成策略（衔接 ART_PIPELINE 与 2026-11 模型升级调研）

1. **顺序**：先出"锚点链"——`enemy_grunt` 全状态帧、莫邪进化链第 1 张复用存量 → 满意的图作为后续**参考图**（Seedream 5.0 支持最多 17 张参考图；4.5 亦支持组图）。
2. **状态帧/进化链一律图生图**，不用纯文生图直出（主体必跑偏）；`art_prompts.yaml` 中这些条目已注明"参考图"。
3. **中性银白版 + tint**：`aura_hero/pet_*`、`badge_realm_t1-t3`、`particle_energy_shard` 出无彩色版本，运行时染 `GROUP_COLORS`。
4. **透明背景试点**：本批叠加型特效（光环/法阵/粒子/弹道）优先试"生成时直接要透明背景 PNG"（Seedream 系支持）；失败回退绿幕+remove.bg 现有链路，零风险。
5. **成本**：66 张 × ¥0.25~0.3 ≈ **¥17~20**（Seedream 4.5/5.0 精修价，2026-11 调研）；高淘汰率的粒子/进度环可先走 CogView-3-Flash 免费档试构图。
6. **入库后处理**：统一缩放（特效 256/粒子 128/敌人 1024 存 256）、TinyPNG 压缩，规则同 ART_PIPELINE §7。

---

## 7. 程序侧配套（非美术，列出防漏）

| 项 | 位置 | 说明 |
|----|------|------|
| GPUParticles2D 引入 | 新 `scenes/fx/particles.fx` 或直接节点 | 全项目零粒子；受击飞溅/死亡爆裂/升境法阵火星全靠它 |
| 击退 | `enemy.gd` 受击 | 位移 8-12px 弹性回弹，一次性 tween |
| fx_hit 接线 | `game_manager.gd:529` 附近 | 命中瞬间 spawn 贴图特效（图早在库里） |
| tier 查表 | 新 `client/src/core/vfx_tiers.gd` | §4 公式；弹道/命中/光环按 `path_realm` 查档 |
| 召唤形态切换 | `summon_unit.gd` + `build_state.gd` | `summon_upgrade` 表（chongmei.md §5 已设计）→ 换贴图+进化演出（顿帧+光柱+新旧形态对比） |
| 半魔化变身 | hero 侧 | 复用 transform_* 框架（黑神话大圣变身机制） |
| 升境演出贴图化 | `hud.gd:230` | 大字+金缝之间插入法阵展开+徽章盖章 |
| bond_pool_bar 升境动画 | `hud/bond_pool_bar.gd:40` | 目前 queue_free 全量重建，改为升境卡组闪光飞入动画 |

---

## 8. 执行顺序

1. **P0**：程序项（粒子/击退/fx_hit 接线）＋ 生图（状态帧→Boss→粒子→血条）→ 小怪手感验收
2. **P1**：法阵/徽章/光环出图 → 接 `bond_devoured` 演出 → 三处羁绊 UI 贴图化验证
3. **P2**：`summon_upgrade` 数据实装 → 莫邪进化链/白魇魔/半魔化出图接线 → 宠魅全流程验收
4. **P3**：tier 查表 → 弹道/命中 tier2/3 → 终极演出 4 张
5. 全量回归：`visual-qa` 技能巡检一致性（ART_PIPELINE 8.4 既定流程）
