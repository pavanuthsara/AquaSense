"""Device-authenticated polling for app-requested appetite measurements.

Networking runs off the camera thread so slow API requests do not stall tracking.
"""

import json
import queue
import threading
from datetime import datetime, timezone
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def result_payload(features):
    if features.get("prediction_status") != "PREDICTED":
        return {
            "status": "INSUFFICIENT_DATA",
            "message": "Not enough fish movement was tracked. Keep the camera steady and try again.",
        }
    return {
        "status": "COMPLETED",
        "appetiteResult": features["predicted_appetite"],
        "confidence": round(float(features["prediction_confidence"]), 4),
        "modelVersion": "random_forest_live_pre-v1",
        "observedAt": features["observed_at_utc"],
        "message": "Before-feeding estimate from the current research model.",
    }


class AppetiteCheckClient:
    def __init__(self, api_base_url, device_id, device_token):
        self.base_url = api_base_url.rstrip("/")
        self.headers = {
            "X-Device-Id": device_id,
            "X-Device-Token": device_token,
            "Content-Type": "application/json",
        }
        self.requests = queue.Queue(maxsize=1)
        self.results = queue.Queue(maxsize=1)
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self._run, name="appetite-check-api", daemon=True)

    def start(self):
        self.thread.start()

    def close(self):
        self.stop.set()
        self.thread.join(timeout=4)
        # Best effort delivery if capture failed just before shutdown.
        try:
            check_id, payload = self.results.get_nowait()
            self._request(f"/api/v1/device-appetite-checks/{check_id}/result", payload)
        except (queue.Empty, OSError, URLError, ValueError):
            pass

    def take_request(self):
        try:
            return self.requests.get_nowait()
        except queue.Empty:
            return None

    def complete(self, check_id, features):
        self.results.put_nowait((check_id, result_payload(features)))

    def fail(self, check_id):
        self.results.put_nowait((check_id, {
            "status": "FAILED", "message": "Camera processing stopped. Reconnect the camera and try again.",
        }))

    def _request(self, path, payload=None):
        request = Request(
            self.base_url + path,
            headers=self.headers,
            data=None if payload is None else json.dumps(payload).encode("utf-8"),
            method="GET" if payload is None else "POST",
        )
        with urlopen(request, timeout=3) as response:
            return None if response.status == 204 else json.load(response)

    def _run(self):
        active = None
        outgoing = None
        last_error = None
        while not self.stop.is_set():
            try:
                if outgoing is None:
                    try:
                        outgoing = self.results.get_nowait()
                    except queue.Empty:
                        pass
                if outgoing is not None:
                    check_id, payload = outgoing
                    self._request(f"/api/v1/device-appetite-checks/{check_id}/result", payload)
                    outgoing = None
                    active = None
                if active is not None:
                    expiry = datetime.fromisoformat(active["expiresAt"].replace("Z", "+00:00"))
                    if datetime.now(timezone.utc) >= expiry:
                        active = None
                if active is None:
                    pending = self._request("/api/v1/device-appetite-checks/next")
                    if pending is not None:
                        self.requests.put_nowait(pending)
                        active = pending
                last_error = None
            except HTTPError as error:
                if outgoing is not None and error.code in (400, 404, 409):
                    outgoing = None
                    active = None
                message = f"Appetite API returned HTTP {error.code}. Check backend/device configuration."
                if message != last_error:
                    print(message)
                    last_error = message
            except (OSError, URLError, ValueError, queue.Full):
                message = "Appetite API unavailable; retrying. Check the backend connection."
                if message != last_error:
                    print(message)
                    last_error = message
            self.stop.wait(1)
