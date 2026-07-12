"""matplotlib 图表生成 — 读取 reports/out/*.json，输出 PNG 到 site/assets/。

无头环境友好：强制 Agg backend（CI 里跑）。
中文字体：显式查找跨平台常见 CJK 字体（macOS PingFang / Linux Noto CJK /
Windows 微软雅黑），避免 CI 无中文字体导致中文渲染成 tofu/等字。
所有函数：读 JSON → 画图 → 保存 PNG。不 print，不 return 数据。
"""
from __future__ import annotations

import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")           # 无头后端，CI 友好
import matplotlib.pyplot as plt
from matplotlib import font_manager
from matplotlib.ticker import FuncFormatter


# ── 中文字体解析（跨平台）──
# 按优先级尝试常见 CJK 字体名；命中第一个存在的就用。
# CI（Ubuntu）需配 apt 装 fonts-noto-cjk（见 .github/workflows/pages.yml）。
_CJK_CANDIDATES = [
    "PingFang SC",        # macOS
    "Heiti SC",           # macOS 备选
    "Noto Sans CJK SC",   # Linux (apt: fonts-noto-cjk)
    "Noto Sans CJK JP",   # Linux 备选
    "Source Han Sans SC", # 思源黑体
    "WenQuanYi Zen Hei",  # Linux 文泉驿
    "Microsoft YaHei",    # Windows
    "SimHei",             # Windows 备选
]


def _resolve_cjk_font() -> str | None:
    """返回第一个在系统里能找到的 CJK 字体名；找不到返回 None。"""
    available = {f.name for f in font_manager.fontManager.ttflist}
    for name in _CJK_CANDIDATES:
        if name in available:
            return name
    return None


_CJK_FONT = _resolve_cjk_font()

# 暗色主题（契合游戏调性，且在 GitHub 暗色模式下也好看）
plt.rcParams.update({
    "figure.facecolor": "#1a1b26",
    "axes.facecolor": "#1a1b26",
    "axes.edgecolor": "#565f89",
    "axes.labelcolor": "#c0caf5",
    "xtick.color": "#9aa5ce",
    "ytick.color": "#9aa5ce",
    "text.color": "#c0caf5",
    "axes.unicode_minus": False,   # 负号用 ASCII，避免无 minus glyph 报警
    "axes.grid": True,
    "grid.color": "#2f334d",
    "grid.linewidth": 0.6,
})
if _CJK_FONT:
    plt.rcParams["font.sans-serif"] = [_CJK_FONT, "DejaVu Sans"]
else:
    # 没找到 CJK 字体：明确警告（CI 应通过 apt 装字体解决）
    import sys
    print("⚠️  未找到中文字体，图表中文将渲染为 tofu。"
          "CI 请 apt install fonts-noto-cjk；macOS 自带 PingFang。", file=sys.stderr)

REPORTS_OUT = Path(__file__).resolve().parent / "out"


def _load(name: str) -> dict | list:
    with (REPORTS_OUT / f"{name}.json").open(encoding="utf-8") as f:
        return json.load(f)


def _to_k(x, _pos):
    if x >= 1_000_000:
        return f"{x/1_000_000:.1f}M"
    if x >= 1_000:
        return f"{x/1_000:.0f}k"
    return f"{int(x)}"


