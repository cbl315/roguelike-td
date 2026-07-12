"""玩家策略 — 可插拔接口 + SimpleStrategy（实装吞噬循环 + 刷新作为金币 sink）。

Strategy.spend_lobby(state, pools, econ, skill_upgrades_available) -> list[Action]
  在一波的大厅里花金币做 Rogue 操作，返回操作记录。

SimpleStrategy 循环优先级（直到没钱或没东西可做）：
  0. 用免费技能升级机会
  1. 若羁绊池满且可吞噬 → 吞噬（扣金 + 腾位 + 进已吞噬池）
  2. 羁绊池未满 → 抽羁绊
  3. 装备未满级 → 升装备
  4. 余钱 → 刷新羁绊（追求更好组合）或刷新技能

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
    skill_reroll_cost,
)
from .player import Action, ActionType, PlayerState
from .rogue_pools import RoguePools

EQUIP_MAX_LEVEL = 9


class Strategy:
    """策略接口（Protocol 风格）。子类实现 spend_lobby。"""
    def spend_lobby(
        self,
        state: PlayerState,
        pools: RoguePools,
        econ: EconomyParams,
        skill_upgrades_available: int,
    ) -> list[Action]:
        raise NotImplementedError


class SimpleStrategy(Strategy):
    """贪心策略：实装吞噬循环 + 刷新作为金币 sink。"""

    def spend_lobby(
        self,
        state: PlayerState,
        pools: RoguePools,
        econ: EconomyParams,
        skill_upgrades_available: int,
    ) -> list[Action]:
        reroll_cap = econ.reroll_cap_per_wave
        actions: list[Action] = []
        bond_times_drawn = 0
        skill_reroll_times = 0

        def do(action: Action) -> None:
            actions.append(action)
            state.record(action)

        # 选一条主修炼路径（开局随机选一条推进；B-3 可改智能选择）
        if not hasattr(state, "_main_path") or state.__dict__.get("_main_path") is None:
            import random as _r
            state.__dict__["_main_path"] = pools.rng.choice(pools.paths).id
        main_path = state._main_path

        def current_realm_needed() -> list[str]:
            """主路径当前境界需要的羁绊。"""
            idx = state.path_realm.get(main_path, 0)
            return pools.current_realm_bonds(main_path, idx)

        # 0) 免费技能升级机会
        for _ in range(skill_upgrades_available):
            offers = pools.draw_skill_offers(set(state.skills.keys()))
            chosen = offers[0]
            if chosen.kind == "new_skill":
                state.skills[chosen.id] = 1
            else:
                if state.skills:
                    sid = next(iter(state.skills))
                    state.skills[sid] = state.skills.get(sid, 0) + 1
                else:
                    state.skills["basic_strike"] = 1
            do(Action(ActionType.SKILL_LEVEL, cost=0.0, detail=f"{chosen.rarity}/{chosen.kind}"))

        # 1-5) 循环花钱
        guard = 0
        while state.gold > 0 and guard < 100:
            guard += 1
            # 1) 检查是否可吞噬（当前境界凑齐）
            dev = pools.find_devourable(state.bond_pool, state.path_realm)
            if dev:
                path_id, realm_idx, needed = dev
                cost = devour_cost(econ)
                if state.spend(cost):
                    pools.devour(state.bond_pool, needed)
                    state.path_realm[path_id] = realm_idx + 1  # 升境
                    do(Action(ActionType.DEVOUR, cost=cost, detail=f"{path_id} realm{realm_idx}→{realm_idx+1}"))
                    continue
            # 2) 抽羁绊（池未满）——强优先抽主路径当前境界需要的（重复加权）
            if not state.bond_pool_full:
                cost = bond_draw_cost(bond_times_drawn, econ)
                if state.spend(cost):
                    needed = current_realm_needed()
                    # 强偏好：需要的羁绊重复多次（占抽取池 70%），通用占 30%
                    needed_not_in_pool = [b for b in needed if b not in state.bond_pool]
                    prefer = (needed_not_in_pool * 7) + [b for b in pools._all_bond_ids if pools._bond_to_set.get(b) == "generic"] * 3
                    offers = pools.draw_bond_offers(prefer_ids=prefer or None)
                    chosen = offers[0]
                    state.bond_pool.append(chosen.id)
                    bond_times_drawn += 1
                    do(Action(ActionType.DRAW_BOND, cost=cost, detail=f"{chosen.name}"))
                    continue
            # 3) 升装备
            if state.equip_level < EQUIP_MAX_LEVEL:
                cost = equip_upgrade_cost(state.equip_level, econ)
                if state.spend(cost):
                    state.equip_level += 1
                    do(Action(ActionType.UPGRADE_EQUIP, cost=cost, detail=f"+{state.equip_level}"))
                    continue
            # 4) 刷新羁绊（追求凑齐当前境界）—— 软上限内
            if state.rerolls_this_wave < reroll_cap and not state.bond_pool_full:
                cost = bond_reroll_cost(state.rerolls_this_wave, econ)
                if state.spend(cost):
                    state.rerolls_this_wave += 1
                    needed = current_realm_needed()
                    prefer = needed + [b for b in pools._all_bond_ids if pools._bond_to_set.get(b) == "generic"]
                    pools.draw_bond_offers(prefer_ids=prefer)
                    do(Action(ActionType.BOND_REROLL, cost=cost, detail=f"#{state.rerolls_this_wave}"))
                    continue
            # 5) 刷新技能（额外出口）
            if state.rerolls_this_wave < reroll_cap:
                cost = skill_reroll_cost(skill_reroll_times, econ)
                if state.spend(cost):
                    skill_reroll_times += 1
                    state.rerolls_this_wave += 1
                    pools.draw_skill_offers(set(state.skills.keys()))
                    do(Action(ActionType.SKILL_REROLL, cost=cost, detail=f"#{skill_reroll_times}"))
                    continue
            break

        return actions
