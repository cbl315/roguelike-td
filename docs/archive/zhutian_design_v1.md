# 《遮天》主题：装备 + 技能 + 羁绊联动模板

> 状态：设计草案（v2），暂不改动现有 `balance/data/*.yaml`。本文是评审稿，落地前需过一轮平衡校验。
>
> ⚠️ **重要：技能系统已重构（2026-07-12，见 `skill_refactor_design.md`）。** 本文部分章节为重构前的设计稿，与当前实现不符的地方：
> - **九秘从技能转为遮天境界子羁绊**（`zt_jm_*`，分散到遮天 9 个境界），不再是 `jt_*` 技能。见 §1.3 / §2.2 标注。
> - **§2.2 的"九秘 + 天帝拳"技能池已废弃**——现在遮天只有 1 个起点技能（emperor_fist），九秘归羁绊。
> - **联动触发 `skill_owned` 已改为 `bond_devoured_set: zhutian` / `path_realm`**。见 §2.4 标注。
> - 实际数据以 `balance/data/*.yaml` 为准。
> 来源：根据辰东《遮天》小说（精校版全文）提炼，对齐本项目既有的 `equipment / skills / bonds / synergies / affixes` 五表 schema 与 `paths` 境界树。
> 与现有内容的关系：项目已存在 `zhutian` path 境界树，但命名通用（凡体/王体/帝体）缺乏遮天辨识度。本模板**重命名境界 + 拆细子羁绊 + 新增九秘/源术/法器/联动**。
> v2 变更（对照上一版）：
> 1. 境界阶梯改用遮天真实境界名（轮海/道宫/四极/化龙/仙台/准帝/大帝/红尘仙/天帝），替换"王者之血/骨/魂"等无辨识度命名。
> 2. 每个大境界拆成多个子羁绊（如道宫=五脏神 5 个），集齐触发突破 reward——复用现有 `RealmDef.bonds + reward`，零新增引擎逻辑。
> 3. 删除"无始钟鸣""虚空碎镜"技能——这些改为**掉落法器自带技能**（新机制 `granted_skill`）。
> 4. 红尘仙/天帝等终境羁绊引入**时间锁吞噬**（获取后 180s 才能吞噬，吞噬前不给属性）——新机制，需扩 `PlayerState`。
> 5. 源天师做成**独立外挂 path（`yuanshu`）**，与 `zhutian` 互不依赖；不选源天师不影响遮天修满。
> 6. 补"词条是什么"的定位说明。

---

## 0. 一句话定位

> **境界是阶梯，九秘是境界子羁绊，天帝拳是起点技能（体系入口），法器是装备，"修为 + 绝学 + 帝兵"三位一体才触发最强联动——还原遮天"越级杀敌"的经典爽点。**
>
> （注：重构后九秘从技能改为遮天境界子羁绊 `zt_jm_*`，天帝拳是遮天体系唯一的起点技能，随境界自动升级。）

设计红线沿用 GDD：**装备只管经济，战斗数值归羁绊/技能，联动走 final 乘区**。遮天所有"强"都通过经济滚雪球与乘区联动体现，不直接给战斗数值加成。

---

## 1. 世界观总结（游戏化提炼）

### 1.1 境界体系（修炼阶梯）

遮天的境界链是天然的阶段性解锁曲线，每层都是"质变 + 量变"双重门槛：

| 阶段 | 秘境 | 关键设定 | 游戏化含义 |
|------|------|----------|------------|
| 1 | **轮海 / 苦海** | 开辟苦海→命泉→神桥→彼岸，海纳百川聚精气 | 新手期，打通经济基础 |
| 2 | **道宫** | 苦海化"道之宫阙"，体内五脏神（心/肝/脾/肺/肾）觉醒 | 第一个 build 分支点（5 子羁绊） |
| 3 | **四极** | 淬炼四肢（左臂/右臂/左腿/右腿） | 装备槽 / 属性成型（4 子羁绊） |
| 4 | **化龙** | 脊柱化龙，龙骨一节节贯通 | 中期爆发点（多子羁绊） |
| 5 | **仙台**（一~九重） | 仙台秘境九重，逐重称谓不同（见下表） | 后期大境界，每重=milestone |
| 6 | **准帝**（一~九重天） | 触碰大道，需渡劫；圣体破诅咒即此境 | 终局前过渡，门槛极高 |