def plot_curves_dps(out_dir: Path) -> Path:
    """30 波所需 DPS 曲线（对数 Y 轴，标注 Boss/精英）。"""
    rows = _load("curves")
    waves = [r["wave"] for r in rows]
    dps = [r["required_dps"] for r in rows]
    boss = [r for r in rows if r["boss"]]
    elite = [r for r in rows if r["elite"]]

    fig, ax = plt.subplots(figsize=(10, 5.5), dpi=120)
    ax.plot(waves, dps, color="#7aa2f7", linewidth=2.2, marker="o", markersize=3.5, label="所需 DPS")
    ax.scatter([r["wave"] for r in boss], [r["required_dps"] for r in boss],
               color="#f7768e", s=120, zorder=5, label="Boss 波", marker="D")
    ax.scatter([r["wave"] for r in elite], [r["required_dps"] for r in elite],
               color="#e0af68", s=80, zorder=4, label="精英波", marker="s")
    ax.set_yscale("log")
    ax.yaxis.set_major_formatter(FuncFormatter(_to_k))
    ax.set_xlabel("波次")
    ax.set_ylabel("所需 DPS（对数轴）")
    ax.set_title("30 波所需 DPS 曲线（指数增长）", fontsize=14, pad=12)
    ax.legend(loc="upper left", facecolor="#1a1b26", edgecolor="#565f89", labelcolor="#c0caf5")
    fig.tight_layout()
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / "curves_dps.png"
    fig.savefig(path)
    plt.close(fig)
    return path


def plot_curves_hp(out_dir: Path) -> Path:
    """敌人血量 & 总血量曲线。"""
    rows = _load("curves")
    waves = [r["wave"] for r in rows]
    hp = [r["enemy_hp"] for r in rows]
    total = [r["total_hp"] for r in rows]

    fig, ax = plt.subplots(figsize=(10, 5.5), dpi=120)
    ax.plot(waves, hp, color="#bb9af7", linewidth=2.2, marker="o", markersize=3.5, label="单怪血量")
    ax.plot(waves, total, color="#9ece6a", linewidth=2.2, marker="s", markersize=3.5, label="该波总血量")
    ax.set_yscale("log")
    ax.yaxis.set_major_formatter(FuncFormatter(_to_k))
    ax.set_xlabel("波次")
    ax.set_ylabel("血量（对数轴）")
    ax.set_title("敌人血量曲线（单怪 / 总血量）", fontsize=14, pad=12)
    ax.legend(loc="upper left", facecolor="#1a1b26", edgecolor="#565f89", labelcolor="#c0caf5")
    fig.tight_layout()
    path = out_dir / "curves_hp.png"
    fig.savefig(path)
    plt.close(fig)
    return path


def plot_walkthrough_compare(out_dir: Path) -> Path:
    """第 15 波：build DPS / 联动后 DPS / 所需 DPS 对比条形。"""
    d = _load("walkthrough")
    labels = ["中期 build\nDPS", "+ 天帝之拳联动", "第15波\n所需 DPS"]
    vals = [d["build_dps"], d["synergy_dps"], d["required_dps"]]
    colors = ["#e0af68", "#7aa2f7", "#f7768e"]

    fig, ax = plt.subplots(figsize=(8, 5), dpi=120)
    bars = ax.bar(labels, vals, color=colors, width=0.55, edgecolor="#1a1b26")
    for b, v in zip(bars, vals):
        ax.text(b.get_x() + b.get_width() / 2, v * 1.02, f"{v:,.0f}",
                ha="center", va="bottom", color="#c0caf5", fontsize=11, fontweight="bold")
    ax.set_ylabel("DPS")
    ax.set_title(f"第 15 波 build 走查（达成率 {d['ratio']*100:.0f}%）", fontsize=14, pad=12)
    ax.set_ylim(0, max(vals) * 1.25)
    ax.yaxis.set_major_formatter(FuncFormatter(_to_k))
    fig.tight_layout()
    path = out_dir / "walkthrough_compare.png"
    fig.savefig(path)
    plt.close(fig)
    return path


