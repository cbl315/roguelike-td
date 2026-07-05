"""抽取池 — 技能/羁绊 3 选 1，稀有度加权 + 重投/锁定 (GDD §4.3 / §6.1)。

设计：
  - draw_skill_offers  生成 3 个技能选项（50% 新技能/50% 已有词条，按稀有度加权）
  - draw_bond_offers   生成 3 个羁绊选项（按稀有度/均匀加权）
  - 重投：新 3 个选项，成本递增（见 economy.reroll_cost）
  - 锁定：B-2 留接口（locked_ids 不随重投消失）

复用 rng（weighted_choice/sample）+ loader（affixes/skills/bonds）。

返回的"选项"是纯数据（id/name/rarity/kind），不含战斗效果——B-2 只验证抽取分布。
"""
from __future__ import annotations

from dataclasses import dataclass

from .loader import load_affixes, load_bonds, load_paths, load_rarity_weights, load_sets, load_skills
from .rng import RNG

# 抽取的"选项"种类
KIND_NEW_SKILL = "new_skill"
KIND_SKILL_AFFIX = "skill_affix"
KIND_BOND = "bond"


@dataclass
class Offer:
    """一个抽取选项。"""
    kind: str
    id: str
    name: str
    rarity: str            # common/rare/epic/legendary


class RoguePools:
    """抽取池管理器。一次性加载内容数据，多次抽取复用。"""

    def __init__(self, rng: RNG) -> None:
        self.rng = rng
        self.skills = load_skills()
        self.affixes = load_affixes()
        self.bonds = load_bonds()
        self.paths = load_paths()          # 修炼路径（境界树）
        self.rarity_weights = load_rarity_weights()
        self.rarities = ["common", "rare", "epic", "legendary"]
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

    def _weighted_rarity(self) -> str:
        """按权重抽一个稀有度。"""
        weights = [self.rarity_weights[r] for r in self.rarities]
        return self.rng.weighted_choice(self.rarities, weights)

    def draw_skill_offers(self, owned_skill_ids: set[str], n: int = 3) -> list[Offer]:
        """生成 n 个技能选项（GDD §4.3：50% 新技能/50% 已有词条）。

        新技能：从玩家未拥有的技能池按稀有度过滤后抽。
        已有词条：从词条池按稀有度抽（模拟"给已有技能加词条"）。
        """
        offers: list[Offer] = []
        unowned = [s for s in self.skills if s.id not in owned_skill_ids]
        for _ in range(n):
            roll = self.rng.float()
            if roll < 0.5 and unowned:
                # 新技能：先定稀有度，再在该稀有度的未拥有技能里抽
                rarity = self._weighted_rarity()
                pool = [s for s in unowned if s.rarity == rarity] or unowned
                s = self.rng.choice(pool)
                offers.append(Offer(KIND_NEW_SKILL, s.id, s.name, s.rarity))
            else:
                # 已有技能的词条（或无新技能时也走这条）
                rarity = self._weighted_rarity()
                pool = [a for a in self.affixes if a.rarity == rarity] or self.affixes
                a = self.rng.choice(pool)
                offers.append(Offer(KIND_SKILL_AFFIX, a.id, a.name, a.rarity))
        return offers

    def draw_bond_offers(self, n: int = 3, prefer_ids: list[str] | None = None) -> list[Offer]:
        """生成 n 个羁绊选项。

        prefer_ids: 优先抽这些羁绊（如当前修炼境界的羁绊），其余从全池补。
        模拟"玩家专注某条修炼路径"的抽取偏好。
        """
        offers: list[Offer] = []
        bond_map = {b.id: b for b in self.bonds}
        pool = prefer_ids if prefer_ids else self._all_bond_ids
        pool = [bid for bid in pool if bid in bond_map] or self._all_bond_ids
        for _ in range(n):
            bid = self.rng.choice(pool)
            b = bond_map[bid]
            offers.append(Offer(KIND_BOND, b.id, b.name, "common"))
        return offers

    def reroll(self, offers: list[Offer], draw_fn, locked_idx: set[int] | None = None) -> list[Offer]:
        """重投：保留 locked 的，其余重新生成。

        draw_fn: draw_skill_offers / draw_bond_offers 的无参绑定。
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
