"""静态站点生成器 — 读 reports/out/*.json + data/*.yaml，渲染 site/。

复用 curves_report/walkthrough/test_report 的 JSON 产物（数据与展示分离）。
图表由 charts.py 生成 PNG。

产出：
  site/index.html        总览（验证结论卡 + 导航）
  site/curves.html       30 波曲线 + 图 + 数据表
  site/walkthrough.html  第 15 波逐步展开 + 图
  site/data.html         9 张 YAML 数据表索引
  site/data/<name>.txt   YAML 原文
  site/assets/           style.css + PNG
"""
from __future__ import annotations

import html
import json
import shutil
from datetime import datetime
from pathlib import Path

from reports import charts

HERE = Path(__file__).resolve().parent
BALANCE = HERE.parent
REPORTS_OUT = HERE / "out"
DATA_DIR = BALANCE / "data"
SITE_DIR = BALANCE.parent / "site"

DATA_TITLES = {
    "waves": "敌人曲线参数",
    "economy": "经济系统",
    "affixes": "技能词条池",
    "skills": "技能定义",
    "bonds": "羁绊 + 套系",
    "equipment": "装备系统",
    "synergies": "联动规则",
    "boss_debuffs": "Boss Debuff",
    "consumables": "应对道具（换/删）",
}

CSS = """
:root{--bg:#1a1b26;--card:#24283b;--border:#2f334d;--txt:#c0caf5;--mut:#9aa5ce;
--accent:#7aa2f7;--good:#9ece6a;--warn:#e0af68;--bad:#f7768e;}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--txt);font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;line-height:1.6}
.container{max-width:960px;margin:0 auto;padding:24px 20px 80px}
h1{font-size:1.8rem;margin:0 0 4px}
h2{font-size:1.3rem;border-bottom:1px solid var(--border);padding-bottom:6px;margin-top:36px}
h3{font-size:1.05rem;color:var(--accent);margin-top:24px}
.subtitle{color:var(--mut);font-size:.9rem;margin-bottom:8px}
nav{display:flex;gap:8px;flex-wrap:wrap;margin:16px 0}
nav a{background:var(--card);border:1px solid var(--border);color:var(--accent);padding:6px 14px;border-radius:6px;text-decoration:none;font-size:.9rem}
nav a:hover{border-color:var(--accent)}
.card{background:var(--card);border:1px solid var(--border);border-radius:10px;padding:18px 20px;margin:12px 0}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px}
.stat{text-align:center}
.stat .num{font-size:1.8rem;font-weight:700}
.stat .lbl{color:var(--mut);font-size:.8rem;text-transform:uppercase;letter-spacing:.05em}
.good{color:var(--good)}.warn{color:var(--warn)}.bad{color:var(--bad)}
img{max-width:100%;height:auto;border-radius:8px;border:1px solid var(--border);margin:10px 0}
table{border-collapse:collapse;width:100%;font-size:.85rem;margin:10px 0}
th,td{border:1px solid var(--border);padding:6px 10px;text-align:right}
th{background:var(--card);color:var(--mut);font-weight:600;text-align:left}
td:first-child,th:first-child{text-align:left}
code,pre{font-family:'SF Mono',Consolas,monospace;font-size:.82rem}
pre{background:var(--card);border:1px solid var(--border);border-radius:8px;padding:14px;overflow:auto;white-space:pre-wrap;word-break:break-word}
.badge{display:inline-block;padding:2px 8px;border-radius:4px;font-size:.75rem;font-weight:600}
.badge.boss{background:#f7768e33;color:#f7768e}
.badge.elite{background:#e0af6833;color:#e0af68}
.step{display:flex;justify-content:space-between;padding:4px 0;border-bottom:1px dashed var(--border)}
.rarity-N{color:var(--mut)}.rarity-SR{color:var(--accent)}.rarity-SSR{color:#bb9af7}
.rarity-UR{color:var(--warn);font-weight:700}
.rarity-EX{color:var(--warn);font-weight:700;background:#e0af6833;padding:2px 6px;border-radius:4px}
.data-table td code{background:#00000022;padding:1px 4px;border-radius:3px}
.step .v{color:var(--accent);font-family:monospace}
footer{color:var(--mut);font-size:.8rem;text-align:center;margin-top:40px;padding-top:16px;border-top:1px solid var(--border)}
a{color:var(--accent)}
"""


