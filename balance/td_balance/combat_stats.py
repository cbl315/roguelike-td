"""PlayerCombat 聚合体 + effect resolver (B-3)。

把 bond/reward/affix/synergy 的 effect dict 解析成玩家战斗属性。
- offense（进攻）：复用 combat.damage.CombatStats（一字不改）
- survival（生存）：hp/减伤/吸血/回复/护盾/反伤
- economy（经济）：gold_mult 等
- special（特殊）：status/transform/chain 简化记录

设计：accumulate() 接收一串 effect dict，累加进 PlayerCombat。
resolve_player() 从 PlayerState（bond_pool + path_realm + skills + equipment）
构造完整 PlayerCombat。

纯逻辑、可单测。
"""
from __future__ import annotations

from dataclasses import dataclass, field

from .combat.damage import CombatStats


@dataclass
class Survival:
    """生存属性（CombatStats 不含的部分）。"""
    max_hp: float = 1000.0          # 核心初始血量
    damage_reduction: float = 0.0   # 减伤 0..0.75（封顶）
    lifesteal_pct: float = 0.0      # 吸血（造成伤害的比例回血）
    regen_per_5s: float = 0.0       # 每 5s 回血（占 max_hp 比例）
    shield_pct: float = 0.0         # 护盾（占 max_hp 比例，受击先扣）
    reflect_pct: float = 0.0        # 反伤（受击伤害的比例反弹）
    # 基础属性增益（百分比，用于 all_stats_pct_delta）
    _hp_pct_bonus: float = 0.0      # hp_pct_delta 累积 → 放大 max_hp

    @property
    def effective_max_hp(self) -> float:
        return self.max_hp * (1.0 + self._hp_pct_bonus)


@dataclass
class Economy:
    """经济属性（装备/羁绊的经济加成累积）。"""
    gold_mult: float = 1.0          # 所有金币 ×此值（乘法叠加 → 累加增量）
    per_kill_gold_delta: float = 0.0
    gold_per_sec_delta: float = 0.0