**仙台秘境九重细分**（原文校对：仙三斩道、仙四成圣、仙五圣人王、仙六=大圣、仙七=半圣、仙八/九=准帝前夜）：

| 仙台重 | 称谓 | 设定要点 | 游戏化子羁绊 |
|--------|------|----------|--------------|
| 仙一 | **大能** | 仙台一层，跨入强者门槛 | `zt_xiantai_daneng` |
| 仙二 | **斩道 / 王者** | 仙三前斩本我之道，又称王者 | `zt_xiantai_zhandao` |
| 仙三 | **斩道圆满 / 半步圣人** | "仙三斩道"全书记忆点，圣人门槛 | `zt_xiantai_zhandao_peak` |
| 仙四 | **圣人** | "仙四成圣"，正式踏入圣人境 | `zt_xiantai_saint` |
| 仙五 | **圣人王** | 圣人之上，原文"仙五圣人王" | `zt_xiantai_saint_king` |
| 仙六 | **大圣** | 大圣之境，战力质变 | `zt_xiantai_dasheng` |
| 仙七 | **半圣（准帝前夜）/ 大圣圆满** | 一只脚踏入准帝 | `zt_xiantai_bansheng` |
| 仙八 | **准帝种子** | 距准帝一步之遥 | `zt_xiantai_quasi_seed` |
| 仙九 | **仙台绝巅** | 仙台尽头，下一步即准帝 | `zt_xiantai_peak` |

> 设计取舍：仙台九重若全做成独立境界太碎，建议**合并为 1 个大境界（仙台），内含 9 个子羁绊**，集齐任意关键 3 重（斩道/成圣/大圣）即可阶段性吞噬突破，九重全满给终极 reward。这样既还原小说层次，又不让境界树膨胀。具体吞噬门槛见 §2.1。
| 7 | **大帝 / 极道** | 一个时代唯一，万道相合 | 通关级 |
| 8 | **红尘仙** | 于红尘中成仙，不死不朽 | NG+ / 肉鸽循环（**时间锁**） |
| 9 | **天帝**（叶凡独有） | 自成天帝，开辟新纪元 | 隐藏结局（**时间锁**） |

**关键突破节点（叶凡线）**：开辟苦海（得道经）→ 圣体重现遭追杀 → 鼎成 → 斩道 → 圣人 → **圣体破诅咒成准帝**（全书最大爽点之一）→ 成帝（天帝）→ 红尘仙 → 战帝尊。

### 1.2 功法体系（= 修炼 path 的核心）

功法决定"你修哪条路"，是 build 分流的天生抓手：

| 功法 | 来源 / 持有者 | 特点 |
|------|---------------|------|
| **道经** | 轮海篇总纲，叶凡主修 | 万法之基，苦海最广 |
| **西皇经** | 西皇母（女帝经），瑶池 | 极道帝经，阴阳 |
| **太阳经 / 太阴经** | 太阳人皇 / 太阴人皇 | 至阳 / 至阴，互为表里 |
| **太皇经** | 太古皇 | 皇道法则 |
| **虚空经** | 虚空大帝 | 空间、镜（虚空镜） |
| **无始经** | 无始大帝 | "谁敢言无敌"，镇压一个时代 |
| **源天书 / 源术** | 源天师一脉 | 挖源、识宝、断生死（**叶凡外挂，独立 path**） |
| **妖帝九斩** | 妖帝雪月清 | 妖族至高 |

### 1.3 九秘（神禁，最强战技 = 现为遮天境界子羁绊）

> 注：九秘**已从技能转为遮天境界子羁绊**（`zt_jm_*`，分散到遮天 9 个境界），不再是 `jt_*` 技能。修满遮天 9 境界即自动集齐全部九秘，触发"九秘合一·神禁"联动。下方表格为原始设计定位记录（游戏化定位现作为羁绊 effect 实现）。

遮天最有辨识度的"九个古字"，原设计对应技能系统，集齐触发"神禁"联动。**重构后改为境界子羁绊**：

