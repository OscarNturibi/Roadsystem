"""
RoadSense v5 — Flask Backend (multi-variant edition)

Everything from v4, PLUS:
  - Support for multiple trained YOLOv8 variants (n/s/m), not just the
    single production "best.pt".
  - GET  /models         — list every available variant + its known metrics
  - POST /select_model   — switch which variant is actually used for /detect
  - /ping and /detect now report which variant is currently active

Why this exists: your lecturer asked you to justify why YOLOv8s was chosen
over n/s/m (and explain how YOLO detection works). This file makes that
comparison a LIVE, runnable part of your deployed system instead of a static
table in a notebook -- you can literally demo switching between n/s/m during
your viva and show the metrics for each, backed by your own trained weights.

Model files expected in MODEL_DIR (defaults to the current directory):
  best.pt                          -- production model: YOLOv8s, 50 epochs
                                       (this is what /detect uses by default)
  road_damage_yolov8n_e15.pt       -- comparison run: YOLOv8n, 15 epochs
  road_damage_yolov8s_e15.pt       -- comparison run: YOLOv8s, 15 epochs
  road_damage_yolov8m_e15.pt       -- comparison run: YOLOv8m, 15 epochs

These filenames match exactly what your training notebook (Section 9 +
Section 10) downloads. Drop whichever of them you have into MODEL_DIR --
missing files are simply left out of /models rather than causing an error.
"""

import base64
import json
import math
import os
import threading
import traceback
import uuid
from datetime import datetime

import cv2
import numpy as np
from flask import Flask, jsonify, request
from flask_cors import CORS
from ultralytics import YOLO

app = Flask(__name__)
CORS(app)

# ── MODEL REGISTRY ──────────────────────────────────────────────────────────
# One entry per variant you trained. "metrics" here are the numbers already
# measured in your training notebook (Section 6 for the production model,
# Section 10 for the n/s/m comparison) -- they're stored here so /models can
# answer instantly without re-running validation on every request.
# If you retrain and get different numbers, update them here to match.
MODEL_DIR = os.environ.get("MODEL_DIR", ".")

MODEL_REGISTRY = {
    "yolov8s_production": {
        "file": "best.pt",
        "variant": "s",
        "params_m": 11.1,
        "epochs_trained": 50,
        "metrics": {"precision": 0.677, "recall": 0.654, "map50": 0.695, "map50_95": 0.386},
        "description": "Production model -- full 50-epoch fine-tune on the merged RDD2022 + Kaggle pothole dataset. This is the deployed model.",
    },
    "yolov8n_comparison": {
        "file": "road_damage_yolov8n_e15.pt",
        "variant": "n",
        "params_m": 3.0,
        "epochs_trained": 15,
        "metrics": {"precision": 0.611, "recall": 0.598, "map50": 0.627, "map50_95": 0.335},
        "description": "Ablation run -- YOLOv8 nano, 15 epochs, same dataset. Fastest, lowest accuracy.",
    },
    "yolov8s_comparison": {
        "file": "road_damage_yolov8s_e15.pt",
        "variant": "s",
        "params_m": 11.1,
        "epochs_trained": 15,
        "metrics": {"precision": 0.651, "recall": 0.615, "map50": 0.654, "map50_95": 0.351},
        "description": "Ablation run -- YOLOv8 small, 15 epochs, same dataset. Best accuracy-per-parameter in the comparison.",
    },
    "yolov8m_comparison": {
        "file": "road_damage_yolov8m_e15.pt",
        "variant": "m",
        "params_m": 25.8,
        "epochs_trained": 15,
        "metrics": {"precision": 0.643, "recall": 0.614, "map50": 0.641, "map50_95": 0.344},
        "description": "Ablation run -- YOLOv8 medium, 15 epochs, same dataset. More than double the parameters of small, but LOWER mAP50 -- direct evidence of diminishing returns on this dataset size.",
    },
}

DEFAULT_MODEL_KEY = "yolov8s_production"

# ── ACTIVE MODEL STATE ──────────────────────────────────────────────────────
_model_lock = threading.Lock()
_active_key = None
model: YOLO | None = None  # currently loaded model, used by /detect