def _load_json(name: str):
    with (REPORTS_OUT / f"{name}.json").open(encoding="utf-8") as f:
        return json.load(f)


def _page(title: str, body: str, active: str = "") -> str:
    nav = "".join(
        f'<a href="{href}"{" class=active" if key==active else ""}>{label}</a>'
        for key, href, label in [
            ("index", "index.html", "总览"),
            ("curves", "curves.html", "波次曲线"),
            ("walk", "walkthrough.html", "走查"),
            ("econ", "economy.html", "经济模拟"),
            ("run", "run.html", "通关模拟"),
            ("data", "data.html", "数据表"),
        ]
    )
    return f"""<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title} · Roguelike-TD 数值</title>
<link rel="stylesheet" href="assets/style.css"></head>
<body><div class="container">
<h1>{title}</h1>
<nav>{nav}</nav>
{body}
<footer>由 <code>balance/</code> 脚本生成 · {datetime.now().strftime('%Y-%m-%d %H:%M')}</footer>
</div></body></html>"""


def render_index() -> str:
    tests = _load_json("tests")
    walk = _load_json("walkthrough")
    status = "good" if tests["all_passed"] else "bad"
    status_txt = "✅ 全部通过" if tests["all_passed"] else f"❌ {tests['failed']} 失败"
    ratio_pct = walk["ratio"] * 100
    ratio_cls = "bad" if walk["ratio"] < 1 else "good"

    # 经济校准（B-2）—— 若 economy.json 存在则展示
    econ_html = ""
    try:
        econ = _load_json("economy")
        b6 = econ["b6_calibration"]
        econ_status_cls = {"ok": "good", "residual_hoarding": "warn",
                           "saturation_crash": "bad", "over": "warn"}.get(b6["status"], "")
        late_ops = b6.get("late_ops_median", b6.get("overall_ops_median", "?"))
        hoarding = b6.get("final_gold_median", econ["final_gold"]["median"])
        econ_html = f"""
<h2>经济校准（B-2）</h2>
<div class="card">
  <div class="grid">
    <div class="stat"><div class="num {econ_status_cls}">{b6['status']}</div><div class="lbl">B6 状态</div></div>
    <div class="stat"><div class="num">{hoarding:,.0f}</div><div class="lbl">终局囤积(原9634)</div></div>
    <div class="stat"><div class="num">{late_ops}</div><div class="lbl">后期操作数/波</div></div>
    <div class="stat"><div class="num">{econ['n_runs']}</div><div class="lbl">模拟局数</div></div>
  </div>
  <p class="subtitle">{b6['verdict']}</p>
  <p><a href="economy.html">查看经济详情 →</a></p>
</div>"""
    except FileNotFoundError:
        pass

    # 通关模拟（B-3）
    run_html = ""
    try:
        run = _load_json("run")
        diag = run["diagnosis"]
        diag_cls = {"too_hard": "bad", "too_easy": "warn", "ok": "good"}.get(diag["status"], "")
        win_cls = "good" if 0.10 <= run["win_rate"] <= 0.40 else "bad"
        run_html = f"""
<h2>通关模拟（B-3）</h2>
<div class="card">
  <div class="grid">
    <div class="stat"><div class="num {win_cls}">{run['win_rate']*100:.0f}%</div><div class="lbl">通关率(目标10-40%)</div></div>
    <div class="stat"><div class="num">{run['median_death_wave']:.0f}</div><div class="lbl">中位死波(目标15-25)</div></div>
    <div class="stat"><div class="num {diag_cls}">{diag['status']}</div><div class="lbl">难度诊断</div></div>
    <div class="stat"><div class="num">{run['n_runs']}</div><div class="lbl">模拟局数</div></div>
  </div>
  <p class="subtitle">{diag['verdict']}</p>
  <p><a href="run.html">查看通关详情 →</a></p>
</div>"""
    except FileNotFoundError:
        pass

    body = f"""
<p class="subtitle">roguelike-td · 数值验证与数据可视化（数据源：<code>balance/data/*.yaml</code>）</p>
<div class="card">
  <div class="grid">
    <div class="stat"><div class="num {status}">{tests['passed']}</div><div class="lbl">单测通过</div></div>
    <div class="stat"><div class="num {ratio_cls}">{ratio_pct:.0f}%</div><div class="lbl">第15波达成率</div></div>
    <div class="stat"><div class="num">{walk['build_dps']:.0f}</div><div class="lbl">build DPS</div></div>
    <div class="stat"><div class="num">{walk['required_dps']:.0f}</div><div class="lbl">所需 DPS</div></div>
  </div>
</div>
<div class="card">
  <h3>战斗公式验证</h3>
  <p><b class="{status}">{status_txt}</b>（{tests['passed']}/{tests['total']}）</p>
  <p>第 15 波走查：中期 build（5 羁绊 + 单技能词条）达成 <b class="{ratio_cls}">{ratio_pct:.0f}%</b> 所需 DPS。
  凑齐"天帝之拳"联动后 → <b>{walk['synergy_ratio']*100:.0f}%</b>。</p>
  <p class="subtitle">⚠️ 中期 build 打不过第 15 波是<b>已知校准项</b>（见 GDD §8），非 bug。</p>
</div>
{econ_html}
{run_html}
<h2>开发进度</h2>
<div class="card">
  <table class="data-table">
    <tr><th>里程碑</th><th>状态</th><th>内容</th></tr>
    <tr><td>B 路线数值验证</td><td class="good">✅ 完成</td><td>69 测试通过，18% 通关校准，联动引擎建模</td></tr>
    <tr><td>M0 骨架</td><td class="good">✅</td><td>Godot 项目、数据 JSON 管线、EventBus</td></tr>
    <tr><td>M1 核心战斗</td><td class="good">✅</td><td>英雄自动战斗、波次刷怪、伤害管线</td></tr>
    <tr><td>M2 技能 3 选 1</td><td class="good">✅</td><td>技能/羁绊抽取、英雄=核心、弹道锁定、卡片加成</td></tr>
    <tr><td>M2.5 手感打磨</td><td class="good">✅</td><td>大地图+相机、波次倒计时、渐进刷怪、角色面板、击杀特效</td></tr>
    <tr><td>M4 联动引擎</td><td class="good">✅</td><td>11 条联动（9 两重+2 三重 EX）、连锁弹射、规则匹配引擎</td></tr>
    <tr><td>M3 装备经济</td><td class="good">✅</td><td>升级+1→+9、里程碑词条（70%正面/30%诅咒）、诅咒代价换收益、经济循环（gold_per_sec/per_kill/gold_mult/double_gold）</td></tr>
    <tr><td>M5 内容平衡</td><td class="warn">⏳ 待做</td><td>数值调参（当前数值偏强）、更多套系/技能</td></tr>
    <tr><td>M6 跨端发布</td><td class="warn">⏳ 待做</td><td>iOS/Android/Web 导出、服务端、IAP/云存档</td></tr>
  </table>
</div>
<h2>联动引擎</h2>
<div class="card">
  <div class="grid">
    <div class="stat"><div class="num good">11</div><div class="lbl">联动规则</div></div>
    <div class="stat"><div class="num">9</div><div class="lbl">两重联动</div></div>
    <div class="stat"><div class="num warn">2</div><div class="lbl">三重(EX)</div></div>
    <div class="stat"><div class="num good">90%</div><div class="lbl">触发局通关率</div></div>
  </div>
  <p>联动 = 羁绊×技能×装备的交叉触发奖励。所有联动统一走 <code>bond_devoured_set</code>（修满体系）。
  Python 验证：触发联动的局通关率 <b class="good">90%</b> vs 未触发 <b>14%</b>。</p>
  <p class="subtitle">M3 装备系统已实现，三重联动（天帝雷罚/雷暴黄金）可完整触发。</p>
</div>
<h2>核心结论</h2>
<div class="card">
  <p>1. <b>公式自洽</b>：Master Damage Pipeline 各乘区（物法伤/技能倍率/最终/元素/暴击/护甲/真伤/多重射）单测锁定。</p>
  <p>2. <b>曲线单调</b>：30 波所需 DPS 从 38 → 11,708，指数增长。</p>
  <p>3. <b>核心发现</b>：纯羁绊+单技能词条撑不起中期 DPS，必须靠 <code>final_mult</code> 联动——印证"联动=滚雪球关键"设计。</p>
</div>"""
    return _page("数值验证总览", body, "index")


