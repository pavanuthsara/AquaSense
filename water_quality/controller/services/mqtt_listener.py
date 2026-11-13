"""Optional MQTT ingestion (enable with `mqtt.enabled: true` in config.yaml).

Subscribes to e.g. `aquasense/+/readings`; the payload is the same JSON as
the REST endpoint. If the payload has no tank_id, it is taken from the topic.
Requires `pip install paho-mqtt` and a broker (e.g. `brew install mosquitto`).
"""
from __future__ import annotations

import json
import logging

from ..core.config import MqttConfig
from .ingest import IngestService

log = logging.getLogger("aquasense.mqtt")


class MqttListener:
    def __init__(self, cfg: MqttConfig, service: IngestService) -> None:
        import paho.mqtt.client as mqtt  # imported lazily: optional dependency

        self.cfg = cfg
        self.service = service
        self.client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
        self.client.on_connect = self._on_connect
        self.client.on_message = self._on_message

    def start(self) -> None:
        self.client.connect_async(self.cfg.host, self.cfg.port)
        self.client.loop_start()  # background thread
        log.info("MQTT connecting to %s:%s", self.cfg.host, self.cfg.port)

    def stop(self) -> None:
        self.client.loop_stop()
        self.client.disconnect()

    def _on_connect(self, client, userdata, flags, reason_code, properties):
        client.subscribe(self.cfg.topic)
        log.info("MQTT subscribed to %s (%s)", self.cfg.topic, reason_code)

    def _on_message(self, client, userdata, msg):
        try:
            payload = json.loads(msg.payload)
            parts = msg.topic.split("/")
            if "tank_id" not in payload and len(parts) >= 2:
                payload["tank_id"] = parts[1]
            self.service.ingest(payload)
        except Exception as exc:  # never let one bad message kill the listener
            log.error("bad MQTT message on %s: %s", msg.topic, exc)
