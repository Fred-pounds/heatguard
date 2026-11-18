"""Firebase Realtime Database backend (firebase-admin SDK).

Credentials are read from environment variables only:
  FIREBASE_CREDENTIALS   path to a service-account JSON file
  FIREBASE_DATABASE_URL  e.g. https://<project>-default-rtdb.<region>.firebasedatabase.app
Never commit the service-account file.

Local emulator (no credentials needed):
  FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9000
  FIREBASE_DATABASE_URL=http://127.0.0.1:9000?ns=demo-heatguard
"""
from __future__ import annotations

from typing import Any

from .base import PersistenceBackend


class FirebaseBackend(PersistenceBackend):
    name = "firebase_rtdb"

    def __init__(self, credentials_path: str | None, database_url: str, root: str = "/"):
        import os

        import firebase_admin
        from firebase_admin import credentials, db

        if not firebase_admin._apps:  # noqa: SLF001
            if credentials_path:
                firebase_admin.initialize_app(credentials.Certificate(credentials_path), {"databaseURL": database_url})
            elif os.getenv("FIREBASE_DATABASE_EMULATOR_HOST"):
                # The Admin SDK uses emulator credentials automatically when this variable is set.
                firebase_admin.initialize_app(options={"databaseURL": database_url, "projectId": "demo-heatguard"})
            else:
                raise ValueError("FIREBASE_CREDENTIALS is required unless FIREBASE_DATABASE_EMULATOR_HOST is set")
        self.emulator = bool(os.getenv("FIREBASE_DATABASE_EMULATOR_HOST"))
        self._db = db
        self._root = root.rstrip("/") or ""
        self._last_error: str | None = None

    def _ref(self, path: str = ""):
        full = f"{self._root}/{path.strip('/')}" if path else (self._root or "/")
        return self._db.reference(full or "/")

    def load_all(self) -> dict[str, Any]:
        data = self._ref().get()
        return data if isinstance(data, dict) else {}

    def apply(self, updates: dict[str, Any]) -> None:
        if not updates:
            return
        try:
            # Multi-path update is atomic in RTDB; None values delete.
            self._ref().update({k.strip("/"): v for k, v in updates.items()})
            self._last_error = None
        except Exception as exc:  # network / permission errors are queued by the caller
            self._last_error = str(exc)
            raise

    def health(self) -> dict[str, Any]:
        return {"backend": self.name + ("_emulator" if self.emulator else ""), "status": "error" if self._last_error else "ok",
                "last_error": self._last_error}
