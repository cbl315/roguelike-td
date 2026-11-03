#!/usr/bin/env python3
"""scan_params.py — 参数网格扫描：调参从"试错"变"查表"。

对单参数（或两参数网格）扫描整体胜率，输出胜率曲面表。
参数注入运行时覆盖（不改 yaml），扫描完即恢复。

用法：
  python3 scan_params.py --param growth:1.070:1.082:7 -n 200
  python3 scan_params.py --param hp_growth --param count_per_wave   # 双参网格
  python3 scan_params.py --param breakthrough_req:0.4:0.8:5 --profile novice
"""
import argparse
import importlib
import sys
from dataclasses import replace
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from td_balance import run_sim  # noqa: E402
from td_balance.curves import WaveParams  # noqa: E402
from td_balance.loader import load_wave_params  # noqa: E402
from td_balance.strategy import SimpleStrategy, NoviceStrategy, MonoPathStrategy  # noqa: E402
import td_balance.strategy as strategy_mod  # noqa: E402
import td_balance.run_sim as run_sim_mod  # noqa: E402

PROFILES = {"greedy": SimpleStrategy, "novice": NoviceStrategy, "mono": MonoPathStrategy}

# 可扫参数注册表：名字 → (注入函数, 默认读取器)
WAVE_KEYS = {"growth": "hp_growth", "count_per_wave": "count_per_wave"}


def parse_spec(spec: str):
    """'growth:1.07:1.082:7' → (key, [values])；'growth' → (key, 默认5点自适应范围)"""
    parts = spec.split(":")
    key = parts[0]
    if len(parts) == 4:
        lo, hi, n = float(parts[1]), float(parts[2]), int(parts[3])
        step = (hi - lo) / (n - 1) if n > 1 else 0
        return key, [round(lo + step * i, 5) for i in range(n)]
    base = load_wave_params()
    d = {"growth": base.hp_growth, "count_per_wave": base.count_per_wave,
         "breakthrough_req": strategy_mod.BREAKTHROUGH_DPS_REQ}.get(key, 1.0)
    return key, [round(d * f, 5) for f in (0.96, 0.98, 1.0, 1.02, 1.04)]


def run_cell(values: dict, strat_cls, n: int, base_params: WaveParams) -> float:
    """按参数覆盖跑 n 局 → 胜率。"""
    wp = base_params
    if "growth" in values:
        wp = replace(wp, hp_growth=values["growth"])
    if "count_per_wave" in values:
        wp = replace(wp, count_per_wave=values["count_per_wave"])
    if "breakthrough_req" in values:
        old = strategy_mod.BREAKTHROUGH_DPS_REQ
        strategy_mod.BREAKTHROUGH_DPS_REQ = values["breakthrough_req"]
    wins = 0
    for i in range(n):
        strat = strat_cls()
        r = run_sim_mod.simulate_run(seed=7 * 1000003 + i, strategy=strat, wave_params=wp)
        if r.won:
            wins += 1
    if "breakthrough_req" in values:
        strategy_mod.BREAKTHROUGH_DPS_REQ = old
    return wins / n * 100.0


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--param", action="append", required=True,
                    help="growth|count_per_wave|breakthrough_req[:lo:hi:n]")
    ap.add_argument("-n", "--runs", type=int, default=200)
    ap.add_argument("--profile", default="greedy", choices=list(PROFILES))
    args = ap.parse_args()

    specs = dict(parse_spec(p) for p in args.param)
    base = load_wave_params()
    strat_cls = PROFILES[args.profile]
    keys = list(specs.keys())

    if len(keys) == 1:
        k = keys[0]
        print(f"扫描 {k}（{args.profile} 画像，n={args.runs}/点）")
        print(f"| {k} | 胜率 |")
        print("|---|---|")
        for v in specs[k]:
            wr = run_cell({k: v}, strat_cls, args.runs, base)
            print(f"| {v} | {wr:.1f}% |")
    else:
        k1, k2 = keys[0], keys[1]
        print(f"网格 {k1} × {k2}（{args.profile}，n={args.runs}/格）")
        head = "| " + k1 + "\\" + k2 + " | " + " | ".join(str(v) for v in specs[k2]) + " |"
        print(head)
        print("|---|" + "---|" * len(specs[k2]))
        for v1 in specs[k1]:
            row = [run_cell({k1: v1, k2: v2}, strat_cls, args.runs, base) for v2 in specs[k2]]
            print(f"| {v1} | " + " | ".join(f"{r:.0f}%" for r in row) + " |")


if __name__ == "__main__":
    main()
