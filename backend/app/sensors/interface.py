"""Abstract sensor input interface.

The backend depends only on this interface (and on the HTTP ingest endpoint),
never on the simulator directly. A future ESP32 station can either POST to
`/api/sensors/ingest` or be wrapped in a SensorSource implementation (e.g. an
MQTT subscriber) that returns readings from `poll()`.
"""
from __future__ import annotations

from abc import ABC, abstractmethod

from ..schemas.sensor import SensorReadingIn


class SensorSource(ABC):
    source_type: str = "abstract"

    def __init__(self, station_id: str, worksite_id: str):
        self.station_id = station_id
        self.worksite_id = worksite_id

    @abstractmethod
    def poll(self) -> list[SensorReadingIn]:
        """Return readings delivered since the previous poll (possibly empty)."""

    @abstractmethod
    def status(self) -> dict:
        ...
