"""run_sim_flags.py — run_sim 特征开关（报告脚本消融对比用）。"""
from __future__ import annotations

ENABLE_DEBUFF: bool = True   # Boss Debuff 建模（波 10/20/30 抽 3）
ENABLE_ULT: bool = True      # 大招建模（清屏 AOE ×8，随波次充能 20→35s）
