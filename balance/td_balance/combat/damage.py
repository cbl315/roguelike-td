"""伤害主公式 (Master Damage Pipeline) — GDD §3.1 的 single source of truth.

公式：
    hit = ATK × atk_ratio × dmg_type_mult × skill_mult
              × final_mult × elemental_mult × crit_factor × defense_mult
    DPS = Σ(每次命中) × attack_speed × projectile_count

叠加规则 (GDD §3.2):
    - 同源加法: dmg_type/skill/elemental 各自加法叠加
    - 跨源乘法: final_mult 每条独立乘法 Π(1+x)
    - 暴击: 率封顶 100%，率/伤分开
    - 多重射: projectile_count 直接相乘（含散射递减）
    - 真伤: 跳过 defense_mult，按比例单独结算

本模块纯逻辑、无副作用，便于单测与跨端复用（未来 Godot/服务端共享同一套定义）。
"""
from __future__ import annotations

from dataclasses import dataclass, field

# ── 英雄基础属性 (GDD §3.1，SSOT) ──
BASE_ATK: float = 50.0
BASE_CRIT_RATE: float = 0.05
BASE_CRIT_DMG: float = 1.5          # 暴击造成 1.5 倍（即 +50%）
BASE_ATTACK_SPEED: float = 1.0      # 次/秒

# 护甲减伤软上限常数
ARMOR_K: float = 100.0

# 叠加封顶
CRIT_RATE_CAP: float = 1.0
DAMAGE_REDUCTION_CAP: float = 0.75  # GDD §4.2 减伤封顶 75%

# 多重射散射递减（GDD §3.2 / affixes multishot）
MULTISHOT_PER_PROJECTILE_DMG_MULT: float = 0.85


@dataclass
class CombatStats:
    """一次命中结算所需的全部战斗属性。

    所有 *_pct / *_delta 字段都是"加法叠加的增量"（来自词条/羁绊），
    在 assemble() 时累加进对应乘区。final_dmg_mults 是乘法叠加的列表。
    """

    # ── 基础（来自英雄 + 羁绊层）──
    atk: float = BASE_ATK
    atk_ratio: float = 1.0           # 技能/武器系数

    # ── 加法叠加的乘区增量 (GDD §3.2 同源加法) ──
    physical_dmg_pct: float = 0.0    # +物伤%
    magic_dmg_pct: float = 0.0       # +法伤%
    skill_mult_pct: float = 0.0      # Σ 技能内倍率词条（如排云掌 +25%）
    elemental_pct: float = 0.0       # +属性伤害%（火/冰/雷，独立乘区）

    # ── 乘法叠加（GDD §3.2 跨源乘法）──
    final_dmg_mults: list[float] = field(default_factory=list)  # 每条 Π(1+x)

    # ── 暴击 ──
    crit_rate: float = BASE_CRIT_RATE
    crit_dmg: float = BASE_CRIT_DMG

    # ── 攻速 / 多重射 ──
    attack_speed: float = BASE_ATTACK_SPEED
    projectile_count: int = 1

    # ── 防御交互 ──
    armor_pen: float = 0.0           # 穿甲 0..1（减免护甲减伤的比例）
    true_dmg_pct: float = 0.0        # 0..1，伤害按此比例转真伤（跳过护甲）

    def with_final_mult(self, x: float) -> "CombatStats":
        """链式追加一条最终伤害乘区（联动用）。返回新实例。"""
        s = CombatStats(**self.__dict__)
        s.final_dmg_mults = [*self.final_dmg_mults, x]
        return s


@dataclass
class EnemyStats:
    """敌人护甲/抗性。GDD §3.1 defense_mult。"""
    armor: float = 0.0


# ──────────────────────────────────────────────
# 公式分解（每一步独立可测，便于 §8 走查逐步展开）
# ──────────────────────────────────────────────

def mitigation(armor: float, K: float = ARMOR_K) -> float:
    """护甲减伤比例 = armor/(armor+K)。线性软上限，避免堆甲无敌。"""
    if armor <= 0:
        return 0.0
    return armor / (armor + K)


def defense_mult(armor: float, armor_pen: float) -> float:
    """实际减伤乘子 = 1 - mitigation×(1-穿甲)。穿甲越高减伤越少。"""
    mit = mitigation(armor) * (1.0 - max(0.0, min(1.0, armor_pen)))
    return max(0.0, 1.0 - mit)


def crit_factor(crit_rate: float, crit_dmg: float) -> float:
    """暴击期望因子 = 1 + min(rate,1)×(crit_dmg−1)。率封顶 100%。"""
    rate = max(0.0, min(CRIT_RATE_CAP, crit_rate))
    return 1.0 + rate * (crit_dmg - 1.0)


