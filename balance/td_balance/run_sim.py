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
from math import fmod
from pathlib import Path

import yaml

from . import curves
from . import run_sim_flags
from .combat.damage import EnemyStats, expected_dps, expected_hit_dmg
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
ENEMY_HP_SCALE: float = 1.0           # 敌人血量全局缩放（大招/debuff 引入后的难度再平衡）
# 敌人行为多样化（远程/分裂/奶妈）宏观近似（wave 5+ 生效，与客户端 KIND_MIX 对应）：
#   splitter/healer 使有效波血抬升、ranged 使核心压力上浮。
#   数值轮 2026-11：1.05→1.03（w5 死亡尖峰 28% 过陡，配 count per_wave 1.5→1.4 一起回调）
ENEMY_BEHAVIOR_HP_MULT: float = 1.03
ENEMY_BEHAVIOR_PRESSURE: float = 1.03
ENEMY_BEHAVIOR_FROM_WAVE: int = 5
PLAYER_ECON_MULT: float = 1.03        # 玩家经济全局加成（行为怪难度再平衡）
# 宠魅召唤单位（莫邪/白魇魔/六尾妖狐）宏观近似：客户端召唤是独立输出实体，
# 模拟不逐实体建模，主体系=宠魅时 DPS 乘此系数（≈两只常驻召唤 35% 输出占比）。
CHONGMEI_SUMMON_DPS_MULT: float = 1.10


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


# ── Boss Debuff 建模（GDD §12，与客户端 boss_debuffs.gd 一致）──
# immune_cc（无控制）/ ult_energy_mult（无大招）仍过滤；
# magic/physical_dmg_taken_mult 已随三伤害类型轮启用（2026-10）。
_DEBUFF_UNSUPPORTED_KEYS = {"immune_cc", "ult_energy_mult"}

# ── 三伤害类型：主体系 → 弹道类型（星辰变/斗破=法术，遮天/宠魅=物理）──
_PATH_DAMAGE_TYPE = {"zhutian": "physical", "chongmei": "physical",
                     "xingchenbian": "magic", "doupo": "magic"}


