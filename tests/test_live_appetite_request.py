"""Exercise the camera loop and API handoff without opening a real camera."""

import os
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

import numpy as np
import torch

import byteTrack


class LiveAppetiteRequestTests(unittest.TestCase):
    def test_app_request_discards_partial_window_and_delivers_fresh_model_output(self):
        state = {"frames": 0, "requested": False}
        image = np.zeros((100, 200, 3), dtype=np.uint8)

        def read():
            state["frames"] += 1
            return True, image.copy()

        cap = Mock()
        cap.isOpened.return_value = True
        cap.read.side_effect = read
        cap.getBackendName.return_value = "MOCK"

        class Boxes:
            id = torch.tensor([1.])

            @property
            def xyxy(self):
                x = float(state["frames"])
                return torch.tensor([[x, 10., x + 10, 20.]])

            def __len__(self):
                return 1

        result = SimpleNamespace(boxes=Boxes(), plot=lambda: image.copy())
        detector = Mock()
        detector.track.return_value = [result]
        predictor = Mock()
        predictor.predict.return_value = ("LOW", 0.84)
        client = Mock()

        def take_request():
            if state["frames"] >= 10 and not state["requested"]:
                state["requested"] = True
                return {"id": "check-fresh"}
            return None

        client.take_request.side_effect = take_request
        delivered_at = []
        client.complete.side_effect = lambda *_: delivered_at.append(state["frames"])

        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as folder:
            model_path = Path(folder) / "model.joblib"
            model_path.touch()
            args = [
                "byteTrack.py", "--source", "1", "--backend", "msmf",
                "--model", str(model_path), "--rf-model", str(model_path),
                "--serve-appetite-checks", "--feature-output", str(Path(folder) / "features.csv"),
            ]
            with (
                patch("sys.argv", args),
                patch.dict(os.environ, {
                    "AQUASENSE_EDGE_DEVICE_ID": "c3d59aca-b28b-4fae-9a80-f37cb56ec8e9",
                    "AQUASENSE_EDGE_DEVICE_TOKEN": "test-token",
                }),
                patch("ultralytics.YOLO", return_value=detector),
                patch("live_behavior.AppetitePredictor", return_value=predictor),
                patch("appetite_check_client.AppetiteCheckClient", return_value=client),
                patch("byteTrack.perf_counter", side_effect=lambda: state["frames"] / 4),
                patch("cv2.VideoCapture", return_value=cap),
                patch("cv2.namedWindow"), patch("cv2.imshow"), patch("cv2.destroyAllWindows"),
                patch("cv2.getWindowProperty", return_value=1),
                patch("cv2.waitKey", side_effect=lambda _: ord("q") if state["frames"] >= 60 else 255),
                patch("builtins.print"),
            ):
                byteTrack.main()

        client.complete.assert_called_once()
        check_id, features = client.complete.call_args.args
        self.assertEqual(check_id, "check-fresh")
        self.assertEqual(features["sampled_frames"], 40)
        self.assertEqual(features["start_sec"], 0)
        self.assertEqual(features["predicted_appetite"], "LOW")
        self.assertEqual(features["prediction_confidence"], 0.84)
        self.assertEqual(delivered_at, [51])
        self.assertIn("check-fresh", features["session_id"])
        self.assertIn("observed_at_utc", features)
        client.close.assert_called_once()
        cap.release.assert_called_once()


if __name__ == "__main__":
    unittest.main()
