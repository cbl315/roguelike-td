# 体系设计：遮天（物理 / 肉盾 / 真伤）

> 状态：草案，落地前需过一轮平衡校验。数值用于跑通公式与曲线，正式数值以 playtest 为准。
> 定位：GDD 三体系之一。**物理伤害 + 肉盾 + 后期真伤**——"越级杀敌"的经典爽点体系。本文自包含：读完即可完整理解遮天体系。
> 相关：通用机制（抽取/商店/经济/公式）见 [`../GAME_DESIGN.md`](../GAME_DESIGN.md)；法术流见 [`xingchenbian.md`](xingchenbian.md)；召唤流见 [`chongmei.md`](chongmei.md)。
> 来源：根据辰东《遮天》小说提炼，对齐本项目 `paths / bonds / skills / synergies / affixes / equipment` 数据 schema。

---

## 0. 一句话定位

> **境界是阶梯，九秘是境界子羁绊，天帝拳是起点技能（体系入口），"修为 + 绝学 + 帝兵"三位一体才触发最强联动——还原遮天"越级杀敌"的经典爽点。**

设计红线沿用 GDD：**装备只管经济，战斗数值归羁绊/技能，联动走 final 乘区**。遮天所有"强"都通过经济滚雪球与乘区联动体现。

---

## 1. 9 境界阶梯（轮海 → 天帝）

把遮天境界映射成 `zhutian` path 的境界树（复用 `RealmDef.bonds + reward`）。**每个大境界由若干子羁绊组成**，集齐子羁绊 → 吞噬突破 → 拿到该境界的整体 reward。

```
轮海   ── (道经/苦海/命泉/神桥/彼岸)            → reward
道宫   ── (心/肝/脾/肺/肾 五脏神，5 子羁绊)      → reward
四极   ── (左臂/右臂/左腿/右腿，4 子羁绊)         → reward
化龙   ── (龙骨多节，3 子羁绊)                    → reward
仙台   ── (仙一~仙九，9 子羁绊)                   → reward
准帝   ── (渡劫/圣体破诅咒)                        → reward
大帝   ── (帝级子羁绊)                             → reward + 解锁天帝拳联动
红尘仙 ── ⏱ 时间锁：获取后 180s 才能吞噬，吞噬前不给属性
天帝   ── ⏱ 时间锁：获取后 180s 才能吞噬；终局隐藏境界
```

### 1.1 境界 YAML（zhutian path）

```yaml
paths:
- id: zhutian
  name: 遮天
  realms:
  - name: 轮海
    bonds:
    - zt_lunhai_daojing      # 道经（轮海总纲）
    - zt_lunhai_kuhai        # 苦海
    - zt_lunhai_mingquan     # 命泉
    - zt_lunhai_shenqiao     # 神桥
    reward:
      atk_pct_delta: 0.35
      gold_per_sec_delta: 2.0       # 轮海=经济基础，给被动收入
    note: 苦海聚精气，新手期打通经济

  - name: 道宫
    bonds:                          # 五脏神
    - zt_daogong_heart             # 心之神
    - zt_daogong_liver             # 肝之神
    - zt_daogong_spleen            # 脾之神
    - zt_daogong_lung              # 肺之神
    - zt_daogong_kidney            # 肾之神
    reward:
      atk_pct_delta: 0.525
      crit_rate_delta: 0.175
    note: 五脏神觉醒，build 第一个分支点

  - name: 四极
    bonds:                          # 四肢
    - zt_siji_left_arm
    - zt_siji_right_arm
    - zt_siji_left_leg
    - zt_siji_right_leg
    reward:
      atk_pct_delta: 0.525
      attack_speed_delta: 0.35
    note: 淬炼四肢，装备槽/属性成型

  - name: 化龙
    bonds:
    - zt_hualong_spine_1
    - zt_hualong_spine_2
    - zt_hualong_spine_3
    reward:
      atk_pct_delta: 0.7
      final_dmg_mult: 0.35
    note: 脊柱化龙，中期爆发

  - name: 仙台
    bonds:                          # 仙台秘境九重
    - zt_xiantai_daneng            # 仙一·大能
    - zt_xiantai_zhandao           # 仙二·斩道（王者）
    - zt_xiantai_zhandao_peak      # 仙三·斩道圆满（半步圣人）—— "仙三斩道"
    - zt_xiantai_saint             # 仙四·圣人 —— "仙四成圣"
    - zt_xiantai_saint_king        # 仙五·圣人王
    - zt_xiantai_dasheng           # 仙六·大圣
    - zt_xiantai_bansheng          # 仙七·半圣（准帝前夜）
    - zt_xiantai_quasi_seed        # 仙八·准帝种子
    - zt_xiantai_peak              # 仙九·仙台绝巅
    reward:
      atk_pct_delta: 0.875
      final_dmg_mult: 0.525
    note: 仙台九重全满给终极 reward

  - name: 准帝
    bonds:
    - zt_zhundi_tribulation        # 渡劫
    - zt_zhundi_curse_break        # 圣体破诅咒（全书最大爽点）
    reward:
      final_dmg_mult: 0.7
      crit_dmg_delta: 1.05
    note: 圣体破诅咒成准帝

  - name: 大帝
    bonds:
    - zt_dadi_dao                  # 帝道
    - zt_dadi_cauldron             # 鼎成
    reward:
      final_dmg_mult: 1.05
    synergy_unlock: zhutian_emperor_fist   # 解锁天帝拳联动
    note: 一个时代唯一，万道相合

  - name: 红尘仙
    bonds:
    - zt_hongchen_xian
    devour_locked_seconds: 180     # ⏱ 时间锁：获取后 180s 才能吞噬
    locked_until_devoured: true    #   吞噬前不给属性
    reward:
      final_dmg_mult: 0.875
    note: 于红尘成仙，时间锁——还原"漫漫长生路"

  - name: 天帝
    bonds:
    - zt_tiandi
    devour_locked_seconds: 180     # ⏱ 时间锁
    locked_until_devoured: true
    reward:
      status: heaven_emperor
      final_dmg_mult: 1.75
    synergy_unlock: zhutian_nine_secrets
    note: 叶凡独有，终局隐藏境界
```

