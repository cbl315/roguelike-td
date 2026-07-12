"""完整 Run 模拟 (B-3) — 经济循环 + 双向战斗判定 + 通关率。

每波：
  1. 战斗获金（复用 economy.wave_income）
  2. 大厅花金（复用 strategy.SimpleStrategy）
  3. 解算 PlayerCombat（羁绊+境界+联动）
  4. 战斗判定：
     - clear_time = enemy_total_hp / player_dps；超过 wave_duration → 失败（清不完）
     - 敌人对核心伤害 = enemy_dps_model × clear_time × (1-减伤) - 吸血抵消
     - 核心血量归零 → 失败
  5. 记录死亡波次 / 死时血量 / DPS

可种子化、可复现。蒙特卡洛由 run_report 跑 N 局聚合。
"""
from __future__ import annotations

from dataclasses import dataclass, field

from . import curves
from .combat.damage import EnemyStats, expected_dps
from .combat_stats import PlayerCombat, resolve_player
from .economy import load_economy_params, wave_income
from .loader import load_wave_params
from .player import PlayerState
from .rogue_pools import RoguePools
from .rng import RNG
from .strategy import SimpleStrategy
from .synergy_engine import SynergyEngine, apply_synergies

# ── 战斗判定参数（可调）──
# 模型：塔防里只有"漏怪"才打核心。核心伤害与玩家"清不完的部分"挂钩，
# 且单波伤害封顶（防突死），跨波累积消耗 → 制造 near-miss（贴着死亡线）。
CORE_BASE_HP: float = 1000.0          # 核心初始血量
LEAK_DAMAGE_RATIO: float = 0.35       # 漏怪伤害系数：每点"未清DPS·秒"对核心的伤害
CORE_REGEN_PER_WAVE: float = 0.05     # 每波结束后核心回血（占 max_hp，制造"贴线"节奏）
MAX_CORE_DAMAGE_PER_WAVE: float = 0.95  # 单波核心伤害封顶（留 5% 余地，制造 near-miss）
ENEMY_ARMOR: float = 20.0             # 敌人基础护甲
ENEMY_ARMER_GROWTH: float = 1.5       # 每波护甲增长


@dataclass
class RunResult:
    """一局模拟结果。"""
    seed: int
    won: bool                         # 是否通关（活过 30 波）
    death_wave: int                   # 死在第几波（通关=31）
    death_hp_pct: float               # 死时核心血量百分比（通关=存活血量）
    maxed_paths: int                  # 修满顶级境界体系数
    synergies_triggered: list[str]    # 触发的联动 id
    dps_per_wave: list[float]         # 每波玩家 DPS
    final_path_realm: dict            # 最终境界进度
    final_gold: float


def _enemy_armor(wave: int) -> float:
    """敌人护甲随波次增长。"""
    return ENEMY_ARMOR + ENEMY_ARMER_GROWTH * (wave - 1)