def render_curves() -> str:
    rows = _load_json("curves")
    img = '<img src="assets/curves_dps.png" alt="所需DPS曲线"><img src="assets/curves_hp.png" alt="血量曲线">'
    boss_badge = '<span class="badge boss">Boss</span>'
    elite_badge = '<span class="badge elite">精英</span>'
    table_rows = "".join(
        f"<tr><td>{r['wave']}</td><td>{r['enemy_hp']:,.1f}</td><td>{r['enemy_count']}</td>"
        f"<td>{r['total_hp']:,.0f}</td><td>{r['duration']:.0f}s</td><td>{r['required_dps']:,.0f}</td>"
        f"<td>{boss_badge if r['boss'] else elite_badge if r['elite'] else ''}</td></tr>"
        for r in rows
    )
    body = f"""
<h2>所需 DPS 曲线</h2>{img}
<h2>30 波数据表</h2>
<table><thead><tr><th>波次</th><th>单怪血量</th><th>怪物数</th><th>总血量</th><th>时长</th><th>所需DPS</th><th>类型</th></tr></thead>
<tbody>{table_rows}</tbody></table>"""
    return _page("波次曲线", body, "curves")


def render_walkthrough() -> str:
    d = _load_json("walkthrough")
    b = d["breakdown"]
    steps = [
        ("ATK × ratio", f"{b['atk']:.1f} × {b['atk_ratio']:.2f} = {b['base']:.2f}"),
        ("× dmg_type (1+物伤+法伤)", f"× {b['dmg_type_mult']:.2f}"),
        ("× skill_mult (1+技能倍率)", f"× {b['skill_mult']:.2f}"),
        ("× final_mult (Π)", f"× {b['final_mult']:.4f}"),
        ("× elemental (1+属性)", f"× {b['elemental_mult']:.2f}"),
        ("× crit_factor (期望)", f"× {b['crit_factor']:.4f}"),
        ("= 护甲前 (无减伤)", f"= {b['pre_def']:.2f}"),
        ("× defense_mult (护甲)", f"× {b['defense_mult']:.4f}"),
        ("= 护甲后 (单发期望)", f"= {b['after_def']:.2f}"),
        ("× 弹数有效 (散射递减)", f"× {b['proj_mult']:.2f} (弹{b['projectile_count']:.0f})"),
        ("× 攻速", f"× {b['attack_speed']:.2f}"),
        ("= 实际 DPS", f"= {b['dps']:.1f}"),
    ]
    steps_html = "".join(f'<div class="step"><span>{lab}</span><span class="v">{val}</span></div>' for lab, val in steps)
    bonds = "".join(f"<li>{x}</li>" for x in d["build_description"]["bonds"])
    affixes = "".join(f"<li>{x}</li>" for x in d["build_description"]["skill_affixes"])
    body = f"""
<h2>build 构成</h2>
<div class="card">
  <h3>羁绊（5 个，未超池上限 10）</h3><ul>{bonds}</ul>
  <h3>技能"天帝拳"词条</h3><ul>{affixes}</ul>
</div>
<h2>伤害公式逐步展开</h2>
<div class="card">{steps_html}</div>
<img src="assets/walkthrough_compare.png" alt="build vs 所需对比">
<img src="assets/walkthrough_waterfall.png" alt="乘区瀑布">
<h2>对照</h2>
<div class="card">
  <p>第 {d['wave']} 波所需 DPS = <b>{d['required_dps']:,.0f}</b></p>
  <p>build DPS / 所需 = <b class="{'bad' if d['ratio']<1 else 'good'}">{d['ratio']*100:.0f}%</b>（差 {d['required_dps']-d['build_dps']:,.0f} DPS）</p>
  <p>凑齐"天帝之拳"联动(final+100%) → DPS×2 ≈ {d['synergy_dps']:.0f}，达成 {d['synergy_ratio']*100:.0f}%</p>
  <p class="subtitle">{d['note']}</p>
</div>"""
    return _page("第 15 波走查", body, "walk")


