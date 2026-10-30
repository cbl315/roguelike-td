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

	# ── 弹道（4 种元素特效，28px）──
	for p in [
		"res://src/assets/effects/fx_projectile_physical.png",
		"res://src/assets/effects/fx_projectile_fire.png",
		"res://src/assets/effects/fx_projectile_ice.png",
		"res://src/assets/effects/fx_projectile_thunder.png",
	]:
		projectile_texs.append(_load_scaled(p, 32))

	# ── 普通敌人（5 种，50px）──
	for p in [
		"res://src/assets/enemies/enemy_grunt.png",
		"res://src/assets/enemies/enemy_runner.png",
		"res://src/assets/enemies/enemy_brute.png",
		"res://src/assets/enemies/enemy_shaman.png",
		"res://src/assets/enemies/enemy_frost_wraith.png",
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