| 古字 | 效果 | 游戏化定位（现为境界子羁绊 `zt_jm_*`） |
|------|------|----------------|
| **皆**字秘 | 战力翻倍 | 爆发 / 增伤 buff |
| **斗**字秘 | 斗战圣法 | 持续输出 |
| **兵**字秘 | 御尽万兵 | 召唤 / 武器强化 |
| **者**字秘 | 调动万物 | 控制 |
| **数**字秘 | 分身 / 算计 | 召唤分身 |
| **组**字秘 | 万阵之祖 | 阵法 / AOE 场控 |
| **前**字秘 | 未卜先知 | 闪避 / 预判 / 减伤 |
| **行**字秘 | 缩地成寸 | 速度 / 攻速 |
| **临**字秘 | 镇压临身 | 眩晕 / boss 控制 |

> **九秘合一**是遮天顶级爽点 → 设计成 **EX 档联动**（集齐九秘触发"神禁"）。
> 技能槽容量问题见 §5 待办：~~九秘 9 个超过现有槽位（约 5–6），需提槽上限或改门槛为"拥有其中 N 个"~~ **已解决**：九秘从技能改为境界子羁绊，不再占技能槽，修满 9 境界自动集齐触发。

### 1.4 法器 / 法宝（= 装备 + 传说掉落）

| 法器 | 设定 | 游戏定位 |
|------|------|----------|
| **九龙拉棺 / 青铜古棺** | 贯穿全书最大谜团，接引星空古路 | 通关 / 转职道具，或最终装备 |
| **荒塔** | 镇压万古之物 | 传说控制装 |
| **菩提子**（佛陀成道树） | 叶凡伴身佛器，禅韵 | 被动成长型装备 |
| **青铜古灯**（大雷音寺那盏） | 避尘长明，佛韵 | 经济 / 续航装 |
| **天帝鼎**（叶凡自铸） | 万器之宗 | 终局装备核心 |
| **无始钟 / 虚空镜 / 恒宇炉**（极道帝兵） | 大帝遗留 | **掉落后自带技能**（新机制 `granted_skill`） |
| **仙泪绿金 / 绿铜锈** | 神材 | 高级锻造材料 |
| **不死药 / 神源** | 续命 / 破境 | 消耗品 / 破境道具 |

### 1.5 重要事件（= 关卡 / 事件节点）

- **泰山封禅、九龙拉棺降临** → 开局事件（项目第一章正是这个）
- **火星（荧惑）大雷音寺取佛器** → 第一个 loot 关
- **抵达北斗紫微星域** → 进入修真界
- **荒古禁地 / 圣体重现遭追杀** → 压力波 / 追击战
- **紫山夺源天师传承** → 源术解锁（外挂系统）
- **鼎成** → 装备里程碑
- **星空古路试炼** → 长线肉鸽关卡序列
- **圣体破诅咒成准帝** → 爽点 boss 战
- **成帝、战帝尊** → 终局

### 1.6 标志性人物（可做羁绊命名 / 英雄单位）

叶凡、庞博、紫月、姬紫月、无始大帝、虚空大帝、狠人大帝（女帝）、妖帝雪月清、青帝、黑皇（黑狗）、段德、神王姜太虚、盖九幽、不死天皇、帝尊。

---

## 2. 联动模板（对齐现有 YAML schema）

### 2.0 词条（affix）是什么 —— 先统一概念

> **词条是技能和装备之间的"公共货币"，是修改 `CombatStats` 的最小颗粒。**

三层关系：

```
技能(Skill)  ──base_affixes──→  词条(Affix)  ──effect──→  CombatStats(攻击/暴击/最终伤害…)
装备(Equip)  ──affixes───────→  词条(Affix)  ──effect──→  CombatStats
```

- 技能有 `base_affixes`（技能自带的词条）
- 装备有 `affixes`（装备词条）
- 每条词条的 `effect` 直接改 `CombatStats` 的某个字段（`atk_pct_delta` / `crit_rate_delta` / `final_dmg_mult` …）
- 联动的触发条件 `affix_owned` / `equipment_affix` = "你身上有没有某条词条"

**为什么要有词条这一层？** 让技能和装备能"说同一种话"——一个"暴击精通"词条，既可以被某个技能自带，也可以装在某件装备上，而联动只需要认"有没有这条词条"，不用关心它来自技能还是装备。这就是"装备 + 技能 + 羁绊能互相联动"的技术基础。

### 2.1 核心设计：境界 = 羁绊吞噬阶梯（遮天真实境界名）