def render_data() -> str:
    import yaml
    sections = []
    data_site_dir = SITE_DIR / "data"
    data_site_dir.mkdir(parents=True, exist_ok=True)
    for name, title in DATA_TITLES.items():
        src = DATA_DIR / f"{name}.yaml"
        # 也保留原始 YAML 下载
        dst = data_site_dir / f"{name}.txt"
        shutil.copyfile(src, dst)
        # 解析 YAML 渲染为表格
        try:
            raw = yaml.safe_load(src.read_text(encoding="utf-8"))
            table_html = _yaml_to_table(name, raw)
        except Exception:
            table_html = f'<p class="subtitle">解析失败，<a href="data/{name}.txt">查看原始 YAML</a></p>'
        sections.append(f'<h2>{title} <a href="data/{name}.txt" class="subtitle" style="font-size:0.6em">[YAML原文]</a></h2>{table_html}')
    body = f"""
<p class="subtitle">所有数值的 single source of truth。策划改这里，CI 重跑后站点自动更新。</p>
{''.join(sections)}"""
    return _page("数据表", body, "data")


def _yaml_to_table(name: str, data) -> str:
    """把 YAML 数据渲染成可读的 HTML 表格。"""
    if data is None:
        return "<p class='subtitle'>（空）</p>"

    # 根据 name 选择渲染策略
    if name == "skills":
        return _render_skills_table(data)
    elif name == "bonds":
        return _render_bonds_table(data)
    elif name == "equipment":
        return _render_equipment_table(data)
    elif name == "synergies":
        return _render_synergies_table(data)
    elif name == "affixes":
        return _render_affixes_table(data)
    else:
        # 通用：键值对
        return _render_generic_table(data)