def plot_walkthrough_waterfall(out_dir: Path) -> Path:
    """第 15 波伤害乘区瀑布图（逐步累乘）。"""
    d = _load("walkthrough")
    b = d["breakdown"]
    # 步骤：从 ATK×ratio 起，逐步乘各乘区
    steps = [
        ("ATK×ratio", b["base"]),
        ("× dmg_type", b["base"] * b["dmg_type_mult"]),
        ("× skill", b["base"] * b["dmg_type_mult"] * b["skill_mult"]),
        ("× final", b["base"] * b["dmg_type_mult"] * b["skill_mult"] * b["final_mult"]),
        ("× elemental", b["pre_def"]),
        ("× crit", b["pre_def"]),  # crit 已含在 pre_def 里，仅标注
        ("× defense", b["after_def"]),
        ("× 弹数", b["after_def"] * b["proj_mult"]),
        ("× 攻速 = DPS", b["dps"]),
    ]
    # crit 与 elemental 同值会显得平，这里把 crit 单独画为占位（实际已乘入）
    # 改为只画有变化的步骤
    labels = [s[0] for s in steps]
    vals = [s[1] for s in steps]

    fig, ax = plt.subplots(figsize=(10, 5.5), dpi=120)
    ax.plot(range(len(steps)), vals, color="#7aa2f7", linewidth=2.2, marker="o", markersize=6)
    for i, (lab, v) in enumerate(steps):
        ax.annotate(f"{v:.1f}", (i, v), textcoords="offset points", xytext=(0, 10),
                    ha="center", color="#c0caf5", fontsize=9)
    ax.set_xticks(range(len(steps)))
    ax.set_xticklabels(labels, rotation=20, ha="right", fontsize=9)
    ax.set_ylabel("伤害 / DPS")
    ax.set_title("第 15 波 伤害公式逐步展开（乘区瀑布）", fontsize=14, pad=12)
    fig.tight_layout()
    path = out_dir / "walkthrough_waterfall.png"
    fig.savefig(path)
    plt.close(fig)
    return path


def plot_economy_ops(out_dir: Path) -> Path:
    """每波操作数中位数曲线 + 1.5–2 目标带（B-2 经济验证）。"""
    d = _load("economy")
    waves = list(range(1, d["n_waves"] + 1))
    ops = d["ops_median_per_wave"]
    target = d["target_ops_per_wave"]

    fig, ax = plt.subplots(figsize=(10, 5.5), dpi=120)
    # 目标带
    ax.axhspan(target[0], target[1], color="#9ece6a", alpha=0.15, label=f"目标带 {target[0]}–{target[1]}")
    ax.plot(waves, ops, color="#7aa2f7", linewidth=2.2, marker="o", markersize=4, label="每波操作数中位数")
    # Boss 波标记
    boss_waves = [10, 20, 30]
    ax.scatter(boss_waves, [ops[w - 1] for w in boss_waves], color="#f7768e", s=100, zorder=5, marker="D", label="Boss 波")
    ax.set_xlabel("波次")
    ax.set_ylabel("操作数（中位数 / 1000 局）")
    status = d["b6_calibration"]["status"]
    ax.set_title(f"每波 Rogue 操作数（B6 校准: {status}）", fontsize=14, pad=12)
    ax.legend(loc="upper right", facecolor="#1a1b26", edgecolor="#565f89", labelcolor="#c0caf5")
    ax.set_ylim(0, max(ops) * 1.2)
    fig.tight_layout()
    path = out_dir / "economy_ops.png"
    fig.savefig(path)
    plt.close(fig)
    return path


def plot_economy_rarity(out_dir: Path) -> Path:
    """抽到的技能稀有度分布（对照权重 58/30/9/2.5/0.5）。"""
    d = _load("economy")
    dist = d["rarity_distribution"]
    labels = ["N", "SR", "SSR", "UR", "EX"]
    actual = [dist.get(l, 0) for l in labels]
    expected = [0.58, 0.30, 0.09, 0.025, 0.005]

    x = range(len(labels))
    fig, ax = plt.subplots(figsize=(8, 5), dpi=120)
    w = 0.35
    ax.bar([i - w / 2 for i in x], actual, w, color="#7aa2f7", label="实际分布")
    ax.bar([i + w / 2 for i in x], expected, w, color="#565f89", label="权重目标 58/30/9/2.5/0.5")
    ax.set_xticks(list(x))
    ax.set_xticklabels(labels)
    ax.set_ylabel("占比")
    ax.yaxis.set_major_formatter(FuncFormatter(lambda v, _: f"{v*100:.0f}%"))
    ax.set_title(f"技能抽取稀有度分布（{d['total_skill_draws']:,} 次抽取）", fontsize=14, pad=12)
    ax.legend(loc="upper right", facecolor="#1a1b26", edgecolor="#565f89", labelcolor="#c0caf5")
    fig.tight_layout()
    path = out_dir / "economy_rarity.png"
    fig.savefig(path)
    plt.close(fig)
    return path


