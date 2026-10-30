# Godot 美术 + 特效实现规划

> 状态：已批准，开始落地。
> 现状：游戏 100% 程序化绘制（色块/几何），零美术资源在用。
> 分 5 个阶段，按优先级推进。每阶段独立可运行。

---

## 阶段 1：精灵替换（色块 → 美术立绘）

**目标**：hero/enemy/summon/projectile 从 `draw_circle` 色块替换为精灵贴图。

**原则**：有贴图则 `draw_texture()`，无贴图 fallback 到 `draw_circle()`。

### 1.1 实体贴图替换

| 实体 | 贴图 | 尺寸 | 改动文件 |
|------|------|------|----------|
| 英雄 | `assets/characters/hero_idle.png` | 128×128 | hero.gd `_draw()` |
| 敌人(普通) | `assets/enemies/enemy_normal.png` | 96×96 | enemy.gd `_draw()` |
| 敌人(精英) | `assets/enemies/enemy_elite.png` | 96×96 | enemy.gd |
| 敌人(Boss) | `assets/enemies/enemy_boss.png` | 128×128 | enemy.gd |
| 召唤·莫邪 | `assets/characters/summon_moxie.png` | 64×64 | summon_unit.gd |
| 召唤·白魇魔 | `assets/characters/summon_baiyanmeng.png` | 64×64 | summon_unit.gd |
| 弹道 | `assets/effects/projectile_default.png` | 32×32 | projectile.gd |

### 1.2 实现方式

每个实体的 `_draw()` 开头：
```gdscript
var tex := preload("res://src/assets/xxx.png")  # 或 load() 带缓存
if tex:
    var tex_size := tex.get_size()
    draw_texture(tex, -tex_size / 2)  # 居中绘制
    # HP 环、拖尾等叠加效果继续用 draw_arc/draw_circle
else:
    draw_circle(Vector2.ZERO, radius, color)  # fallback
```

### 1.3 HP 环 / 拖尾 / 爆裂保留
- HP 环（hero/enemy）：继续 `_draw()` 叠加在贴图上方
- 拖尾（projectile）：继续 `_draw()` 在贴图后面画
- 爆裂（enemy 死亡）：继续 `_draw()` 放大圆环

---

## 阶段 2：羁绊卡面（文字 → 美术卡片）

**目标**：lobby 卡片从纯文字 StyleBox 改为带卡面贴图。

### 2.1 按 set 出卡框（4 张通用背景）
- `assets/ui/card_frame_zhutian.png`（金紫色调）
- `assets/ui/card_frame_xingchenbian.png`（蓝白色调）
- `assets/ui/card_frame_chongmei.png`（橙红色调）
- `assets/ui/card_frame_generic.png`（灰色调）

### 2.2 lobby.gd `_make_card()` 改动
- Panel 顶部加 `TextureRect`（卡框背景，按 bond.set 选择）
- 文字信息（name/rarity/desc）用 Label 叠加在卡框上

---

## 阶段 3：UI 美化（原生控件 → 主题皮肤）

### 3.1 Theme 资源（.tres）
- 字体：加载中文 .ttf（思源黑体/阿里巴巴普惠体）
- 按钮样式：NinePatch（normal/hover/pressed 3 态）
- 面板背景：NinePatch

### 3.2 血条
- ProgressBar 自定义纹理：hp_bar_bg.png + hp_bar_fill.png

### 3.3 背景
- ColorRect → TextureRect（bg_battle.png）

### 3.4 素材清单
| 素材 | 文件 | 数量 |
|------|------|------|
| 字体 | `assets/fonts/cn_font.ttf` | 1 |
| 按钮 3 态 | `assets/ui/btn_normal/hover/pressed.png` | 3 |
| 血条 | `assets/ui/hp_bar_bg/fill.png` | 2 |
| 背景 | `assets/bg/bg_battle.png` | 1 |

---

## 阶段 4：特效系统（手写 → 粒子+Tween+Shader）

### 4.1 GPUParticles2D

| 特效 | 触发 | 参数 |
|------|------|------|
| 命中爆发 | projectile 命中敌人 | 8-12 粒子，径向，0.3s |
| 死亡爆裂 | enemy 死亡 | 16 粒子，扩散，0.5s |
| 暴击溅射 | 暴击命中 | 金色粒子，10 粒子 |
| 元素特效 | 火/冰/雷属性命中 | 对应色粒子 |

### 4.2 Tween 动画
- 弹道发射器微缩放（开火反馈）
- 敌人受击晃动
- 召唤单位出现/消失淡入淡出
- Toast 弹窗（替换 `_process` 计时器）

### 4.3 Shader
- 受击闪白（.gdshader）
- 无敌帧闪烁
- 半魔化变身色调

### 4.4 素材
- `assets/effects/particle_spark.png`（通用火花）
- `assets/effects/particle_circle.png`（圆形粒子）

---

## 阶段 5：进阶视觉（按需做）

- 召唤单位精灵动画（idle/attack 多帧 AnimatedSprite2D）
- 英雄行走动画（4 方向 AnimatedSprite2D）
- Boss 登场动画（缩放+震动 Tween）
- 突破演出（AI 插画 + 文字旁白）
- 伤害飘字（DamageNumber 场景）

---

## 目录结构

```
client/src/assets/
├── characters/
│   ├── hero_idle.png
│   ├── summon_moxie.png
│   └── summon_baiyanmeng.png
├── enemies/
│   ├── enemy_normal.png
│   ├── enemy_elite.png
│   └── enemy_boss.png
├── effects/
│   ├── projectile_default.png
│   └── particle_spark.png
├── ui/
│   ├── card_frame_*.png
│   ├── btn_*.png
│   └── hp_bar_*.png
├── bg/
│   └── bg_battle.png
└── fonts/
    └── cn_font.ttf
```

## 落地顺序

1. ✅ **阶段 1**（精灵替换）— 视觉提升最大
2. **阶段 3**（UI 美化）— 改善整体观感
3. **阶段 2**（羁绊卡面）— 数据驱动
4. **阶段 4**（特效系统）— 技术含量最高
5. **阶段 5**（进阶）— 持续迭代