def _load_model(key: str) -> None:
    """Load MODEL_REGISTRY[key] into the global `model`, skipping the reload
    if it's already the active one. Raises FileNotFoundError with a clear
    message if the weights file isn't present in MODEL_DIR."""
    global model, _active_key

    if key not in MODEL_REGISTRY:
        raise KeyError(f"Unknown model key '{key}'. Available: {list(MODEL_REGISTRY.keys())}")

    if key == _active_key and model is not None:
        return  # already loaded, nothing to do

    entry = MODEL_REGISTRY[key]
    path = os.path.join(MODEL_DIR, entry["file"])
    if not os.path.exists(path):
        raise FileNotFoundError(
            f"'{entry['file']}' not found in MODEL_DIR ('{MODEL_DIR}'). "
            f"Download it from Section 9/10 of your training notebook and place it there, "
            f"or set MODEL_DIR to wherever it lives."
        )

    with _model_lock:
        model = YOLO(path)
        _active_key = key
    print(f"Loaded model '{key}' ({entry['file']}) -- {entry['description']}")


# Load the production model at startup so /detect works immediately.
_load_model(DEFAULT_MODEL_KEY)

# ── IN-MEMORY SESSION HISTORY ────────────────────────────────────────────────
scan_history: list[dict] = []
MAX_HISTORY = 50

# ── MODEL EVALUATION CONFIG (unchanged from v4) ──────────────────────────────
VAL_DATA_YAML = os.environ.get("VAL_DATA_YAML", "data.yaml")
EVAL_CACHE_FILE = "eval_cache.json"
_eval_cache: dict = {"result": None}

if os.path.exists(EVAL_CACHE_FILE):
    try:
        with open(EVAL_CACHE_FILE, "r") as f:
            _eval_cache["result"] = json.load(f)
        print(f"Loaded cached evaluation from {EVAL_CACHE_FILE} "
              f"(evaluated_at={_eval_cache['result'].get('evaluated_at')}) — "
              f"GET /evaluate?refresh=true to recompute.")
    except Exception:
        _eval_cache["result"] = None

_eval_lock = threading.Lock()
_eval_running = False


# ═══════════════════════════════════════════════════════════════════════════
#  HELPER FUNCTIONS (unchanged from v4)
# ═══════════════════════════════════════════════════════════════════════════

def compute_severity(area: float, confidence: float) -> str:
    adjusted = area * (0.7 + 0.6 * confidence)
    if adjusted < 6_000:
        return "Low"
    elif adjusted < 22_000:
        return "Medium"
    else:
        return "High"


def compute_health_score(detections: list[dict], image_area: int) -> int:
    if not detections:
        return 100
    penalty = 0
    for d in detections:
        weight = {"High": 1.8, "Medium": 1.0, "Low": 0.4}.get(d["severity"], 1.0)
        defect_ratio = d["area"] / max(image_area, 1)
        penalty += defect_ratio * weight * 100
    return max(0, math.floor(100 - penalty))


def build_summary(detections: list[dict]) -> dict:
    if not detections:
        return {"total": 0, "high": 0, "medium": 0, "low": 0,
                "dominant_class": None, "condition": "Good"}

    high   = sum(1 for d in detections if d["severity"] == "High")
    medium = sum(1 for d in detections if d["severity"] == "Medium")
    low    = sum(1 for d in detections if d["severity"] == "Low")

    class_counts: dict[str, int] = {}
    for d in detections:
        class_counts[d["class_name"]] = class_counts.get(d["class_name"], 0) + 1
    dominant = max(class_counts, key=class_counts.get)

    if high >= 2:
        condition = "Critical"
    elif high == 1 or medium >= 3:
        condition = "Poor"
    elif medium >= 1:
        condition = "Fair"
    else:
        condition = "Good"

    return {"total": len(detections), "high": high, "medium": medium, "low": low,
            "dominant_class": dominant, "condition": condition}


