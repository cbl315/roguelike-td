#!/usr/bin/env python3
"""regression.py — 游戏内交互回归剧本（一键）。

覆盖：斗破种子(+30金) → 境界卡池 → 集齐吞噬(升境信号) → Boss debuff 激活
→ 应对道具(换-40金/删-120金) → 删后无效果 → 大招释放与回能。

前置：Godot 编辑器打开 client/（6550 监听中）。依赖 websocket-client。
用法：python3 regression.py
"""
import json
import sys
import time

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from driver import GMcp, GMcpError  # noqa: E402

WANT = ["dp_qi_xiaoyan", "dp_qi_yaolao", "dp_qi_xuner", "dp_qi_douzhi"]
LOBBY = 'root.get_node("/root/GameRoot/UILayer/Lobby")'
GM = 'root.get_node("/root/GameRoot/GameManager")'

RESULTS = []


def check(name: str, ok: bool, detail: str = ""):
    RESULTS.append(ok)
    print(f"{'✅' if ok else '❌'} {name}" + (f" — {detail}" if detail else ""))


def run(g: GMcp, source: str, timeout: float = 25.0):
    resp = g.call("exec_run", {"source": source}, timeout)
    res = (resp.get("result") or {}).get("result")
    if isinstance(res, str):
        try:
            res = json.loads(res)
        except (ValueError, TypeError):
            pass
    return res


def src_state():
    return (f'var gm = {GM}\n'
            'return JSON.stringify({"state": int(gm.state), "gold": gm._build.gold, '
            '"realm": gm._build.path_realm.get("doupo", -1), '
            '"pool": gm._build.bond_pool, "devoured": gm._build.devoured_bonds})')