def plot_run_dps_vs_required(out_dir: Path) -> Path:
    """玩家实际 DPS 中位 vs 所需 DPS（揭示卡点波次）。"""
    d = _load("run")
    waves = list(range(1, 31))
    player = d["dps_median_per_wave"]
    required = d["required_dps_per_wave"]

    fig, ax = plt.subplots(figsize=(10, 5.5), dpi=120)
    ax.plot(waves, required, color="#f7768e", linewidth=2.2, marker="o", markersize=4, label="所需 DPS")
    ax.plot(waves, player, color="#7aa2f7", linewidth=2.2, marker="s", markersize=4, label="玩家 DPS 中位")
    ax.set_yscale("log")
    ax.yaxis.set_major_formatter(FuncFormatter(_to_k))
    ax.set_xlabel("波次")
    ax.set_ylabel("DPS（对数轴）")
    ax.set_title(f"玩家 DPS vs 所需 DPS（通关率 {d['win_rate']*100:.0f}%）", fontsize=14, pad=12)
    ax.legend(loc="upper left", facecolor="#1a1b26", edgecolor="#565f89", labelcolor="#c0caf5")
    fig.tight_layout()
    path = out_dir / "run_dps.png"
    fig.savefig(path)
    plt.close(fig)
    return path


def plot_run_death_dist(out_dir: Path) -> Path:
    """死亡波次分布柱状图。"""
    d = _load("run")
    dist = d["death_wave_distribution"]
    if not dist:
        # 无人死亡（全通关）
        fig, ax = plt.subplots(figsize=(8, 4), dpi=120)
        ax.text(0.5, 0.5, "全员通关，无死亡", ha="center", va="center", fontsize=16)
        ax.axis("off")
        path = out_dir / "run_death.png"
        fig.savefig(path)
        plt.close(fig)
        return path
    waves = [int(w) for w in dist.keys()]
    counts = list(dist.values())

    fig, ax = plt.subplots(figsize=(10, 5), dpi=120)
    ax.bar(waves, counts, color="#e0af68", edgecolor="#1a1b26")
    for w, c in zip(waves, counts):
        ax.text(w, c, str(c), ha="center", va="bottom", color="#c0caf5", fontsize=9)
    ax.set_xlabel("死亡波次")
    ax.set_ylabel("局数")
    ax.set_title(f"死亡波次分布（中位 {d['median_death_wave']:.0f}，{d['n_runs']} 局）", fontsize=14, pad=12)
    fig.tight_layout()
    path = out_dir / "run_death.png"
    fig.savefig(path)
    plt.close(fig)
    return path


def render_all(assets_dir: Path) -> list[Path]:
    """生成全部图，返回路径列表。"""
    out = [
        plot_curves_dps(assets_dir),
        plot_curves_hp(assets_dir),
        plot_walkthrough_compare(assets_dir),
        plot_walkthrough_waterfall(assets_dir),
    ]
    # 经济图（若 economy.json 存在）
    if (REPORTS_OUT / "economy.json").exists():
        out.append(plot_economy_ops(assets_dir))
        out.append(plot_economy_rarity(assets_dir))
    # Run 模拟图（若 run.json 存在）
    if (REPORTS_OUT / "run.json").exists():
        out.append(plot_run_dps_vs_required(assets_dir))
        out.append(plot_run_death_dist(assets_dir))
    return out