def _run_evaluation() -> dict:
    if not os.path.exists(VAL_DATA_YAML):
        raise FileNotFoundError(
            f"VAL_DATA_YAML points to '{VAL_DATA_YAML}' but that file doesn't exist "
            f"(checked relative to '{os.getcwd()}'). Set the VAL_DATA_YAML env var."
        )

    metrics = model.val(data=VAL_DATA_YAML, plots=True, verbose=False)
    names = model.names
    per_class = []
    for i, cls_idx in enumerate(metrics.box.ap_class_index.tolist()):
        per_class.append({
            "class_name": names[int(cls_idx)],
            "precision":  round(float(metrics.box.p[i]), 4),
            "recall":     round(float(metrics.box.r[i]), 4),
            "map50":      round(float(metrics.box.ap50[i]), 4),
            "map50_95":   round(float(metrics.box.ap[i]), 4),
        })

    overall = {
        "precision": round(float(metrics.box.mp), 4),
        "recall":    round(float(metrics.box.mr), 4),
        "map50":     round(float(metrics.box.map50), 4),
        "map50_95":  round(float(metrics.box.map), 4),
    }

    cm_b64 = None
    try:
        save_dir = str(metrics.save_dir)
        candidates = [
            os.path.join(save_dir, "confusion_matrix_normalized.png"),
            os.path.join(save_dir, "confusion_matrix.png"),
        ]
        cm_path = next((p for p in candidates if os.path.exists(p)), None)
        if cm_path:
            with open(cm_path, "rb") as f:
                cm_b64 = base64.b64encode(f.read()).decode("utf-8")
    except Exception:
        cm_b64 = None

    return {
        "overall": overall, "per_class": per_class, "confusion_matrix_b64": cm_b64,
        "num_classes": len(names), "evaluated_at": datetime.now().isoformat(),
        "data_yaml": VAL_DATA_YAML, "active_model": _active_key,
    }


# ═══════════════════════════════════════════════════════════════════════════
#  ROUTES
# ═══════════════════════════════════════════════════════════════════════════

@app.route("/")
def home():
    return jsonify({"message": "RoadSense v5 API running", "version": "5.0",
                     "active_model": _active_key})


# ── MODEL VARIANT MANAGEMENT (new in v5) ─────────────────────────────────────
@app.route("/models", methods=["GET"])
def list_models():
    """List every registered YOLOv8 variant, its known metrics, whether its
    weights file is actually present on disk, and which one is currently
    active for /detect. This is the live version of your comparison table."""
    out = []
    for key, entry in MODEL_REGISTRY.items():
        path = os.path.join(MODEL_DIR, entry["file"])
        out.append({
            "key": key,
            "variant": entry["variant"],
            "file": entry["file"],
            "params_m": entry["params_m"],
            "epochs_trained": entry["epochs_trained"],
            "metrics": entry["metrics"],
            "description": entry["description"],
            "available": os.path.exists(path),
            "active": key == _active_key,
        })
    return jsonify({"models": out, "active_model": _active_key})


@app.route("/select_model", methods=["POST"])
def select_model():
    """Switch the active model used by /detect.
    Body: {"key": "yolov8n_comparison"}  (use a key from GET /models)"""
    data = request.get_json(silent=True) or {}
    key = data.get("key")
    if not key:
        return jsonify({"error": "Missing 'key' in request body. See GET /models for valid keys."}), 400
    try:
        _load_model(key)
    except (KeyError, FileNotFoundError) as e:
        return jsonify({"error": str(e)}), 400
    return jsonify({"message": f"Active model switched to '{key}'", "active_model": _active_key})


# ── MAIN DETECTION ────────────────────────────────────────────────────────────
@app.route("/detect", methods=["POST"])
def detect():
    try:
        if "image" not in request.files:
            return jsonify({"error": "No image field in request"}), 400

        file = request.files["image"]
        raw = np.frombuffer(file.read(), np.uint8)
        img = cv2.imdecode(raw, cv2.IMREAD_COLOR)
        if img is None:
            return jsonify({"error": "Could not decode image"}), 400

        h, w = img.shape[:2]
        image_area = h * w

        lat    = float(request.form.get("lat",  -1.2864))
        lon    = float(request.form.get("lon",   36.8172))
        street = request.form.get("street", "Unknown Road")
        scan_id = str(uuid.uuid4())[:8].upper()

        # Confidence/IOU thresholds from the app's sliders. Previously these were
        # sent by the Flutter app but silently ignored server-side -- the sliders
        # had no real effect. Now actually applied to the YOLO call.
        conf = float(request.form.get("conf", 0.25))
        iou  = float(request.form.get("iou", 0.7))

        results = model(img, conf=conf, iou=iou, verbose=False)

        detections = []
        for r in results:
            for box in r.boxes:
                x1, y1, x2, y2 = box.xyxy[0].tolist()
                cls  = int(box.cls[0])
                conf = float(box.conf[0])
                area = int((x2 - x1) * (y2 - y1))
                sev  = compute_severity(area, conf)

                detections.append({
                    "id": str(uuid.uuid4())[:6], "class_id": cls,
                    "class_name": model.names[cls], "confidence": round(conf, 4),
                    "box": [round(x1), round(y1), round(x2), round(y2)],
                    "area": area, "severity": sev,
                    "timestamp": datetime.now().isoformat(),
                })

        health  = compute_health_score(detections, image_area)
        summary = build_summary(detections)

        result = {
            "scan_id": scan_id, "detections": detections,
            "image_width": w, "image_height": h,
            "health_score": health, "summary": summary,
            "model_used": _active_key,   # new in v5 -- know which variant produced this result
            "location": {"lat": lat, "lon": lon, "street": street},
            "scanned_at": datetime.now().isoformat(),
        }

        history_entry = {
            "scan_id": scan_id, "health_score": health, "summary": summary,
            "model_used": _active_key,
            "location": result["location"], "scanned_at": result["scanned_at"],
        }
        scan_history.append(history_entry)
        if len(scan_history) > MAX_HISTORY:
            scan_history.pop(0)

        return jsonify(result)

    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ── HISTORY / STATS / CLEAR (unchanged from v4) ──────────────────────────────
