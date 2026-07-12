# 体系设计：星辰变（法术 / AOE 流）

> 状态：设计草案，落地前需确认数值平衡。**零新引擎机制**，复用现有 magic_dmg / elemental_dmg / final_dmg 乘区，三体系中落地最快。
> 定位：GDD 三体系之一。**法术伤害 + 星辰属性 + AOE**——纯法术流，主角自身就是输出源。本文自包含：读完即可完整理解星辰变体系。
> 相关：通用机制（抽取/商店/经济/公式）见 [`../GAME_DESIGN.md`](../GAME_DESIGN.md)；物理流见 [`zhutian.md`](zhutian.md)；召唤流见 [`chongmei.md`](chongmei.md)。
> 来源：《星辰变》主角**秦羽**天生无法修内功，走**外功肉身 + 星辰之力**路线。核心是自创功法"星辰变"——按天体演化排列阶段。
> 基准：对齐遮天体系（9 境界阶梯，~31 羁绊，1 起点技能，联动）。星辰变 ~35 羁绊，零召唤单位。

---

## 0. 一句话定位

> **星辰变功法是起点技能，按天体演化（星云→流星→星核→行星→…→黑洞→宇宙）自动升级，每个境界解锁一个新法术形态（AOE/弹射/雷/火/控制/吞噬）。纯法术 AOE，无召唤、无新机制。**

设计红线沿用 GDD：战斗数值归羁绊/技能，联动走 final 乘区。星辰变**不需要新引擎机制**——复用现有 magic_dmg / elemental_dmg / final_dmg 乘区。

---

## 1. 9 境界阶梯（星云 → 宇宙）

**星辰变功法 9 阶**（原著 11 阶：星云→流星→星核→行星→渡劫→恒星→暗星→黑洞→原点→乾坤→宇宙，后 3 阶合并为"宇宙"终极境，精选/合并为 9 境以对齐遮天）。

| 境界 | index | 天体阶段 | 含义 | rarity |
|------|-------|----------|------|--------|
| 星云 | 0 | 星云 | 气态凝聚，法术萌芽 | SR |
| 流星 | 1 | 流星 | 破空而出，速度爆发 | SSR |
| 星核 | 2 | 星核 | 凝聚核心，法术成型 | SSR |
| 行星 | 3 | 行星 | 稳定轨道，全面成长 | SSR |
| 渡劫 | 4 | 渡劫 | 天劫洗礼，质变门槛 | UR |
| 恒星 | 5 | 恒星 | 自身发光，法术巅峰 | UR |
| 暗星 | 6 | 暗星 | 暗物质，隐藏力量 | UR |
| 黑洞 | 7 | 黑洞 | 吞噬万物，终极法术 | EX |
| 宇宙 | 8 | 宇宙 | 自成一界，造物之主 | EX |

---

## 2. 羁绊设计（~35 张卡）

```yaml
# path: xingchenbian
bonds:
  # ── 星云（境0，rarity SR）── 法术萌芽
  - xc_xy_xingchen            # 星辰之力（基础法力源）
  - xc_xy_yunqi                # 云气（星云凝聚）
  - xc_xy_linggen              # 灵根（法术天赋）
  # ── 流星（境1，rarity SSR）── 速度爆发
  - xc_lx_liuxing              # 流星（破空速度）
  - xc_lx_liuxinglei           # 流星泪（核心法器羁绊，贯穿全书）
  - xc_lx_poeng                # 破空（空间法则入门）
  # ── 星核（境2，rarity SSR）── 法术成型
  - xc_xh_xinhe                # 星核（凝聚核心）
  - xc_xh_faize                # 法则（法则之力觉醒）
  - xc_xh_yuanshen             # 元神（神识初成）
  # ── 行星（境3，rarity SSR）── 全面成长
  - xc_xx_guidao               # 轨道（稳定输出）
  - xc_xx_wuxing               # 五行（五行法术齐全）
  - xc_xx_dunjia               # 遁甲（空间移动）
  # ── 渡劫（境4，rarity UR）── 质变门槛
  - xc_dj_leijie               # 雷劫（天劫洗礼）
  - xc_dj_duomie               # 渡灭（生死蜕变）
  # ── 恒星（境5，rarity UR）── 法术巅峰
  - xc_hx_hengguang            # 恒光（自身发光，法术巅峰）
  - xc_hx_taoyang              # 太阳（阳极法术）
  # ── 暗星（境6，rarity UR）── 隐藏力量
  - xc_ax_ansu                 # 暗素（暗物质）
  - xc_ax_xuanying             # 玄影（暗影法术）
  # ── 黑洞（境7，rarity EX）── 吞噬万物
  - xc_hd_tunshi               # 吞噬（黑洞核心能力）
  - xc_hd_xumie                # 虚灭（湮灭法术）
  # ── 宇宙（境8，rarity EX）── 造物之主
  - xc_yz_yuzhou               # 宇宙（自成一界）
  - xc_yz_hongmeng             # 鸿蒙（鸿蒙掌控者，终极）
```

