"""测试结果报告 — 跑 pytest 并写 reports/out/tests.json。

供 build_site 渲染"验证结论"卡。CI 也用同一份 JSON。
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parent / "out"
BALANCE_DIR = Path(__file__).resolve().parent.parent


def run_tests() -> dict:
    """跑 pytest，解析结果，返回结构化 dict。"""
    proc = subprocess.run(
        [sys.executable, "-m", "pytest", "-q", "--tb=short"],
        cwd=BALANCE_DIR,
        capture_output=True,
        text=True,
    )
    out = proc.stdout + proc.stderr
    passed = failed = errors = 0
    # 优先匹配摘要行 "21 passed" / "3 failed"
    m = re.search(r"(\d+)\s+passed", out)
    if m:
        passed = int(m.group(1))
    m = re.search(r"(\d+)\s+failed", out)
    if m:
        failed = int(m.group(1))
    m = re.search(r"(\d+)\s+error", out)
    if m:
        errors = int(m.group(1))
    # 若摘要未匹配（被捕获时可能只有点），从进度行统计：'.' = passed
    if passed == 0 and failed == 0 and errors == 0:
        # 合并所有行里的 '.'（pytest 进度点）
        dots = sum(line.count(".") for line in out.splitlines())
        passed = dots

    return {
        "passed": passed,
        "failed": failed,
        "errors": errors,
        "total": passed + failed + errors,
        "returncode": proc.returncode,
        "all_passed": proc.returncode == 0,
        "output_tail": "\n".join(out.splitlines()[-15:]),
    }


def write_json(data: dict | None = None) -> Path:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / "tests.json"
    if data is None:
        data = run_tests()
    with path.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    return path


def main() -> dict:
    data = run_tests()
    path = write_json(data)
    status = "✅ 全部通过" if data["all_passed"] else f"❌ {data['failed']} 失败"
    print(f"\n═══ 测试结果 ═══\n  {status}  ({data['passed']}/{data['total']})\n  JSON: {path}\n")
    return data