@app.route("/history", methods=["GET"])
def history():
    limit = min(int(request.args.get("limit", 20)), MAX_HISTORY)
    return jsonify({"history": list(reversed(scan_history[-limit:])), "total": len(scan_history)})


@app.route("/stats", methods=["GET"])
def stats():
    if not scan_history:
        return jsonify({"total_scans": 0, "avg_health": 100, "total_defects": 0,
                         "high_count": 0, "medium_count": 0, "low_count": 0,
                         "condition_dist": {"Good": 0, "Fair": 0, "Poor": 0, "Critical": 0}})

    total_scans   = len(scan_history)
    avg_health    = round(sum(s["health_score"] for s in scan_history) / total_scans, 1)
    total_defects = sum(s["summary"]["total"]  for s in scan_history)
    high_count    = sum(s["summary"]["high"]   for s in scan_history)
    medium_count  = sum(s["summary"]["medium"] for s in scan_history)
    low_count     = sum(s["summary"]["low"]    for s in scan_history)

    condition_dist: dict[str, int] = {"Good": 0, "Fair": 0, "Poor": 0, "Critical": 0}
    for s in scan_history:
        cond = s["summary"].get("condition", "Good")
        condition_dist[cond] = condition_dist.get(cond, 0) + 1

    return jsonify({"total_scans": total_scans, "avg_health": avg_health,
                     "total_defects": total_defects, "high_count": high_count,
                     "medium_count": medium_count, "low_count": low_count,
                     "condition_dist": condition_dist})


@app.route("/clear", methods=["POST"])
def clear_history():
    scan_history.clear()
    return jsonify({"message": "History cleared"})


# ── MODEL EVALUATION (unchanged from v4) ─────────────────────────────────────
@app.route("/evaluate", methods=["GET"])
def evaluate():
    global _eval_running
    refresh = request.args.get("refresh", "false").lower() == "true"

    if not refresh and _eval_cache["result"] is not None:
        return jsonify(_eval_cache["result"])

    if not _eval_lock.acquire(blocking=False):
        return jsonify({"error": "An evaluation is already running — this can take "
                                  "20-30+ minutes on CPU. Please wait for it to finish."}), 409

    try:
        _eval_running = True
        _eval_cache["result"] = _run_evaluation()
        try:
            with open(EVAL_CACHE_FILE, "w") as f:
                json.dump(_eval_cache["result"], f)
        except Exception:
            pass
        return jsonify(_eval_cache["result"])
    except Exception as e:
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500
    finally:
        _eval_running = False
        _eval_lock.release()


# ── HEALTH CHECK ──────────────────────────────────────────────────────────────
@app.route("/ping", methods=["GET"])
def ping():
    return jsonify({"status": "ok",
                     "model": MODEL_REGISTRY[_active_key]["file"],  # kept for the existing Settings screen
                     "active_model": _active_key,
                     "model_file": MODEL_REGISTRY[_active_key]["file"],
                     "history_count": len(scan_history)})


# ═══════════════════════════════════════════════════════════════════════════
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)