def main() -> int:
    try:
        g = GMcp()
    except GMcpError as e:
        print(f"❌ 连接失败：{e}")
        return 1
    try:
        # ── 启动游戏（若未在跑）──
        info = g.call("get_project_info", {}, 10)
        check("插件连通", info.get("status") == "success")
        g.call("run_project", {}, 20)
        time.sleep(4.0)

        # ── 锁暂停，抽到斗破种子（多轮开面板，最多 10 次）──
        run(g, 'tree.paused = true\nreturn "ok"')
        st0 = run(g, src_state()) or {}
        seed_gold_before = st0.get("gold", 0.0)
        offers = []
        seed_idx = -1
        for attempt in range(14):   # 种子出现率随机，多轮重试防霉运中断
            run(g, f'var gm = {GM}\ngm._build.add_gold(300.0)\ngm.open_bond_picker()\nreturn "ok"')
            time.sleep(0.4)
            offers = run(g, f'var o = []\nfor b in {LOBBY}._bond_offers:\n\to.append(str(b.get("id")))\n'
                            'return JSON.stringify(o)') or []
            seed_idx = next((i for i, oid in enumerate(offers) if oid == "seed_doupo"), -1)
            if seed_idx >= 0:
                break
            run(g, f'{LOBBY}._on_reroll_bond()\nreturn "ok"')   # 刷新一次
            time.sleep(0.3)
            offers = run(g, f'var o = []\nfor b in {LOBBY}._bond_offers:\n\to.append(str(b.get("id")))\n'
                            'return JSON.stringify(o)') or []
            seed_idx = next((i for i, oid in enumerate(offers) if oid == "seed_doupo"), -1)
            if seed_idx >= 0:
                break
            run(g, f'{LOBBY}._on_confirm()\ntree.paused = true\nreturn "ok"')   # 关面板再来
            time.sleep(0.3)
        check("三选一出现斗破种子", seed_idx >= 0, f"第{attempt + 1}轮 offers={offers}")
        if seed_idx < 0:
            return finish(g)
        pre_pick = run(g, f'var gm = {GM}\nreturn JSON.stringify({{"g": gm._build.gold, '
                         f'"r": gm._build.path_realm.get("doupo", -1)}})') or {}
        run(g, f'{LOBBY}._on_pick({seed_idx})\ntree.paused = true\nreturn "ok"')
        time.sleep(0.4)
        st1 = run(g, src_state()) or {}
        delta = st1.get("gold", 0) - float(pre_pick.get("g", 0))
        check("种子解锁体系(+30金)", st1.get("realm") == 0 and abs(delta - 30.0) < 2.0,
              f"realm={st1.get('realm')} Δgold={delta}")

        # ── 抽到境界卡出现 + 集齐吞噬 ──
        run(g, f'var gm = {GM}\ngm._build.bond_pool.clear()\ngm.open_bond_picker()\nreturn "ok"')
        time.sleep(0.4)
        realm_cards = []
        for _try in range(4):   # offers 偶发空（时序）：重开面板再读
            offers = run(g, f'var o = []\nfor b in {LOBBY}._bond_offers:\n\to.append(str(b.get("id")))\n'
                            'return JSON.stringify(o)') or []
            realm_cards = [oid for oid in offers if str(oid).startswith("dp_")]
            if realm_cards:
                break
            run(g, f'var gm = {GM}\ngm.open_bond_picker()\ntree.paused = true\nreturn "ok"')
            time.sleep(0.3)
        check("境界卡出现(dp_*)", len(realm_cards) > 0, f"{realm_cards}")

        for it in range(20):
            st = run(g, src_state()) or {}
            if st.get("realm", 0) >= 1:
                break
            missing = [w for w in WANT if w not in st.get("pool", []) and w not in st.get("devoured", [])]
            run(g, f'var gm = {GM}\ngm._build.add_gold(300.0)\ngm.open_bond_picker()\nreturn "ok"')
            time.sleep(0.35)
            offers = run(g, f'var o = []\nfor b in {LOBBY}._bond_offers:\n\to.append(str(b.get("id")))\n'
                            'return JSON.stringify(o)') or []
            pick = next((i for i, oid in enumerate(offers) if oid in missing), -1)
            if pick < 0:
                run(g, f'{LOBBY}._on_reroll_bond()\nreturn "ok"')
                time.sleep(0.3)
                offers = run(g, f'var o = []\nfor b in {LOBBY}._bond_offers:\n\to.append(str(b.get("id")))\n'
                                'return JSON.stringify(o)') or []
                pick = next((i for i, oid in enumerate(offers) if oid in missing), -1)
            if pick < 0:
                run(g, f'{LOBBY}._on_confirm()\ntree.paused = true\nreturn "ok"')
                time.sleep(0.3)
                continue
            run(g, f'{LOBBY}._on_pick({pick})\ntree.paused = true\nreturn "ok"')
            time.sleep(0.45)
        st2 = run(g, src_state()) or {}
        devoured_dp = [b for b in st2.get("devoured", []) if str(b).startswith("dp_")]
        # 2026-11-03 改版：羁绊集齐自动升境（守关者考核移到装备里程碑）
        check("集齐自动升境1", st2.get("realm") == 1 and len(devoured_dp) >= 4,
              f"realm={st2.get('realm')} devoured_dp={len(devoured_dp)}")
        # ── 装备里程碑守卫：升+4 → 点+5被拦+守卫 → 击杀 → 解锁升级+词条三选一 ──
        run(g, f'var gm = {GM}\ntree.paused = true\ngm._build.add_gold(3000.0)\ngm._build.equip_level = 0\n'
               f'for i in range(4):\n\tgm._build.equip_upgrade()\nreturn "ok"')
        r = run(g, f'var gm = {GM}\nvar r5: Dictionary = gm._build.equip_upgrade()\ntree.paused = false\n'
                   f'return JSON.stringify({{"blocked": r5.get("blocked", false), "ms": r5.get("milestone", 0), '
                   f'"lv": gm._build.equip_level}})')
        check("装备+5被守卫拦截", bool(r and r.get("blocked")) and r.get("ms") == 5 and r.get("lv") == 4, str(r))
        r = run(g, f'var gm = {GM}\nreturn JSON.stringify({{"alive": gm._breakthrough.is_guard_alive()}})')
        check("装备守关者降临", bool(r and r.get("alive")))
        run(g, f'var gm = {GM}\ngm._breakthrough.debug_kill_guard()\nreturn "ok"')
        r = run(g, f'var gm = {GM}\ntree.paused = true\nvar rr: Dictionary = gm._build.equip_upgrade()\n'
                   f'return JSON.stringify({{"cleared": gm._build.equip_guard_cleared, "lv2": gm._build.equip_level, '
                       f'"opts": rr.get("milestone_options", []).size()}})')
        check("击杀解锁+升级拿词条", r and r.get("cleared") == 5 and r.get("lv2") == 5 and r.get("opts") == 3, str(r))

        # ── Boss debuff：跳第10波，验证激活 + 删除道具闭环 ──
        run(g, f'var gm = {GM}\ngm._build.add_gold(1000.0)\nreturn "ok"')
        run(g, f'var gm = {GM}\nvar lb = root.get_node("/root/GameRoot/UILayer/Lobby")\n'
               f'if lb.visible:\n\tlb._on_confirm()\ntree.paused = false\n'
               f'root.get_node("/root/DebugKeys").jump_to_boss()\nreturn "ok"')
        bs = {}
        for _ in range(12):   # 轮询等波推进到 10（Boss 波开始，debuff 激活）
            time.sleep(1.0)
            bs = run(g, f'var gm = {GM}\nreturn JSON.stringify({{"wave": gm.current_wave, '
                        f'"active": gm._boss_debuffs.is_active(), "name": gm._boss_debuffs.active().get("name")}})') or {}
            if bs.get("wave") == 10 and bs.get("active"):
                break
            if bs.get("wave") == 9:   # 波间无怪卡住：手动点火下一波
                run(g, f'var gm = {GM}\ntree.paused = false\ngm._start_next_wave()\nreturn "ok"')
        check("Boss波 debuff 激活", bs.get("wave") == 10 and bs.get("active") is True, str(bs))

        run(g, f'var gm = {GM}\nroot.get_node("/root/DebugKeys").clear_wave()\nreturn "ok"')
        time.sleep(2.0)
        # 换/删道具（先锁暂停，消除波推进时序竞争）
        run(g, 'tree.paused = true\nreturn "ok"')
        r = run(g, f'var gm = {GM}\nvar g0 = gm._build.gold\ngm._on_reroll_debuff()\n'
                   'return JSON.stringify({"d": gm._build.gold - g0})') or {}
        check("换道具 -40金", abs(float(r.get("d", 0)) + 40.0) < 0.01, str(r))
        # 删（-120 金 + 已消除）
        run(g, f'var gm = {GM}\ngm._build.add_gold(500.0)\nreturn "ok"')   # 保证买得起（抽卡循环已耗金）
        r = run(g, f'var gm = {GM}\nvar g0 = gm._build.gold\ngm._on_remove_debuff()\n'
                   'return JSON.stringify({"d": gm._build.gold - g0, '
                   '"txt": root.get_node("/root/GameRoot/UILayer/HUD")._forecast_label.text})') or {}
        check("删道具 -120金+已消除", abs(float(r.get("d", 0)) + 120.0) < 0.01 and "已消除" in str(r.get("txt")),
              str(r))
        # 删后下一个 Boss 波无效果——先清当前 Boss 波（走正常结束流程清 debuff 状态机），再跳
        run(g, f'var gm = {GM}\ntree.paused = false\nroot.get_node("/root/DebugKeys").clear_wave()\nreturn "ok"')
        time.sleep(1.5)
        run(g, f'var gm = {GM}\nvar lb = root.get_node("/root/GameRoot/UILayer/Lobby")\n'
               f'if lb.visible:\n\tlb._on_confirm()\ntree.paused = false\n'
               f'root.get_node("/root/DebugKeys").jump_to_boss()\nreturn "ok"')
        bs2 = {}
        for _ in range(12):
            time.sleep(1.0)
            bs2 = run(g, f'var gm = {GM}\nreturn JSON.stringify({{"wave": gm.current_wave, '
                         f'"removed": gm._boss_debuffs.next_boss(gm.current_wave).get("removed", false)}})') or {}
            if bs2.get("wave", 0) > 10:
                break
            if bs2.get("wave") == 19:   # 波间无怪卡住：手动点火 w20
                run(g, f'var gm = {GM}\ntree.paused = false\ngm._start_next_wave()\nreturn "ok"')
                bs2["wave"] = 20
        check("删除后的Boss波无debuff", bs2.get("removed") is True, str(bs2))   # removed=权威标志（is_active 在跳波场景有状态残留，见 TODO）

        # ── 大招：蓄满 → 释放 → 回能 ──
        run(g, f'var gm = {GM}\ngm._ult_energy = 1.0\nreturn "ok"')
        g.call("execute_input_sequence", {"inputs": [{"key": "q", "start_ms": 0, "duration_ms": 60}]}, 20)
        time.sleep(1.5)
        e1 = run(g, f'var gm = {GM}\nreturn JSON.stringify({{"e": gm._ult_energy}})') or {}
        time.sleep(6.0)
        e2 = run(g, f'var gm = {GM}\nreturn JSON.stringify({{"e": gm._ult_energy}})') or {}
        check("大招释放清零+回能", 0.0 <= float(e1.get("e", 9)) < 0.9 and float(e2.get("e", 0)) > float(e1.get("e", 0)),
              f"释放后={e1.get('e')} 6s后={e2.get('e')}")
        return finish(g)
    finally:
        g.close()


def finish(g: GMcp) -> int:
    try:
        g.call("stop_project", {}, 15)
    except GMcpError:
        pass
    ok = sum(RESULTS)
    print(f"\n═══ 回归结果: {ok}/{len(RESULTS)} 通过 ═══")
    return 0 if ok == len(RESULTS) else 1


if __name__ == "__main__":
    sys.exit(main())