### 1.2 子羁绊示例（节选）

```yaml
bonds:
  # ── 轮海境 ──
  - id: zt_lunhai_daojing
    name: 道经
    set: zhutian
    effect: { atk_pct_delta: 0.10 }
  - id: zt_lunhai_kuhai
    name: 苦海
    set: zhutian
    effect: { gold_per_sec_delta: 1.0 }   # 经济基础
  # …（命泉/神桥/彼岸 同理）

  # ── 道宫境（五脏神）──
  - id: zt_daogong_heart
    name: 心之神
    set: zhutian
    effect: { atk_pct_delta: 0.14 }
  - id: zt_daogong_liver
    name: 肝之神
    set: zhutian
    effect: { lifesteal_pct: 0.05 }
  # …（脾/肺/肾 同理）
```

### 1.3 仙台九重说明

仙台秘境九重原文：仙三斩道、仙四成圣、仙五圣人王、仙六=大圣、仙七=半圣、仙八/九=准帝前夜。

> 设计取舍：仙台九重若全做成独立境界太碎，故**合并为 1 个大境界（仙台），内含 9 个子羁绊**，集齐即突破，九重全满给终极 reward。可选的阶段性吞噬（斩道/成圣/大圣 三档各给一次小 reward）需扩 `RealmDef` 支持"子里程碑"，列为可选改动。

---

## 2. 九秘（遮天境界子羁绊 `zt_jm_*`）

九秘是遮天最有辨识度的"九个古字"，**已设计为遮天境界子羁绊**（`zt_jm_*`），分散到遮天 9 个境界。修满遮天 9 境界即自动集齐全部九秘羁绊，触发"九秘合一·神禁"联动。

| 古字 | 效果 | 游戏化定位（境界子羁绊） |
|------|------|--------------------------|
| **皆**字秘 | 战力翻倍 | 爆发 / 增伤 buff |
| **斗**字秘 | 斗战圣法 | 持续输出 |
| **兵**字秘 | 御尽万兵 | 召唤 / 武器强化 |
| **者**字秘 | 调动万物 | 控制 |
| **数**字秘 | 分身 / 算计 | 召唤分身 |
| **组**字秘 | 万阵之祖 | 阵法 / AOE 场控 |
| **前**字秘 | 未卜先知 | 闪避 / 预判 / 减伤 |
| **行**字秘 | 缩地成寸 | 速度 / 攻速 |
| **临**字秘 | 镇压临身 | 眩晕 / boss 控制 |