@dataclass
class Special:
    """特殊效果（精确建模为 DPS 乘数）。"""
    statuses: list[str] = field(default_factory=list)   # status 名（heaven_emperor 等）
    # transform（变身）：周期性触发，期间攻速 ×mult
    transform_mult: float = 1.0          # 变身期间攻速倍率
    transform_duration: float = 0.0      # 变身持续秒
    transform_cooldown: float = 0.0      # 变身冷却秒
    transform_aoe: bool = False          # 变身期间 AOE
    # chain（连锁弹射）：每次命中额外弹射，递减伤害
    chain_extra_bounces: int = 0
    # followup（追击）：每 n_hits 次攻击追击 1 次
    followup_hit_ratio: float = 0.0      # 追击伤害倍率
    followup_every_n_hits: int = 0       # 每 N 次触发

    def transform_uptime(self, wave_duration: float) -> float:
        """变身在一个波次内的覆盖率（0..1）。
        uptime = min(1, duration/duration) 若 cooldown<=duration 则可多次。
        """
        if self.transform_duration <= 0 or self.transform_cooldown <= 0:
            return 0.0
        # 该波次内变身总时长（可能多次触发）
        if self.transform_cooldown >= wave_duration:
            # 冷却 ≥ 波长：最多触发 1 次（持续 min(duration, wave_duration)）
            return min(self.transform_duration, wave_duration) / wave_duration
        # 冷却 < 波长：可多次，总时长 = floor(wave/cooldown) × duration + 余量
        cycles = int(wave_duration // self.transform_cooldown)
        total_up = cycles * self.transform_duration
        remain = wave_duration - cycles * self.transform_cooldown
        total_up += min(remain, self.transform_duration)
        return min(1.0, total_up / wave_duration)

    def chain_mult(self, decay: float = 0.7) -> float:
        """连锁弹射的 DPS 乘数。每次弹射伤害 ×decay（递减）。
        原始 1 发 + N 弹 × decay^k → 1 + Σ decay^k。
        """
        if self.chain_extra_bounces <= 0:
            return 1.0
        return 1.0 + sum(decay ** (k + 1) for k in range(self.chain_extra_bounces))

    def followup_mult(self) -> float:
        """追击的 DPS 乘数 = 1 + hit_ratio / every_n_hits。"""
        if self.followup_every_n_hits <= 0 or self.followup_hit_ratio <= 0:
            return 1.0
        return 1.0 + self.followup_hit_ratio / self.followup_every_n_hits


@dataclass
class PlayerCombat:
    """玩家完整战斗属性 = 进攻 + 生存 + 经济 + 特殊。"""
    offense: CombatStats = field(default_factory=CombatStats)
    survival: Survival = field(default_factory=Survival)
    economy: Economy = field(default_factory=Economy)
    special: Special = field(default_factory=Special)

    def accumulate(self, effect: dict) -> None:
        """把一个 effect dict 累加进来。覆盖全部已知 key。"""
        for key, val in effect.items():
            self._apply(key, val)

    # ── key → 字段映射 ──
    def _apply(self, key: str, val) -> None:
        o = self.offense
        s = self.survival
        e = self.economy
        sp = self.special

        # 进攻 → CombatStats
        if key == "atk_pct_delta":
            # CombatStats.atk 是绝对值；这里累加百分比，resolve_player 时再乘 base
            o._atk_pct_bonus = getattr(o, "_atk_pct_bonus", 0.0) + val
        elif key == "crit_rate_delta":
            o.crit_rate += val
        elif key == "crit_dmg_delta":
            o.crit_dmg += val
        elif key == "attack_speed_delta":
            o.attack_speed += val
        elif key == "skill_mult_pct_delta":
            o.skill_mult_pct += val
        elif key == "magic_dmg_pct_delta":
            o.magic_dmg_pct += val
        elif key == "physical_dmg_pct_delta":
            o.physical_dmg_pct += val
        elif key == "elemental_dmg_mult":
            # synergy 用 elemental_dmg_mult（与 CombatStats.elemental_pct 同义）
            o.elemental_pct += val
        elif key == "elemental_pct":
            o.elemental_pct += val
        elif key == "final_dmg_mult":
            # 进 final_dmg_mults 乘区（ CombatStats.final_mult 做 Π(1+x)）
            o.final_dmg_mults.append(val)
        elif key == "true_dmg_pct_delta":
            o.true_dmg_pct += val
        elif key == "armor_pen_delta":
            o.armor_pen += val
        # 生存 → Survival
        elif key == "hp_pct_delta":
            s._hp_pct_bonus += val
        elif key == "damage_reduction_delta":
            s.damage_reduction = min(0.75, s.damage_reduction + val)  # 封顶 75%
        elif key == "lifesteal_pct":
            s.lifesteal_pct += val
        elif key == "hp_regen_pct_per_5s":
            s.regen_per_5s += val
        elif key == "shield_pct":
            s.shield_pct += val
        elif key == "reflect_pct":
            s.reflect_pct += val
        # 经济 → Economy
        elif key == "gold_mult":
            e.gold_mult += val              # gold_mult 初值 1.0，增量累加
        elif key == "per_kill_gold_delta":
            e.per_kill_gold_delta += val
        elif key == "gold_per_sec_delta":
            e.gold_per_sec_delta += val
        # 全属性百分比
        elif key == "all_stats_pct_delta":
            o._atk_pct_bonus = getattr(o, "_atk_pct_bonus", 0.0) + val
            s._hp_pct_bonus += val
            o.crit_rate += val * 0.5        # 全属性含少量暴击
        # 特殊（精确建模）
        elif key == "status":
            sp.statuses.append(val)
        elif key == "transform_duration":
            sp.transform_duration = val
        elif key == "transform_cooldown":
            sp.transform_cooldown = val
        elif key == "transform_aoe":
            sp.transform_aoe = bool(val)
        elif key == "transform_attack_speed_mult":
            sp.transform_mult = val      # 记录倍率，由战斗判定按 uptime 应用
        elif key == "chain_extra_bounces":
            sp.chain_extra_bounces += val
        elif key == "followup_hit_ratio":
            sp.followup_hit_ratio = val
        elif key == "followup_every_n_hits":
            sp.followup_every_n_hits = int(val)
        # 忽略的 key（经济类/控制类，B-3 不影响战斗判定；transform_gold_mult 是变身期金币加成，经济层处理）
        elif key in ("gold_on_hit", "double_gold_chance", "bond_draw_cost_delta",
                     "reroll_cost_delta", "equip_upgrade_cost_delta",
                     "bond_devour_level_delta", "synergy_effect_mult",
                     "per_hit_dmg_mult", "dmg_taken_mult", "draw_cost_mult",
                     "legendary_draw_chance_mult", "core_hp_loss_per_5s",
                     "bond_pool_capacity_delta", "per_bond_effect_mult",
                     "transform_gold_mult", "execute_threshold",
                     "execute_dmg_mult", "double_strike_chance", "poison_chance",
                     "poison_dmg_mult", "chain_chance", "chain_bounces",
                     "stun_chance", "stun_duration", "cdr_pct", "immune_cc",
                     "synergy_unlock"):
            pass
        else:
            # 未知 key：静默忽略（B-3 不报错，避免数据小改炸模拟）
            pass


# ── 从 PlayerState 构造完整 PlayerCombat ──

def resolve_player(state, pools) -> PlayerCombat:
    """从 PlayerState + RoguePools 构造完整 PlayerCombat。

    汇总来源：
    - 羁绊池里每个羁绊的 effect（BondDef.effect）
    - 已修炼境界的 reward（path_realm[id] 累积所有已过境界的 reward）
    - 装备词条（state.equip_affixes，若 PlayerState 有；当前简化为空）
    """
    pc = PlayerCombat()
    bond_map = {b.id: b for b in pools.bonds}

    # 1) 羁绊池羁绊 effect
    for bid in state.bond_pool:
        b = bond_map.get(bid)
        if b and b.effect:
            pc.accumulate(b.effect)

    # 2) 已修炼境界的 reward（path_realm[id] = 已通过的境界数；reward 是 0..idx-1）
    for p in pools.paths:
        reached = state.path_realm.get(p.id, 0)
        for idx in range(reached):
            if idx < len(p.realms):
                reward = p.realms[idx].reward
                if reward:
                    pc.accumulate(reward)

    # 3) 应用 ATK 百分比加成（base × (1+Σ%)）
    atk_pct = getattr(pc.offense, "_atk_pct_bonus", 0.0)
    if atk_pct:
        pc.offense.atk = CombatStats().atk * (1.0 + atk_pct)

    return pc
