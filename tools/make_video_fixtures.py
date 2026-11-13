"""Generate parity fixtures for the Dart video white-spot pipeline (DIS-012).

The Dart pipeline (DIS-013..015) must give the same answers as the reference
script `video_check/check_video.py`. This script runs that script's real
`FishFinder` and `SpotModel` on a few frames of one clip and saves their exact
inputs and outputs, so the Dart code can be tested against the real thing.

Run (PowerShell, from the repo root):
  python tools/make_video_fixtures.py "C:\\path\\to\\clip.mp4"

Outputs go to mobile_app/test/fixtures/video_parity/. No video file is written.

Needs: opencv-python(-headless), numpy, and a TFLite runtime
(ai-edge-litert or tensorflow), same as check_video.py.
"""
import argparse
import json
import os
import subprocess
import sys

import cv2
import numpy as np

# --- locate the reference script and the real model files -------------------
VIDEO_CHECK_DIR = r"C:\Users\starg\Downloads\Research new\video_check"
MODELS_DIR = r"C:\Users\starg\Downloads\Research new\All models data notebooks\1_models"
FISH_MODEL = os.path.join(MODELS_DIR, "fish_finder_2026-10-19", "fish_detector.tflite")
SPOT_MODEL = os.path.join(MODELS_DIR, "video_model_v5_2026-10-19_CURRENT", "guppy_video_model.tflite")
SPOT_LABELS = os.path.join(MODELS_DIR, "video_model_v5_2026-10-19_CURRENT", "labels_video.txt")

sys.path.insert(0, VIDEO_CHECK_DIR)
from check_video import FishFinder, SpotModel, PAD, MIN_FISH_PX  # noqa: E402

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(REPO_ROOT, "mobile_app", "test", "fixtures", "video_parity")
FRAME_TIMES_S = [1.0, 3.0, 5.0]


def letterbox_det_input(finder, frame_bgr):
    """Replicate FishFinder.__call__ preprocessing, returning the BGR letterbox
    image (so cv2.imwrite stores the model's RGB input) and the raw model
    output normalised to (5, N)."""
    H, W = frame_bgr.shape[:2]
    s = finder.size / max(H, W)
    nh, nw = int(round(H * s)), int(round(W * s))
    img = np.full((finder.size, finder.size, 3), 114, np.uint8)
    top, left = (finder.size - nh) // 2, (finder.size - nw) // 2
    img[top:top + nh, left:left + nw] = cv2.resize(frame_bgr, (nw, nh))
    x = cv2.cvtColor(img, cv2.COLOR_BGR2RGB).astype(np.float32)[None] / 255.0
    if finder.nchw:
        x = x.transpose(0, 3, 1, 2)
    finder.it.set_tensor(finder.inp["index"], x)
    finder.it.invoke()
    p = finder.it.get_tensor(finder.out["index"])[0]
    if p.shape[0] > p.shape[1]:
        p = p.T  # normalise to (5, N)
    return img, p.astype(np.float32)


def letterbox_crop_input(spot, crop_bgr):
    """Replicate SpotModel.__call__ preprocessing, returning the BGR letterbox
    image and the raw float probs, white-spot score and not_fish flag."""
    h, w = crop_bgr.shape[:2]
    s = spot.size / max(h, w)
    nh, nw = max(1, int(round(h * s))), max(1, int(round(w * s)))
    img = np.zeros((spot.size, spot.size, 3), np.uint8)
    top, left = (spot.size - nh) // 2, (spot.size - nw) // 2
    img[top:top + nh, left:left + nw] = cv2.resize(crop_bgr, (nw, nh), interpolation=cv2.INTER_AREA)
    x = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)[None].astype(spot.inp["dtype"])
    spot.it.set_tensor(spot.inp["index"], x)
    spot.it.invoke()
    probs = spot.it.get_tensor(spot.out["index"])[0].astype(np.float32)
    q = spot.out["quantization"]
    if spot.out["dtype"] == np.uint8:
        probs = (probs - q[1]) * q[0]
    not_fish = spot.notfish is not None and int(probs.argmax()) == spot.notfish
    score = float(probs[spot.spot] / max(1e-6, probs[spot.spot] + probs[spot.healthy]))
    return img, probs, score, not_fish


