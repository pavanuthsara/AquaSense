import threading
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import Mock

from appetite_check_client import AppetiteCheckClient, result_payload


class AppetiteCheckClientTests(unittest.TestCase):
    def test_result_uses_model_label_probability_and_observation_time(self):
        features = {
            "prediction_status": "PREDICTED", "predicted_appetite": "LOW",
            "prediction_confidence": 0.876543, "observed_at_utc": "2026-10-22T10:00:00+00:00",
        }
        payload = result_payload(features)
        self.assertEqual(payload["appetiteResult"], "LOW")
        self.assertEqual(payload["confidence"], 0.8765)
        self.assertEqual(payload["observedAt"], features["observed_at_utc"])

    def test_insufficient_data_does_not_send_a_fake_label(self):
        payload = result_payload({"prediction_status": "INSUFFICIENT_DATA"})
        self.assertEqual(payload["status"], "INSUFFICIENT_DATA")
        self.assertNotIn("appetiteResult", payload)

    def test_background_polling_delivers_request_and_submits_its_matching_result(self):
        client = AppetiteCheckClient("http://localhost:8080", "device", "secret")
        delivered = threading.Event()
        calls = []
        check = {"id": "check-1", "expiresAt": (datetime.now(timezone.utc) + timedelta(seconds=60)).isoformat()}

        def api(path, payload=None):
            calls.append((path, payload))
            if payload is not None:
                delivered.set()
                return {"status": "INSUFFICIENT_DATA"}
            return check if len(calls) == 1 else None

        client._request = api
        client.start()
        try:
            incoming = client.requests.get(timeout=3)
            self.assertEqual(incoming["id"], "check-1")
            client.complete(incoming["id"], {"prediction_status": "INSUFFICIENT_DATA"})
            self.assertTrue(delivered.wait(timeout=3))
            self.assertEqual(calls[1][0], "/api/v1/device-appetite-checks/check-1/result")
        finally:
            client.close()

    def test_camera_failure_is_delivered_during_shutdown(self):
        client = AppetiteCheckClient("http://localhost:8080", "device", "secret")
        client._request = Mock(return_value=None)
        client.start()
        client.fail("check-2")
        client.close()
        result_calls = [call for call in client._request.call_args_list if len(call.args) == 2]
        self.assertEqual(result_calls[0].args[0], "/api/v1/device-appetite-checks/check-2/result")
        self.assertEqual(result_calls[0].args[1]["status"], "FAILED")


if __name__ == "__main__":
    unittest.main()
