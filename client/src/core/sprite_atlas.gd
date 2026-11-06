## sprite_atlas.gd — 精灵贴图集中加载器（autoload 单例 "SpriteAtlas"）。
## 所有美术资源在此预加载 + 按目标尺寸缩放，实体通过属性/getter 取用。
## 原始贴图 1024×1024，缩放后缓存为 ImageTexture（1:1 绘制，避免实时缩放开销）。
extends Node

# ── 缓存：避免重复加载同一张图 ──
var _cache: Dictionary = {}   # "path@size" → ImageTexture

# ── 预加载贴图引用 ──
var hero_tex: Texture2D = null
var summon_moxie_tex: Texture2D = null
var summon_baiyanmeng_tex: Texture2D = null
# 第三魂宠三选一（VFX 资源批次 2026-11）
var summon_third_texs: Dictionary = {}   # third_dragon/third_flower/third_wind → Texture2D
# Boss 立绘（HUD 大血条用）+ 狂暴态
var boss_portrait_texs: Dictionary = {}  # boss 贴图索引 → portrait 立绘
var boss_enraged_texs: Dictionary = {}   # boss 贴图索引 → 狂暴立绘
# 大招特效（四体系）
var ult_fx_texs: Dictionary = {}         # zhutian/xingchenbian/chongmei/doupo → Texture2D
# 弹道 t2/t3（伤害等级升级视觉）
var projectile_t2_texs: Array[Texture2D] = []
# VFX 资源批次二（光环/徽章/状态帧/背景）
var aura_circle_texs: Dictionary = {}
var aura_hero_texs: Array[Texture2D] = []
var aura_pet_texs: Array[Texture2D] = []
var realm_badge_texs: Array[Texture2D] = []
var devour_ring_tex: Texture2D = null
var enemy_hit_texs: Dictionary = {}
var enemy_death_texs: Dictionary = {}
var bg_texs: Dictionary = {}
var effect_icon_texs: Dictionary = {}   # effect key → 词条图标
var debuff_icon_texs: Dictionary = {}   # debuff id → 图标
var particle_texs: Array[Texture2D] = []

# 弹道贴图（4 种元素，随机选取增加视觉多样性）
var projectile_texs: Array[Texture2D] = []

# 敌人贴图池
var _normal_enemy_texs: Array[Texture2D] = []   # 5 种普通怪
var _elite_enemy_texs: Array[Texture2D] = []    # 2 种精英
var _boss_enemy_texs: Array[Texture2D] = []     # 3 种 Boss


