"""波次曲线报告 — 输出 30 波表格 + CSV + JSON，对照 GDD §3.3。

设计：数据与展示分离。
  - get_curve_data()    返回 rows（list[dict]，供 build_site / 测试）
  - print_curve_table() 人类可读打印
  - write_csv() / write_json()  落盘结构化文件（供 CI/站点）
"""
from __future__ import annotations

import json
from pathlib import Path

from td_balance import curves
from td_balance.loader import load_wave_params

OUT_DIR = Path(__file__).resolve().parent / "out"


def get_curve_data(waves: list[int] | None = None) -> list[dict]:
    """返回波次曲线行（list[dict]）。供 build_site / 测试消费。"""
    p = load_wave_params()
    if waves is None:
        waves = list(range(1, p.main_quest_waves + 1))
    return curves.curve_table(waves, p)


def print_curve_table(rows: list[dict] | None = None) -> list[dict]:
    """人类可读打印。返回 rows。"""
    if rows is None:
        rows = get_curve_data()

    headers = ["wave", "enemy_hp", "enemy_count", "total_hp", "duration", "required_dps", "type"]
    widths = [6, 12, 12, 12, 9, 12, 8]
    sep = " | "
    header_line = sep.join(h.ljust(w) for h, w in zip(headers, widths))
    print(header_line)
    print("-" * len(header_line))
    for r in rows:
        tag = "Boss" if r["boss"] else ("Elite" if r["elite"] else "")
        vals = [
            str(r["wave"]).rjust(widths[0]),
            f"{r['enemy_hp']:,.1f}".rjust(widths[1]),
            str(r["enemy_count"]).rjust(widths[2]),
            f"{r['total_hp']:,.0f}".rjust(widths[3]),
            f"{r['duration']:.0f}s".rjust(widths[4]),
            f"{r['required_dps']:,.0f}".rjust(widths[5]),
            tag.ljust(widths[6]),
        ]
        print(sep.join(vals))
    return rows


def write_csv(rows: list[dict] | None = None) -> Path:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / "curves.csv"
    if rows is None:
        rows = get_curve_data()
    headers = ["wave", "enemy_hp", "enemy_count", "total_hp", "duration", "required_dps", "boss", "elite"]
    with path.open("w", encoding="utf-8") as f:
        f.write(",".join(headers) + "\n")
        for r in rows:
            f.write(",".join(str(r[h]) for h in headers) + "\n")
    return path


def write_json(rows: list[dict] | None = None) -> Path:
    """写 reports/out/curves.json（供 CI/站点消费）。"""
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / "curves.json"
    if rows is None:
        rows = get_curve_data()
    with path.open("w", encoding="utf-8") as f:
        json.dump(rows, f, ensure_ascii=False, indent=2)
    return path


def main() -> None:
    print("\n═══ 波次曲线（对照 GDD §3.3）═══\n")
    rows = get_curve_data()
    print_curve_table(rows)
    csv = write_csv(rows)
    js = write_json(rows)
    print(f"\nCSV 已导出：{csv}")
    print(f"JSON 已导出：{js}")
