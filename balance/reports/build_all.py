"""一键生成全部 JSON 报告 + 静态站点（供 CI / 本地用）。

等价于：
  curves + walkthrough + tests + economy + run 蒙特卡洛 + build_site

CI 用这个单入口，避免 workflow 里写多行内联 Python（YAML 易错）。
本地也可直接：uv run python reports/build_all.py
"""
from __future__ import annotations

# 兼容 uv run python reports/build_all.py（直接运行）与 -m（模块运行）
if __package__ in (None, ""):
    from pathlib import Path
    import sys
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from reports import (build_site, build_walkthrough, curves_report,
                         economy_report, run_report, test_report)
    from export_json import export_all as export_game_data
else:
    from . import (build_site, build_walkthrough, curves_report,
                   economy_report, run_report, test_report)
    import sys as _sys, pathlib as _pl
    _sys.path.insert(0, str(_pl.Path(__file__).resolve().parent.parent))
    from export_json import export_all as export_game_data


def build_all() -> None:
    print("═══ 0/7 导出游戏数据 JSON（供 Godot）═══")
    exported = export_game_data()
    print(f"  导出 {len(exported)} 个 JSON 到 client/data/")
    print("\n═══ 1/7 生成波次曲线 JSON ═══")
    curves_report.main()
    print("\n═══ 2/6 生成第 15 波走查 JSON ═══")
    build_walkthrough.main()
    print("\n═══ 3/6 生成测试结果 JSON ═══")
    test_report.main()
    print("\n═══ 4/6 生成经济模拟 JSON ═══")
    economy_report.main()
    print("\n═══ 5/6 生成 Run 蒙特卡洛 JSON ═══")
    run_report.main()
    print("\n═══ 6/6 生成静态站点 ═══")
    site = build_site.build_site()
    print(f"\n✅ 全部完成。站点：{site}/index.html")


if __name__ == "__main__":
    build_all()