### 星辰变专属：流星泪成长线（独立小套，类似遮天九秘）

```yaml
  # ══ 流星泪成长（秦羽命根子，贯穿全书的法器）══
  - xc_llt_awaken               # 流星泪·觉醒
  - xc_llt_recover              # 流星泪·恢复（超强回血）
  - xc_llt_soul                 # 流星泪·灵魂法则
  - xc_llt_space                # 流星泪·空间法则
  - xc_llt_refine               # 流星泪·炼化（终极，法器觉醒）
```

> 流星泪（恢复+法则）走奇遇掉落系统（后面做），不在技能池；匠神（炼器）走经济向羁绊。详见 §5。

---

## 3. 起点技能：星辰变·功法（随境界自动升级）

星辰变体系**只有 1 个起点技能**：星辰变·功法（`xc_xingchenbian`）。选了星辰变体系就自动获得。原来的多个独立技能（星辰箭/流星雨/星核击/黑洞吞噬…）全部改成**境界突破的功法升级效果**。

```yaml
skills:
  - id: xc_xingchenbian             # 星辰变·功法
    name: 星辰变·功法
    rarity: SR                       # 起点
    tags: [magic, aoe]
    atk_ratio: 1.5                   # 基础法术倍率
    note: 星辰变体系入口——选了才解锁星辰变羁绊池。随境界突破自动升级
```

### 功法随境界自动升级（reward 里的 skill_upgrade）

```yaml
# 境界突破时自动强化起点技能（不需玩家操作）
# upgrade: {effect: 强化的属性, tags_add: 新增攻击形态}
realm_rewards_skill_upgrade:
  流星(境1):
    xc_xingchenbian: { effect: { magic_dmg_pct_delta: 0.10 }, tags_add: [aoe] }        # 流星雨：+AOE
  星核(境2):
    xc_xingchenbian: { effect: { atk_ratio_delta: 0.3 } }                              # 星核击：+单体爆发
  行星(境3):
    xc_xingchenbian: { effect: { magic_dmg_pct_delta: 0.10 }, tags_add: [chain] }      # 轨道连锁：+弹射
  渡劫(境4):
    xc_xingchenbian: { effect: { elemental_dmg_mult: 0.15 }, tags_add: [thunder] }     # 天劫雷罚：+雷属性
  恒星(境5):
    xc_xingchenbian: { effect: { elemental_dmg_mult: 0.15 }, tags_add: [fire] }        # 恒星耀斑：+火属性AOE
  暗星(境6):
    xc_xingchenbian: { effect: { magic_dmg_pct_delta: 0.15 }, tags_add: [debuff] }     # 暗虚：+减速控制
  黑洞(境7):
    xc_xingchenbian: { effect: { final_dmg_mult: 0.30, lifesteal_pct: 0.05 } }         # 黑洞吞噬：+最终伤害+击杀回血
  宇宙(境8):
    xc_xingchenbian: { effect: { final_dmg_mult: 0.50, magic_dmg_pct_delta: 0.30 } }   # 宇宙诞生：终极，法术翻倍
```

> **设计要点**：玩家选了星辰变后，不需要再"抽技能"——只要修境界，功法自动变强。每个境界解锁一个新的法术形态（AOE/弹射/雷/火/控制/吞噬），全部叠加到同一个起点技能上。

---

## 4. 联动（触发条件用 `bond_devoured_set` / `path_realm`）

