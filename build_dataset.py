"""
build_dataset.py
=================
Rebuilds the merged YOLO-format dataset (RDD2022 United States + Kaggle
annotated potholes) LOCALLY, replicating the exact conversion/merge/split
logic from RoadDamage_YOLOv8_Pipeline_Commented.ipynb.

WHY THIS EXISTS:
The notebook builds `RoadDamageDataset/` (images + YOLO .txt labels +
data.yaml) inside Colab's temporary /content/ storage. Only best.pt was
ever downloaded to this machine (see the notebook's "Download the trained
model" cell) — the dataset itself was discarded when the Colab session
ended. This script reconstructs it from the raw sources you already have
locally (RDD2022 United_States + the Kaggle "archive (5)" pothole set),
so /evaluate has real ground-truth labels to compare best.pt against.

USAGE:
    cd C:\\Users\\User\\Desktop\\roadsystem
    venv\\Scripts\\activate
    python build_dataset.py

If auto-detection can't find your folders, it will tell you exactly what
it looked for — edit RDD_ROOT / KAGGLE_ROOT below to match reality (right-
click the folder in Explorer -> Copy as path) and re-run.
"""

import os
import glob
import random
import shutil
import xml.etree.ElementTree as ET
from collections import Counter

# ═══════════════════════════════════════════════════════════════════════
#  CONFIG — edit these if auto-detection below fails
# ═══════════════════════════════════════════════════════════════════════
RDD_ROOT    = "United_States"      # your extracted RDD2022 (United States) folder
KAGGLE_ROOT = "archive (5)"        # your extracted Kaggle pothole dataset folder
OUTPUT_DIR  = "RoadDamageDataset"  # where the merged YOLO dataset gets written
VAL_RATIO   = 0.2
SEED        = 42                   # reproducible train/val split

# Must match the notebook exactly — this order = the class IDs best.pt uses.
classes = ["D00", "D10", "D20", "D40"]


# ═══════════════════════════════════════════════════════════════════════
#  VOC -> YOLO conversion (identical to the notebook)
# ═══════════════════════════════════════════════════════════════════════
def convert_box(size, box):
    dw = 1.0 / size[0]
    dh = 1.0 / size[1]
    x = (box[0] + box[1]) / 2.0
    y = (box[2] + box[3]) / 2.0
    w = box[1] - box[0]
    h = box[3] - box[2]
    return (x * dw, y * dh, w * dw, h * dh)


def voc_to_yolo(xml_path, output_txt, force_class=None, allowed_names=None):
    tree = ET.parse(xml_path)
    root = tree.getroot()

    size = root.find("size")
    w = int(size.find("width").text)
    h = int(size.find("height").text)

    lines = []
    for obj in root.findall("object"):
        name = obj.find("name").text.strip()

        if allowed_names is not None and name.lower() not in allowed_names:
            continue

        if force_class is not None:
            cls_name = force_class
        else:
            cls_name = name
            if cls_name not in classes:
                continue

        cls_id = classes.index(cls_name)

        bbox = obj.find("bndbox")
        box = (
            float(bbox.find("xmin").text),
            float(bbox.find("xmax").text),
            float(bbox.find("ymin").text),
            float(bbox.find("ymax").text),
        )
        bb = convert_box((w, h), box)
        lines.append(f"{cls_id} " + " ".join(f"{v:.6f}" for v in bb))

    with open(output_txt, "w") as f:
        f.write("\n".join(lines))


# ═══════════════════════════════════════════════════════════════════════
#  Auto-detect source folder layouts
# ═══════════════════════════════════════════════════════════════════════
def find_rdd_dirs(root):
    """Return (train_img_dir, train_xml_dir, test_img_dir) for RDD2022 US."""
    candidates = [
        (root, f"{root}/train/images", f"{root}/train/annotations/xmls", f"{root}/test/images"),
        (root, f"{root}/United_States/train/images",
         f"{root}/United_States/train/annotations/xmls",
         f"{root}/United_States/test/images"),
    ]
    for _, img_dir, xml_dir, test_dir in candidates:
        if os.path.isdir(img_dir) and os.path.isdir(xml_dir):
            return img_dir, xml_dir, test_dir if os.path.isdir(test_dir) else None
    raise FileNotFoundError(
        f"Couldn't find RDD2022 train images/annotations under '{root}'.\n"
        f"Looked for:\n"
        + "\n".join(f"  {c[1]}\n  {c[2]}" for c in candidates) +
        f"\n\nOpen '{root}' in File Explorer, find the real path to the "
        f"folder containing train/images and train/annotations/xmls, and "
        f"edit RDD_ROOT at the top of this script."
    )


def find_kaggle_dir(root):
    """Return the folder containing Kaggle pothole images + matching .xml files."""
    candidates = [f"{root}/annotated-images", root]
    for d in candidates:
        if os.path.isdir(d) and any(f.endswith(".xml") for f in os.listdir(d)):
            return d
    raise FileNotFoundError(
        f"Couldn't find Kaggle pothole images+xmls under '{root}'.\n"
        f"Looked in:\n" + "\n".join(f"  {c}" for c in candidates) +
        f"\n\nOpen '{root}' in File Explorer, find the folder that directly "
        f"contains .jpg + matching .xml files, and edit KAGGLE_ROOT at the "
        f"top of this script."
    )


