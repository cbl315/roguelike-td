## event_bus.gd — 全局事件总线（autoload 单例）
## 所有跨系统通信走这里（解耦）。M0 只声明信号；M1+ 系统发射、UI 订阅。
##
## 用法：
##   EventBus.enemy_killed.connect(_on_enemy_killed)
##   EventBus.enemy_killed.emit(enemy)
extends Node


# ── 波次 / 战斗 ──
signal wave_started(wave: int)
signal wave_cleared(wave: int)
signal enemy_killed(enemy: Node)
signal enemy_reached_core(enemy: Node, damage: float)
signal core_hp_changed(hp: float, max_hp: float)
signal run_won()
signal run_lost(death_wave: int)

# ── 经济 ──
signal gold_changed(gold: float)
signal income_received(amount: float, source: String)

# ── Rogue 构筑大厅 ──
signal lobby_entered(wave: int)             # 进入波次间大厅
signal choice_presented(offers: Array)      # 3 选 1
signal choice_made(offer)                    # 玩家选了某项

# ── 羁绊 / 境界 ──
signal bond_drawn(bond_id: String)
signal bond_devoured(path_id: String, realm_idx: int, realm_name: String)   # 境界提升
signal path_maxed(path_id: String)          # 修满顶级境界

# ── 联动 ──
signal synergy_triggered(synergy_id: String)

# ── 大招（手动，GDD §11）──
signal ult_energy_changed(ratio: float)     # 0..1
signal ult_activated()

# ── Boss debuff（GDD §12）──
signal boss_debuff_revealed(debuff_id: String, next_boss_wave: int)
signal debuff_rerolled(new_debuff_id: String)
signal debuff_removed()
