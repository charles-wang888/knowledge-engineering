"""多LLM负载均衡提供者：轮询分发请求到多个后端，最大化利用多平台配额。"""
from __future__ import annotations

import itertools
import logging
import threading
from typing import Any

from .protocol import LLMProvider

_LOG = logging.getLogger(__name__)


class MultiProvider:
    """
    将多个 LLM Provider 组合为一个，请求按轮询（round-robin）分发。

    典型场景：Qwen Coding Plan（5小时）+ MiniMax Coding Plan（5小时），
    两者同时使用，吞吐量翻倍。

    用法::

        provider = MultiProvider([qwen_provider, minimax_provider])
        text = provider.generate(prompt)  # 自动轮询分发

    容错：某个 Provider 失败时自动切换到下一个，全部失败才抛异常。
    """

    def __init__(self, providers: list[LLMProvider], names: list[str] | None = None):
        if not providers:
            raise ValueError("MultiProvider: 至少需要一个 provider")
        self._providers = providers
        self._names = names or [f"provider-{i}" for i in range(len(providers))]
        self._cycle = itertools.cycle(range(len(providers)))
        self._lock = threading.Lock()
        self._call_counts = [0] * len(providers)

    def generate(self, prompt: str, **kwargs: Any) -> str:
        """轮询分发请求，失败时自动尝试下一个 Provider。"""
        with self._lock:
            start_idx = next(self._cycle)

        last_error: Exception | None = None
        for offset in range(len(self._providers)):
            idx = (start_idx + offset) % len(self._providers)
            provider = self._providers[idx]
            name = self._names[idx]
            try:
                result = provider.generate(prompt, **kwargs)
                with self._lock:
                    self._call_counts[idx] += 1
                return result
            except Exception as e:
                _LOG.warning("MultiProvider: %s 调用失败，尝试下一个: %s", name, e)
                last_error = e
                continue

        raise RuntimeError(
            f"MultiProvider: 所有 {len(self._providers)} 个 Provider 均失败"
        ) from last_error

    def stats(self) -> dict[str, int]:
        """返回每个 Provider 的调用次数。"""
        with self._lock:
            return {name: count for name, count in zip(self._names, self._call_counts)}
