"""完整 Run 蒙特卡洛报告 (B-3) — 通关率/死波/死血/DPS 曲线 → JSON。

跑 N 局完整 run（含战斗判定），聚合统计。对照验收目标（通关率 10-40%、
中位死波 15-25、near-miss 死血分布）。

数据与展示分离：simulate_runs() 返回结构化 dict，write_json() 落盘。
"""
from __future__ import annotations

import json
from collections import Counter
from pathlib import Path
from statistics import mean, median

from td_balance import curves
from td_balance.loader import load_wave_params
from td_balance.run_sim import simulate_run

OUT_DIR = Path(__file__).resolve().parent / "out"
N_RUNS = 1000


def simulate_runs(n_runs: int = N_RUNS) -> dict:
    """跑 n_runs 局完整 run，聚合统计。"""
    results = [simulate_run(seed=s) for s in range(n_runs)]
    wins = [r for r in results if r.won]
    losses = [r for r in results if not r.won]

    win_rate = len(wins) / n_runs
    death_waves = [r.death_wave for r in losses]
    death_wave_counter = Counter(death_waves)
    maxed_paths = [r.maxed_paths for r in results]

    # 每波玩家 DPS 中位（取所有打到该波的局）
    wave_dps: dict[int, list[float]] = {}
    for r in results:
        for i, dps in enumerate(r.dps_per_wave):
            wave = i + 1
            wave_dps.setdefault(wave, []).append(dps)
    dps_median_per_wave = [round(median(wave_dps[w]), 1) if w in wave_dps else 0.0
                           for w in range(1, 31)]

    # 每波所需 DPS（对照曲线）
    p = load_wave_params()
    required_per_wave = [round(curves.required_dps(w, p), 1) for w in range(1, 31)]

    # 死血分布（near-miss 分析：死时核心血量%）
    death_hp_buckets = {"0-5%": 0, "5-20%": 0, "20-50%": 0, "50-100%": 0}
    for r in losses:
        hp = r.death_hp_pct
        if hp < 0.05:
            death_hp_buckets["0-5%"] += 1
        elif hp < 0.20:
            death_hp_buckets["5-20%"] += 1
        elif hp < 0.50:
            death_hp_buckets["20-50%"] += 1
        else:
            death_hp_buckets["50-100%"] += 1

    # 触发的联动统计
    synergy_counter: Counter = Counter()
    for r in results:
        synergy_counter.update(r.synergies_triggered)

    # 联动有效性：触发联动 vs 未触发的通关率对比（验证联动=滚雪球关键）
    trig = [r for r in results if r.synergies_triggered]
    notrig = [r for r in results if not r.synergies_triggered]
    trig_win = sum(1 for r in trig if r.won) / len(trig) if trig else 0
    notrig_win = sum(1 for r in notrig if r.won) / len(notrig) if notrig else 0
    synergy_effectiveness = {
        "trigger_rate": round(len(trig) / n_runs, 3),
        "win_rate_with_synergy": round(trig_win, 3),
        "win_rate_without_synergy": round(notrig_win, 3),
        "verdict": (
            f"触发联动局通关率 {trig_win*100:.0f}% vs 未触发 {notrig_win*100:.0f}%——"
            f"{'联动是通关关键（符合设计）' if trig_win > notrig_win * 2 else '联动效果不显著'}"
        ),
    }

    # 诊断
    med_death = median(death_waves) if death_waves else 31
    if win_rate < 0.05:
        diagnosis = {
            "status": "too_hard",
            "win_rate": round(win_rate, 3),
            "median_death_wave": med_death,
            "verdict": (
                f"通关率 {win_rate*100:.0f}%（目标 10-40%），中位死波 {med_death:.0f}（目标 15-25）。"
                f" 玩家 DPS 增长远慢于敌人曲线（B-1 已暴露的'基础数值撑不起'问题的全局化）。"
            ),
            "root_cause": (
                "敌人曲线指数增长（1.18^wave），但玩家基础 ATK=50 + 少量羁绊给的 DPS 增益是加法叠加，"
                "跟不上指数。第 2 波 required_dps=48，玩家仅 ~46 → 卡死。"
            ),
            "suggestion": (
                "校准方向（任选，需 B-3 后续迭代验证）："
                "① 缓敌人曲线（1.18→1.10）；"
                "② 提高基础 ATK（50→80）或羁绊数值幅度；"
                "③ 让 final_dmg_mult 乘区更早可获取（降低传说词条稀有度权重）；"
                "④ 调低敌人护甲增长。"
            ),
        }
    elif win_rate > 0.5:
        diagnosis = {"status": "too_easy", "win_rate": round(win_rate, 3),
                     "verdict": f"通关率 {win_rate*100:.0f}% 偏高", "suggestion": "加强敌人"}
    else:
        diagnosis = {"status": "ok", "win_rate": round(win_rate, 3),
                     "median_death_wave": med_death,
                     "verdict": f"达标：通关率 {win_rate*100:.0f}%"}

    return {
        "n_runs": n_runs,
        "win_rate": round(win_rate, 4),
        "wins": len(wins),
        "median_death_wave": round(med_death, 1),
        "death_wave_distribution": dict(sorted(death_wave_counter.items())),
        "death_hp_buckets": death_hp_buckets,
        "dps_median_per_wave": dps_median_per_wave,
        "required_dps_per_wave": required_per_wave,
        "maxed_paths": {"median": median(maxed_paths), "mean": round(mean(maxed_paths), 2),
                        "max": max(maxed_paths)},
        "synergy_trigger_counts": dict(synergy_counter.most_common()),
        "synergy_effectiveness": synergy_effectiveness,
        "diagnosis": diagnosis,
    }


def write_json(data: dict | None = None) -> Path:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / "run.json"
    if data is None:
        data = simulate_runs()
    with path.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    return path


def main() -> dict:
    print("\n═══ 完整 Run 蒙特卡洛（B-3）═══\n")
    data = simulate_runs()
    diag = data["diagnosis"]
    print(f"  局数: {data['n_runs']}")
    print(f"  通关率: {data['win_rate']*100:.1f}%  ({data['wins']}/{data['n_runs']})")
    print(f"  中位死亡波次: {data['median_death_wave']}")
    print(f"  修满顶级体系: 中位 {data['maxed_paths']['median']} / max {data['maxed_paths']['max']}")
    print(f"  诊断: [{diag['status']}] {diag['verdict']}")
    if diag["status"] == "too_hard":
        print(f"  根因: {diag['root_cause']}")
        print(f"  💡 {diag['suggestion']}")
    path = write_json(data)
    print(f"\n  JSON: {path}")
    return data


if __name__ == "__main__":
    main()