def _render_skills_table(data) -> str:
    skills = data.get("skills", [])
    rows = "".join(
        f"<tr><td>{s.get('id','')}</td><td>{s.get('name','')}</td>"
        f"<td><span class='rarity-{s.get('rarity','N')}'>{s.get('rarity','')}</span></td>"
        f"<td>{', '.join(s.get('tags',[]))}</td>"
        f"<td>{s.get('atk_ratio','')}</td>"
        f"<td>{', '.join(s.get('base_affixes',[]))}</td></tr>"
        for s in skills
    )
    return f"""<div class="card"><table class="data-table">
<tr><th>id</th><th>名称</th><th>稀有度</th><th>标签</th><th>倍率</th><th>基础词条</th></tr>
{rows}</table></div>"""


def _render_bonds_table(data) -> str:
    bonds = data.get("bonds", [])
    paths = data.get("paths", [])
    # 羁绊表
    rows = "".join(
        f"<tr><td>{b.get('id','')}</td><td>{b.get('name','')}</td>"
        f"<td>{b.get('set','')}</td>"
        f"<td>{_fmt_effect(b.get('effect',{}))}</td></tr>"
        for b in bonds
    )
    bonds_table = f"""<div class="card"><h3>羁绊 ({len(bonds)})</h3>
<table class="data-table"><tr><th>id</th><th>名称</th><th>体系</th><th>效果</th></tr>
{rows}</table></div>"""
    # 境界树
    path_html = []
    for p in paths:
        realms = p.get("realms", [])
        realm_rows = "".join(
            f"<tr><td>{i}</td><td>{r.get('name','')}</td>"
            f"<td>{', '.join(r.get('bonds',[]))}</td>"
            f"<td>{_fmt_effect(r.get('reward',{}))}</td></tr>"
            for i, r in enumerate(realms)
        )
        path_html.append(f"""<div class="card"><h3>{p.get('name','')} ({p.get('id','')}) — {len(realms)} 境</h3>
<table class="data-table"><tr><th>境界</th><th>名称</th><th>需要羁绊</th><th>升境奖励</th></tr>
{realm_rows}</table></div>""")
    return bonds_table + "".join(path_html)