func _ready() -> void:
	# ── 角色 ──
	hero_tex = _load_scaled("res://src/assets/characters/hero_sword_cultivator.png", 88)
	summon_moxie_tex = _load_scaled("res://src/assets/characters/summon_moxie.png", 68)
	summon_baiyanmeng_tex = _load_scaled("res://src/assets/characters/summon_baiyanmeng.png", 68)

	# ── 行为怪贴图（远程=萨满 / 分裂=冰魂 / 奶妈=蛮兵）──
	_kind_texs["ranged"] = _load_scaled("res://src/assets/enemies/enemy_shaman.png", 52)
	_kind_texs["splitter"] = _load_scaled("res://src/assets/enemies/enemy_frost_wraith.png", 52)
	_kind_texs["healer"] = _load_scaled("res://src/assets/enemies/enemy_brute.png", 58)

	# ── 弹道（4 种元素特效，28px）──
	for p in [
		"res://src/assets/effects/fx_projectile_physical.png",
		"res://src/assets/effects/fx_projectile_fire.png",
		"res://src/assets/effects/fx_projectile_ice.png",
		"res://src/assets/effects/fx_projectile_thunder.png",
	]:
		projectile_texs.append(_load_scaled(p, 32))

	# ── 普通追击怪（2 种；shaman/frost_wraith/brute 已专属行为怪，避免视觉混淆）──
	for p in [
		"res://src/assets/enemies/enemy_grunt.png",
		"res://src/assets/enemies/enemy_runner.png",
	]:
		_normal_enemy_texs.append(_load_scaled(p, 52))

	# ── 精英敌人（用 brute/shaman 放大，76px）──
	_elite_enemy_texs.append(_load_scaled("res://src/assets/enemies/enemy_brute.png", 76))
	_elite_enemy_texs.append(_load_scaled("res://src/assets/enemies/enemy_shaman.png", 76))

	# ── Boss（3 种，150px）──
	for p in [
		"res://src/assets/enemies/boss_blind_eye.png",
		"res://src/assets/enemies/boss_regen_core.png",
		"res://src/assets/enemies/boss_immortal_body.png",
	]:
		_boss_enemy_texs.append(_load_scaled(p, 150))

	# ── 第三魂宠（三选一，68px）──
	summon_third_texs["third_dragon"] = _load_scaled("res://src/assets/characters/summon_dragonlet.png", 68)
	summon_third_texs["third_flower"] = _load_scaled("res://src/assets/characters/summon_flower_king.png", 68)
	summon_third_texs["third_wind"] = _load_scaled("res://src/assets/characters/summon_wind_binder.png", 68)

	# ── Boss 立绘/狂暴态（HUD 大血条 + 狂暴切换）──
	var boss_keys := ["blind_eye", "regen_core", "immortal_body"]
	for i in range(boss_keys.size()):
		boss_portrait_texs[i] = _load_scaled("res://src/assets/enemy_states/boss_%s_portrait.png" % boss_keys[i], 96)
		boss_enraged_texs[i] = _load_scaled("res://src/assets/enemy_states/boss_%s_enraged.png" % boss_keys[i], 96)

	# ── 大招特效（四体系，300px）──
	for pid in ["zhutian", "xingchenbian", "chongmei", "doupo"]:
		ult_fx_texs[pid] = _load_scaled("res://src/assets/effects/fx_ult_%s.png" % pid, 300)

	# ── 弹道 t2（伤害等级升级，36px）──
	for p in [
		"res://src/assets/effects/fx_projectile_physical_t2.png",
		"res://src/assets/effects/fx_projectile_fire_t2.png",
		"res://src/assets/effects/fx_projectile_ice_t2.png",
		"res://src/assets/effects/fx_projectile_thunder_t2.png",
	]:
		projectile_t2_texs.append(_load_scaled(p, 36))

	# ── 光环（体系色圈/英雄t1-3/宠物t1-3，VFX 资源批次二）──
	aura_circle_texs = {
		"zhutian": _load_scaled("res://src/assets/auras/aura_circle_zhutian.png", 120),
		"xingchenbian": _load_scaled("res://src/assets/auras/aura_circle_xingchenbian.png", 120),
		"chongmei": _load_scaled("res://src/assets/auras/aura_circle_chongmei.png", 120),
		"doupo": _load_scaled("res://src/assets/auras/aura_circle_doupo.png", 120),
		"generic_fusion": _load_scaled("res://src/assets/auras/aura_circle_generic.png", 120),
	}
	for i in range(3):
		aura_hero_texs.append(_load_scaled("res://src/assets/auras/aura_hero_t%d.png" % (i + 1), 110))
		aura_pet_texs.append(_load_scaled("res://src/assets/auras/aura_pet_t%d.png" % (i + 1), 80))

	# ── 境界徽章（t1-t4）+ 吞噬进度环 ──
	for i in range(4):
		realm_badge_texs.append(_load_scaled("res://src/assets/auras/badge_realm_t%d.png" % (i + 1), 44))
	devour_ring_tex = _load_scaled("res://src/assets/auras/ring_devour_progress.png", 90)

	# ── 敌人受击/死亡帧（5 种敌人）──
	var kinds5 := ["grunt", "runner", "shaman", "frost_wraith", "brute"]
	for k in kinds5:
		enemy_hit_texs[k] = _load_scaled("res://src/assets/enemy_states/enemy_%s_hit.png" % k, 56)
		enemy_death_texs[k] = _load_scaled("res://src/assets/enemy_states/enemy_%s_death.png" % k, 56)

	# ── 战斗背景（3 张：普通/Boss/高境）──
	bg_texs = {
		"arena": _load_scaled("res://src/assets/bg/bg_battle_arena.png", 1024),
		"dungeon": _load_scaled("res://src/assets/bg/bg_dungeon.png", 1024),
		"heaven": _load_scaled("res://src/assets/bg/bg_heaven_realm.png", 1024),
	}

	# ── 词条效果图标（15 张：effect key → 图标，卡面/角色面板用）──
	var eff_icons := {
		"atk_pct_delta": "skill_attack_speed", "crit_rate_delta": "skill_crit_rate",
		"crit_dmg_delta": "skill_crit_dmg", "attack_speed_delta": "skill_attack_speed",
		"magic_dmg_pct_delta": "skill_magic_dmg", "physical_dmg_pct_delta": "skill_phys_dmg",
		"final_dmg_mult": "skill_final_dmg", "armor_pen_delta": "skill_armor_pen",
		"true_dmg_pct_delta": "skill_true_dmg", "lifesteal_pct": "skill_lifesteal",
		"damage_reduction_delta": "skill_dmg_reduce", "hp_pct_delta": "skill_dmg_reduce",
		"pet_atk_pct_delta": "skill_multishot", "projectile_delta": "skill_multishot",
		"all_stats_pct_delta": "skill_final_dmg",
	}
	for k in eff_icons.keys():
		effect_icon_texs[k] = _load_scaled("res://src/assets/skills/%s.png" % eff_icons[k], 24)

	# ── Boss debuff 图标（17 张：debuff id → 图标，预告条/横幅用）──
	for db in ["armor_break", "blind_eye", "bond_suppress", "counter_force", "crit_shatter",
			"gold_phage", "haste_order", "healing_seal", "immortal_body", "immovable",
			"magic_resist", "mirror_armor", "phys_resist", "regen_core", "sealed_hand",
			"single_shot", "ult_seal"]:
		debuff_icon_texs[db] = _load_scaled("res://src/assets/debuffs/debuff_%s.png" % db, 32)

	# ── 粒子贴图（4 张：击杀爆发随机）──
	for pn in ["blood_drop", "debris_stone", "energy_shard", "soul_flame"]:
		particle_texs.append(_load_scaled("res://src/assets/particles/particle_%s.png" % pn, 20))

