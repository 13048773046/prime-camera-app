from __future__ import annotations

import time
from dataclasses import dataclass, field
from threading import Lock


@dataclass
class UsageState:
    day: str = ""
    deep_count: int = 0
    last_signature: str = ""
    last_request_at: float = 0.0


class CounterStore:
    def __init__(self, daily_limit: int, dedup_seconds: int):
        self.daily_limit = daily_limit
        self.dedup_seconds = dedup_seconds
        self._lock = Lock()
        self._states: dict[str, UsageState] = {}

    def _today(self) -> str:
        return time.strftime("%Y-%m-%d", time.localtime())

    def allow_deep(self, identity: str, signature: str) -> tuple[bool, str]:
        now = time.time()
        today = self._today()
        with self._lock:
            state = self._states.setdefault(identity, UsageState())
            if state.day != today:
                state.day = today
                state.deep_count = 0
                state.last_signature = ""
                state.last_request_at = 0.0

            if state.last_signature == signature and now - state.last_request_at < self.dedup_seconds:
                return False, "duplicate_request"
            if state.deep_count >= self.daily_limit:
                return False, "daily_limit_exceeded"

            state.deep_count += 1
            state.last_signature = signature
            state.last_request_at = now
            return True, "ok"

    def remaining_deep(self, identity: str) -> int:
        today = self._today()
        with self._lock:
            state = self._states.get(identity)
            if not state or state.day != today:
                return self.daily_limit
            return max(0, self.daily_limit - state.deep_count)
