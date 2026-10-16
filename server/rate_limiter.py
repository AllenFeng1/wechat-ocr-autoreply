"""频率限制 + 活跃时段判断（内存实现，重启清零，个人使用足够）。"""
from __future__ import annotations

import time
from collections import defaultdict, deque
from datetime import datetime


class RateLimiter:
    def __init__(self, max_per_hour: int, max_per_day: int, min_interval_seconds: int) -> None:
        self.max_per_hour = max_per_hour
        self.max_per_day = max_per_day
        self.min_interval = min_interval_seconds
        self._events: dict[str, deque[float]] = defaultdict(deque)

    def _trim(self, key: str, now: float) -> deque[float]:
        q = self._events[key]
        day_ago = now - 86400
        while q and q[0] < day_ago:
            q.popleft()
        return q

    def allow(self, device_id: str) -> tuple[bool, str]:
        """返回 (是否允许, 拒绝原因)。"""
        now = time.time()
        q = self._trim(device_id, now)
        if q and now - q[-1] < self.min_interval:
            return False, "min_interval"
        if sum(1 for t in q if t > now - 3600) >= self.max_per_hour:
            return False, "hourly_limit"
        if len(q) >= self.max_per_day:
            return False, "daily_limit"
        q.append(now)
        return True, ""

    def count_today(self, device_id: str) -> int:
        now = time.time()
        return sum(1 for t in self._trim(device_id, now) if t > now - 86400)


def in_active_hours(start: int, end: int, now: datetime | None = None) -> bool:
    now = now or datetime.now()
    hour = now.hour
    if start <= end:
        return start <= hour <= end
    return hour >= start or hour <= end  # 跨午夜