def _render_equipment_table(data) -> str:
    affixes = data.get("affixes", [])
    pos = [a for a in affixes if a.get("polarity", "positive") != "curse"]
    curs = [a for a in affixes if a.get("polarity") == "curse"]
    pos_rows = "".join(
        f"<tr><td>{a.get('id','')}</td><td>{a.get('name','')}</td>"
        f"<td>{_fmt_effect(a.get('effect',{}))}</td></tr>"
        for a in pos
    )
    cur_rows = "".join(
        f"<tr><td>{a.get('id','')}</td><td>{a.get('name','')}</td>"
        f"<td class='bad'>代价: {_fmt_effect(a.get('cost',{}))}</td>"
        f"<td class='good'>收益: {_fmt_effect(a.get('benefit',{}))}</td></tr>"
        for a in curs
    )
    curve = data.get("upgrade_curve", {})
    return f"""<div class="card"><h3>正面词条 ({len(pos)})</h3>
<table class="data-table"><tr><th>id</th><th>名称</th><th>效果</th></tr>{pos_rows}</table></div>
<div class="card"><h3>诅咒词条 ({len(curs)})</h3>
<table class="data-table"><tr><th>id</th><th>名称</th><th>代价</th><th>收益</th></tr>{cur_rows}</table></div>"""


def _render_synergies_table(data) -> str:
    syns = data.get("synergies", [])
    rows = "".join(
        f"<tr><td>{s.get('name','')}</td>"
        f"<td><span class='rarity-{s.get('rarity','') or 'N'}'>{s.get('rarity','') or 'N'}</span></td>"
        f"<td>{_fmt_trigger(s.get('trigger',{}))}</td>"
        f"<td>{_fmt_effect(s.get('effect',{}))}</td></tr>"
        for s in syns
    )
    return f"""<div class="card"><table class="data-table">
<tr><th>联动</th><th>Rarity</th><th>触发条件</th><th>效果</th></tr>
{rows}</table></div>"""


def _render_affixes_table(data) -> str:
    affixes = data.get("affixes", [])
    rows = "".join(
        f"<tr><td>{a.get('id','')}</td><td>{a.get('name','')}</td>"
        f"<td><span class='rarity-{a.get('rarity','N')}'>{a.get('rarity','')}</span></td>"
        f"<td>{a.get('stacking','')}</td>"
        f"<td>{_fmt_effect(a.get('effect',{}))}</td></tr>"
        for a in affixes
    )
    return f"""<div class="card"><table class="data-table">
<tr><th>id</th><th>名称</th><th>稀有度</th><th>叠加</th><th>效果</th></tr>
{rows}</table></div>"""


