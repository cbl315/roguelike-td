"""完整 Run 模拟单测。"""
from __future__ import annotations

from td_balance.run_sim import RunResult, simulate_run


def test_simulate_run_returns_result():
    r = simulate_run(seed=1)
    assert isinstance(r, RunResult)
    assert r.death_wave >= 1
    assert 0.0 <= r.death_hp_pct <= 1.0 or r.won
    assert len(r.dps_per_wave) >= 1
    assert r.maxed_paths >= 0


def test_run_reproducible():
    """同种子 → 同结果。"""
    r1 = simulate_run(seed=42)
    r2 = simulate_run(seed=42)
    assert r1.won == r2.won
    assert r1.death_wave == r2.death_wave
    assert r1.dps_per_wave == r2.dps_per_wave


def test_dps_positive_in_played_waves():
    """玩到的波次 DPS 必须 > 0（否则无法清波）。"""
    r = simulate_run(seed=1)
    for dps in r.dps_per_wave[:r.death_wave]:
        assert dps > 0


def test_runs_produce_distribution():
    """多局结果有分布（不全相同）。"""
    results = [simulate_run(seed=s) for s in range(15)]
    death_waves = {r.death_wave for r in results}
    # 至少有 2 种不同死亡波次（分布存在）
    assert len(death_waves) >= 2
