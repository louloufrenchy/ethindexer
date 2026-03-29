from __future__ import annotations

from .engine import TraceEngine
from .models import TraceQuery, TraceResult


class TracerService:
    def __init__(self, pool) -> None:
        self.engine = TraceEngine(pool)

    async def run(self, query: TraceQuery) -> TraceResult:
        return await self.engine.trace(query)
