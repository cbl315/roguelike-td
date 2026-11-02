"""玩家策略 — 可插拔接口 + SimpleStrategy（实装吞噬循环 + 刷新作为金币 sink）。

Strategy.spend_lobby(state, pools, econ) -> list[Action]
  在一波的大厅里花金币做 Rogue 操作，返回操作记录。

SimpleStrategy 循环优先级（直到没钱或没东西可做）：
  1. 若羁绊池满且可吞噬 → 吞噬（扣金 + 腾位 + 进已吞噬池）
  2. 羁绊池未满 → 抽羁绊
  3. 装备未满级 → 升装备
  4. 余钱 → 刷新羁绊（追求更好组合）

技能已重构为"每体系 1 个起点技能"：选了体系自动获得，随境界突破自动升级，
不再走大厅抽取消费，故策略不再处理技能抽取/升级/重投。

吞噬→腾位→再抽 形成无限 sink 循环，是后期金币主要出口（修 B-2 saturation）。
不求"最优 build"，只为压力测试经济曲线。更智能策略在 B-3 完整 Run 模拟器。
"""
from __future__ import annotations

from .economy import (
    EconomyParams,
    bond_draw_cost,
    bond_reroll_cost,
    devour_cost,
    equip_upgrade_cost,
)
from .player import Action, ActionType, PlayerState
from .combat import damage as _dmg_mod   # 突破守关者 DPS 考核用
from .rogue_pools import RoguePools

# 突破守关者考核：波间 DPS ≥ 下一波 required_dps × 此系数才允许吞噬升境
# （客户端是真实怪物战斗；模拟用 DPS 阈值等价建模。设计意图：纯单体系卡打不过，
# 需搭配散卡/多体系加成才稳过——强制构筑多样性）
BREAKTHROUGH_DPS_REQ = 0.55   # 扫参定稿：当前波基准×0.55（星辰变对 gate 过敏，留宽限）

# 装备里程碑（与 data/equipment.yaml 对齐；max_level 也从中读）
EQUIP_MILESTONES = (5, 10, 15, 20)
EQUIP_MAX_LEVEL = 20


def _draw_milestone_affix(pools: RoguePools):
    """装备里程碑词条抽取（宏观近似）：70% 正面 / 30% 诅咒，随机一条。
    用 pools 的种子 rng——保持整局模拟可复现。"""
    rng = getattr(pools, "rng", None)
    if rng is None:
        return None
    affixes = getattr(pools, "affixes", [])
    if not affixes:
        return None
    positive = [a for a in affixes if getattr(a, "polarity", "positive") != "curse"]
    curse = [a for a in affixes if getattr(a, "polarity", "") == "curse"]
    if rng.float() < 0.7 and positive:
        return positive[rng.int(0, len(positive) - 1)]
    if curse:
        return curse[rng.int(0, len(curse) - 1)]
    return affixes[rng.int(0, len(affixes) - 1)]


def _pick_discard(bond_pool: list[str], path_realm: dict, pools: RoguePools, incoming: str) -> str | None:
    """池满时选一个最该丢的羁绊（模拟玩家合理选择）。

    优先级（最该丢 → 最不该丢）：
      1. generic 通用符文（不助任何境界突破）
      2. 已修满境界之外、且非当前境界的体系羁绊
      3. 当前境界不需要的（基本不会发生，阶梯抽取保证了）
    永不丢：当前境界突破还需要的羁绊。
    返回 id 或 None（无可丢）。
    """
    if not bond_pool:
        return None
    bond_to_set = {b.id: b.set for b in pools.bonds}
    # 当前各 path 正在修的境界还需要的羁绊
    needed_now: set[str] = set()
    for p in pools.paths:
        idx = path_realm.get(p.id, 0)
        if idx < len(p.realms):
            needed_now.update(p.realms[idx].bonds)
    # 1) 优先丢 generic（不助突破）
    for bid in bond_pool:
        if bond_to_set.get(bid) == "generic":
            return bid
    # 2) 丢非当前需要的体系羁绊
    for bid in bond_pool:
        if bid not in needed_now and bid != incoming:
            return bid
    # 3) 兜底：丢池里任意一个（不该走到这——说明全是当前需要的但重复了）
    for bid in bond_pool:
        if bid != incoming:
            return bid
    return None


class Strategy:
    """策略接口（Protocol 风格）。子类实现 spend_lobby。"""
    def spend_lobby(
        self,
        state: PlayerState,
        pools: RoguePools,
        econ: EconomyParams,
    ) -> list[Action]:
        raise NotImplementedError