把遮天境界映射成 `zhutian` path 的境界树（复用现有 `RealmDef.bonds + reward`）。**每个大境界由若干子羁绊组成**，集齐子羁绊 → 吞噬突破 → 拿到该境界的整体 reward。

```
轮海   ── (道经/苦海/命泉/神桥/彼岸)            → reward
道宫   ── (心/肝/脾/肺/肾 五脏神，5 子羁绊)      → reward  ← 你提的"道宫 5 部位"
四极   ── (左臂/右臂/左腿/右腿，4 子羁绊)         → reward
化龙   ── (龙骨多节，N 子羁绊)                    → reward
仙台   ── (仙一~仙九，多子羁绊)                   → reward
准帝   ── (渡劫/圣体破诅咒等)                     → reward
大帝   ── (帝级子羁绊)                            → reward + 解锁天帝拳联动
红尘仙 ── ⏱ 时间锁：获取后 180s 才能吞噬，吞噬前不给属性
天帝   ── ⏱ 时间锁：获取后 180s 才能吞噬；终局隐藏境界
```

**这是替换现有 `zhutian` path 的命名方案**（现有用"凡体/王体/帝体"，无遮天味）：

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
    bonds:                          # 五脏神——你说的"道宫 5 部位"
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
    bonds:                          # 仙台秘境九重（原文：仙三斩道/仙四成圣/仙五圣人王/仙六大圣…）
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
    note: 仙台九重全满给终极 reward；建议支持阶段性吞噬（斩道/成圣/大圣 三档）

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
    devour_locked_seconds: 180     # ⏱ 新机制：获取后 180s 才能吞噬
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

对应子羁绊（节选示例，风格统一用遮天术语）：

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

### 2.2 技能（skills.yaml）—— 九秘 + 天帝拳（不含帝兵绝学）

> ⚠️ **已重构（2026-07-12，见 `skill_refactor_design.md`）。本节为重构前设计记录。**
> - 现在遮天只有 **1 个起点技能**（emperor_fist），选了遮天体系自动获得，随境界突破自动升级。
> - **九秘已从技能（`jt_*`）转为遮天境界子羁绊（`zt_jm_*`）**，分散到遮天 9 个境界，修满即集齐。
> - 下方 `jt_*` 技能 YAML 已废弃，仅作历史记录。当前实际数据见 `balance/data/skills.yaml`（仅 emperor_fist）+ `balance/data/bonds.yaml`（`zt_jm_*`）。

> **帝兵绝学（无始钟鸣/虚空碎镜）不再放技能池**，改为掉落法器 `granted_skill` 自带（见 §2.4）。
> 技能池只留"人能学的"：~~九秘 + 天帝拳~~（重构后仅天帝拳，九秘归羁绊）。

```yaml
skills:
  # ══ 遮天九秘（集齐触发神禁联动）══
  - id: jt_jie
    name: 皆字秘·战力倍增
    rarity: UR
    tags: [physical, buff]
    atk_ratio: 1.0
    base_affixes: [final_dmg]
    note: 短时自身最终伤害翻倍

  - id: jt_dou
    name: 斗字秘·斗战圣法
    rarity: SSR
    tags: [physical, single_target]
    atk_ratio: 1.6
    base_affixes: [physical_dmg]

  - id: jt_bing
    name: 兵字秘·御万兵
    rarity: SSR
    tags: [summon, buff]
    atk_ratio: 0.8
    base_affixes: [physical_dmg]

  - id: jt_zuzi
    name: 组字秘·万阵之祖
    rarity: SSR
    tags: [magic, aoe, debuff]
    atk_ratio: 1.2
    base_affixes: [magic_dmg]

  - id: jt_xing
    name: 行字秘·缩地成寸
    rarity: SR
    tags: [physical, pierce]
    atk_ratio: 1.0
    base_affixes: [attack_speed]

  - id: jt_qian
    name: 前字秘·未卜先知
    rarity: SR
    tags: [buff, survival]
    atk_ratio: 0.6
    base_affixes: [dodge]

  - id: jt_lin
    name: 临字秘·镇压临身
    rarity: SSR
    tags: [magic, single_target, debuff]
    atk_ratio: 1.3
    base_affixes: [stun_chance]

  - id: jt_zhe
    name: 者字秘·御万物
    rarity: SR
    tags: [magic, control]
    atk_ratio: 0.9
    base_affixes: [slow_chance]

  - id: jt_shu
    name: 数字秘·身外化身
    rarity: SSR
    tags: [summon]
    atk_ratio: 0.7
    base_affixes: [multishot]

  # ══ 人级绝学 ══
  - id: emperor_fist     # 已有，保留
    name: 天帝拳
    rarity: UR
    tags: [physical, single_target]
    atk_ratio: 2.0
    base_affixes: [physical_dmg]
    note: 修满遮天大帝境后联动 +100% 最终伤害
```

