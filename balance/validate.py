"""一键验证：跑全部单测 + 生成曲线/走查/测试结果（打印 + JSON）+ 可选建站。

用法：
  uv run python validate.py            # 验证 + 生成 JSON
  uv run python validate.py --site     # 同上 + 生成 site/（需要 matplotlib）

JSON 产物落 reports/out/，供 GitHub Pages 站点消费。
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def run_tests() -> int:
    """跑 pytest（直接，不走 test_report，保留彩色/进度输出给开发者看）。"""
    print("═══ 运行单测（pytest）═══\n")
    result = subprocess.run(
        [sys.executable, "-m", "pytest", "-q"],
        cwd=HERE,
    )
    return result.returncode


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--site", action="store_true", help="生成 site/ 静态站点")
    args = parser.parse_args()

    from reports import build_walkthrough, curves_report, test_report

    rc = run_tests()
    print()
    if rc != 0:
        print("⚠️  单测未全部通过——见上方输出。报告仍会生成供 review。\n")

    curves_report.main()
    build_walkthrough.main()
    test_report.main()

    if args.site:
        try:
            from reports import build_site
            build_site.build_site()
        except ImportError:
            print("⚠️  --site 需要 matplotlib：uv sync --extra reports")
            sys.exit(1)

    print("═══ 验证完成 ═══")
    print("  产物（reports/out/）：curves.json / curves.csv / walkthrough.json / tests.json")
    if args.site:
        print("  站点：site/index.html（浏览器打开预览）")


if __name__ == "__main__":
    main()
