# RoadSense — Smart Road Defect Detection and Analysis System

RoadSense detects road damage — cracks and potholes — from a single photo, using a YOLOv8
model fine-tuned on a merged public dataset. Detections are scored for severity, rolled up
into a 0–100 road health score, and served to a Flutter mobile app through a Flask REST API.

Built as a final-year project, this repository contains the full pipeline end to end:
dataset preparation, model training and comparison, the deployed API, and the mobile client.

## Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Repository Structure](#repository-structure)
- [Dataset](#dataset)
- [Model](#model)
- [Backend Setup](#backend-setup)
- [Running the API](#running-the-api)
- [API Reference](#api-reference)
- [Mobile App Setup](#mobile-app-setup)
- [Training Pipeline](#training-pipeline)
- [Results](#results)
- [Known Limitations](#known-limitations)
- [Roadmap](#roadmap)
- [Acknowledgements](#acknowledgements)
- [License](#license)

## Overview

**Problem.** Manual road inspection is slow, inconsistent, and hard to scale — defects go
unreported until they're already a hazard.

**Approach.** A single photo, taken on foot, from a vehicle, or by drone, is run through a
fine-tuned YOLOv8 model that detects and classifies four defect types. The backend converts
raw detections into something actionable: a severity rating per defect (based on both size
and model confidence) and an overall road health score for the image, then makes that
available to a mobile app for logging, mapping, and reporting.

**Key design decision.** The model is served from one central Flask API rather than bundled
into the mobile app. This keeps the app lightweight, lets the model be upgraded independently
of app releases, and allows any client (not just this Flutter app) to use the same endpoint.

## Architecture

![RoadSense architecture — training pipeline and runtime system](docs/architecture.png)

- **Model layer** — YOLOv8s, fine-tuned via transfer learning from COCO-pretrained weights
- **API layer** — Flask, handles inference, severity scoring, health-score calculation,
  session history, and live model evaluation
- **Client layer** — Flutter app, handles capture/upload, result display, history, analytics,
  and reporting UI

## Repository Structure

```
roadsystem/
├── api.py                                         # Flask REST API
├── build_dataset.py                                # Merges RDD2022 + Kaggle into one YOLO dataset
├── requirements.txt                                # Python dependencies
├── RoadDamage_YOLOv8_Pipeline_Commented (1).ipynb   # Full training pipeline (Google Colab)
├── .gitignore                                      # Python/backend ignores
├── mobileapp/                                      # Flutter mobile application
│   ├── lib/
│   │   ├── main.dart
│   │   ├── screens/                                # UI screens (detect, map, reports, analytics, ...)
│   │   ├── services/                                # API client, location, server discovery
│   │   ├── theme/
│   │   └── widgets/
│   ├── android/
│   ├── ios/
│   ├── pubspec.yaml
│   └── .gitignore                                  # Flutter/Dart-specific ignores
└── docs/
    └── project_report.docx                          # Full project report
```

> **Not included in this repo** (excluded via `.gitignore` — see below): trained model
> weights (`.pt`), raw/merged datasets, and generated training artifacts. These regenerate
> from the training notebook, or download pretrained weights as described under
> [Model](#model).

## Dataset

Two public datasets, merged into one YOLO-format training set:

| Source | Images | Format | Notes |
|---|---|---|---|
| [RDD2022 (United States)](https://github.com/sekilab/RoadDamageDetector) | 4,805 | Pascal VOC XML | 3 crack classes |
| [Kaggle Annotated Potholes](https://www.kaggle.com/datasets/chitholian/annotated-potholes-dataset) | 665 | Pascal VOC XML | Pothole-only, mapped to class D40 |
| **Merged total** | **5,470** | YOLO `.txt` | 80/20 split, applied per source before merging |

**Class distribution after merge:**

| Class | Code | Description | Train | Val |
|---|---|---|---|---|
| 0 | D00 | Longitudinal crack | 5,417 | 1,333 |
| 1 | D10 | Transverse crack | 2,657 | 638 |
| 2 | D20 | Alligator crack | 674 | 160 |
| 3 | D40 | Pothole | 1,502 | 373 |

**Final split:** 4,376 training images, 1,094 validation images — verified with zero images
missing a corresponding label file.

Datasets are not committed to this repo (too large for git). To rebuild:
1. Download RDD2022 (United States subset) from the link above
2. Download the Kaggle Annotated Potholes dataset
3. Run `build_dataset.py`, or Sections 2–5 of the training notebook, to convert annotations
   and produce the merged, split dataset

## Model

- **Architecture:** YOLOv8s (11.1M parameters)
- **Training:** 50 epochs, image size 640, batch size 16, Tesla T4 GPU (Google Colab)
- **Method:** Transfer learning — initialized from COCO-pretrained weights, fully fine-tuned
  (no frozen layers), detection head reconfigured from 80 COCO classes to the 4 classes above
- **Why YOLOv8s specifically:** compared against nano, small, and medium at equal training
  budget (15 epochs each, same dataset) — small gave the best accuracy; medium scored *lower*
  than small despite 2x+ the parameters, indicating the dataset size had already reached its
  useful capacity ceiling (see [Results](#results))

Trained weights (`best.pt`) are excluded from this repo via `.gitignore`. Either:
- Retrain using the notebook (Sections 6–9), or
- Download pretrained weights: `[add your Drive/Hugging Face link here]`

## Backend Setup

**Requirements:** Python 3.10+

```bash
git clone https://github.com/OscarNturibi/Roadsystem.git
cd Roadsystem

python -m venv venv
venv\Scripts\activate        # Windows
source venv/bin/activate     # macOS/Linux

pip install -r requirements.txt
```

Place your trained `best.pt` in the project root (see [Model](#model) for how to get one).

## Running the API

```bash
python api.py
```

Runs on `http://0.0.0.0:5000` by default.

**Environment variables (optional):**

| Variable | Purpose | Default |
|---|---|---|
| `MODEL_DIR` | Folder containing weights files | `.` (project root) |
| `VAL_DATA_YAML` | Path to dataset `data.yaml`, needed for `/evaluate` | `data.yaml` |

## API Reference

| Endpoint | Method | Description |
|---|---|---|
| `/` | GET | API status and currently active model |
| `/detect` | POST | Upload an image, get back detections + severity + health score |
| `/models` | GET | Lists every registered YOLOv8 variant and its known metrics |
| `/select_model` | POST | Switches which trained variant `/detect` uses |
| `/evaluate` | GET | Runs (or returns cached) validation metrics + confusion matrix |
| `/history` | GET | Recent scan history (session-based) |
| `/stats` | GET | Aggregate statistics across recent scans |
| `/clear` | POST | Clears scan history |
| `/ping` | GET | Health check |

### Example: `POST /detect`

```bash
curl -X POST http://localhost:5000/detect \
  -F "image=@road_photo.jpg" \
  -F "conf=0.25" \
  -F "iou=0.7" \
  -F "lat=-1.2864" \
  -F "lon=36.8172" \
  -F "street=Kenyatta Avenue"
```

**Response (abridged):**

```json
{
  "scan_id": "A1B2C3D4",
  "detections": [
    {
      "class_name": "D40",
      "confidence": 0.812,
      "box": [120, 340, 410, 560],
      "severity": "High"
    }
  ],
  "health_score": 62,
  "summary": { "total": 1, "high": 1, "medium": 0, "low": 0, "condition": "Poor" },
  "model_used": "yolov8s_production"
}
```

### Example: `GET /models`

Returns every trained variant with its known metrics — this is what powers the in-app model
switcher and the ablation study documented in the project report:

```json
{
  "models": [
    { "key": "yolov8s_production", "variant": "s", "epochs_trained": 50,
      "metrics": { "map50": 0.695, "map50_95": 0.386 }, "active": true },
    { "key": "yolov8n_comparison", "variant": "n", "epochs_trained": 15,
      "metrics": { "map50": 0.627 }, "active": false }
  ]
}
```

## Mobile App Setup

**Requirements:** Flutter SDK (stable channel), Android Studio (with Flutter/Dart plugins)
or VS Code (with the Flutter extension)

1. Open `mobileapp/` in Android Studio (or VS Code)
2. Fetch dependencies:
   ```bash
   cd mobileapp
   flutter pub get
   ```
3. Point the app at your running Flask API — in `lib/services/api_service.dart` (or the
   server-discovery config), set the base URL to your machine's **LAN IP**, not `localhost`
   (the phone/emulator can't resolve your computer's `localhost` as itself):
   ```dart
   static const String baseUrl = "http://192.168.x.x:5000";
   ```
4. Run:
   ```bash
   flutter run
   ```
   or select a device and click **Run** in Android Studio.

The Flask API must be running and reachable on the same network as the device for the app
to function.

## Training Pipeline

The full pipeline is in `RoadDamage_YOLOv8_Pipeline_Commented (1).ipynb`, built to run on
Google Colab with a GPU runtime:

| Section | What it does |
|---|---|
| 1 | Install libraries |
| 2 | Download & convert RDD2022 annotations |
| 3 | Download & convert Kaggle pothole annotations |
| 4 | Merge both sources into one dataset (80/20 split per source) |
| 5 | Verify dataset integrity (label matching, class counts) |
| 6 | Train YOLOv8s — 50 epochs |
| 7 | Evaluate — confusion matrix, PR curve, precision/recall/mAP |
| 8 | Run inference on held-out test images |
| 9 | Download trained weights |
| 10 | Compare YOLOv8 variants (n/s/m ablation study) |

## Results

**Production model (YOLOv8s, 50 epochs):**

| Metric | All classes | D00 | D10 | D20 | D40 |
|---|---|---|---|---|---|
| Precision | 0.677 | 0.700 | 0.658 | 0.635 | 0.715 |
| Recall | 0.654 | 0.720 | 0.611 | 0.651 | 0.633 |
| mAP50 | 0.695 | 0.761 | 0.651 | 0.667 | 0.702 |
| mAP50-95 | 0.386 | 0.449 | 0.312 | 0.360 | 0.423 |

**Variant comparison (15 epochs each, identical dataset/conditions):**

| Variant | Params | Precision | Recall | mAP50 | mAP50-95 |
|---|---|---|---|---|---|
| YOLOv8n | 3.0M | 0.611 | 0.598 | 0.627 | 0.335 |
| **YOLOv8s** | **11.1M** | **0.651** | **0.615** | **0.654** | **0.351** |
| YOLOv8m | 25.8M | 0.643 | 0.614 | 0.641 | 0.344 |

YOLOv8s outperformed both nano and medium — medium's lower score despite more than double the
parameters of small is evidence the ~5,470-image dataset had already reached its useful model
capacity at this size, which is why larger variants (l, x) were not pursued further. Full
reasoning and methodology are documented in `docs/project_report.docx`.

## Known Limitations

- Dataset is US/general-road-focused (RDD2022) plus a general pothole dataset — not yet
  validated on a large, dedicated set of Kenyan road imagery specifically
- `/evaluate` runs a full validation pass, which is slow (several minutes) and not intended
  to be called on every app load — it's cached, with an explicit `?refresh=true` to recompute
- Session history in the API is in-memory only — it resets when the server restarts (no
  persistent database yet, see Roadmap)

## Roadmap

- [ ] Persistent storage for scan history (replace in-memory list with a real database)
- [ ] Expand training data with locally captured Kenyan road imagery
- [ ] User accounts and multi-user support
- [ ] Offline detection fallback in the mobile app

## Acknowledgements

- [RDD2022 / RoadDamageDetector](https://github.com/sekilab/RoadDamageDetector) — SekiLab
- [Kaggle Annotated Potholes Dataset](https://www.kaggle.com/datasets/chitholian/annotated-potholes-dataset) — chitholian
- [Ultralytics YOLOv8](https://github.com/ultralytics/ultralytics)

## License

`[Add your chosen license here, e.g. MIT — or state "All rights reserved" if this is
submitted coursework not intended for reuse.]`

---

**Author:** Oscar Omido
**Mobile app repo (if pushed separately):** `[add link if applicable]`
