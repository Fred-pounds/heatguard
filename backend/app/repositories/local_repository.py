"""Local JSON-file backend used in demo mode when Firebase credentials are absent.

Mirrors the Realtime Database tree so data can later be imported into Firebase
(`firebase database:set / local_store.json`).
"""
from __future__ import annotations

import json
import os
import threading
from pathlib import Path
from typing import Any

from .base import PersistenceBackend


def set_path(tree: dict, path: str, value: Any) -> None:
    parts = [p for p in path.strip("/").split("/") if p]
    node = tree
    for p in parts[:-1]:
        nxt = node.get(p)
        if not isinstance(nxt, dict):
            if value is None:
                return
            nxt = node[p] = {}
        node = nxt
    if value is None:
        node.pop(parts[-1], None)
    else:
        node[parts[-1]] = value


class LocalJsonBackend(PersistenceBackend):
    name = "local_json"

    def __init__(self, path: str):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._tree: dict = {}
        self._lock = threading.Lock()
        self._dirty = False
        if self.path.exists():
            try:
                self._tree = json.loads(self.path.read_text(encoding="utf-8") or "{}")
            except json.JSONDecodeError:
                self._tree = {}

    def load_all(self) -> dict[str, Any]:
        with self._lock:
            return json.loads(json.dumps(self._tree))

    def apply(self, updates: dict[str, Any]) -> None:
        with self._lock:
            for path, value in updates.items():
                set_path(self._tree, path, json.loads(json.dumps(value)) if value is not None else None)
            self._dirty = True

    def flush(self) -> None:
        with self._lock:
            if not self._dirty:
                return
            tmp = self.path.with_suffix(".tmp")
            tmp.write_text(json.dumps(self._tree), encoding="utf-8")
            os.replace(tmp, self.path)
            self._dirty = False

    def reset(self) -> None:
        with self._lock:
            self._tree = {}
            self._dirty = True

    def health(self) -> dict[str, Any]:
        return {"backend": self.name, "status": "ok", "path": str(self.path)}
