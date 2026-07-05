"""第 15 波 build 走查 — 复现 GDD §8（修正后可追溯版）。

设计：数据与展示分离。
  - get_walkthrough_data()  返回结构化 dict（供 build_site / 测试消费）
  - print_walkthrough()     人类可读打印（调 get_*）
  - write_json()            写 reports/out/walkthrough.json（供 CI/站点）

注意（GDD §8 已注明）：纯羁绊+单技能词条的中期 build 打不过第 15 波
（DPS ≈ 345 vs 所需 761 ≈ 45%）——这是已知的校准项，不是 bug。
"""
from __future__ import annotations

import json
from pathlib import Path

from td_balance import curves
from td_balance.combat.damage import CombatStats, EnemyStats, breakdown
from td_balance.loader import load_wave_params

OUT_DIR = Path(__file__).resolve().parent / "out"


def build_mid_game_stats() -> CombatStats:
    """构造 GDD §8 的中期 build（每个数值可追溯）。

    羁绊（5 个，未超池上限 10）：
      荒古圣体 +15%ATK、遮天2件套 +20%ATK → ATK = 50×1.35 = 67.5
      圣人果位 +10%暴击率
      风神腿 +20%攻速
      排云掌 +25%技能倍率
      聂家霸刀 +60%暴伤
    技能"天帝拳"词条：物伤+60%、最终伤害+15%、多重射+1、暴击率+15%
    """
    atk_pct = 0.15 + 0.20                      # 荒古圣体 + 遮天2件套
    atk = 50.0 * (1.0 + atk_pct)               # = 67.5
    crit_rate = 0.05 + 0.10 + 0.15             # 基础 + 圣人果位 + 词条
    crit_dmg = 1.50 + 0.60                     # 基础150% + 聂家霸刀
    attack_speed = 1.0 * (1.0 + 0.20)          # 风神腿

    return CombatStats(
        atk=atk,
        atk_ratio=1.0,
        physical_dmg_pct=0.60,                 # 物伤词条
        skill_mult_pct=0.25,                   # 排云掌
        final_dmg_mults=[0.15],                # 最终伤害传说词条
        crit_rate=crit_rate,
        crit_dmg=crit_dmg,
        attack_speed=attack_speed,
        projectile_count=2,                    # 多重射 +1
    )


def get_walkthrough_data() -> dict:
    """返回走查的结构化数据（不打印）。供 build_site / 测试消费。"""
    p = load_wave_params()
    target_wave = 15
    need = curves.required_dps(target_wave, p)
    enemy = EnemyStats(armor=33.0)             # mitigation≈25%
    stats = build_mid_game_stats()
    b = breakdown(stats, enemy)

    # 联动后的 DPS（天帝之拳 final +100%）
    synergy_stats = stats.with_final_mult(1.0)
    synergy_dps = breakdown(synergy_stats, enemy)["dps"]

    return {
        "wave": target_wave,
        "required_dps": round(need, 1),
        "build_dps": round(b["dps"], 1),
        "ratio": round(b["dps"] / need, 3),
        "synergy_dps": round(synergy_dps, 1),
        "synergy_ratio": round(synergy_dps / need, 3),
        "breakdown": {k: (round(v, 4) if isinstance(v, float) else v) for k, v in b.items()},
        "build_description": {
            "bonds": ["荒古圣体+15%ATK", "遮天2件套+20%ATK", "圣人果位+10%暴击",
                      "风神腿+20%攻速", "排云掌+25%技能倍率", "聂家霸刀+60%暴伤"],
            "skill_affixes": ["物伤+60%", "最终伤害+15%(传说)", "多重射+1", "暴击率+15%"],
        },
        "note": "纯羁绊+单技能词条的中期 build 打不过第 15 波（已知校准项，见 GDD §8）",
    }


def write_json(data: dict | None = None) -> Path:
    """写 reports/out/walkthrough.json。"""
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / "walkthrough.json"
    if data is None:
        data = get_walkthrough_data()
    with path.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    return path


def print_walkthrough() -> dict:
    """人类可读打印（调 get_walkthrough_data）。返回同 dict。"""
    d = get_walkthrough_data()
    b = d["breakdown"]

    print("\n═══ 第 15 波 build 走查（对照 GDD §8）═══\n")
    print("【build 构成】")
    print("  羁绊: 荒古圣体+圣人果位+风神腿+排云掌+聂家霸刀 (遮天2件套)")
    print("  技能: 天帝拳 + 词条[物伤+60%/最终+15%/多重射+1/暴击率+15%]")
    print()
    print("【逐步展开（伤害公式每一步乘区）】")
    print(f"  ATK × ratio            = {b['atk']:.1f} × {b['atk_ratio']:.2f} = {b['base']:.2f}")
    print(f"  × dmg_type(1+物伤+法伤) = × {b['dmg_type_mult']:.2f}")
    print(f"  × skill_mult(1+技能倍率)= × {b['skill_mult']:.2f}")
    print(f"  × final_mult(Π)        = × {b['final_mult']:.4f}")
    print(f"  × elemental(1+属性)    = × {b['elemental_mult']:.2f}")
    print(f"  × crit_factor(期望)    = × {b['crit_factor']:.4f}")
    print(f"  = 护甲前(无减伤)        = {b['pre_def']:.2f}")
    print(f"  × defense_mult(护甲)   = × {b['defense_mult']:.4f}")
    print(f"  = 护甲后(单发期望)      = {b['after_def']:.2f}")
    print(f"  × projectile(弹数有效) = × {b['proj_mult']:.2f}  (弹数={b['projectile_count']:.0f})")
    print(f"  × attack_speed         = × {b['attack_speed']:.2f}")
    print(f"  = 实际 DPS              = {b['dps']:.1f}")
    print()
    print("【对照】")
    print(f"  第 {d['wave']} 波所需 DPS = {d['required_dps']:,.0f}")
    ratio = d["ratio"]
    print(f"  build DPS / 所需       = {ratio:.2f}×")
    if ratio < 1.0:
        gap = d["required_dps"] - d["build_dps"]
        print(f"  ⚠️  差 {gap:,.0f} DPS（{ratio*100:.0f}% of 所需）—— 已知校准项，见 GDD §8 注")
        print(f"     凑齐'天帝之拳'联动(final+100%) → DPS×2 ≈ {d['synergy_dps']:.0f}，仍接近所需")
        print(f"     建议 B-1 校准：降敌人曲线(1.18→更缓) 或 升羁绊/基础数值")
    else:
        print(f"  ✅ 富余 {(ratio-1)*100:.0f}%")
    print()
    return d


def main() -> None:
    d = print_walkthrough()
    path = write_json(d)
    print(f"JSON 已导出：{path}")