### 2.3 装备（equipment.yaml）—— 传说法器掉落 + 自带技能

> 法器严守"只管经济"红线，经济向 affix。**帝兵额外 `granted_skill` 自带绝学**（新机制，见 §3）。

```yaml
legendary_drops:
  - id: bodhi_seed
    name: 菩提子
    slot: relic
    affixes: [gold_per_sec_plus_2, wisdom]
    note: 佛陀成道菩提树所结，伴身佛器

  - id: ancient_bronze_lamp
    name: 青铜古灯
    slot: relic
    affixes: [kill_gold_plus, clean_dust]      # 避尘=免疫诅咒词条
    note: 大雷音寺长明灯

  - id: heaven_emperor_cauldron
    name: 天帝鼎
    slot: relic
    affixes: [gold_multiplier, gold_per_sec_plus_2]
    note: 叶凡自铸，万器之宗——经济终局装

  - id: desolate_tower
    name: 荒塔
    slot: relic
    affixes: [gold_multiplier]
    note: 镇压万古

  # ══ 极道帝兵：掉落后自带绝学（granted_skill）══
  - id: wushi_bell_relic
    name: 无始钟
    slot: relic
    affixes: [gold_multiplier]
    granted_skill: wushi_bell_strike           # 新机制：装备自带技能
    note: 无始大帝遗留，钟鸣震慑万古

  - id: void_mirror_relic
    name: 虚空镜
    slot: relic
    affixes: [gold_multiplier]
    granted_skill: void_mirror_pierce
    note: 虚空大帝遗留，碎裂虚空

  - id: nine_dragons_coffin
    name: 青铜古棺（九龙拉棺）
    slot: relic
    affixes: [gold_multiplier, gold_per_sec_plus_2, kill_gold_plus]
    note: 通关级掉落，星空古路终点
```

帝兵自带的"绝学"定义在技能表（但不在抽取池，只能靠掉落获得）：

```yaml
skills:
  # ══ 帝兵自带绝学（仅掉落获得，不在抽取池）══
  - id: wushi_bell_strike
    name: 无始钟鸣
    rarity: UR
    tags: [magic, aoe, debuff]
    atk_ratio: 1.5
    base_affixes: [magic_dmg, stun_chance]
    pool: drop_only                            # 新标记：不进抽取池
    note: 仅由"无始钟"掉落物 granted_skill 提供

  - id: void_mirror_pierce
    name: 虚空碎镜
    rarity: SSR
    tags: [magic, pierce]
    atk_ratio: 1.4
    base_affixes: [magic_dmg]
    pool: drop_only
```

### 2.4 联动（synergies.yaml）—— 遮天联动的灵魂

> ⚠️ **已重构（2026-07-12）：触发条件 `skill_owned` 已改为 `bond_devoured_set: zhutian` / `path_realm`。** 起点技能=体系入口（选了遮天就有天帝拳=在修），九秘已从技能转为境界子羁绊（修满遮天=集齐全部九秘）。下方 YAML 已更新为重构后触发，实际数据见 `balance/data/synergies.yaml`。

```yaml
synergies:
  # ── 天帝之拳（修满遮天即触发；起点技能=体系入口，有技能=在修）──
  - id: zhutian_emperor_fist
    name: 天帝之拳
    trigger: { all: [ { bond_devoured_set: zhutian } ] }
    effect: { final_dmg_mult: 1.0 }

  # ══ 九秘·神禁（修满遮天 9 境界 = 集齐全部 9 个九秘羁绊 zt_jm_*）══
  - id: zhutian_nine_secrets
    name: 九秘合一·神禁
    trigger:
      all:
        - bond_devoured_set: zhutian        # 九秘现为境界子羁绊，修满即集齐
    effect: { final_dmg_mult: 2.0 }
    rarity: EX
    note: 遮天最强战技组合，九秘合一

  # ═─ 三重联动：圣体(遮天大帝境) + 天帝拳 + 天帝鼎 ═
  - id: saint_emperor_trinity
    name: 圣体帝鼎·三位一体
    trigger:
      all:
        - bond_devoured_set: zhutian        # 修满遮天（含天帝拳，原 skill_owned 已并入）
        - equipment_affix: gold_multiplier
    effect: { final_dmg_mult: 1.5 }
    rarity: EX
```

