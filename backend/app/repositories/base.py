"""Abstract persistence backend. Paths are slash-separated, Realtime-Database style."""
from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any


class PersistenceBackend(ABC):
    name: str = "abstract"

    @abstractmethod
    def load_all(self) -> dict[str, Any]:
        """Return the full tree (used at startup to restore state)."""

    @abstractmethod
    def apply(self, updates: dict[str, Any]) -> None:
        """Apply a multi-path update {path: value|None}. None deletes. Raises on failure."""

    @abstractmethod
    def health(self) -> dict[str, Any]:
        ...

    def flush(self) -> None:  # pragma: no cover - optional
        pass