> 九秘不占技能槽（9 个超过技能槽上限），作为境界子羁绊修满自动集齐触发。落地 id：`zt_jm_jie / zt_jm_dou / zt_jm_bing / zt_jm_zhe / zt_jm_shu / zt_jm_zu / zt_jm_qian / zt_jm_xing / zt_jm_lin`，见 `balance/data/bonds.yaml`。

---

## 3. 起点技能：天帝拳（随境界自动升级）

遮天体系**只有 1 个起点技能**：天帝拳（`emperor_fist`）。选了遮天体系就自动获得，**随境界突破自动升级**（写在境界 reward 的 `skill_upgrade` 字段），不需要手动升级、不需要抽取。

```yaml
skills:
  - id: emperor_fist
    name: 天帝拳
    rarity: UR
    tags: [physical, single_target]
    atk_ratio: 2.0
    note: 遮天体系入口——随境界突破自动升级
```

升级路线（随境界自动，无需操作）：

```
选了遮天（开局）  → 基础：物理倍率 2.0
修到化龙（境3）   → +穿甲（龙骨之力）
修到大帝（境6）   → +最终伤害（万道相合）
修到天帝（境8）   → +肉度100%（天帝之躯）+ final_dmg 翻倍
```

> 数据文件：`balance/data/skills.yaml` 中遮天仅此 1 个起点技能。强化效果由各境界 reward 的 `skill_upgrade` 字段提供。

---

## 4. 联动（触发条件用 `bond_devoured_set` / `path_realm`）

遮天联动是"修为 + 绝学 + 帝兵"三位一体的数值落点。所有联动**统一走 final_mult 乘区**。

```yaml
synergies:
  # ── 天帝之拳（修满遮天即触发）──
  - id: zhutian_emperor_fist
    name: 天帝之拳
    trigger: { all: [ { bond_devoured_set: zhutian } ] }
    effect: { final_dmg_mult: 1.0 }      # 最终伤害 +100%（乘区）
    rarity: SSR
    note: 选了遮天体系（起点技能=天帝拳），修满即触发

  # ══ 九秘·神禁（修满遮天 9 境界 = 集齐全部 9 个九秘羁绊 zt_jm_*）══
  - id: zhutian_nine_secrets
    name: 九秘合一·神禁
    trigger:
      all:
        - bond_devoured_set: zhutian     # 九秘为境界子羁绊，修满即集齐
    effect: { final_dmg_mult: 2.0 }
    rarity: EX
    note: 遮天最强战技组合，九秘合一

  # ═─ 三重联动：圣体(遮天大帝境) + 天帝鼎（装备词条） ═
  - id: saint_emperor_trinity
    name: 圣体帝鼎·三位一体
    trigger:
      all:
        - bond_devoured_set: zhutian     # 修满遮天
        - equipment_affix: gold_multiplier
    effect: { final_dmg_mult: 1.5 }
    rarity: EX
```

---

## 5. 奇遇法器（后面做）

> 状态：奇遇/掉落系统未实装，法器为后续内容储备。法器严守"只管经济"红线（经济向 affix）；帝兵额外 `granted_skill` 自带绝学。

| 法器 | 设定 | 游戏定位 |
|------|------|----------|
| **九龙拉棺 / 青铜古棺** | 贯穿全书最大谜团，接引星空古路 | 通关 / 转职道具，或最终装备 |
| **荒塔** | 镇压万古之物 | 传说控制装 |
| **菩提子**（佛陀成道树） | 叶凡伴身佛器，禅韵 | 被动成长型装备 |
| **青铜古灯**（大雷音寺那盏） | 避尘长明，佛韵 | 经济 / 续航装 |
| **天帝鼎**（叶凡自铸） | 万器之宗 | 终局装备核心（经济终局装） |
| **无始钟 / 虚空镜 / 恒宇炉**（极道帝兵） | 大帝遗留 | **掉落后自带技能**（`granted_skill`，法器解锁战技） |
| **不死药 / 神源** | 续命 / 破境 | 消耗品 / 破境道具 |

帝兵自带的"绝学"（如无始钟鸣、虚空碎镜）定义在技能表，但**不进抽取池**（`pool: drop_only`），只能靠掉落获得。

---

## 6. 平衡数据

### 6.1 境界 reward 数值总览

