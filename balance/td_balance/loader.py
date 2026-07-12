"""YAML → dataclass 加载器。

把 data/*.yaml 读成 td_balance.schemas 的 dataclass，
供后续模块（抽取池/联动引擎）使用。B-1 仅加载 waves（曲线用）；
其余 schema 已定义但加载逻辑在 B-2 完善。

路径默认指向本包同级 ./data。
"""
from __future__ import annotations

from pathlib import Path

import yaml

from .curves import WaveParams
from .schemas import (
    AffixDef,
    BondDef,
    CostDef,
    EnemyCountCurve,
    EnemyHpCurve,
    IncomeDef,
    PathDef,
    RealmDef,
    SetDef,
    SetTier,
    SkillDef,
    SynergyDef,
    WaveConfig,
    WaveDurationCurve,
)

DATA_DIR = Path(__file__).resolve().parent.parent / "data"


def _load(name: str) -> dict:
    path = DATA_DIR / f"{name}.yaml"
    with path.open(encoding="utf-8") as f:
        return yaml.safe_load(f)


# ── waves ──（B-1 核心：curves.py 需要）

def load_wave_params() -> WaveParams:
    """从 data/waves.yaml 构造 WaveParams。"""
    d = _load("waves")
    hp = d["enemy_hp"]
    cnt = d["enemy_count"]
    dur = d["wave_duration"]
    boss = d["boss"]
    elite = d["elite"]
    mq = d["main_quest"]
    return WaveParams(
        hp_base=hp["base"],
        hp_growth=hp["growth"],
        count_base=cnt["base"],
        count_per_wave=cnt["per_wave"],
        duration_base=dur["base_seconds"],
        duration_per_wave=dur["per_wave_seconds"],
        boss_every_n=boss["every_n_waves"],
        boss_share=boss["total_hp_share"],
        elite_every_n=elite["every_n_waves"],
        main_quest_waves=mq["waves"],
    )


def load_wave_config() -> WaveConfig:
    """完整 WaveConfig（schemas），供需要原始结构的模块用。"""
    d = _load("waves")
    return WaveConfig(
        enemy_hp=EnemyHpCurve(**d["enemy_hp"]),
        enemy_count=EnemyCountCurve(**d["enemy_count"]),
        wave_duration=WaveDurationCurve(**d["wave_duration"]),
        boss_every_n=d["boss"]["every_n_waves"],
        boss_total_hp_share=d["boss"]["total_hp_share"],
        elite_every_n=d["elite"]["every_n_waves"],
        main_quest_waves=d["main_quest"]["waves"],
    )


# ── economy ──

def load_income() -> IncomeDef:
    d = _load("economy")["income"]
    return IncomeDef(**d)


def load_costs() -> CostDef:
    d = _load("economy")["costs"]
    return CostDef(**d)


# ── affixes ──

def load_affixes() -> list[AffixDef]:
    d = _load("affixes")
    return [
        AffixDef(
            id=a["id"],
            name=a["name"],
            rarity=a["rarity"],
            stacking=a["stacking"],
            effect=a.get("effect", {}),
            note=a.get("note", ""),
        )
        for a in d["affixes"]
    ]


def load_rarity_weights() -> dict[str, int]:
    return _load("affixes")["rarity_weights"]


# ── skills ──

def load_skills() -> list[SkillDef]:
    d = _load("skills")
    return [
        SkillDef(
            id=s["id"],
            name=s["name"],
            rarity=s["rarity"],
            tags=s.get("tags", []),
            atk_ratio=s.get("atk_ratio", 1.0),
            base_affixes=s.get("base_affixes", []),
            note=s.get("note", ""),
        )
        for s in d["skills"]
    ]


# ── bonds ──

def load_bonds() -> list[BondDef]:
    d = _load("bonds")
    return [
        BondDef(
            id=b["id"],
            name=b["name"],
            set=b["set"],
            effect=b.get("effect", {}),
        )
        for b in d["bonds"]
    ]


def load_sets() -> list[SetDef]:
    """旧：平铺套系（已弃用，保留兼容）。新逻辑用 load_paths()。"""
    # bonds.yaml 已重构为 paths；此函数返回空以防旧调用报错
    return []


def load_paths() -> list[PathDef]:
    """加载修炼路径（境界树）。"""
    d = _load("bonds")
    paths = []
    for p in d.get("paths", []):
        realms = [
            RealmDef(
                name=r["name"],
                bonds=r.get("bonds", []),
                reward=r.get("reward", {}),
                synergy_unlock=r.get("synergy_unlock", ""),
            )
            for r in p.get("realms", [])
        ]
        paths.append(PathDef(id=p["id"], name=p["name"], realms=realms))
    return paths


# ── synergies ──

def load_synergies() -> list[SynergyDef]:
    d = _load("synergies")
    return [
        SynergyDef(
            id=s["id"],
            name=s["name"],
            trigger=s.get("trigger", {}),
            effect=s.get("effect", {}),
            note=s.get("note", ""),
            tier=s.get("tier", ""),
        )
        for s in d["synergies"]
    ]