```yaml
synergies:
  # ── 星辰变·星耀（修满星辰变 + 至少恒星境）──
  - id: xingchenbian_star
    name: 星辰变·星耀
    rarity: SSR
    trigger:
      all:
        - bond_devoured_set: xingchenbian       # 修满星辰变境界
        - path_realm: {xingchenbian: ">=5"}      # 至少修到恒星境（法术成型）
    effect:
      magic_dmg_pct_delta: 0.50                  # 法伤 +50%

  # ── 三重联动：黑洞·吞噬万物（法术终极）──
  - id: xingchenbian_blackhole
    name: 黑洞·吞噬万物
    rarity: EX
    trigger:
      all:
        - bond_devoured_set: xingchenbian
        - path_realm: {xingchenbian: ">=7"}      # 修到黑洞境
        - equipment_affix: magic_amp              # 装备"法术增幅"
    effect:
      final_dmg_mult: 1.5
      magic_dmg_pct_delta: 0.50

  # ── 宇宙诞生（法术流天花板）──
  - id: xingchenbian_universe
    name: 宇宙诞生
    rarity: EX
    trigger:
      all:
        - bond_devoured_set: xingchenbian
        - path_realm: {xingchenbian: ">=8"}      # 修到宇宙境（终极）
    effect:
      final_dmg_mult: 1.0
      lifesteal_pct: 0.10                         # 法术吸血 10%（终极续航）
    note: 法术流天花板——自成宇宙，万法归一
```

---

## 5. 流星泪成长线（奇遇法器，后面做）

> 状态：奇遇/掉落系统未实装，流星泪为后续内容储备。秦羽命根子，贯穿全书的法器，走奇遇掉落系统，不在技能/羁绊池。

| 流星泪阶段 | 设定 | 游戏定位 |
|-----------|------|----------|
| 觉醒 | 秦羽偶得流星泪 | 法力源 + 超强回血 |
| 恢复 | 流星泪核心能力 | 续航（回血流 build 拼图） |
| 灵魂法则 | 领悟灵魂之力 | 法术增强 |
| 空间法则 | 领悟空间之力 | 空间法术 |
| 炼化（终极） | 流星泪完全觉醒 | 法器觉醒，终极形态 |

> 流星泪的成长对应羁绊 `xc_llt_*`（见 §2），但实际获取走奇遇系统（野外掉落），不放技能/羁绊池。匠神（炼器）走经济向羁绊，也不当技能。

---

## 6. 新机制需求

星辰变**零新引擎机制**——三体系中落地最快。

| 机制 | 说明 | 引擎改动 |
|------|------|----------|
| 起点技能自动升级 | 星辰变功法随境界突破自动获得新法术形态（AOE/弹射/雷/火/控制/吞噬），叠加到同一个技能 | 境界 reward 里加 `skill_upgrade: {id, effect, tags_add}`（与遮天/宠魅共用） |
| path_realm 触发器 | 联动用 `path_realm: {xingchenbian: ">=N"}` 触发 | synergy_engine 加 path_realm 条件判断（已有） |
| magic_amp 词条 | 装备法术增幅（联动触发条件） | 复用现有 affix 框架 |
| 流星泪 | 走奇遇系统（野外掉落） | 后面做奇遇系统时实装 |

> **星辰变零召唤单位**——纯法术流，主角自身就是输出源。不需要宠魅那套虚拟跟随单位系统，引擎改动最小。
>
> 与宠魅对比：宠魅需召唤系统（SummonUnit 场景 + CombatStats 分拆 + summon_upgrade），引擎改动最大；星辰变零新机制，建议**先做星辰变验证法术流，再做宠魅**。

---

## 7. 设计要点

1. **天体演化 = 天然境界阶梯**——星云→流星→星核→…→黑洞→宇宙，每个阶段都有清晰的"质变"叙事，比通用命名（凡体/王体）辨识度高。
2. **功法随境界自动升级，每境解锁新法术形态**——AOE/弹射/雷/火/控制/吞噬全部叠加到同一个起点技能，玩家只修境界不抽技能，法术流体验聚焦。
3. **法术 AOE 是核心差异化**——遮天偏单体物理爆发，星辰变偏 AOE 法术清场，多修互补（物理单体+法术 AOE）才能覆盖所有战斗场景。
4. **零新机制**——复用现有 magic_dmg / elemental_dmg / final_dmg 乘区，落地成本最低，适合作为三体系第二个上线的验证体系。
5. **流星泪成长线**作为奇遇储备（后面做），给后期 build 拼图（续航/法则），不挤占境界羁绊空间。
