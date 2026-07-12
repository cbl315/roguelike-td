## test_synergy.gd — 客户端联动引擎测试（Godot headless 可跑）
## 用法: godot --headless --path client -s tests/test_synergy.gd
##
## 注意：技能系统已重构。联动现在统一走 bond_devoured_set（修满体系），
## 不再有 skill_owned / skill_tag 条件；九秘已改为羁绊（zt_jm_*）。
extends SceneTree


const _ZHUTIAN_DEVOURED := [
	"zt_lunhai_daojing", "zt_lunhai_kuhai", "zt_lunhai_mingquan", "zt_lunhai_shenqiao",
	"zt_daogong_heart", "zt_daogong_liver", "zt_daogong_spleen", "zt_daogong_lung", "zt_daogong_kidney",
	"zt_siji_left_arm", "zt_siji_right_arm", "zt_siji_left_leg", "zt_siji_right_leg",
	"zt_hualong_spine_1", "zt_hualong_spine_2", "zt_hualong_spine_3",
	"zt_xiantai_zhandao", "zt_xiantai_saint", "zt_xiantai_dasheng",
	"zt_zhundi_tribulation", "zt_zhundi_curse_break",
	"zt_dadi_dao", "zt_dadi_cauldron", "zt_dadi_busiyao", "zt_dadi_diershi", "zt_dadi_xianlu",
	"zt_hongchen_nihuo", "zt_hongchen_zikhan", "zt_hongchen_jiqu", "zt_hongchen_xian",
	"zt_tiandi_wandao", "zt_tiandi_quan", "zt_tiandi_duduan", "zt_tiandi",
	# 九秘羁绊（zt_jm_*）也算遮天体系的羁绊
	"zt_jm_jie", "zt_jm_dou", "zt_jm_xing", "zt_jm_bing", "zt_jm_zu", "zt_jm_qian", "zt_jm_lin", "zt_jm_zhe", "zt_jm_shu",
]


func _init():
	print("========================================")
	print("  客户端联动引擎测试")
	print("========================================")

	# 用 load 显式加载，避免 -s 模式下类解析问题
	var BuildStateScript: Resource = load("res://src/systems/build_state.gd")
	var RoguePoolsScript: Resource = load("res://src/core/rogue_pools.gd")

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pools: Object = RoguePoolsScript.new(rng)
	var build: Object = BuildStateScript.new()
	build.setup(pools, rng)

	var passed := 0
	var failed := 0

	# ── 测试 1：未修满体系 → 联动不触发 ──
	print("\n[测试1] 未修满体系 → 无联动")
	build.path_realm = {"zhutian": 3}   # 只修完 3 境，未修满（共 9 境）
	build.bond_pool = []
	build.devoured_bonds = _ZHUTIAN_DEVOURED.slice(0, 10)
	build.assemble_stats()
	if build.active_synergies.is_empty():
		print("  ✅ PASS: 无联动触发")
		passed += 1
	else:
		print("  ❌ FAIL: 不该有联动，但有 %d 条" % build.active_synergies.size())
		failed += 1

	# ── 测试 2：修满遮天 → 天帝之拳 / 九秘合一 ──
	print("\n[测试2] 修满遮天 → 天帝之拳 (final_dmg_mult) / 九秘合一")
	build.path_realm = {"zhutian": 9}   # 9 境全满 = bond_devoured_set:zhutian 成立
	build.bond_pool = []
	build.devoured_bonds = _ZHUTIAN_DEVOURED.duplicate()
	var stats2: Object = build.assemble_stats()
	if _has_synergy(build, "zhutian_emperor_fist") and _has_synergy(build, "zhutian_nine_secrets"):
		print("  ✅ PASS: 天帝之拳 + 九秘合一触发, final_mult=%.2f" % _final_mult(stats2))
		passed += 1
	else:
		_print_active(build)
		print("  ❌ FAIL: 联动未触发")
		failed += 1

	# ── 测试 3：修满遮天 + 装备词条 → 天帝雷罚 ──
	print("\n[测试3] 修满遮天 + 装备词条(synergy_amp) → 天帝雷罚 (final +200%)")
	build.path_realm = {"zhutian": 9}
	build.bond_pool = []
	build.devoured_bonds = _ZHUTIAN_DEVOURED.duplicate()
	var stats3: Object = build.assemble_stats()
	if _has_synergy(build, "emperor_thunder_judgment"):
		print("  ✅ PASS: 天帝雷罚触发, final_mult=%.2f" % _final_mult(stats3))
		passed += 1
	else:
		_print_active(build)
		print("  ❌ FAIL: 天帝雷罚未触发")
		failed += 1

	# ── 测试 4：Bug回归 — 吞噬后联动仍触发（不丢失）──
	print("\n[测试4] Bug回归: 吞噬后联动仍触发")
	build.path_realm = {"zhutian": 9}
	build.bond_pool = []  # 全部吞噬了，池为空
	build.devoured_bonds = _ZHUTIAN_DEVOURED.duplicate()
	var stats4: Object = build.assemble_stats()
	if _has_synergy(build, "zhutian_emperor_fist"):
		print("  ✅ PASS: 联动在吞噬后仍触发")
		passed += 1
	else:
		print("  ❌ FAIL: 吞噬后联动丢失")
		failed += 1

	# ── 测试 5：Bug回归 — 无体系修满时无联动触发 ──
	print("\n[测试5] Bug回归: 无体系修满时无联动触发")
	build.path_realm = {}
	build.bond_pool = ["zt_saint_body"]
	build.devoured_bonds = []
	build.assemble_stats()
	if build.active_synergies.is_empty():
		print("  ✅ PASS: 无体系修满时无联动触发")
		passed += 1
	else:
		_print_active(build)
		print("  ❌ FAIL: 不该有联动触发")
		failed += 1

	# ── 总结 ──
	print("\n========================================")
	print("  结果: %d passed, %d failed" % [passed, failed])
	if failed == 0:
		print("  🎉 全部通过！")
	else:
		print("  ⚠️ 有 %d 个失败" % failed)
	print("========================================")
	quit()


func _has_synergy(build: Object, sid: String) -> bool:
	for syn in build.active_synergies:
		if syn.get("id") == sid:
			return true
	return false


func _final_mult(stats: Object) -> float:
	var result := 1.0
	for x in stats.final_dmg_mults:
		result *= (1.0 + float(x))
	return result


func _print_active(build: Object) -> void:
	var ids: Array = []
	for syn in build.active_synergies:
		ids.append(syn.get("id"))
	print("  (已触发: %s)" % str(ids))
