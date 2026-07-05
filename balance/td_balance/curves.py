"""敌人曲线 (GDD §3.3) — 波次血量/数量/时长/所需 DPS。

公式：
    enemy_hp    = base × growth^(wave-1)
    enemy_count = round(base + per_wave × wave)
    wave_total_hp = enemy_hp × enemy_count   (Boss 波已含 Boss 本体，见 boss_share)
    wave_duration = base_sec + per_wave_sec × wave
    required_dps  = wave_total_hp / wave_duration

Boss 波定义（A3 已澄清）：Boss 波总血量已包含 Boss 本体；
boss_share 是 Boss 在总血量中的占比（仅影响 UI 血条分配，不影响所需 DPS 计算）。

纯逻辑、无副作用。所有参数从 data/waves.yaml 读取（loader 注入）。
"""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class WaveParams:
    """波次曲线参数（来自 data/waves.yaml）。"""
    hp_base: float = 100.0
    hp_growth: float = 1.05        # 与 data/waves.yaml / client/data/waves.json 对齐（B-3 校准值）
    count_base: int = 8
    count_per_wave: float = 1.5
    duration_base: int = 25
    duration_per_wave: int = 1
    boss_every_n: int = 10
    boss_share: float = 0.4          # Boss 占总血量比例（UI 用，不影响 required_dps）
    elite_every_n: int = 5
    main_quest_waves: int = 30


# ── 单项曲线 ──

def enemy_hp(wave: int, p: WaveParams = WaveParams()) -> float:
    """单怪血量 = base × growth^(wave-1)。"""
    if wave < 1:
        raise ValueError("wave 必须 ≥ 1")
    return p.hp_base * (p.hp_growth ** (wave - 1))


def enemy_count(wave: int, p: WaveParams = WaveParams()) -> int:
    """怪物数量 = round(base + per_wave × wave)。"""
    if wave < 1:
        raise ValueError("wave 必须 ≥ 1")
    return round(p.count_base + p.count_per_wave * wave)


def wave_total_hp(wave: int, p: WaveParams = WaveParams()) -> float:
    """该波总血量 = 单怪血量 × 怪物数（Boss 波已含 Boss 本体）。"""
    return enemy_hp(wave, p) * enemy_count(wave, p)


def wave_duration(wave: int, p: WaveParams = WaveParams()) -> float:
    """该波时长（秒）= base + per_wave × wave。"""
    return p.duration_base + p.duration_per_wave * wave


def required_dps(wave: int, p: WaveParams = WaveParams()) -> float:
    """该波所需 DPS = 总血量 / 时长。"""
    return wave_total_hp(wave, p) / wave_duration(wave, p)


def is_boss_wave(wave: int, p: WaveParams = WaveParams()) -> bool:
    return wave % p.boss_every_n == 0


def is_elite_wave(wave: int, p: WaveParams = WaveParams()) -> bool:
    """精英波（每 elite_every_n 波，但不算 Boss 波）。"""
    return (wave % p.elite_every_n == 0) and not is_boss_wave(wave, p)


def boss_hp(wave: int, p: WaveParams = WaveParams()) -> float:
    """Boss 波中 Boss 本体的血量（= 总血量 × share）。仅在 Boss 波有意义。"""
    if not is_boss_wave(wave, p):
        return 0.0
    return wave_total_hp(wave, p) * p.boss_share


def wave_row(wave: int, p: WaveParams = WaveParams()) -> dict[str, float | int | bool]:
    """一行波次数据（供报告表格）。"""
    return {
        "wave": wave,
        "enemy_hp": round(enemy_hp(wave, p), 1),
        "enemy_count": enemy_count(wave, p),
        "total_hp": round(wave_total_hp(wave, p)),
        "duration": wave_duration(wave, p),
        "required_dps": round(required_dps(wave, p)),
        "boss": is_boss_wave(wave, p),
        "elite": is_elite_wave(wave, p),
    }


def curve_table(waves: range | list[int], p: WaveParams = WaveParams()) -> list[dict]:
    """整张曲线表（供 reports 输出 + 对照 GDD §3.3）。"""
    return [wave_row(w, p) for w in waves]
