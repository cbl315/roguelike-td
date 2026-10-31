#!/usr/bin/env python3
"""diag_paths.py — 分体系胜率诊断（数值调参专用）。

固定体系跑 N 局，输出各体系胜率 / 死亡分布 / 末期 DPS / 死亡热点，
快速定位"哪条体系在哪个波次失血"。

用法：
  python3 diag_paths.py            # 每体系 400 局
  python3 diag_paths.py -n 200     # 快速迭代用小样本
"""
import argparse
import statistics
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from td_balance import run_sim  # noqa: E402
from td_balance.strategy import SimpleStrategy  # noqa: E402

PATHS = ["zhutian", "xingchenbian", "chongmei", "doupo"]


def run_path(path: str, n: int, seed_base: int = 7) -> str:
    strat = SimpleStrategy(fixed_path=path)
    wins, deaths, dps_final = 0, [], []
    for i in range(n):
        r = run_sim.simulate_run(seed=seed_base * 1000003 + i, strategy=strat)
        if r.won:
            wins += 1
            dps_final.append(r.dps_per_wave[-1] if r.dps_per_wave else 0.0)
        else:
            deaths.append(r.death_wave)
    wr = wins / n * 100.0
    med = statistics.median(deaths) if deaths else 0
    mid = sum(1 for d in deaths if 5 <= d <= 15)
    hot = Counter(deaths)
    top = ", ".join(f"w{k}:{v}" for k, v in sorted(hot.items(), key=lambda x: -x[1])[:5])
    dps = f"{statistics.median(dps_final):,.0f}" if dps_final else "-"
    return (f"{path:12s} 胜率 {wr:5.1f}% | 死亡中位 {med:4.0f} | "
            f"w5-15死 {mid:3d}/{n - wins} | 末期DPS {dps} | 死亡热点 {top}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("-n", "--runs", type=int, default=400)
    args = ap.parse_args()
    print(f"每体系 {args.runs} 局（seed 基 7，debuff/ult on）")
    for p in PATHS:
        print(run_path(p, args.runs))


if __name__ == "__main__":
    main()