| 境界 | rarity | 核心 reward |
|------|--------|-------------|
| 轮海 | SR | ATK +35% + 被动金 +2/s |
| 道宫 | SR | ATK +52.5% + 暴击率 +17.5% |
| 四极 | SR | ATK +52.5% + 攻速 +35% |
| 化龙 | SSR | ATK +70% + 最终伤害 +35% |
| 仙台 | SSR | ATK +87.5% + 最终伤害 +52.5% |
| 准帝 | UR | 最终伤害 +70% + 暴伤 +105% |
| 大帝 | UR | 最终伤害 +105% + 解锁天帝拳联动 |
| 红尘仙 | EX | 最终伤害 +87.5%（⏱ 时间锁 180s） |
| 天帝 | EX | 最终伤害 +175% + 解锁九秘合一联动（⏱ 时间锁 180s） |

> 数值设计意图：轮海/道宫/四极给 ATK 等加法底子（基础数值层），化龙起开始给 `final_dmg_mult`（最终乘区），后期境界 reward 越来越偏乘区——符合 GDD "基础数值靠羁绊、最终倍率靠修炼到顶"的分层。

### 6.2 rarity 分布

- 遮天 9 境界 rarity 阶梯：SR(轮海/道宫/四极) → SSR(化龙/仙台) → UR(准帝/大帝) → EX(红尘仙/天帝)
- 子羁绊总数 ~31 个（含 9 个九秘子羁绊 `zt_jm_*`）
- 抽取概率对齐 GDD 全池权重：N 58 / SR 30 / SSR 9 / UR 2.5 / EX 0.5（EX 专为天帝/九秘等终局内容保留）

---

## 7. 新机制与引擎改动

| 机制 | 说明 | 引擎改动 |
|------|------|----------|
| 境界改名 + 子羁绊细化 | 复用现有 `RealmDef.bonds + reward`，只改数据 | ✅ 零引擎改动 |
| 时间锁吞噬（红尘仙/天帝） | `devour_locked_seconds` + `locked_until_devoured`：入手 N 秒内不可吞噬，吞噬前 effect 不生效 | 🆕 需扩 `PlayerState.bond_acquired_at` + 吞噬校验 |
| 装备自带技能（`granted_skill`） | 掉落法器带 `granted_skill`，装备后获得该技能（独立于起点技能） | 🆕 需扩 equipment schema + skill 池标记 `pool: drop_only` |
| 源天师外挂 path（可选） | 独立 `yuanshu` path，经济识宝增益，与 `zhutian` 互不依赖 | ✅ 零引擎改动（独立 path 独立判定） |
| 阶段性吞噬（可选） | 仙台九重内部设子里程碑，集齐斩道/成圣/大圣各给小 reward | 🆕 可选，需扩 `RealmDef.milestones` |

---

## 8. 设计要点（为什么这样映射）

1. **境界名用遮天原典** → 轮海/道宫/四极/化龙/仙台/准帝/大帝/红尘仙/天帝，辨识度拉满。
2. **大境界拆子羁绊** → 还原小说"道宫修五脏、四极修四肢"的修炼颗粒感，集齐才突破，复用现有 realm 结构。
3. **九秘作为境界子羁绊** → 9 个超过技能槽，改为子羁绊修满自动集齐触发神禁，不占槽位。
4. **帝兵绝学走掉落而非技能池** → 让法器不只是经济装，而是真能解锁战技；技能池保持"人能学的"纯净（仅天帝拳起点技能）。
5. **红尘仙/天帝时间锁** → 还原小说"长生漫漫、成仙非一日"的叙事，同时给终局羁绊一个天然的反滚雪球阀门。
6. **三重联动**（境界修满 + 起点技能 + 装备词条）= 还原"修为 + 绝学 + 帝兵"三位一体才能越级杀敌的经典桥段。

---

## 9. 待办与风险

- [ ] 落地前跑 `balance/` 测试与报表，确认新联动（尤其 `zhutian_nine_secrets` ×2 final、红尘仙时间锁）不破坏平衡曲线。
- [ ] `dodge / stun_chance / slow_chance / curse_immunity / dodge_chance_delta` 等字段需在 `CombatStats` 补字段，否则 loader 报未知 key。
- [ ] 时间锁吞噬的 UX：需在 UI 上显示"距可吞噬剩余时间"，避免玩家困惑。
- [ ] `granted_skill`（法器技能）占不占技能槽？建议占（否则法器给技能纯赚），需与 GDD 技能机制对齐。
- [ ] 命名去重：新增 path/bond id 需与现有 `zt_*` 旧条目去重；境界改名是破坏性数据改动，落地时全局搜索替换。