### 2.5 源天师（外挂型独立 path）

> **独立 path `yuanshu`，与 `zhutian` 互不依赖。不选源天师不影响遮天修满。**
> 对应叶凡"源天师传承"外挂，定位为经济识宝增益。

```yaml
paths:
- id: yuanshu
  name: 源术
  realms:
  - name: 源术入门
    bonds: [ys_source_eye]            # 源眼——识源
    reward: { gold_mult: 0.35 }
  - name: 源术小成
    bonds: [ys_cut_source, ys_read_source]   # 切源/读源
    reward: { gold_mult: 0.525, per_kill_gold_delta: 3.5 }
  - name: 源天师
    bonds: [ys_yuantianshi]           # 源天师传承
    reward: { gold_mult: 1.05 }
    synergy_unlock: yuanshu_devour_source

bonds:
  - id: ys_source_eye
    name: 源眼
    set: yuanshu
    effect: { gold_mult: 0.20 }
  - id: ys_cut_source
    name: 切源
    set: yuanshu
    effect: { per_kill_gold_delta: 2.0 }
  - id: ys_read_source
    name: 读源
    set: yuanshu
    effect: { gold_mult: 0.35 }
  - id: ys_yuantianshi
    name: 源天师传承
    set: yuanshu
    effect: { gold_mult: 0.70 }

synergies:
  - id: yuanshu_devour_source
    name: 源术识宝
    trigger:
      all:
        - bond_devoured_set: yuanshu
        - equipment_affix: kill_gold_plus
    effect: { gold_mult: 1.0 }            # 击杀金翻倍
    note: 独立外挂，不依赖遮天套
```

### 2.6 词条（affixes.yaml）—— 补遮天风机制词条

```yaml
  - id: wisdom
    name: 禅韵
    rarity: SR
    stacking: add
    effect: { gold_per_sec_delta: 2.0 }

  - id: clean_dust
    name: 避尘
    rarity: SSR
    stacking: replace
    effect: { curse_immunity: true }        # 免疫诅咒（青铜古灯特色）

  - id: dodge
    name: 缩地
    rarity: SR
    stacking: chance
    effect: { dodge_chance_delta: 0.15 }    # 前字秘

  - id: stun_chance
    name: 镇压
    rarity: SSR
    stacking: chance
    effect: { stun_chance_delta: 0.12 }

  - id: slow_chance
    name: 御物
    rarity: SR
    stacking: chance
    effect: { slow_chance_delta: 0.15 }
```

---

## 3. 新机制与引擎改动清单

> 这些是需要引擎/`schema` 配合的新机制。标注影响面，供落地排期。

### 3.1 境界改名 + 子羁绊细化 —— ✅ 零引擎改动

复用现有 `PathDef.realms[].bonds + reward`。只改 `bonds.yaml` 数据。

> 注：仙台九重若做成"九个独立境界"会让境界树过深。**默认方案：仙台 = 1 个大境界含 9 子羁绊，全满才突破**（零引擎改动）。
> **可选方案：阶段性吞噬**（集齐斩道/成圣/大圣三档各给一次小 reward）→ 这需要扩 `RealmDef` 支持"子里程碑"，列为 🆕 可选改动，见 §3.5。

### 3.2 时间锁吞噬（红尘仙/天帝）—— 🆕 需扩 PlayerState + 吞噬校验

机制：部分境界/羁绊标记 `devour_locked_seconds: N` 且 `locked_until_devoured: true`：
- 羁绊入手时记录时间戳
- 吞噬前该羁绊的 effect **不生效**
- 满 N 秒后才允许吞噬，吞噬后 effect 生效 + 触发 reward

