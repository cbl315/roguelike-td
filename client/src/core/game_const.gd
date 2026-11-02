## game_const.gd — 全局游戏常量（SSOT）。
## 房间边界等核心几何此前在 6 个文件重复字面量——漏改一处即隐性 bug，
## 统一收口于此（静态访问：GameConst.ROOM_RECT，无需实例化）。
extends Node

## 房间边界（与 main.tscn RoomBorder 一致：80,80 → 2920,1920）
const ROOM_RECT := Rect2(80, 80, 2840, 1840)