def _render_generic_table(data) -> str:
    """通用 dict/list 渲染。"""
    if isinstance(data, dict):
        rows = ""
        for k, v in data.items():
            if isinstance(v, (dict, list)):
                import json
                val_str = f"<code>{json.dumps(v, ensure_ascii=False)[:200]}</code>"
            else:
                val_str = str(v)
            rows += f"<tr><td>{k}</td><td>{val_str}</td></tr>"
        return f'<div class="card"><table class="data-table"><tr><th>key</th><th>value</th></tr>{rows}</table></div>'
    return f"<div class='card'><pre>{data}</pre></div>"


def _fmt_effect(eff: dict) -> str:
    """格式化 effect dict 为简洁文本。"""
    if not eff:
        return "—"
    import json
    return f"<code>{json.dumps(eff, ensure_ascii=False)}</code>"


def _fmt_trigger(trigger: dict) -> str:
    """格式化触发条件。"""
    conds = trigger.get("all", [])
    parts = []
    for c in conds:
        for k, v in c.items():
            label = {"bond_devoured_set": "吞噬", "skill_tag": "标签",
                     "equipment_affix": "装备", "affix_owned": "词条"}.get(k, k)
            parts.append(f"{label}: {v}")
    return " + ".join(parts)


def render_economy() -> str:
    """B-2 经济模拟页：每波操作数 + 稀有度分布 + B6 校准结论。"""
    try:
        d = _load_json("economy")
    except FileNotFoundError:
        return _page("经济模拟", '<p class="subtitle">economy.json 未生成（跑 reports/economy_report.py）</p>', "econ")
    b6 = d["b6_calibration"]
    status_cls = {"saturation_crash": "bad", "over": "warn", "under": "warn", "ok": "good"}.get(b6["status"], "")
    # 收入表（前 5 + Boss 波）
    inc_rows = "".join(
        f"<tr><td>{w}</td><td>{d['income_per_wave'][w-1]:,.0f}</td>"
        f"<td>{d['ops_median_per_wave'][w-1]}</td>"
        f"<td>{d['reroll_rate_per_wave'][w-1]*100:.0f}%</td></tr>"
        for w in [1, 2, 3, 5, 10, 15, 20, 25, 30]
    )
    reroll_avg = sum(d["reroll_rate_per_wave"]) / len(d["reroll_rate_per_wave"]) * 100
    body = f"""
<h2>B6 经济校准结论</h2>
<div class="card">
  <p><b class="{status_cls}">[{b6['status']}]</b> {b6['verdict']}</p>
  <p class="subtitle">💡 {b6.get('suggestion', '无需调整，已达目标')}</p>
</div>
<h2>每波 Rogue 操作数</h2>
<img src="assets/economy_ops.png" alt="每波操作数曲线">
<div class="card">
  <div class="grid">
    <div class="stat"><div class="num">{d['n_runs']}</div><div class="lbl">模拟局数</div></div>
    <div class="stat"><div class="num">{reroll_avg:.0f}%</div><div class="lbl">平均重投率(目标30-50%)</div></div>
    <div class="stat"><div class="num">{d['final_gold']['median']:,.0f}</div><div class="lbl">终局金币(不应囤积)</div></div>
  </div>
</div>
<h2>关键波次明细</h2>
<table><thead><tr><th>波次</th><th>收入(金)</th><th>操作数中位</th><th>重投率</th></tr></thead>
<tbody>{inc_rows}</tbody></table>"""
    return _page("经济模拟", body, "econ")


