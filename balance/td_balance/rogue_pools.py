"""抽取池 — 羁绊 3 选 1，稀有度加权 + 重投/锁定 (GDD §4.3 / §6.1)。

设计：
  - draw_bond_offers   生成 3 个羁绊选项（按稀有度/均匀加权，阶梯抽取）
  - 重投：新 3 个选项，成本递增（见 economy.reroll_cost）
  - 锁定：B-2 留接口（locked_ids 不随重投消失）

技能已重构为"每体系 1 个起点技能"（选了体系自动获得，随境界突破自动升级），
不再走抽取消费，故本模块不再生成技能选项。

复用 rng（weighted_choice/sample）+ loader（affixes/skills/bonds）。

返回的"选项"是纯数据（id/name/rarity/kind），不含战斗效果——B-2 只验证抽取分布。
"""
from __future__ import annotations

from dataclasses import dataclass

from .loader import load_affixes, load_bonds, load_paths, load_rarity_weights, load_sets, load_skills
from .rng import RNG

# 抽取的"选项"种类
KIND_BOND = "bond"


@dataclass
class Offer:
    """一个抽取选项。"""
    kind: str
    id: str
    name: str
    rarity: str            # N/SR/SSR/UR/EX


class RoguePools:
    """抽取池管理器。一次性加载内容数据，多次抽取复用。"""

    def __init__(self, rng: RNG) -> None:
        self.rng = rng
        self.skills = load_skills()
        self.affixes = load_affixes()
        self.bonds = load_bonds()
        self.paths = load_paths()          # 修炼路径（境界树）
        self.rarity_weights = load_rarity_weights()
        self.rarities = ["N", "SR", "SSR", "UR", "EX"]
        # 羁绊 id → 所属套系/路径
        self._bond_to_set = {b.id: b.set for b in self.bonds}
        # 全部羁绊 id（含 generic）用于抽取池
        self._all_bond_ids = [b.id for b in self.bonds]
        # 路径 id → 该路径所有境界的羁绊 id 并集
        self._path_bond_ids: dict[str, list[str]] = {}
        for p in self.paths:
            ids: list[str] = []
            for r in p.realms:
                ids.extend(r.bonds)
            self._path_bond_ids[p.id] = ids
        # 种子羁绊查找表：seed_path → BondDef
        self._seeds: dict[str, "BondDef"] = {b.seed_path: b for b in self.bonds if b.is_seed}

    def get_seed(self, bond_id: str):
        """如果 bond_id 是种子，返回对应的 BondDef，否则 None。"""
        for b in self.bonds:
            if b.id == bond_id and b.is_seed:
                return b
        return None

    def _weighted_rarity(self) -> str:
        """按权重抽一个稀有度。"""
        weights = [self.rarity_weights[r] for r in self.rarities]
        return self.rng.weighted_choice(self.rarities, weights)
        """按权重抽一个稀有度。"""
        weights = [self.rarity_weights[r] for r in self.rarities]
        return self.rng.weighted_choice(self.rarities, weights)

    def draw_bond_offers(
        self,
        n: int = 3,
        path_realm: dict | None = None,
        owned_bond_ids: list[str] | None = None,
        prefer_ids: list[str] | None = None,
    ) -> list[Offer]:
        """生成 n 个羁绊选项（严格阶梯抽取）。

        阶梯规则（GDD §6.1，2026-07-12 修订）：
          - 只能抽 generic 通用符文 + 当前境界（path_realm[id]）的羁绊。
          - 已拥有的羁绊不重复出现（owned_bond_ids 排除）。
          - 突破（吞噬升境）后 path_realm[id] +1，自动解锁下一境界。
          - 修满所有境界后，只能抽 generic。

        path_realm: {path_id: 当前境界索引}；None 表示未修任何路径（只抽 generic）。
        owned_bond_ids: 玩家已拥有的羁绊 id（不重复抽）。
        prefer_ids: 兼容旧接口——若提供，作为加权偏好叠加在合法池上（不再绕过阶梯限制）。
        """
        offers: list[Offer] = []
        bond_map = {b.id: b for b in self.bonds}
        owned = set(owned_bond_ids or [])

        # 构建合法池 = generic + 种子 + 已选体系当前境界的羁绊
        pr = path_realm or {}
        legal: list[str] = [b.id for b in self.bonds if b.set == "generic"]
        # 种子卡：始终可见（不管选没选体系），但已选的不重复出现
        for b in self.bonds:
            if b.set == "seed" and b.seed_path not in pr:
                legal.append(b.id)
        # 已选体系的当前境界羁绊
        for p in self.paths:
            if p.id not in pr:
                continue
            idx = pr[p.id]
            if idx < len(p.realms):
                legal.extend(p.realms[idx].bonds)
        # 去重 + 排除已拥有
        legal = [bid for bid in dict.fromkeys(legal) if bid not in owned and bid in bond_map]

        # 无可抽羁绊时（当前境界全凑齐但未突破）→ 只剩 generic 兜底
        pool = legal or [b.id for b in self.bonds if b.set == "generic" and b.id not in owned]
        if not pool:
            # 极端：generic 也全拥有了且当前境界全凑齐——返回空（玩家应去突破）
            return []

        # prefer_ids 作为加权（仅放大合法池内条目的权重，不引入非法羁绊）
        if prefer_ids:
            prefer_set = set(prefer_ids) & set(pool)
            weighted_pool = [bid for bid in pool if bid in prefer_set] * 3 + pool
        else:
            weighted_pool = pool

        picked: set[str] = set()
        for _ in range(n):
            bid = self.rng.choice(weighted_pool)
            # 去重：已抽到的不重复
            tries = 0
            while bid in picked and tries < 8:
                bid = self.rng.choice(weighted_pool)
                tries += 1
            picked.add(bid)
            b = bond_map[bid]
            offers.append(Offer(KIND_BOND, b.id, b.name, b.rarity))
        return offers

    def reroll(self, offers: list[Offer], draw_fn, locked_idx: set[int] | None = None) -> list[Offer]:
        """重投：保留 locked 的，其余重新生成。

        draw_fn: draw_bond_offers 的无参绑定。
        B-2: locked 留接口，默认不锁（重投全部）。
        """
        if not locked_idx:
            return draw_fn()
        new = draw_fn()
        # 把锁定的旧选项保留到对应位置（简化：锁定的放前面）
        kept = [offers[i] for i in sorted(locked_idx) if i < len(offers)]
        return kept + new[len(kept):]

    # ── 羁绊境界吞噬（scalable sink，GDD §6.1）──

    def current_realm_bonds(self, path_id: str, realm_idx: int) -> list[str]:
        """返回某路径某境界需要的羁绊 id 列表。越界返回空（已修满）。"""
        for p in self.paths:
            if p.id == path_id:
                if realm_idx < len(p.realms):
                    return list(p.realms[realm_idx].bonds)
                return []
        return []

    def find_devourable(self, bond_pool: list[str], path_realm: dict) -> tuple[str, int, list[str]] | None:
        """找一条可晋升的修炼路径：当前境界的羁绊已全部在池中。

        path_realm: {path_id: 当前境界索引}
        返回 (path_id, realm_idx, needed_bond_ids) 或 None。
        一旦某路径当前境界凑齐 → 可吞噬（升境）。
        """
        # 池中羁绊集合（去重，因玩家可能抽到重复——但境界需求是 id 集合）
        pool_set = set(bond_pool)
        for p in self.paths:
            idx = path_realm.get(p.id, 0)
            if idx >= len(p.realms):
                continue  # 已修满
            needed = p.realms[idx].bonds
            if needed and all(b in pool_set for b in needed):
                return (p.id, idx, list(needed))
        return None

    def devour(self, bond_pool: list[str], needed: list[str]) -> list[str]:
        """吞噬：从池中移除当前境界所需的羁绊（每种移除 1 个）。返回被移除的 id。"""
        removed: list[str] = []
        for bid in needed:
            if bid in bond_pool:
                bond_pool.remove(bid)
                removed.append(bid)
        return removed
