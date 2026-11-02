# TODO

## 🎭 Boss 波设计与表演（2026-11-03 首版落地 ✅）
> 结构修正：原实现"Boss 波全场怪都带 Boss 标记"→ 唯一大 Boss（波总血×40%）+ 普通怪群（对齐模拟模型）。

- [x] Boss 出场演出：红色横幅大字 + 出场冲击波 + 大血条置顶（含 Boss 名）
- [x] Boss 专属行为：血<50% 狂暴（移速+40%/接触伤+50%/变红+红波）+ 周期召唤小怪（8s×2只）+ 环形弹幕（8向直线可躲避，狂暴后加速）
- [x] Boss 击杀演出：顿帧慢动作（_fb_kill_boss）+ 双金色冲击波 + HUD「★ BOSS 击杀 ★」
- [x] Boss 波视觉区分：暗红氛围层（波开始淡入/结束清除）
- [x] 数值：模拟侧 Boss AI 召唤宏观近似 ×1.08（曲线 growth 1.076 回调，整体 51.7%）

## 其他待办
- [x] 结算差距诊断（2026-11-03 ✅：DPS vs 需求差距 + 乘区短板建议×2）
- [ ] BGM 素材（SFX 36 个已齐，BGM 0 个）
- [ ] 美术尾巴：图集合并 + 移动端性能验证（M5.5）
- [ ] 服务端架构文档（M6 前另起：账号/云存档/排行榜/每日种子）
- [ ] iOS/Android 打包 + IAP/广告
- [ ] boss_debuffs.is_active() 跳波场景状态残留：波未正常结束就跳到下一 Boss 波时
      _active_idx 不清（removed 槽位读 is_active 仍 True）——正常游玩不触发，
      仅调试跳波/测试场景可见（regression 已改读 removed 权威标志）
- [ ] 发布流程：导出前移除 addons/godot_mcp + 对应 autoload（MCPGameBridge）
      ——插件在导出版是死代码（bridge 需编辑器 debugger 通路，无注入风险），
      但占体积且 autoload 指向需同步清理；建议做一次性 export 脚本
- [ ] game_manager 两处 `../UILayer/HUD|Lobby` 相对路径 → unique name（%HUD/%Lobby）