def _pick_boss_debuffs(rng) -> list[dict]:
    """从不支持 key 过滤后的池随机抽 3 个，顺序=波次(10/20/30)顺序。"""
    data_dir = Path(__file__).resolve().parent.parent / "data" / "boss_debuffs.yaml"
    with open(data_dir, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    pool = []
    for b in data.get("bosses", []):
        keys = set((b.get("debuff") or {}).keys())
        if keys & _DEBUFF_UNSUPPORTED_KEYS:
            continue
        pool.append(b)
    return rng.sample(pool, k=3) if pool else []


def _apply_debuff_to_combat(pc: PlayerCombat, deb: dict) -> None:
    """属性类 debuff：直接改 PlayerCombat 进攻/生存字段（与客户端 modify_stats 一致）。"""
    d = deb.get("debuff", {})
    o = pc.offense
    if "crit_dmg_mult_delta" in d:
        o.crit_dmg = max(1.0, o.crit_dmg + float(d["crit_dmg_mult_delta"]))
    if "crit_rate_delta" in d:
        o.crit_rate = max(0.0, o.crit_rate + float(d["crit_rate_delta"]))
    if "armor_pen_mult_delta" in d:
        o.armor_pen = max(0.0, o.armor_pen + float(d["armor_pen_mult_delta"]))
    if "projectile_delta" in d:
        o.projectile_count = max(1, o.projectile_count + int(d["projectile_delta"]))
    if "healing_mult" in d:
        pc.survival.lifesteal_pct *= float(d["healing_mult"])
        pc.survival.regen_per_5s *= float(d["healing_mult"])


# ── 大招建模（GDD §11，与客户端一致）──
# 定稿（2026-10 数值轮）：×8 继承乘区 + 每怪伤害上限（单怪血×20%）+ 满槽 30→80s。
# 效果：前期全额爽（×8 < 20% 单怪血），中后期恒定"每发清 20% 波血"（GDD 贡献 15-25% 达标）。
# 全模拟胜率（含 debuff）：51-57%，均值 ~54%。
ULT_DMG_MULT: float = 8.0
ULT_HIT_RATIO: float = 1.0   # 命中率抽象（扫参用），定稿 100%
ULT_PER_ENEMY_CAP: float = 0.22


def _ult_full_time(wave: int) -> float:
    """大招满槽时间：30s → 80s 随波次（与客户端 _ult_full_time 一致；后期约 1.1-1.5 波一发）。"""
    return 30.0 + 50.0 * min(1.0, max(0.0, wave / 30.0))


def _battle_outcome(pc: PlayerCombat, wave: int, p, core_hp_current: float,
                    deb: dict | None = None, use_ult: bool = False,
                    ult_carry: float = 0.0, main_path: str = "") -> dict:
    """单波战斗判定。返回 {cleared, core_damage, dps, clear_time, ult_carry}。

    deb: 本波 Boss Debuff 定义（None=无）；use_ult: 是否计入大招贡献。
    ult_carry: 跨波累积的大招能量（秒），与客户端一致不清零。
    """
    total_hp = curves.wave_total_hp(wave, p) * ENEMY_HP_SCALE
    duration = curves.wave_duration(wave, p)
    # 敌人行为多样化宏观近似（wave 5+）：分裂+奶妈 → 有效波血抬升；远程 → 核心压力上浮
    pressure_mult = ENEMY_BEHAVIOR_PRESSURE if wave >= ENEMY_BEHAVIOR_FROM_WAVE else 1.0
    if wave >= ENEMY_BEHAVIOR_FROM_WAVE:
        total_hp *= ENEMY_BEHAVIOR_HP_MULT
    enemy = EnemyStats(armor=_enemy_armor(wave))
    ult_carry_out: float = ult_carry

    dps = expected_dps(pc.offense, enemy)
    # 宠魅召唤单位宏观近似（常量注释见上）
    if main_path == "chongmei":
        dps *= CHONGMEI_SUMMON_DPS_MULT
    if dps <= 0:
        return {"cleared": False, "core_damage": core_hp_current,
                "dps": 0.0, "clear_time": duration}

    # Boss Debuff：敌人类效果（改 total_hp / 有效时长 / dps 乘区 / 额外核心伤）
    reflect_pct = 0.0
    extra_core_pct_per_hit = 0.0
    if deb is not None:
        d = deb.get("debuff", {})
        if d.get("boss_hp_mult"):
            total_hp *= float(d["boss_hp_mult"])
        if d.get("boss_regen_pct_per_5s"):
            total_hp *= 1.0 + float(d["boss_regen_pct_per_5s"]) * duration / 5.0
        if d.get("enemy_speed_mult", 1.0) > 1.0:
            # 怪加速 = 输出窗口缩短
            duration /= float(d["enemy_speed_mult"])
        if d.get("bond_effect_mult_delta"):
            # 客户端语义：塞进 final 乘区 → 全伤害 ×(1+delta)
            dps *= (1.0 + float(d["bond_effect_mult_delta"]))
        # 三伤害类型双抗：法术抗性削法术弹道，物理抗性削物理弹道（真伤不受影响）
        if pc.offense.damage_type == "magic" and "magic_dmg_taken_mult" in d:
            pc.offense.type_resist_mult = float(d["magic_dmg_taken_mult"])
            dps *= pc.offense.type_resist_mult
        elif pc.offense.damage_type == "physical" and "physical_dmg_taken_mult" in d:
            pc.offense.type_resist_mult = float(d["physical_dmg_taken_mult"])
            dps *= pc.offense.type_resist_mult
        reflect_pct = float(d.get("reflect_pct", 0.0))
        extra_core_pct_per_hit = float(d.get("core_hp_loss_per_hit", 0.0))

    # 大招：清屏 AOE（×8 单发期望 × 敌数 × 次数），先扣 total_hp
    if use_ult:
        casts = int((ult_carry + duration) / _ult_full_time(wave))
        ult_carry_out = fmod(ult_carry + duration, _ult_full_time(wave))
        if casts > 0:
            hit = expected_hit_dmg(pc.offense, enemy)
            n = curves.enemy_count(wave, p)
            # 每怪上限：min(×8 期望, 单怪血×cap) —— 前期全额爽，后期恒定百分比清屏
            per_enemy = min(hit * ULT_DMG_MULT,
                            curves.enemy_hp(wave, p) * ULT_PER_ENEMY_CAP)
            total_hp = max(0.0, total_hp - per_enemy * casts * n * ULT_HIT_RATIO)
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

    # Boss Debuff：镜面反弹（已造成伤害的 reflect 比例，无视减伤/吸血抵消）
    if reflect_pct > 0.0:
        pass   # 计入下方 raw（对清完/未清完都生效）

    if cleared:
        # 清完：核心持续受压（贴线设计），但清完波不致死（最多压到 25%）。
        margin = 1.0 - (clear_time / duration)
        base_pct = (0.12 - 0.06 * margin) * pressure_mult   # 6%..12%（远程怪弹雨上浮）
        raw = base_pct * max_hp * (1.0 - pc.survival.damage_reduction)
        heal = dps * min(clear_time, duration) * pc.survival.lifesteal_pct
        heal += max_hp * pc.survival.regen_per_5s * (min(clear_time, duration) / 5.0)
        raw_after_heal = max(0.0, raw - heal)
        # 保护：清完波不会把核心打到 25% 以下（留余地，让未清完波来终结）
        floor_hp = 0.25 * max_hp
        if core_hp_current - raw_after_heal < floor_hp:
            raw_after_heal = max(0.0, core_hp_current - floor_hp)
        core_damage = raw_after_heal
        # 镜面反弹：对英雄的反弹伤害（无视减伤；清完波也有）
        if reflect_pct > 0.0:
            core_damage = min(core_damage + dps * min(clear_time, duration) * reflect_pct,
                              MAX_CORE_DAMAGE_PER_WAVE * max_hp)
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

    return {"cleared": cleared, "core_damage": core_damage, "dps": dps,
            "clear_time": clear_time, "ult_carry": ult_carry_out}


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

    # Boss Debuff：每局抽 3 个绑波次（10/20/30），与客户端一致
    boss_waves = [10, 20, 30]
    debuffs = _pick_boss_debuffs(pools.rng) if run_sim_flags.ENABLE_DEBUFF else []

    dps_per_wave: list[float] = []
    death_wave = n_waves + 1           # 默认通关
    synergies_final: list[str] = []
    death_max_hp = CORE_BASE_HP        # 死亡波的有效 max_hp（用于 death_hp_pct 归一化）
    ult_carry: float = 0.0             # 大招能量跨波累积（秒，与客户端一致）

    for wave in range(1, n_waves + 1):
        # 本波 Boss Debuff（若有）
        deb = None
        if debuffs and wave in boss_waves:
            deb = debuffs[boss_waves.index(wave)]

        # 1) 战斗获金（贪婪之噬：Boss 波内金币减半）
        income = wave_income(wave, econ)
        income_total = income["total"]
        if deb is not None and "gold_gain_mult_delta" in (deb.get("debuff") or {}):
            income_total *= (1.0 + float(deb["debuff"]["gold_gain_mult_delta"]))
        state.add_gold(income_total * PLAYER_ECON_MULT)
        # 2) 大厅花金
        state.begin_wave()
        strat.spend_lobby(state, pools, econ)

        # 3) 解算 PlayerCombat（羁绊 + 境界 reward + 联动）
        pc = resolve_player(state, pools)
        synergies_final = apply_synergies(pc, state, pools, engine)
        # 三伤害类型：主体系决定弹道类型（物伤卡只乘物理，法伤卡只乘法术）
        pc.offense.damage_type = _PATH_DAMAGE_TYPE.get(getattr(state, "_main_path", ""), "physical")
        # 属性类 Boss Debuff（暴伤/暴率/穿甲/弹数/禁疗）——与客户端 modify_stats 一致
        if deb is not None:
            _apply_debuff_to_combat(pc, deb)

        # 4) 战斗判定（传当前核心血量，用于 near-miss 残血计算）
        death_max_hp = pc.survival.effective_max_hp   # 记录本波 max_hp（死亡时用）
        outcome = _battle_outcome(pc, wave, wave_params, core_hp_current=state.survival_hp,
                                  deb=deb, use_ult=run_sim_flags.ENABLE_ULT,
                                  ult_carry=ult_carry, main_path=getattr(state, "_main_path", ""))
        ult_carry = float(outcome["ult_carry"])
        dps_per_wave.append(round(outcome["dps"], 1))
        # 反噬之力：受击额外掉核心血（怪接触频率≈1/s，上限 10 次）
        if deb is not None:
            per_hit = float((deb.get("debuff") or {}).get("core_hp_loss_per_hit", 0.0))
            if per_hit > 0.0:
                hits = min(10.0, outcome["clear_time"])
                state.survival_hp -= pc.survival.effective_max_hp * per_hit * hits
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