引擎改动：
- `PlayerState` 加 `bond_acquired_at: dict[str, float]`（羁绊入手时间）
- `RealmDef` 加 `devour_locked_seconds: int = 0`、`locked_until_devoured: bool = False`
- `resolve_player` 累加 bond effect 时，跳过未吞噬的 locked bond
- 吞噬动作校验 `now - acquired_at >= devour_locked_seconds`

### 3.3 装备自带技能（`granted_skill`）—— 🆕 需扩 equipment schema + skill 池标记

机制：掉落法器带 `granted_skill: <skill_id>`，装备后玩家获得该技能（注：重构后技能已不抽取，改为选体系自动获得；此处"不占技能抽取机会"的历史说明仍成立——法器技能独立于起点技能）。
- `equipment` schema 加 `granted_skill: str = ""`
- `SkillDef` 加 `pool: str = "normal"`（`drop_only` 表示不进抽取池）
- `PlayerState` 区分 `skills`（抽取来的）与 `granted_skills`（装备给的）

### 3.4 源天师外挂 path —— ✅ 零引擎改动

`paths: yuanshu` 独立存在，`bond_devoured_set: yuanshu` 的联动独立判定，天然不干扰 `zhutian`。

### 3.5 阶段性吞噬（子里程碑）—— 🆕 可选，需扩 RealmDef

机制：一个大境界内部设多个"子里程碑"，集齐该里程碑的子羁绊就先给一次小 reward，不必等九重全满。专为仙台九重这种长境界设计，避免玩家修到一半没正反馈。
- 默认不实装也能玩（仙台就按"全满突破"走）
- 若要实装：`RealmDef` 加 `milestones: list[{bonds: [], reward: {}}]`，吞噬引擎增加"子里程碑"判定
- 影响面：`schemas.py` / `synergy_engine.py` / resolve_player

---

## 4. 设计要点（为什么这样映射）

1. **境界名用遮天原典** → 轮海/道宫/四极/化龙/仙台/准帝/大帝/红尘仙/天帝，替换"王者之血"等通用词，辨识度拉满。
2. **大境界拆子羁绊** → 还原小说"道宫修五脏、四极修四肢"的修炼颗粒感，集齐才突破，复用现有 realm 结构，零引擎改动。
3. **帝兵绝学走掉落而非技能池** → 无始钟鸣/虚空碎镜改成"无始钟/虚空镜掉落后自带技能"，让法器不只是经济装，而是真能解锁战技；（重构后遮天技能池仅 1 个起点技能 emperor_fist，技能池保持"人能学的"纯净。）
4. **红尘仙/天帝时间锁** → 还原小说"长生漫漫、成仙非一日"的叙事，同时给终局羁绊一个天然的反滚雪球阀门。
5. **源天师独立外挂 path** → 对应叶凡的源术外挂，与战斗体系正交，玩家可选可不选，不绑架遮天主线。
6. **三重联动**（羁绊境界 + 技能 + 装备词条）= 还原"修为 + 绝学 + 帝兵"三位一体才能越级杀敌的经典桥段。

---

## 5. 待办与风险

- [ ] 落地前跑 `balance/` 测试与报表，确认新联动（尤其 `zhutian_nine_secrets` ×2 final、红尘仙时间锁）不破坏平衡曲线。
- [ ] `dodge / stun_chance / slow_chance / curse_immunity / dodge_chance_delta` 等字段需在 `td_balance.combat.damage.CombatStats` 补字段，否则 loader 报未知 key。
- [ ] ~~**九秘 9 技能 vs 技能槽上限（约 5–6）**~~ **已解决（重构）**：九秘从技能转为遮天境界子羁绊（`zt_jm_*`），不再占技能槽，修满 9 境界自动集齐触发。原"提槽上限或改 N/9 门槛"方案已不需要。
- [ ] 时间锁吞噬的 UX：需在 UI 上显示"距可吞噬剩余时间"，避免玩家困惑。
- [ ] `granted_skill` 占不占技能槽？建议占（否则法器给技能纯赚），但需与 GDD §4（重构后技能=体系入口）对齐。
- [ ] 命名去重：`emperor_fist` 已存在；新增 path/bond id 需与现有 `zt_*` 旧条目去重（落地时旧的 `zt_king_blood` 等要删或迁移）。
- [ ] 境界改名是**破坏性数据改动**：现有测试/报表若硬编码旧境界名（凡体/王体/帝体）会挂，落地时全局搜索替换。
