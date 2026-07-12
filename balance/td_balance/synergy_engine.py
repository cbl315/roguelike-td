"""联动引擎 (B-3) — 根据玩家状态重算 active 联动规则。

触发条件（GDD §7，对齐境界树）：
  - bond_devoured_set: <path_id>  → 该体系修满所有境界（path_realm[id] >= len(realms)）
  - affix_owned: <affix_id>       → 拥有该词条（技能/装备；B-3 简化：检查技能 base_affixes）
  - equipment_affix: <affix_id>   → 装备该词条（B-3 简化：同 affix_owned）

技能已重构为"每体系 1 个起点技能"：选了体系自动获得，修满体系即触发对应联动，
故不再需要 skill_owned / skill_tag 条件（修满体系 = 自动拥有其起点技能）。

效果：返回 active 联动的 effect dict 列表，供 resolve_player 累加。

纯逻辑、可单测。
"""
from __future__ import annotations

from .loader import load_synergies
from .schemas import SynergyDef


class SynergyEngine:
    """联动规则引擎。加载一次，多次查询。"""

    def __init__(self) -> None:
        self.synergies: list[SynergyDef] = load_synergies()

    def active(self, state, pools) -> list[SynergyDef]:
        """返回当前所有满足触发条件的联动。"""
        result: list[SynergyDef] = []
        for syn in self.synergies:
            if self._check(syn, state, pools):
                result.append(syn)
        return result

    def _check(self, syn: SynergyDef, state, pools) -> bool:
        """检查一条联动：trigger.all 里所有条件都满足。"""
        conditions = syn.trigger.get("all", [])
        for cond in conditions:
            if not self._check_one(cond, state, pools):
                return False
        return True

    def _check_one(self, cond: dict, state, pools) -> bool:
        """检查单个触发条件。cond 是 {key: value} 单键 dict。"""
        for key, val in cond.items():
            if key == "bond_devoured_set":
                # 该体系修满顶级境界
                realms = self._path_realms(val, pools)
                if realms is None:
                    return False
                return state.path_realm.get(val, 0) >= len(realms)
            elif key == "affix_owned":
                return self._has_affix(val, state, pools)
            elif key == "equipment_affix":
                # B-3 简化：与 affix_owned 同处理
                return self._has_affix(val, state, pools)
            elif key == "bond_owned":
                # 兼容旧：羁绊在池中
                return val in state.bond_pool
        return False

    def _path_realms(self, path_id: str, pools):
        for p in pools.paths:
            if p.id == path_id:
                return p.realms
        return None

    def _has_affix(self, affix_id: str, state, pools) -> bool:
        """检查玩家是否拥有某词条（来自技能的 base_affixes）。

        B-3 简化：检查技能的 base_affixes 列表。
        装备词条需要 PlayerState 追踪，当前未实装，故仅查技能。
        """
        affix_ids = set()
        skill_map = {s.id: s for s in pools.skills}
        for sid in state.skills:
            s = skill_map.get(sid)
            if s:
                affix_ids.update(s.base_affixes)
        return affix_id in affix_ids


def apply_synergies(pc, state, pools, engine: SynergyEngine) -> list[str]:
    """把 active 联动的 effect 累加进 PlayerCombat，返回触发的联动 id 列表。"""
    active = engine.active(state, pools)
    for syn in active:
        if syn.effect:
            pc.accumulate(syn.effect)
    return [s.id for s in active]
