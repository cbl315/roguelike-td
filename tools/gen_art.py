#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "pyyaml>=6.0",
#     "zhipuai>=2.1",
#     "sniffio",      # zhipuai 实际依赖但未在 its metadata 中声明
# ]
# ///
"""AI 批量生图脚本 —— 读 art_prompts.yaml，调 CogView-3-Flash 生成图片并入库。

管线设计（见 docs/ART_PIPELINE.md）：
  - CogView-3-Flash（免费）出草图与批量素材（图标 / 特效 / debuff）
  - Seedream 4.5 / GLM-Image（付费）精修一致性敏感素材（羁绊卡面 / 英雄 / Boss）
  - 本脚本只负责调用 CogView；精修环节可在后续按需接入

用法（用 uv run 直接运行脚本，自动装依赖；勿加 python）：
  uv run tools/gen_art.py dry-run                  # 不调 API，只打印计划
  uv run tools/gen_art.py gen --category bonds     # 只生成羁绊卡面
  uv run tools/gen_art.py gen --id bond_zhutian_01 # 只生成指定条目
  uv run tools/gen_art.py gen                      # 生成全部
  uv run tools/gen_art.py sync --id bond_zhutian_01 --ref exported.png
                                                    # 用现成图替换某条目

环境变量：
  ZHIPU_API_KEY  智谱开放平台 API Key（open.bigmodel.cn 控制台获取）

依赖（PEP 723 内联声明于文件头，uv run 自动安装）：pyyaml>=6.0  zhipuai>=2.1
"""
from __future__ import annotations

import argparse
import os
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError as e:
    sys.exit(
        f"导入 pyyaml 失败：{e}\n"
        "请用 uv run tools/gen_art.py ...（直接运行脚本，自动装依赖）。"
    )

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent
PROMPTS_YAML = HERE / "art_prompts.yaml"
ASSETS_DIR = REPO_ROOT / "client" / "src" / "assets"


# ── 配置 ──────────────────────────────────────────────────────────────
MODEL = "cogview-3-flash"   # 免费模型；精修可改 cogview-3-plus
DEFAULT_SIZE = "1024x1024"
RATE_LIMIT_SEC = 1.0        # 每次调用间隔（秒），防触发免费层限流
MAX_RETRIES = 3
RETRY_BACKOFF = 4.0         # 重试退避基数（秒），指数增长


@dataclass
class ArtEntry:
    """一条素材生成任务。"""
    id: str                 # 全局唯一，如 bond_zhutian_01
    category: str           # bonds / skills / debuffs / characters / enemies / effects / ui / bg
    filename: str           # 入库文件名，如 bond_zhutian_01.png
    prompt: str             # 完整生图 prompt
    size: str = DEFAULT_SIZE


def load_entries(path: Path = PROMPTS_YAML) -> list[ArtEntry]:
    """读 YAML，展平成 ArtEntry 列表。"""
    with path.open(encoding="utf-8") as f:
        cfg = yaml.safe_load(f)

    style = cfg.get("style_prefix", "").strip()
    entries: list[ArtEntry] = []
    seen_ids: set[str] = set()

    for cat in cfg.get("categories", []):
        cat_id = cat["id"]
        cat_style = cat.get("style_suffix", "").strip()
        for item in cat.get("items", []):
            eid = item["id"]
            if eid in seen_ids:
                raise ValueError(f"重复的条目 id: {eid}")
            seen_ids.add(eid)

            prompt = f"{style} {item['prompt']} {cat_style}".strip()
            entries.append(ArtEntry(
                id=eid,
                category=cat_id,
                filename=item.get("filename", f"{eid}.png"),
                prompt=prompt,
                size=item.get("size", cat.get("size", DEFAULT_SIZE)),
            ))
    return entries


def out_path(entry: ArtEntry) -> Path:
    """条目的最终入库路径。"""
    return ASSETS_DIR / entry.category / entry.filename


# ── 过滤 ──────────────────────────────────────────────────────────────
def filter_entries(
    entries: list[ArtEntry],
    category: str | None = None,
    only_id: str | None = None,
    skip_existing: bool = True,
) -> list[ArtEntry]:
    result = list(entries)
    if category:
        result = [e for e in result if e.category == category]
    if only_id:
        result = [e for e in result if e.id == only_id]
        if not result:
            sys.exit(f"找不到 id={only_id} 的条目")
    if skip_existing:
        result = [e for e in result if not out_path(e).exists()]
    return result