def render_run() -> str:
    """B-3 通关模拟页：通关率/死波分布/玩家vs所需DPS/诊断。"""
    try:
        d = _load_json("run")
    except FileNotFoundError:
        return _page("通关模拟", '<p class="subtitle">run.json 未生成</p>', "run")
    diag = d["diagnosis"]
    diag_cls = {"too_hard": "bad", "too_easy": "warn", "ok": "good"}.get(diag["status"], "")
    win_pct = d["win_rate"] * 100
    win_cls = "good" if 0.10 <= d["win_rate"] <= 0.40 else ("bad" if d["win_rate"] < 0.10 else "warn")
    death_dist = d["death_wave_distribution"]
    dist_rows = "".join(
        f"<tr><td>第 {w} 波</td><td>{c}</td><td>{c/d['n_runs']*100:.1f}%</td></tr>"
        for w, c in sorted(death_dist.items(), key=lambda x: int(x[0]))
    ) if death_dist else "<tr><td colspan=3>全员通关</td></tr>"
    hp_buckets = d["death_hp_buckets"]

    body = f"""
<div class="card">
  <div class="grid">
    <div class="stat"><div class="num {win_cls}">{win_pct:.1f}%</div><div class="lbl">通关率(目标10-40%)</div></div>
    <div class="stat"><div class="num">{d['median_death_wave']:.0f}</div><div class="lbl">中位死亡波次(目标15-25)</div></div>
    <div class="stat"><div class="num">{d['maxed_paths']['median']}</div><div class="lbl">修满体系数</div></div>
    <div class="stat"><div class="num">{d['n_runs']}</div><div class="lbl">模拟局数</div></div>
  </div>
</div>
<h2>诊断</h2>
<div class="card">
  <p><b class="{diag_cls}">[{diag['status']}]</b> {diag['verdict']}</p>
  {'<p class="subtitle">根因: ' + diag.get('root_cause','') + '</p>' if diag.get('root_cause') else ''}
  {'<p class="subtitle">💡 ' + diag.get('suggestion','') + '</p>' if diag.get('suggestion') else ''}
</div>
<h2>玩家 DPS vs 所需 DPS</h2>
<img src="assets/run_dps.png" alt="玩家vs所需DPS">
<p class="subtitle">两线交叉点 = 卡点波次。玩家低于所需 → 清不完波 → 失败。</p>
<h2>死亡波次分布</h2>
<img src="assets/run_death.png" alt="死亡波次分布">
<table><thead><tr><th>死亡波次</th><th>局数</th><th>占比</th></tr></thead>
<tbody>{dist_rows}</tbody></table>
<h2>死时核心血量分布（near-miss 分析）</h2>
<div class="card">
  <p>0-5%（惜败）: <b>{hp_buckets['0-5%']}</b> &nbsp; 5-20%: <b>{hp_buckets['5-20%']}</b> &nbsp; 20-50%: <b>{hp_buckets['20-50%']}</b> &nbsp; 50-100%（碾压死）: <b>{hp_buckets['50-100%']}</b></p>
  <p class="subtitle">理想：5-20% 惜败为主（near-miss 驱动"再来一局"）。当前若大量 0-5% 或集中某波 = 难度断层。</p>
</div>"""
    return _page("通关模拟", body, "run")


def build_site() -> Path:
    """生成完整站点。返回 SITE_DIR。"""
    assets = SITE_DIR / "assets"
    assets.mkdir(parents=True, exist_ok=True)
    (assets / "style.css").write_text(CSS, encoding="utf-8")
    charts.render_all(assets)
    (SITE_DIR / "index.html").write_text(render_index(), encoding="utf-8")
    (SITE_DIR / "curves.html").write_text(render_curves(), encoding="utf-8")
    (SITE_DIR / "walkthrough.html").write_text(render_walkthrough(), encoding="utf-8")
    if (REPORTS_OUT / "economy.json").exists():
        (SITE_DIR / "economy.html").write_text(render_economy(), encoding="utf-8")
    if (REPORTS_OUT / "run.json").exists():
        (SITE_DIR / "run.html").write_text(render_run(), encoding="utf-8")
    (SITE_DIR / "data.html").write_text(render_data(), encoding="utf-8")
    return SITE_DIR


def main() -> None:
    site = build_site()
    print(f"✅ 站点已生成：{site}/index.html")
    print("   本地预览：浏览器打开上述 index.html")


if __name__ == "__main__":
    main()