def _battle_outcome(pc: PlayerCombat, wave: int, p, core_hp_current: float) -> dict:
    """单波战斗判定。返回 {cleared, core_damage, dps, clear_time}。

    核心伤害模型（near-miss 设计）：
    - 清完波：核心吃少量漏怪伤害（与富余度反相关）。
    - 清不完波：怪涌到核心，把核心打到残血(5-20%)但不直接死。
      缺口越大残血越低（差一点→18%，差很多→5%）。
    core_hp_current: 战斗前核心血量（用于算"打到残血"的实际伤害）。
    """
    total_hp = curves.wave_total_hp(wave, p)
    duration = curves.wave_duration(wave, p)
    enemy = EnemyStats(armor=_enemy_armor(wave))

    dps = expected_dps(pc.offense, enemy)
    if dps <= 0:
        return {"cleared": False, "core_damage": core_hp_current,
                "dps": 0.0, "clear_time": duration}

    # 精确建模特殊效果对 DPS 的加成（DPS 乘数）
    sp = pc.special
    # 连锁弹射（雷属性额外弹射，递减）
    dps *= sp.chain_mult()
    # 追击（每 N 击追击）
    dps *= sp.followup_mult()
    # 变身（周期性触发，按覆盖率加权攻速倍率）
    if sp.transform_mult > 1.0 and sp.transform_duration > 0:
        uptime = sp.transform_uptime(duration)
        if uptime > 0:
            dps *= (1.0 - uptime) + uptime * sp.transform_mult
            # AOE：变身期间清场效率提升（额外 30% 清怪速度）
            if sp.transform_aoe:
                dps *= (1.0 - uptime) + uptime * 1.3

    clear_time = total_hp / dps
    cleared = clear_time <= duration
    max_hp = pc.survival.effective_max_hp

    if cleared:
        # 清完：核心持续受压（贴线设计），但清完波不致死（最多压到 25%）。
        margin = 1.0 - (clear_time / duration)
        base_pct = 0.12 - 0.06 * margin   # 6%..12%
        raw = base_pct * max_hp * (1.0 - pc.survival.damage_reduction)
        heal = dps * min(clear_time, duration) * pc.survival.lifesteal_pct
        heal += max_hp * pc.survival.regen_per_5s * (min(clear_time, duration) / 5.0)
        raw_after_heal = max(0.0, raw - heal)
        # 保护：清完波不会把核心打到 25% 以下（留余地，让未清完波来终结）
        floor_hp = 0.25 * max_hp
        if core_hp_current - raw_after_heal < floor_hp:
            raw_after_heal = max(0.0, core_hp_current - floor_hp)
        core_damage = raw_after_heal
    else:
        # 清不完：怪涌核心，强制打到残血（near-miss，5-15% 区间）——这是主要死因。
        remaining_hp = max(0.0, total_hp - dps * duration)
        gap_ratio = remaining_hp / total_hp if total_hp > 0 else 1.0
        target_remain_pct = max(0.05, 0.15 - 0.10 * gap_ratio)  # 5%..15%
        target_remain_hp = target_remain_pct * max_hp
        core_damage = max(0.0, core_hp_current - target_remain_hp)
    # 单波封顶（防异常）
    cap = MAX_CORE_DAMAGE_PER_WAVE * max_hp
    core_damage = min(core_damage, cap)

    return {"cleared": cleared, "core_damage": core_damage, "dps": dps, "clear_time": clear_time}


def simulate_run(seed: int, strategy=None, n_waves: int | None = None) -> RunResult:
    """模拟一局完整 run（经济 + 战斗）。返回 RunResult。"""
    econ = load_economy_params()
    wave_params = load_wave_params()
    if n_waves is None:
        n_waves = wave_params.main_quest_waves

    state = PlayerState(gold=0.0)
    state.survival_hp = CORE_BASE_HP   # 动态挂在 state 上（核心当前血量）
    pools = RoguePools(RNG(seed=seed))
    strat = strategy or SimpleStrategy()
    engine = SynergyEngine()

    dps_per_wave: list[float] = []
    death_wave = n_waves + 1           # 默认通关
    synergies_final: list[str] = []
    death_max_hp = CORE_BASE_HP        # 死亡波的有效 max_hp（用于 death_hp_pct 归一化）

    for wave in range(1, n_waves + 1):
        # 1) 战斗获金
        income = wave_income(wave, econ)
        state.add_gold(income["total"])
        # 2) 大厅花金
        state.begin_wave()
        strat.spend_lobby(state, pools, econ)

        # 3) 解算 PlayerCombat（羁绊 + 境界 reward + 联动）
        pc = resolve_player(state, pools)
        synergies_final = apply_synergies(pc, state, pools, engine)

        # 4) 战斗判定（传当前核心血量，用于 near-miss 残血计算）
        death_max_hp = pc.survival.effective_max_hp   # 记录本波 max_hp（死亡时用）
        outcome = _battle_outcome(pc, wave, wave_params, core_hp_current=state.survival_hp)
        dps_per_wave.append(round(outcome["dps"], 1))
        state.survival_hp -= outcome["core_damage"]

        if not outcome["cleared"] or state.survival_hp <= 0:
            death_wave = wave
            break

        # 5) 波间核心回血（按 effective max_hp 回，不超 max）
        state.survival_hp = min(pc.survival.effective_max_hp,
                                state.survival_hp + CORE_REGEN_PER_WAVE * pc.survival.effective_max_hp)

    won = death_wave > n_waves
    # 修满顶级境界体系数
    maxed = 0
    for p in pools.paths:
        if state.path_realm.get(p.id, 0) >= len(p.realms) - 1:
            maxed += 1

    death_hp_pct = max(0.0, getattr(state, "survival_hp", 0.0)) / death_max_hp

    return RunResult(
        seed=seed,
        won=won,
        death_wave=death_wave,
        death_hp_pct=round(death_hp_pct, 3),
        maxed_paths=maxed,
        synergies_triggered=synergies_final,
        dps_per_wave=dps_per_wave,
        final_path_realm=dict(state.path_realm),
        final_gold=round(state.gold, 1),
    )