def final_mult(mults: list[float]) -> float:
    """最终伤害乘区 = Π(1+x)。每条独立乘法。空列表 = 1.0。"""
    result = 1.0
    for x in mults:
        result *= (1.0 + x)
    return result


def expected_hit_dmg(stats: CombatStats, enemy: EnemyStats) -> float:
    """单发命中期望伤害（含暴击期望、含护甲、含真伤拆分）。

    真伤部分跳过 defense_mult；其余部分正常结算。两部分相加。
    """
    # 普通部分（受护甲影响）
    normal = (
        stats.atk
        * stats.atk_ratio
        * (1.0 + stats.physical_dmg_pct + stats.magic_dmg_pct)  # dmg_type
        * (1.0 + stats.skill_mult_pct)                          # skill_mult
        * final_mult(stats.final_dmg_mults)                     # final
        * (1.0 + stats.elemental_pct)                           # elemental
        * crit_factor(stats.crit_rate, stats.crit_dmg)          # crit
        * defense_mult(enemy.armor, stats.armor_pen)            # defense
    )
    # 真伤部分（跳过护甲，按比例切出）
    if stats.true_dmg_pct > 0:
        # 真伤的基数：同样的前置乘区，但不乘 defense_mult
        true_base = (
            stats.atk
            * stats.atk_ratio
            * (1.0 + stats.physical_dmg_pct + stats.magic_dmg_pct)
            * (1.0 + stats.skill_mult_pct)
            * final_mult(stats.final_dmg_mults)
            * (1.0 + stats.elemental_pct)
            * crit_factor(stats.crit_rate, stats.crit_dmg)
        )
        # 把"若没有真伤切分时的整段"按比例拆：普通×(1-tp) + 真伤×tp
        # 这里用更直观的重算：normal 已含 defense，真伤不含
        # 为避免重复，重新统一为：total = normal_full_def * (1-tp) + no_def * tp
        tp = max(0.0, min(1.0, stats.true_dmg_pct))
        return normal * (1.0 - tp) + true_base * tp
    return normal


def expected_dps(stats: CombatStats, enemy: EnemyStats) -> float:
    """期望 DPS = 单发期望 × 攻速 × 弹数（含散射递减）。

    多重射递减（GDD §3.2 / affixes multishot）：
    每根额外弹的伤害 ×0.85，故总弹数 n 的有效倍率 = 1 + (n-1)×0.85。
    """
    n = max(1, stats.projectile_count)
    effective_proj_mult = 1.0 + (n - 1) * MULTISHOT_PER_PROJECTILE_DMG_MULT
    return expected_hit_dmg(stats, enemy) * stats.attack_speed * effective_proj_mult


# ──────────────────────────────────────────────
# 逐步展开（供 reports/walkthrough 逐步打印，对应 GDD §8）
# ──────────────────────────────────────────────

def breakdown(stats: CombatStats, enemy: EnemyStats) -> dict[str, float]:
    """返回每一步乘区的数值，用于走查报告逐段展示。"""
    dmg_type = 1.0 + stats.physical_dmg_pct + stats.magic_dmg_pct
    skill = 1.0 + stats.skill_mult_pct
    fm = final_mult(stats.final_dmg_mults)
    elem = 1.0 + stats.elemental_pct
    cf = crit_factor(stats.crit_rate, stats.crit_dmg)
    dm = defense_mult(enemy.armor, stats.armor_pen)

    base = stats.atk * stats.atk_ratio
    pre_def = base * dmg_type * skill * fm * elem * cf
    after_def = pre_def * dm
    # 真伤拆分
    tp = max(0.0, min(1.0, stats.true_dmg_pct))
    hit = after_def * (1.0 - tp) + pre_def * tp

    n = max(1, stats.projectile_count)
    proj_mult = 1.0 + (n - 1) * MULTISHOT_PER_PROJECTILE_DMG_MULT
    return {
        "atk": stats.atk,
        "atk_ratio": stats.atk_ratio,
        "base": base,                 # ATK × ratio
        "dmg_type_mult": dmg_type,
        "skill_mult": skill,
        "final_mult": fm,
        "elemental_mult": elem,
        "crit_factor": cf,
        "pre_def": pre_def,           # 护甲前
        "defense_mult": dm,
        "after_def": after_def,       # 护甲后（无真伤）
        "true_dmg_pct": tp,
        "hit_expected": hit,
        "projectile_count": float(n),
        "proj_mult": proj_mult,
        "attack_speed": stats.attack_speed,
        "dps": hit * stats.attack_speed * proj_mult,
    }
