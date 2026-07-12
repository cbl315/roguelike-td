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
from .rogue_pools import RoguePools

EQUIP_MAX_LEVEL = 9


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
    """贪心策略：实装吞噬循环 + 刷新作为金币 sink。"""

    def spend_lobby(
        self,
        state: PlayerState,
        pools: RoguePools,
        econ: EconomyParams,
    ) -> list[Action]:
        reroll_cap = econ.reroll_cap_per_wave
        actions: list[Action] = []
        bond_times_drawn = 0

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

        # 1-4) 循环花钱
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
                chosen = offers[0]
                # 池满 → 丢最无用的（模拟玩家合理选择）
                if len(state.bond_pool) >= state.bond_pool_capacity:
                    discard = _pick_discard(state.bond_pool, state.path_realm, pools, chosen.id)
                    if discard:
                        state.bond_pool.remove(discard)
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