# ── 新资源访问器 ──
func get_third_pet_tex(unit_id: String) -> Texture2D:
	return summon_third_texs.get(unit_id)

func get_boss_portrait_tex(index: int, enraged: bool = false) -> Texture2D:
	var d: Dictionary = boss_enraged_texs if enraged else boss_portrait_texs
	return d.get(index % max(d.size(), 1))

func get_ult_fx_tex(path_id: String) -> Texture2D:
	return ult_fx_texs.get(path_id)

func get_aura_circle(path_id: String) -> Texture2D:
	return aura_circle_texs.get(path_id)

func get_aura_hero(tier: int) -> Texture2D:
	return aura_hero_texs[clampi(tier - 1, 0, aura_hero_texs.size() - 1)] if not aura_hero_texs.is_empty() else null

func get_aura_pet(tier: int) -> Texture2D:
	return aura_pet_texs[clampi(tier - 1, 0, aura_pet_texs.size() - 1)] if not aura_pet_texs.is_empty() else null

func get_realm_badge(tier: int) -> Texture2D:
	return realm_badge_texs[clampi(tier - 1, 0, realm_badge_texs.size() - 1)] if not realm_badge_texs.is_empty() else null

func get_devour_ring() -> Texture2D:
	return devour_ring_tex

func get_enemy_hit_tex(kind_key: String) -> Texture2D:
	return enemy_hit_texs.get(kind_key)

func get_enemy_death_tex(kind_key: String) -> Texture2D:
	return enemy_death_texs.get(kind_key)

func get_effect_icon(effect_key: String) -> Texture2D:
	return effect_icon_texs.get(effect_key)

func get_debuff_icon(debuff_id: String) -> Texture2D:
	return debuff_icon_texs.get(debuff_id)

func get_particle_tex(rng: RandomNumberGenerator) -> Texture2D:
	if particle_texs.is_empty():
		return null
	return particle_texs[rng.randi() % particle_texs.size()]

func get_bg(key: String) -> Texture2D:
	return bg_texs.get(key)

func get_projectile_t2_tex(rng: RandomNumberGenerator) -> Texture2D:
	if projectile_t2_texs.is_empty():
		return null
	return projectile_t2_texs[rng.randi() % projectile_t2_texs.size()]


## 加载并缩放贴图（缓存按 path+size 组合）。
func _load_scaled(path: String, target_size: int) -> Texture2D:
	var key: String = "%s@%d" % [path, target_size]
	if _cache.has(key):
		return _cache[key]
	var orig: Texture2D = load(path)
	if orig == null:
		push_error("SpriteAtlas: 无法加载 %s" % path)
		return null
	var img: Image = orig.get_image()
	if img == null:
		push_error("SpriteAtlas: 无法获取图像 %s" % path)
		return null
	img.resize(target_size, target_size, Image.INTERPOLATE_LANCZOS)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## 随机取一个弹道贴图
func get_projectile_tex(rng: RandomNumberGenerator) -> Texture2D:
	if projectile_texs.is_empty():
		return null
	return projectile_texs[rng.randi() % projectile_texs.size()]


## 随机取一个普通敌人贴图
func get_normal_enemy_tex(rng: RandomNumberGenerator) -> Texture2D:
	if _normal_enemy_texs.is_empty():
		return null
	return _normal_enemy_texs[rng.randi() % _normal_enemy_texs.size()]


## 按行为类型取贴图（远程=萨满施法者 / 分裂=冰魂 / 奶妈=蛮兵）
func get_enemy_tex_by_kind(kind: int) -> Texture2D:
	match kind:
		Enemy.Kind.RANGED:
			return _kind_texs.get("ranged")
		Enemy.Kind.SPLITTER:
			return _kind_texs.get("splitter")
		Enemy.Kind.HEALER:
			return _kind_texs.get("healer")
	return null


var _kind_texs: Dictionary = {}


## 随机取一个精英敌人贴图
func get_elite_enemy_tex(rng: RandomNumberGenerator) -> Texture2D:
	if _elite_enemy_texs.is_empty():
		return null
	return _elite_enemy_texs[rng.randi() % _elite_enemy_texs.size()]


## 按 index 取 Boss 贴图（每波循环，给不同 Boss 视觉差异）
func get_boss_enemy_tex(index: int) -> Texture2D:
	if _boss_enemy_texs.is_empty():
		return null
	return _boss_enemy_texs[index % _boss_enemy_texs.size()]