# ═══════════════════════════════════════════════════════════════════════
#  Split + copy into the merged dataset (identical logic to the notebook)
# ═══════════════════════════════════════════════════════════════════════
def split_and_copy(image_paths, label_dir, master, prefix="", val_ratio=VAL_RATIO, image_ext=".jpg"):
    random.shuffle(image_paths)
    val_count = int(len(image_paths) * val_ratio)
    added, skipped = 0, 0

    for i, img_path in enumerate(image_paths):
        fname = os.path.basename(img_path)
        label_name = fname.replace(image_ext, ".txt")
        label_path = os.path.join(label_dir, label_name)

        if not os.path.exists(label_path) or os.path.getsize(label_path) == 0:
            skipped += 1
            continue

        split = "val" if i < val_count else "train"
        new_img = f"{prefix}{fname}"
        new_lbl = f"{prefix}{label_name}"

        shutil.copy(img_path, f"{master}/images/{split}/{new_img}")
        shutil.copy(label_path, f"{master}/labels/{split}/{new_lbl}")
        added += 1

    return added, skipped


def count_classes(label_dir):
    counter = Counter()
    for f in os.listdir(label_dir):
        if f.endswith(".txt"):
            with open(os.path.join(label_dir, f)) as fh:
                for line in fh:
                    if line.strip():
                        counter[classes[int(line.split()[0])]] += 1
    return counter


# ═══════════════════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════════════════
def main():
    random.seed(SEED)

    print("── Locating source datasets ──────────────────────────────")
    rdd_train_img_dir, rdd_train_xml_dir, rdd_test_img_dir = find_rdd_dirs(RDD_ROOT)
    print(f"RDD2022 images: {rdd_train_img_dir}  ({len(os.listdir(rdd_train_img_dir))} files)")
    print(f"RDD2022 xmls:   {rdd_train_xml_dir}  ({len(os.listdir(rdd_train_xml_dir))} files)")

    kaggle_img_dir = find_kaggle_dir(KAGGLE_ROOT)
    n_kaggle_files = len(os.listdir(kaggle_img_dir))
    print(f"Kaggle folder:  {kaggle_img_dir}  ({n_kaggle_files} files)")

    print("\n── Converting RDD2022 VOC xmls -> YOLO labels ────────────")
    rdd_label_dir = f"{RDD_ROOT}/train/labels_generated"
    os.makedirs(rdd_label_dir, exist_ok=True)
    converted = 0
    for xml_file in os.listdir(rdd_train_xml_dir):
        if xml_file.endswith(".xml"):
            voc_to_yolo(
                os.path.join(rdd_train_xml_dir, xml_file),
                os.path.join(rdd_label_dir, xml_file.replace(".xml", ".txt")),
            )
            converted += 1
    print(f"Converted {converted} RDD2022 annotations")

    print("\n── Converting Kaggle pothole xmls -> YOLO labels (D40) ───")
    kaggle_label_dir = f"{KAGGLE_ROOT}/labels_generated"
    os.makedirs(kaggle_label_dir, exist_ok=True)
    converted = 0
    for xml_file in os.listdir(kaggle_img_dir):
        if xml_file.endswith(".xml"):
            voc_to_yolo(
                os.path.join(kaggle_img_dir, xml_file),
                os.path.join(kaggle_label_dir, xml_file.replace(".xml", ".txt")),
                force_class="D40",
                allowed_names={"pothole"},
            )
            converted += 1
    print(f"Converted {converted} Kaggle pothole annotations")

    print("\n── Building merged dataset ────────────────────────────────")
    master = OUTPUT_DIR
    for split in ["train", "val", "test"]:
        os.makedirs(f"{master}/images/{split}", exist_ok=True)
        os.makedirs(f"{master}/labels/{split}", exist_ok=True)

    rdd_images = glob.glob(os.path.join(rdd_train_img_dir, "*.jpg"))
    added, skipped = split_and_copy(rdd_images, rdd_label_dir, master, prefix="")
    print(f"RDD2022: added {added}, skipped {skipped} (no/empty label)")

    kaggle_images = glob.glob(os.path.join(kaggle_img_dir, "*.jpg"))
    added, skipped = split_and_copy(kaggle_images, kaggle_label_dir, master, prefix="kaggle_")
    print(f"Kaggle: added {added}, skipped {skipped} (no/empty label)")

    if rdd_test_img_dir:
        for img_path in glob.glob(os.path.join(rdd_test_img_dir, "*.jpg")):
            shutil.copy(img_path, f"{master}/images/test/{os.path.basename(img_path)}")
        print(f"Demo test images copied: {len(os.listdir(f'{master}/images/test'))}")

    print("\n── Writing data.yaml (absolute paths) ──────────────────────")
    abs_master = os.path.abspath(master).replace("\\", "/")
    data_yaml_path = os.path.join(master, "data.yaml")
    with open(data_yaml_path, "w") as f:
        f.write(
            f"path: {abs_master}\n"
            f"train: images/train\n"
            f"val: images/val\n\n"
            f"nc: {len(classes)}\n"
            f"names: {classes}\n"
        )
    abs_data_yaml = os.path.abspath(data_yaml_path)
    print(f"Wrote {abs_data_yaml}")

    print("\n── Verifying class distribution ─────────────────────────────")
    for split in ["train", "val"]:
        n_imgs = len(os.listdir(f"{master}/images/{split}"))
        n_lbls = len(os.listdir(f"{master}/labels/{split}"))
        counts = count_classes(f"{master}/labels/{split}")
        print(f"{split}: {n_imgs} images, {n_lbls} labels")
        print(f"  class counts: {dict(counts)}")

    print("\n══════════════════════════════════════════════════════════")
    print("Done. To point the Flask server at this dataset, run:")
    print(f'  $env:VAL_DATA_YAML="{abs_data_yaml}"   (PowerShell)')
    print(f'  set VAL_DATA_YAML={abs_data_yaml}       (cmd)')
    print("then start api.py in that same terminal.")
    print("══════════════════════════════════════════════════════════")


if __name__ == "__main__":
    main()