# ── CogView 调用 ──────────────────────────────────────────────────────
def call_cogview(prompt: str, size: str, api_key: str) -> str:
    """调用智谱 CogView，返回图片 URL。带指数退避重试。"""
    try:
        from zhipuai import ZhipuAI
    except ImportError as e:
        sys.exit(
            f"导入 zhipuai 失败：{e}\n"
            "可能原因：zhipuai 漏声明了 sniffio 等依赖。\n"
            "修复：uv run --with zhipuai --with sniffio tools/gen_art.py gen ..."
        )

    client = ZhipuAI(api_key=api_key)

    last_err: Exception | None = None
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            resp = client.images.generations(model=MODEL, prompt=prompt, size=size)
            url = resp.data[0].url
            if not url:
                raise RuntimeError("API 返回空 URL")
            return url
        except Exception as e:  # noqa: BLE001
            last_err = e
            if attempt < MAX_RETRIES:
                wait = RETRY_BACKOFF * (2 ** (attempt - 1))
                print(f"    ⚠ 第 {attempt} 次失败：{e}，{wait:.0f}s 后重试…")
                time.sleep(wait)
    raise RuntimeError(f"重试 {MAX_RETRIES} 次仍失败：{last_err}")


def download(url: str, dest: Path) -> None:
    """下载图片到本地。"""
    import urllib.request
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": "roguelike-td/gen_art"})
    with urllib.request.urlopen(req, timeout=60) as r, dest.open("wb") as f:  # noqa: S310
        f.write(r.read())


# ── 命令 ──────────────────────────────────────────────────────────────
def cmd_dry_run(args: argparse.Namespace) -> None:
    entries = load_entries()
    if args.category or args.id:
        entries = filter_entries(entries, args.category, args.id, skip_existing=False)

    print(f"\n═══ 生图计划（dry-run，不调 API）═══")
    print(f"  模型: {MODEL}")
    print(f"  入库: {ASSETS_DIR}")
    print(f"  条目: {len(entries)} 个\n")

    by_cat: dict[str, list[ArtEntry]] = {}
    for e in entries:
        by_cat.setdefault(e.category, []).append(e)
    for cat in sorted(by_cat):
        print(f"  [{cat}] {len(by_cat[cat])} 个")
        for e in by_cat[cat]:
            mark = "✓" if out_path(e).exists() else " "
            print(f"    {mark} {e.id:28} → {e.category}/{e.filename}  ({e.size})")
    print()


def cmd_gen(args: argparse.Namespace) -> None:
    api_key = os.environ.get("ZHIPU_API_KEY")
    if not api_key:
        sys.exit("请先设置环境变量 ZHIPU_API_KEY（open.bigmodel.cn 控制台获取）")

    entries = load_entries()
    todo = filter_entries(entries, args.category, args.id, skip_existing=not args.force)
    if not todo:
        print("没有待生成的条目（全部已存在；用 --force 强制重新生成）。")
        return

    print(f"\n═══ 开始生成 ═══")
    print(f"  模型: {MODEL} | 待生成: {len(todo)} | 间隔: {RATE_LIMIT_SEC}s\n")

    ok = 0
    for i, e in enumerate(todo, 1):
        prefix = f"[{i}/{len(todo)}] {e.id}"
        print(f"  {prefix}")
        print(f"    → {e.category}/{e.filename}  ({e.size})")
        try:
            url = call_cogview(e.prompt, e.size, api_key)
            dest = out_path(e)
            download(url, dest)
            print(f"    ✓ 已保存 {dest.relative_to(REPO_ROOT)}")
            ok += 1
        except Exception as e2:  # noqa: BLE001
            print(f"    ✗ 失败：{e2}")
        if i < len(todo):
            time.sleep(RATE_LIMIT_SEC)

    print(f"\n  完成：{ok}/{len(todo)} 成功。")


def cmd_sync(args: argparse.Namespace) -> None:
    """用一张现成图（如 Seedream 精修后的）替换某条目的入库图。"""
    entries = load_entries()
    match = [e for e in entries if e.id == args.id]
    if not match:
        sys.exit(f"找不到 id={args.id} 的条目")
    entry = match[0]

    src = Path(args.ref).expanduser().resolve()
    if not src.exists():
        sys.exit(f"源文件不存在：{src}")
    dest = out_path(entry)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(src.read_bytes())
    print(f"  ✓ 已同步 {src.name} → {dest.relative_to(REPO_ROOT)}")


# ── CLI ───────────────────────────────────────────────────────────────
def main() -> None:
    parser = argparse.ArgumentParser(
        description="AI 批量生图（CogView-3-Flash）。见 docs/ART_PIPELINE.md。",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p_dry = sub.add_parser("dry-run", help="不调 API，只打印生成计划")
    p_dry.add_argument("--category", help="只看某分类")
    p_dry.add_argument("--id", help="只看某条目")
    p_dry.set_defaults(func=cmd_dry_run)

    p_gen = sub.add_parser("gen", help="调用 CogView 生成图片")
    p_gen.add_argument("--category", help="只生成某分类（bonds/skills/debuffs/…）")
    p_gen.add_argument("--id", help="只生成某条目")
    p_gen.add_argument("--force", action="store_true", help="强制重新生成（覆盖已有）")
    p_gen.set_defaults(func=cmd_gen)

    p_sync = sub.add_parser("sync", help="用现成图替换某条目（如精修后的图）")
    p_sync.add_argument("--id", required=True, help="条目 id")
    p_sync.add_argument("--ref", required=True, help="源图路径")
    p_sync.set_defaults(func=cmd_sync)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
