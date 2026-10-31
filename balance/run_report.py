"""run_report.py — 蒙特卡洛批量模拟报告：胜率 / 死亡波次分布 / 关键分位。

用法：
  python balance/run_report.py                    # 默认 1000 局
  python balance/run_report.py -n 2000 --seed 7
  python balance/run_report.py --no-debuff --no-ult   # 消融对比
"""
from __future__ import annotations

import argparse
import statistics
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from td_balance import run_sim_flags, run_sim  # noqa: E402


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("-n", "--runs", type=int, default=1000)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--no-debuff", action="store_true", help="关闭 Boss Debuff 建模")
    ap.add_argument("--no-ult", action="store_true", help="关闭大招建模")
    args = ap.parse_args()

    run_sim_flags.ENABLE_DEBUFF = not args.no_debuff
    run_sim_flags.ENABLE_ULT = not args.no_ult

    wins = 0
    death_waves: list[int] = []
    win_dps_final: list[float] = []
    for i in range(args.runs):
        r = run_sim.simulate_run(seed=args.seed * 1000003 + i)
        if r.won:
            wins += 1
            win_dps_final.append(r.dps_per_wave[-1] if r.dps_per_wave else 0.0)
        else:
            death_waves.append(r.death_wave)

    n = args.runs
    wr = wins / n * 100.0
    dw = Counter(death_waves)
    print(f"局数 {n} | 种子基 {args.seed} | debuff={'on' if not args.no_debuff else 'off'} ult={'on' if not args.no_ult else 'off'}")
    print(f"胜率: {wr:.1f}%  ({wins}/{n})")
    if death_waves:
        print(f"死亡波次: 中位 {statistics.median(death_waves):.0f} | 均值 {statistics.mean(death_waves):.1f}")
        hot = ", ".join(f"w{k}:{v}" for k, v in sorted(dw.items())[-8:])
        print(f"死亡分布(后8): {hot}")
    if win_dps_final:
        print(f"通关局末期DPS: 中位 {statistics.median(win_dps_final):,.0f}")


if __name__ == "__main__":
    main()
