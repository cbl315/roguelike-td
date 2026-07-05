"""可种子化 RNG — 所有随机的统一入口。

设计目的（技术文档 §2.2 / §6）：
- 同一种子 → 同一随机序列 → bug 可复现、可做回放/异步排行/服务端校验续局。
- 提供"按权重抽取"等常用操作，供抽取池/刷新使用。

B-1 仅提供基础；B-2 抽取池会重度使用。
"""
from __future__ import annotations

import random
from collections.abc import Sequence


class RNG:
    """可种子化随机源。包装 random.Random，便于全局替换与测试注入。"""

    def __init__(self, seed: int | None = None) -> None:
        self.seed = seed
        self._r = random.Random(seed)

    def float(self) -> float:
        return self._r.random()

    def int(self, a: int, b: int) -> int:
        return self._r.randint(a, b)

    def choice(self, seq: Sequence):
        return self._r.choice(seq)

    def weighted_choice(self, items: Sequence, weights: Sequence[float]):
        """按权重选一个。weights 长度须与 items 一致。"""
        return self._r.choices(items, weights=weights, k=1)[0]

    def sample(self, population: Sequence, k: int):
        """无放回抽样 k 个。"""
        return self._r.sample(population, k)

    def shuffle(self, seq: list) -> None:
        self._r.shuffle(seq)

    def fork(self, label: str) -> "RNG":
        """派生子流（不同子系统用独立子种子，互不干扰）。
        用于：战斗随机、抽取随机、刷新随机分离。
        """
        sub_seed = hash((self.seed, label)) & 0xFFFFFFFF
        return RNG(sub_seed)