def grab_frame(cap, t_s):
    cap.set(cv2.CAP_PROP_POS_MSEC, t_s * 1000.0)
    ok, frame = cap.read()
    if not ok:
        raise SystemExit(f"Could not read a frame at {t_s}s")
    return frame


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    args = ap.parse_args()
    os.makedirs(OUT_DIR, exist_ok=True)

    finder = FishFinder(FISH_MODEL)
    spot = SpotModel(SPOT_MODEL, SPOT_LABELS)

    cap = cv2.VideoCapture(args.video)
    try:
        cap.set(cv2.CAP_PROP_ORIENTATION_AUTO, 1.0)
    except Exception:
        pass
    if not cap.isOpened():
        raise SystemExit(f"Could not open {args.video}")

    manifest = {
        "clip": os.path.basename(args.video),
        "labels": spot.labels,
        "frame_times_s": FRAME_TIMES_S,
        "frames": [],
    }

    for k, t in enumerate(FRAME_TIMES_S, start=1):
        frame = grab_frame(cap, t)
        H, W = frame.shape[:2]
        cv2.imwrite(os.path.join(OUT_DIR, f"frame_{k}.png"), frame)

        det_bgr, raw = letterbox_det_input(finder, frame)
        cv2.imwrite(os.path.join(OUT_DIR, f"det_input_{k}.png"), det_bgr)
        raw.tofile(os.path.join(OUT_DIR, f"det_output_{k}.bin"))

        boxes = finder(frame)  # final decoded + NMS boxes in video pixels
        with open(os.path.join(OUT_DIR, f"boxes_{k}.json"), "w") as f:
            json.dump([[int(x0), int(y0), int(x1), int(y1), round(float(sc), 6)]
                       for (x0, y0, x1, y1, sc) in boxes], f, indent=1)

        crops = []
        for j, (x0, y0, x1, y1, conf) in enumerate(boxes):
            small = min(x1 - x0, y1 - y0) < MIN_FISH_PX
            if small:
                crops.append({"j": j, "box": [x0, y0, x1, y1], "too_small": True})
                continue
            pw, ph = (x1 - x0) * PAD, (y1 - y0) * PAD
            cx0, cy0 = max(0, int(x0 - pw)), max(0, int(y0 - ph))
            cx1, cy1 = min(W, int(x1 + pw)), min(H, int(y1 + ph))
            crop_bgr = frame[cy0:cy1, cx0:cx1]
            crop_img, probs, score, not_fish = letterbox_crop_input(spot, crop_bgr)
            cv2.imwrite(os.path.join(OUT_DIR, f"crop_input_{k}_{j}.png"), crop_img)
            crops.append({
                "j": j,
                "box": [x0, y0, x1, y1],
                "crop_box": [cx0, cy0, cx1, cy1],
                "probs": [round(float(v), 6) for v in probs],
                "white_spot_score": round(float(score), 6),
                "not_fish": bool(not_fish),
                "too_small": False,
            })
        with open(os.path.join(OUT_DIR, f"crops_{k}.json"), "w") as f:
            json.dump(crops, f, indent=1)

        manifest["frames"].append({"k": k, "time_s": t, "width": W, "height": H,
                                   "det_rows": int(raw.shape[0]), "det_cols": int(raw.shape[1]),
                                   "box_count": len(boxes)})
        print(f"frame {k} (t={t}s, {W}x{H}): {len(boxes)} boxes")

    cap.release()
    with open(os.path.join(OUT_DIR, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1)

    # --- full-run parity: check_video.py over the whole clip --------------
    tmp = os.path.join(OUT_DIR, "_run")
    os.makedirs(tmp, exist_ok=True)
    proc = subprocess.run(
        [sys.executable, os.path.join(VIDEO_CHECK_DIR, "check_video.py"), args.video,
         "--no-video", "--out-dir", tmp,
         "--model", SPOT_MODEL, "--labels", SPOT_LABELS, "--fish-model", FISH_MODEL],
        capture_output=True, text=True)
    stdout = proc.stdout
    print(stdout)
    if proc.returncode != 0:
        print(proc.stderr, file=sys.stderr)

    # copy the _checked.csv next to the fixtures
    csv_src = None
    for fn in os.listdir(tmp):
        if fn.endswith("_checked.csv"):
            csv_src = os.path.join(tmp, fn)
    if csv_src:
        with open(csv_src) as f:
            csv_text = f.read()
        with open(os.path.join(OUT_DIR, "checked.csv"), "w", newline="") as f:
            f.write(csv_text)

    # parse the per-fish and video answers from stdout
    fish_answers = []
    overall = None
    for line in stdout.splitlines():
        line = line.strip()
        if line.startswith("fish ") and ":" in line:
            # "fish   1: white spot  average white spot score 0.82 over 9 frames"
            head, rest = line.split(":", 1)
            fid = int(head.split()[1])
            verdict = rest.strip().split("  ")[0].strip()
            fish_answers.append({"fish": fid, "answer": verdict})
        if line.startswith("Video answer:"):
            overall = line.split("Video answer:", 1)[1].strip()
    with open(os.path.join(OUT_DIR, "expected_answers.json"), "w") as f:
        json.dump({"video_answer": overall, "fish": fish_answers}, f, indent=1)

    # clean the temp run dir (keep only checked.csv copy)
    for fn in os.listdir(tmp):
        os.remove(os.path.join(tmp, fn))
    os.rmdir(tmp)

    print("\nWrote fixtures to", OUT_DIR)
    print("video_answer:", overall)
    for fa in fish_answers:
        print("  fish", fa["fish"], "->", fa["answer"])


if __name__ == "__main__":
    main()
