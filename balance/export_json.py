"""把 balance/data/*.yaml 导出为 JSON，供 Godot 客户端读取（零依赖接入）。

Python (YAML) 是 SSOT；Godot 只读 JSON（内置 JSON.parse，无第三方依赖）。
导出目标：client/data/*.json（每个 yaml 一个同名 json）。

用法：uv run python export_json.py
也可在 build_all.py 里调用，让 CI 一并导出。
"""
from __future__ import annotations

import json
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent
DATA_DIR = HERE / "data"
# client/ 与 balance/ 同级
CLIENT_DATA_DIR = HERE.parent / "client" / "data"


def export_all() -> list[Path]:
    """导出 data/*.yaml → client/data/*.json。返回导出的文件路径列表。"""
    CLIENT_DATA_DIR.mkdir(parents=True, exist_ok=True)
    exported: list[Path] = []
    for yaml_path in sorted(DATA_DIR.glob("*.yaml")):
        with yaml_path.open(encoding="utf-8") as f:
            data = yaml.safe_load(f)
        json_path = CLIENT_DATA_DIR / (yaml_path.stem + ".json")
        with json_path.open("w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        exported.append(json_path)
    return exported


def main() -> None:
    exported = export_all()
    print(f"\n═══ 导出 YAML→JSON（供 Godot 读）═══")
    print(f"  源:   {DATA_DIR}")
    print(f"  目标: {CLIENT_DATA_DIR}")
    for p in exported:
        print(f"  ✓ {p.name}")
    print(f"  共 {len(exported)} 个文件")


if __name__ == "__main__":
    main()
