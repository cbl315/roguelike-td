#!/usr/bin/env python3
"""diag_paths.py — 分体系×玩家画像胜率诊断（数值调参主工具）。

画像分层（业界惯例）：
  greedy  贪心混修（原 SimpleStrategy：needed 优先→体系卡，装备照升）
  novice  新手乱选（随机挑卡、不升装备）——新手体验护栏
  mono    纯单修（只拿主体系卡）——混修设计的代价幅度

用法：
  python3 diag_paths.py                     # 贪心 × 4 体系（兼容原用法）
  python3 diag_paths.py --profiles greedy novice mono   # 画像矩阵
  python3 diag_paths.py -n 200 --profile novice
"""
import argparse
import statistics
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from td_balance import run_sim  # noqa: E402
from td_balance.strategy import SimpleStrategy, NoviceStrategy, MonoPathStrategy  # noqa: E402

PATHS = ["zhutian", "xingchenbian", "chongmei", "doupo"]
PROFILES = {"greedy": SimpleStrategy, "novice": NoviceStrategy, "mono": MonoPathStrategy}


def run_cell(path: str, strat_cls, n: int, seed_base: int = 7) -> str:
    strat = strat_cls(fixed_path=path)
    wins, deaths = 0, []
    for i in range(n):
        r = run_sim.simulate_run(seed=seed_base * 1000003 + i, strategy=strat)
        if r.won:
            wins += 1
        else:
            deaths.append(r.death_wave)
    wr = wins / n * 100.0
    med = statistics.median(deaths) if deaths else 0
    hot = ", ".join(f"w{k}:{v}" for k, v in sorted(Counter(deaths).items(), key=lambda x: -x[1])[:3])
    return f"{wr:5.1f}%|med{med:3.0f}|{hot}"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("-n", "--runs", type=int, default=400)
    ap.add_argument("--profiles", nargs="+", default=["greedy"], choices=list(PROFILES))
    args = ap.parse_args()
    multi = len(args.profiles) > 1
    if multi:
        print(f"| 体系 | " + " | ".join(f"{p}" for p in args.profiles) + " |")
        print("|---|" + "---|" * len(args.profiles))
    for p in PATHS:
        cells = [run_cell(p, PROFILES[prof], args.runs) for prof in args.profiles]
        if multi:
            print(f"| {p} | " + " | ".join(cells) + " |")
        else:
            print(f"{p:12s} {cells[0]}   (n={args.runs})")
    if not multi:
        print(f"画像={args.profiles[0]}（greedy=贪心混修 novice=新手 mono=单修；--profiles 全画像矩阵）")


if __name__ == "__main__":
    main()