class SimpleStrategy(Strategy):
    """贪心策略：实装吞噬循环 + 刷新作为金币 sink。

    fixed_path: 固定开局选择的体系（强度对照测试用；None=随机）。
    """

    def __init__(self, fixed_path: str | None = None) -> None:
        self.fixed_path = fixed_path

    def spend_lobby(
        self,
        state: PlayerState,
        pools: RoguePools,
        econ: EconomyParams,
        wave: int = 1,
    ) -> list[Action]:
        reroll_cap = econ.reroll_cap_per_wave
        actions: list[Action] = []
        bond_times_drawn = 0

        def do(action: Action) -> None:
            actions.append(action)
            state.record(action)

        # 主修炼路径：开局自动选 2 个种子（模拟多修互补）
        if not hasattr(state, "_main_path") or state.__dict__.get("_main_path") is None:
            state.__dict__["_main_path"] = None
        # 开局选种子（第一次 spend_lobby 时）
        if not state.path_realm and not hasattr(state, "_seeds_taken"):
            state.__dict__["_seeds_taken"] = True
            import random as _r
            available_paths = [p.id for p in pools.paths if p.id != "generic_fusion"]
            if self.fixed_path is not None and self.fixed_path in available_paths:
                chosen = [self.fixed_path]
            else:
                # 随机选 1 个体系
                chosen = pools.rng.sample(available_paths, min(1, len(available_paths)))
            for path_id in chosen:
                state.path_realm[path_id] = 0
            # generic_fusion 默认解锁
            state.path_realm["generic_fusion"] = 0
            state.__dict__["_main_path"] = chosen[0]
        # 如果已选了体系，设 main_path
        if state._main_path is None and state.path_realm:
            state.__dict__["_main_path"] = list(state.path_realm.keys())[0]
        main_path = state._main_path

        def current_realm_needed() -> list[str]:
            """主路径当前境界需要的羁绊。"""
            if main_path is None:
                return []
            idx = state.path_realm.get(main_path, 0)
            return pools.current_realm_bonds(main_path, idx)

        # 1-4) 循环花钱
        guard = 0
        while state.gold > 0 and guard < 100:
            guard += 1
            # 1) 检查是否可吞噬（当前境界凑齐）——突破守关者考核：
            #    波间 DPS ≥ 下一波需求×系数才放行（纯单体系卡打不过，混修才稳）
            dev = pools.find_devourable(state.bond_pool, state.path_realm)
            if dev:
                path_id, realm_idx, needed = dev
                from .combat_stats import resolve_player
                from .curves import required_dps
                from .loader import load_wave_params
                pc = resolve_player(state, pools)
                armor = 20.0 + 1.5 * wave   # 与 run_sim._enemy_armor 同式（避免循环 import）
                dps = _dmg_mod.expected_dps(pc.offense, _dmg_mod.EnemyStats(armor=armor))
                req = required_dps(wave, load_wave_params()) * BREAKTHROUGH_DPS_REQ   # 当前波基准（避开 Boss 波需求尖峰）
                cost = devour_cost(econ)
                if dps >= req and state.spend(cost):
                    pools.devour(state.bond_pool, needed)
                    state.path_realm[path_id] = realm_idx + 1  # 升境
                    do(Action(ActionType.DEVOUR, cost=cost, detail=f"{path_id} realm{realm_idx}→{realm_idx+1}"))
                    continue
            # 2) 抽羁绊——阶梯抽取：引擎只给当前境界的羁绊 + generic
            #    池满时可替换：丢掉对当前突破最无用的羁绊，腾位给新的
            cost = bond_draw_cost(bond_times_drawn, econ)
            if state.spend(cost):
                offers = pools.draw_bond_offers(
                    path_realm=state.path_realm,
                    owned_bond_ids=state.bond_pool,
                )
                if not offers:
                    state.add_gold(cost)
                    continue
                # 优先选体系羁绊（跳过 generic，除非只有 generic）
                chosen = offers[0]
                needed = current_realm_needed()
                needed_set = set(needed)
                for o in offers:
                    # 优先选当前境界需要的
                    if o.id in needed_set:
                        chosen = o
                        break
                if chosen.id not in needed_set:
                    # 其次选体系羁绊（非 generic）
                    for o in offers:
                        bset = pools._bond_to_set.get(o.id, "")
                        if bset not in ("generic", "seed", ""):
                            chosen = o
                            break
                # 种子卡：不进 bond_pool，直接解锁体系 + 给金币 + 加起点效果
                seed = pools.get_seed(chosen.id)
                if seed:
                    state.path_realm[seed.seed_path] = 0
                    state.add_gold(seed.seed_gold)
                    # 种子不计入抽取递增成本（bond_times_drawn 不变）
                    do(Action(ActionType.DRAW_BOND, cost=cost, detail=f"🌱 种子: {chosen.name} (解锁{seed.seed_path}+{seed.seed_gold}金)"))
                    # 选了种子后更新 main_path
                    if state._main_path is None:
                        state.__dict__["_main_path"] = seed.seed_path
                    continue
                # 池满 → 丢最无用的（模拟玩家合理选择）
                if len(state.bond_pool) >= state.bond_pool_capacity:
                    discard = _pick_discard(state.bond_pool, state.path_realm, pools, chosen.id)
                    if discard:
                        state.bond_pool.remove(discard)
                state.bond_pool.append(chosen.id)
                bond_times_drawn += 1
                do(Action(ActionType.DRAW_BOND, cost=cost, detail=f"{chosen.name}"))
                continue
            # 3) 升装备（里程碑抽词条：一次性 gold_lump 立即加金，其余进持续属性池）
            if state.equip_level < EQUIP_MAX_LEVEL:
                cost = equip_upgrade_cost(state.equip_level, econ)
                if state.spend(cost):
                    state.equip_level += 1
                    detail = f"+{state.equip_level}"
                    if state.equip_level in EQUIP_MILESTONES:
                        aff = _draw_milestone_affix(pools)
                        if aff is not None:
                            eff = aff.effect
                            if "gold_lump" in eff:
                                state.add_gold(float(eff["gold_lump"]))
                                detail += f"·{aff.name}(+{int(eff['gold_lump'])}金)"
                            else:
                                state.equip_affixes.append(eff)
                                detail += f"·{aff.name}"
                    do(Action(ActionType.UPGRADE_EQUIP, cost=cost, detail=detail))
                    continue
            # 4) 刷新羁绊（追求凑齐当前境界）—— 软上限内
            if state.rerolls_this_wave < reroll_cap:
                cost = bond_reroll_cost(state.rerolls_this_wave, econ)
                if state.spend(cost):
                    state.rerolls_this_wave += 1
                    pools.draw_bond_offers(
                        path_realm=state.path_realm,
                        owned_bond_ids=state.bond_pool,
                    )
                    do(Action(ActionType.BOND_REROLL, cost=cost, detail=f"#{state.rerolls_this_wave}"))
                    continue
            break

        return actions
