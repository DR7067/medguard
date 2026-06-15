from flask import Flask, request, jsonify
import os
import base64
import cv2
import traceback
import shutil
import pytesseract
import re
from werkzeug.exceptions import HTTPException
from preprocess import preprocess_image
from ocr import (
    extract_text,
    find_value_boxes_multi,
    render_pdf_page,
    get_image_meta,
    find_row_boxes_from_value_boxes,
    find_row_boxes_by_test_names,
)
from lab_parser import parse_lab_report
from reference_store import update_reference_ranges, load_reference_ranges, update_reference_ranges_all
from diet_recommender import recommend_diet

try:
    from pillow_heif import register_heif_opener
    register_heif_opener()
except Exception:
    pass
try:
    import fitz  # PyMuPDF
except Exception:
    fitz = None

app = Flask(__name__)

@app.errorhandler(Exception)
def handle_exception(e):
    if isinstance(e, HTTPException):
        return jsonify({"error": e.description}), e.code
    return jsonify({
        "error": f"Server error: {e}",
        "trace": traceback.format_exc(),
    }), 500

UPLOAD_FOLDER = "uploads"
PROCESSED_FOLDER = "processed"

os.makedirs(UPLOAD_FOLDER, exist_ok=True)
os.makedirs(PROCESSED_FOLDER, exist_ok=True)

def _load_tesseract_cmd_from_env_file() -> str:
    env_path = os.path.join(os.path.dirname(__file__), ".env")
    if not os.path.isfile(env_path):
        return ""
    for encoding in ("utf-8", "utf-16", "utf-16-le", "utf-16-be"):
        try:
            with open(env_path, "r", encoding=encoding) as fh:
                for raw_line in fh:
                    line = raw_line.strip()
                    if not line or line.startswith("#") or "=" not in line:
                        continue
                    key, value = line.split("=", 1)
                    if key.strip() == "TESSERACT_CMD":
                        return value.strip().strip('"').strip("'")
        except Exception:
            continue
    return ""

def _configure_tesseract_cmd() -> str:
    candidates = [
        os.environ.get("TESSERACT_CMD", ""),
        _load_tesseract_cmd_from_env_file(),
        getattr(pytesseract.pytesseract, "tesseract_cmd", ""),
        r"C:\Program Files\Tesseract-OCR\tesseract.exe",
        r"C:\Program Files (x86)\Tesseract-OCR\tesseract.exe",
    ]
    for candidate in candidates:
        cmd = str(candidate or "").strip().strip('"').strip("'")
        if cmd and os.path.isfile(cmd):
            os.environ["TESSERACT_CMD"] = cmd
            pytesseract.pytesseract.tesseract_cmd = cmd
            return cmd
    which_cmd = shutil.which("tesseract") or ""
    if which_cmd:
        pytesseract.pytesseract.tesseract_cmd = which_cmd
        return which_cmd
    return ""

def _is_tesseract_available() -> bool:
    resolved = _configure_tesseract_cmd()
    try:
        cmd = getattr(pytesseract.pytesseract, "tesseract_cmd", None)
        if cmd and os.path.isfile(cmd):
            return True
    except Exception:
        pass
    return bool(resolved)

def _tesseract_debug() -> dict:
    configured = _configure_tesseract_cmd()
    current_cmd = str(getattr(pytesseract.pytesseract, "tesseract_cmd", "") or "")
    return {
        "configured_cmd": configured,
        "current_cmd": current_cmd,
        "current_cmd_exists": os.path.isfile(current_cmd) if current_cmd else False,
        "which_tesseract": shutil.which("tesseract"),
        "env_cmd": os.environ.get("TESSERACT_CMD"),
    }

def _merge_row_boxes(primary, secondary, top_tol=4, height_tol=8):
    merged = list(primary or [])
    for box in secondary or []:
        duplicate = False
        for existing in merged:
            if (
                abs(int(existing.get("top", 0)) - int(box.get("top", 0))) <= top_tol
                and abs(int(existing.get("height", 0)) - int(box.get("height", 0))) <= height_tol
            ):
                duplicate = True
                break
        if not duplicate:
            merged.append(box)
    return merged

def _suppress_rdw_when_rdw_sd(parsed_items, overrides_primary, overrides_secondary, range_overrides):
    has_rdw_sd = any(item.get("test") == "RDW-SD" for item in parsed_items)
    if not has_rdw_sd:
        return parsed_items
    rdw_override = False
    if range_overrides and isinstance(range_overrides, dict):
        rdw_override = any(str(k).strip().lower() == "rdw" for k in range_overrides.keys())
    if overrides_primary and any(str(k).strip().lower() == "rdw" for k in overrides_primary.keys()):
        rdw_override = True
    if overrides_secondary and any(str(k).strip().lower() == "rdw" for k in overrides_secondary.keys()):
        rdw_override = True
    if rdw_override:
        return parsed_items
    cleaned = []
    for item in parsed_items:
        if item.get("test") == "RDW":
            rng = item.get("range") or item.get("range_used")
            if rng and len(rng) == 2:
                rmin, rmax = rng
                if rmax is not None and rmax <= 20:
                    continue
        cleaned.append(item)
    return cleaned

def _apply_stored_ranges(parsed_items, stored_ranges):
    updated = []
    diff_tests = {
        "NEUTROPHILS",
        "EOSINOPHILS",
        "LYMPHOCYTES",
        "BASOPHILS",
        "MONOCYTES",
    }
    for item in parsed_items:
        test = item.get("test")
        value = item.get("value")
        current_range = item.get("range")
        stored = stored_ranges.get(test) if test else None

        range_used = None
        test_upper = str(test or "").strip().upper()
        is_diff = test_upper in diff_tests
        # Prefer range from the current report; fall back to stored range only if missing.
        if current_range and len(current_range) == 2:
            range_used = current_range
        elif stored and stored.get("min") is not None and stored.get("max") is not None:
            # Avoid applying tiny stored ranges to differential (%) tests.
            if not (is_diff and isinstance(stored.get("max"), (int, float)) and stored.get("max") <= 10):
                range_used = [stored["min"], stored["max"]]

        # If stored range is scaled (<1) but current range looks like a percent range (>=1),
        # prefer the current range for non-absolute tests.
        if (
            test
            and not str(test).endswith("#")
            and current_range
            and len(current_range) == 2
            and range_used
        ):
            try:
                crmin, crmax = current_range
                srmin, srmax = range_used
                # Ignore tiny ranges on differential (%) tests.
                if is_diff and srmax is not None and srmax <= 10:
                    range_used = None
                    current_range = None
                    srmin = srmax = None
                if srmax is not None and crmax is not None and srmax < 1 and crmax >= 1:
                    range_used = [crmin, crmax]
            except Exception:
                pass

        # If stored range flags abnormal but parsed range looks normal, trust parsed range.
        if (
            value is not None
            and current_range
            and len(current_range) == 2
            and range_used
        ):
            prmin, prmax = current_range
            srmin, srmax = range_used
            try:
                parsed_ok = prmin is not None and prmax is not None and prmin <= value <= prmax
                stored_bad = srmin is not None and srmax is not None and (value < srmin or value > srmax)
            except Exception:
                parsed_ok = False
                stored_bad = False
            if parsed_ok and stored_bad:
                range_used = [prmin, prmax]

        abnormal = item.get("abnormal")
        direction = None
        if range_used and value is not None:
            rmin, rmax = range_used
            abnormal = value < rmin or value > rmax
            if abnormal:
                direction = "low" if value < rmin else "high"

        # Cholesterol reports often list bands; treat <200 as normal.
        if test == "TOTAL CHOLESTEROL" and value is not None and value < 200:
            range_used = [0.0, 200.0]
            abnormal = False
            direction = None

        updated_item = dict(item)
        if range_used is not None:
            updated_item["range_used"] = range_used
            updated_item["range"] = range_used
        updated_item["abnormal"] = abnormal
        if direction:
            updated_item["abnormal_direction"] = direction
        updated.append(updated_item)
    return updated

def _sanitize_diff_ranges(parsed_items):
    if not parsed_items:
        return parsed_items
    diff_tests = {
        "NEUTROPHILS",
        "EOSINOPHILS",
        "LYMPHOCYTES",
        "BASOPHILS",
        "MONOCYTES",
    }
    cleaned = []
    for item in parsed_items:
        test = str(item.get("test") or "").strip().upper()
        rng = item.get("range")
        val = item.get("value")
        if (
            test in diff_tests
            and isinstance(rng, list)
            and len(rng) == 2
            and isinstance(rng[1], (int, float))
            and rng[1] <= 10
            and isinstance(val, (int, float))
            and 0 <= val <= 100
        ):
            fixed = dict(item)
            fixed["range"] = None
            fixed["range_used"] = None
            fixed["abnormal"] = None
            fixed.pop("abnormal_direction", None)
            cleaned.append(fixed)
        else:
            cleaned.append(item)
    return cleaned

def _is_good_range_text(text: str) -> bool:
    if not text:
        return False
    compact = re.sub(r"\s+", "", str(text))
    if re.search(r"\d+(?:\.\d+)?[-â€“]\d+(?:\.\d+)?", compact):
        return True
    return bool(re.search(r"\d+\.\d+\s*\d+\.\d+", compact))

def _range_dominance_ratio(ranges: dict) -> float:
    if not ranges:
        return 0.0
    vals = []
    for v in ranges.values():
        if not v:
            continue
        m = re.search(r"(\d+(?:[.,]\d+)?)\s*[-â€“]\s*(\d+(?:[.,]\d+)?)", str(v))
        if m:
            vals.append(f"{m.group(1)}-{m.group(2)}")
    if len(vals) < 2:
        return 0.0
    from collections import Counter
    c = Counter(vals)
    return c.most_common(1)[0][1] / len(vals)

def _dominant_range_text(ranges: dict) -> str:
    if not ranges:
        return ""
    vals = []
    for v in ranges.values():
        if not v:
            continue
        m = re.search(r"(\d+(?:[.,]\d+)?)\s*[-Ã¢â‚¬â€œ]\s*(\d+(?:[.,]\d+)?)", str(v))
        if m:
            vals.append(f"{m.group(1)}-{m.group(2)}")
    if not vals:
        return ""
    from collections import Counter
    c = Counter(vals)
    return c.most_common(1)[0][0]

def _prune_suspect_ranges(ranges: dict) -> dict:
    if not ranges:
        return {}
    dom_ratio = _range_dominance_ratio(ranges)
    dom_text = _dominant_range_text(ranges)
    if not dom_text or dom_ratio < 0.6 or len(ranges) < 4:
        return dict(ranges)
    m = re.search(r"(\d+(?:[.,]\d+)?)\s*-\s*(\d+(?:[.,]\d+)?)", dom_text)
    if not m:
        return dict(ranges)
    try:
        rmin = float(m.group(1).replace(",", "."))
        rmax = float(m.group(2).replace(",", "."))
    except Exception:
        return dict(ranges)

    # If a small range dominates many tests, it's likely a mis-assigned range.
    if rmax <= 10:
        suspect_tests = {
            "NEUTROPHILS",
            "EOSINOPHILS",
            "LYMPHOCYTES",
            "BASOPHILS",
            "MONOCYTES",
        }
        cleaned = dict(ranges)
        for key in list(cleaned.keys()):
            if str(key).strip().upper() in suspect_tests:
                cleaned.pop(key, None)
        return cleaned

    return dict(ranges)

def _choose_range_overrides(label_ranges: dict, range_overrides: dict) -> dict:
    label_ranges = label_ranges or {}
    range_overrides = range_overrides or {}
    if not label_ranges:
        # If the extracted ranges are dominated by a single value, they are
        # likely misassigned (e.g., one row's range copied to many tests).
        # In that case, drop them and fall back to stored ranges.
        range_dom = _range_dominance_ratio(range_overrides)
        if len(range_overrides) >= 4 and range_dom >= 0.6:
            return {}
        return _prune_suspect_ranges(range_overrides)
    if not range_overrides:
        return _prune_suspect_ranges(label_ranges)

    label_good = sum(1 for v in label_ranges.values() if _is_good_range_text(v))
    range_good = sum(1 for v in range_overrides.values() if _is_good_range_text(v))
    label_dom = _range_dominance_ratio(label_ranges)
    range_dom = _range_dominance_ratio(range_overrides)

    label_low = len(label_ranges) >= 4 and label_dom >= 0.6
    range_low = len(range_overrides) >= 4 and range_dom >= 0.6

    if label_low and not range_low:
        base = dict(range_overrides)
        base_source = "range"
    elif range_low and not label_low:
        base = dict(label_ranges)
        base_source = "label"
    elif range_good > label_good:
        base = dict(range_overrides)
        base_source = "range"
    elif label_good > range_good:
        base = dict(label_ranges)
        base_source = "label"
    else:
        if len(range_overrides) >= len(label_ranges):
            base = dict(range_overrides)
            base_source = "range"
        else:
            base = dict(label_ranges)
            base_source = "label"

    other = label_ranges if base_source == "range" else range_overrides
    for k, v in other.items():
        if k not in base and _is_good_range_text(v):
            base[k] = v
    return _prune_suspect_ranges(base)

@app.route("/", methods=["GET"])
def home():
    return "OCR Backend is running"

@app.route("/upload", methods=["POST"])
def upload_image():
    if not _is_tesseract_available():
        dbg = _tesseract_debug()
        return jsonify({
            "error": "Tesseract OCR is not installed/configured. Install Tesseract and ensure 'tesseract.exe' is on PATH.",
            "details": dbg,
        }), 503

    if "image" not in request.files:
        return jsonify({"error": "No image file received"}), 400

    file = request.files["image"]

    if file.filename == "":
        return jsonify({"error": "Empty filename"}), 400

    input_path = os.path.join(UPLOAD_FOLDER, file.filename)
    processed_path = os.path.join(PROCESSED_FOLDER, "processed_" + file.filename)

    file.save(input_path)

    ext = os.path.splitext(input_path)[1].lower()
    ocr_source_path = input_path
    rendered_base64 = None
    rendered_mime = None

    def _json_pipeline_response(result):
        if not isinstance(result, dict):
            return jsonify({
                "error": "Pipeline returned invalid response type.",
                "details": str(type(result)),
            }), 500
        return jsonify(result)

    def _run_pipeline(source_path, rendered_b64, rendered_m):
        processed_path = os.path.join(PROCESSED_FOLDER, "processed_" + os.path.basename(source_path))
        processed_path = preprocess_image(source_path, processed_path)

        extracted_text, overrides_primary, overrides_secondary, range_overrides, label_ranges = extract_text(
            processed_path,
            original_image_path=source_path
        )

        chosen_ranges = _choose_range_overrides(label_ranges, range_overrides)

        stored_ranges = load_reference_ranges()
        parsed = parse_lab_report(
            extracted_text,
            overrides_primary=overrides_primary,
            overrides_secondary=overrides_secondary,
            range_overrides=chosen_ranges,
            stored_ranges=stored_ranges,
        )
        parsed = _suppress_rdw_when_rdw_sd(
            parsed,
            overrides_primary=overrides_primary,
            overrides_secondary=overrides_secondary,
            range_overrides=chosen_ranges,
        )
        parsed = _sanitize_diff_ranges(parsed)

        stored_ranges = update_reference_ranges(parsed)
        update_reference_ranges_all(chosen_ranges)
        parsed = _apply_stored_ranges(parsed, stored_ranges)
        # Final safeguard: drop RDW when only RDW-SD exists and no explicit RDW override.
        has_rdw_sd = any(item.get("test") == "RDW-SD" for item in parsed)
        has_rdw_cv = bool(re.search(r"\bRDW\s*[- ]?CV\b", extracted_text, re.I)) or bool(
            re.search(r"\bRDW\s*%\b", extracted_text, re.I)
        )
        if has_rdw_sd and not has_rdw_cv:
            parsed = [item for item in parsed if item.get("test") != "RDW"]
        try:
            print("DEBUG rdw_suppress:", {
                "has_rdw_sd": has_rdw_sd,
                "has_rdw_cv": has_rdw_cv,
                "tests_after_suppress": [item.get("test") for item in parsed],
            })
        except Exception:
            pass
        abnormal_only = [item for item in parsed if item.get("abnormal") is True]
        try:
            print("DEBUG parsed tests:", [item.get("test") for item in parsed])
            print("DEBUG parsed details:", [
                {
                    "test": item.get("test"),
                    "value": item.get("value"),
                    "range": item.get("range"),
                    "range_used": item.get("range_used"),
                    "flag": item.get("flag"),
                    "abnormal": item.get("abnormal"),
                } for item in parsed
            ])
            print("DEBUG abnormal tests:", [item.get("test") for item in abnormal_only])
            print("DEBUG abnormal details:", abnormal_only)
        except Exception:
            pass

        abnormal_values = [item["value"] for item in abnormal_only if "value" in item]
        image_meta, value_boxes = find_value_boxes_multi(
            [source_path, processed_path],
            abnormal_values,
        )

        def _value_match(a, b):
            try:
                av = float(a)
                bv = float(b)
            except Exception:
                return False
            tol = max(0.01, abs(bv) * 0.005)
            return abs(av - bv) <= tol

        # Tag value boxes with test/direction for reliable mapping later.
        for box in value_boxes:
            match = next(
                (item for item in abnormal_only if _value_match(item.get("value"), box.get("value"))),
                None,
            )
            if match:
                box["test"] = match.get("test")
                box["direction"] = match.get("abnormal_direction")

        source_meta = get_image_meta(source_path)
        if source_meta["width"] and source_meta["height"]:
            if (image_meta["width"], image_meta["height"]) != (source_meta["width"], source_meta["height"]):
                scale_x = source_meta["width"] / image_meta["width"] if image_meta["width"] else 1.0
                scale_y = source_meta["height"] / image_meta["height"] if image_meta["height"] else 1.0
                for box in value_boxes:
                    box["left"] = int(round(box["left"] * scale_x))
                    box["top"] = int(round(box["top"] * scale_y))
                    box["width"] = int(round(box["width"] * scale_x))
                    box["height"] = int(round(box["height"] * scale_y))
                image_meta = source_meta

        test_names = [item.get("test") for item in abnormal_only if item.get("test")]
        row_boxes_by_name = find_row_boxes_by_test_names(source_path, test_names)
        if processed_path != source_path:
            row_boxes_from_processed = find_row_boxes_by_test_names(processed_path, test_names)
            processed_meta = get_image_meta(processed_path)
            source_meta = get_image_meta(source_path)
            if row_boxes_from_processed and processed_meta["width"] and processed_meta["height"]:
                if (processed_meta["width"], processed_meta["height"]) != (source_meta["width"], source_meta["height"]):
                    scale_x = source_meta["width"] / processed_meta["width"] if processed_meta["width"] else 1.0
                    scale_y = source_meta["height"] / processed_meta["height"] if processed_meta["height"] else 1.0
                    for box in row_boxes_from_processed:
                        box["left"] = int(round(box["left"] * scale_x))
                        box["top"] = int(round(box["top"] * scale_y))
                        box["width"] = int(round(box["width"] * scale_x))
                        box["height"] = int(round(box["height"] * scale_y))
            row_boxes_by_name = _merge_row_boxes(row_boxes_by_name, row_boxes_from_processed)

        row_boxes_by_value = find_row_boxes_from_value_boxes(source_path, value_boxes)
        # Tag row boxes by matching their value to abnormal tests.
        for box in row_boxes_by_value:
            match = next(
                (item for item in abnormal_only if _value_match(item.get("value"), box.get("value"))),
                None,
            )
            if match:
                box["test"] = match.get("test")
                box["direction"] = match.get("abnormal_direction")

        # Build per-test row boxes: prefer value-box anchored rows, then name rows.
        name_by_test = {b.get("test"): b for b in row_boxes_by_name if b.get("test")}
        value_by_test = {b.get("test"): b for b in row_boxes_by_value if b.get("test")}
        value_box_by_test = {b.get("test"): b for b in value_boxes if b.get("test")}

        def _center_y(box):
            return float(box.get("top", 0)) + (float(box.get("height", 0)) / 2.0)

        def _height(box):
            try:
                return float(box.get("height", 0))
            except Exception:
                return 0.0

        row_boxes = []
        for t in test_names:
            if not t:
                continue
            name_box = name_by_test.get(t)
            value_box = value_by_test.get(t)
            raw_value_box = value_box_by_test.get(t)
            chosen = None
            if raw_value_box and image_meta["width"] and image_meta["height"]:
                vtop = float(raw_value_box.get("top", 0))
                vheight = float(raw_value_box.get("height", 0))
                band_h = max(18, int(round(vheight * 1.3)))
                top = int(round(vtop - (band_h - vheight) / 2.0))
                top = max(0, min(int(image_meta["height"]) - 1, top))
                chosen = {
                    "left": 0,
                    "top": top,
                    "width": int(image_meta["width"]),
                    "height": band_h,
                    "test": t,
                    "direction": raw_value_box.get("direction"),
                    "value": raw_value_box.get("value"),
                }
            if name_box and value_box:
                dy = abs(_center_y(name_box) - _center_y(value_box))
                thresh = max(12.0, max(_height(name_box), _height(value_box)) * 1.2)
                chosen = value_box if dy > thresh else (chosen or name_box)
            elif name_box:
                chosen = chosen or name_box
            elif value_box:
                chosen = chosen or value_box

            if chosen is not None:
                row_boxes.append(chosen)
                continue

            # Fallback to a tight band around the value box if available.
            vbox = next((b for b in value_boxes if b.get("test") == t), None)
            if vbox and image_meta["width"] and image_meta["height"]:
                vtop = float(vbox.get("top", 0))
                vheight = float(vbox.get("height", 0))
                band_h = max(18, int(round(vheight * 1.4)))
                top = int(round(vtop - (band_h - vheight) / 2.0))
                top = max(0, min(int(image_meta["height"]) - 1, top))
                row_boxes.append({
                    "left": 0,
                    "top": top,
                    "width": int(image_meta["width"]),
                    "height": band_h,
                    "test": t,
                    "direction": vbox.get("direction"),
                    "value": vbox.get("value"),
                })
        try:
            print("DEBUG row_boxes:", [
                {
                    "test": b.get("test"),
                    "value": b.get("value"),
                    "top": b.get("top"),
                    "height": b.get("height"),
                } for b in row_boxes
            ])
        except Exception:
            pass
        for box in value_boxes:
            match = next(
                (item for item in abnormal_only if item.get("value") == box["value"]),
                None,
            )
            if match:
                box["test"] = match.get("test")
                box["direction"] = match.get("abnormal_direction")
        for box in row_boxes:
            if box.get("test"):
                continue
            match = next(
                (item for item in abnormal_only if item.get("value") == box.get("value")),
                None,
            )
            if match:
                box["test"] = match.get("test")
                box["direction"] = match.get("abnormal_direction")

        # Tighten overly tall boxes using a median row height heuristic.
        heights = [b.get("height") for b in (row_boxes_by_name or row_boxes) if b.get("height")]
        heights = [h for h in heights if isinstance(h, (int, float)) and h > 0]
        if heights:
            heights.sort()
            mid = len(heights) // 2
            median_h = heights[mid] if len(heights) % 2 == 1 else (heights[mid - 1] + heights[mid]) / 2.0
            max_h = max(18, int(round(median_h * 1.6)))
            target_h = max(18, int(round(median_h * 1.2)))
            for b in row_boxes:
                h = b.get("height")
                if not h or h <= max_h:
                    continue
                center_y = float(b.get("top", 0)) + (float(h) / 2.0)
                new_h = min(max_h, target_h)
                new_top = int(round(center_y - (new_h / 2.0)))
                b["top"] = max(0, new_top)
                b["height"] = int(new_h)

        # Prevent row boxes from overlapping the next row.
        if row_boxes:
            ordered = sorted(row_boxes, key=lambda b: (b.get("top", 0), b.get("height", 0)))
            for i in range(len(ordered) - 1):
                cur = ordered[i]
                nxt = ordered[i + 1]
                cur_top = int(cur.get("top", 0))
                cur_h = int(cur.get("height", 0) or 0)
                next_top = int(nxt.get("top", 0))
                if cur_h <= 0:
                    continue
                max_h = max(16, next_top - cur_top - 3)
                if max_h > 0 and cur_h > max_h:
                    cur["height"] = max_h

        # Prefer row boxes from OCR line detection. Use wide-band fallback only if empty.
        if not row_boxes:
            if value_boxes and image_meta["width"] and image_meta["height"]:
                for vbox in value_boxes:
                    vtop = float(vbox.get("top", 0))
                    vheight = float(vbox.get("height", 0))
                    band_h = max(24, int(round(vheight * 2.4)))
                    top = int(round(vtop - (band_h - vheight) / 2.0))
                    top = max(0, min(int(image_meta["height"]) - 1, top))
                    row_boxes.append({
                        "left": 0,
                        "top": top,
                        "width": int(image_meta["width"]),
                        "height": band_h,
                        "test": vbox.get("test"),
                        "direction": vbox.get("direction"),
                        "value": vbox.get("value"),
                    })
            elif row_boxes_by_value:
                row_boxes = row_boxes_by_value

        # Ensure every abnormal test has a row box; add name-based rows when missing.
        abnormal_tests = {item.get("test") for item in abnormal_only if item.get("test")}
        present_tests = {b.get("test") for b in row_boxes if b.get("test")}
        missing_tests = [t for t in abnormal_tests if t not in present_tests]
        if missing_tests:
            for b in row_boxes_by_name:
                if b.get("test") in missing_tests:
                    row_boxes.append(b)

        # Drop oversized boxes (OCR sometimes merges multiple rows).
        if image_meta["height"]:
            max_row_h = max(24, int(image_meta["height"] * 0.12))
            filtered = [b for b in row_boxes if b.get("height") and b["height"] <= max_row_h]
            if filtered:
                row_boxes = filtered

        # Fallback: if no reasonable row boxes remain, build a tight band around abnormal values.
        if not row_boxes and value_boxes and image_meta["width"] and image_meta["height"]:
            for vbox in value_boxes:
                vtop = float(vbox.get("top", 0))
                vheight = float(vbox.get("height", 0))
                band_h = max(22, int(round(vheight * 2.2)))
                top = int(round(vtop - (band_h - vheight) / 2.0))
                top = max(0, min(int(image_meta["height"]) - 1, top))
                row_boxes.append({
                    "left": 0,
                    "top": top,
                    "width": int(image_meta["width"]),
                    "height": band_h,
                    "test": vbox.get("test"),
                    "direction": vbox.get("direction"),
                    "value": vbox.get("value"),
                })

        diet = recommend_diet(abnormal_only)

        return {
            "parsed": abnormal_only,
            "reference_ranges": stored_ranges,
            "diet": diet,
            "highlights": {
                "image_width": image_meta["width"],
                "image_height": image_meta["height"],
                "boxes": row_boxes,
                "rendered_image_base64": rendered_b64,
                "rendered_image_mime": rendered_m,
            },
        }

    if ext == ".pdf":
        if fitz is None:
            return jsonify({"error": "PyMuPDF (fitz) is not installed for PDF rendering."}), 500
        try:
            doc = fitz.open(input_path)
        except Exception as exc:
            return jsonify({"error": f"PDF rendering failed: {exc}"}), 500
        page_index = 0
        raw_page_index = request.form.get("page_index")
        raw_page = request.form.get("page")
        try:
            if raw_page_index is not None:
                page_index = int(raw_page_index)
            elif raw_page is not None:
                page_index = max(int(raw_page) - 1, 0)
        except Exception:
            doc.close()
            return jsonify({"error": "Invalid page index."}), 400
        rendered_path = os.path.join(
            PROCESSED_FOLDER,
            f"rendered_{os.path.splitext(file.filename)[0]}_p{page_index + 1}.png",
        )
        try:
            render_pdf_page(input_path, rendered_path, page_index=page_index, zoom=4.5)
        except Exception as exc:
            doc.close()
            return jsonify({"error": f"PDF rendering failed: {exc}"}), 400
        with open(rendered_path, "rb") as img_f:
            rendered_base64 = base64.b64encode(img_f.read()).decode("utf-8")
        rendered_mime = "image/png"
        doc.close()
        try:
            return _json_pipeline_response(_run_pipeline(rendered_path, rendered_base64, rendered_mime))
        except Exception as exc:
            return jsonify({
                "error": f"Pipeline failed: {exc}",
                "trace": traceback.format_exc(),
            }), 500
    else:
        normalized_path = os.path.join(
            PROCESSED_FOLDER,
            "normalized_" + os.path.splitext(file.filename)[0] + ".png",
        )
        try:
            img = cv2.imread(input_path)
            if img is None:
                raise ValueError("Unsupported file type")
            cv2.imwrite(normalized_path, img)
            ocr_source_path = normalized_path
            with open(normalized_path, "rb") as img_f:
                rendered_base64 = base64.b64encode(img_f.read()).decode("utf-8")
            rendered_mime = "image/png"
        except Exception as exc:
            return jsonify({"error": f"Unsupported image format: {exc}"}), 400
        try:
            return _json_pipeline_response(_run_pipeline(ocr_source_path, rendered_base64, rendered_mime))
        except Exception as exc:
            return jsonify({
                "error": f"Pipeline failed: {exc}",
                "trace": traceback.format_exc(),
            }), 500

if __name__ == "__main__":
    app.run(
        host="0.0.0.0",
        port=5000,
        debug=True
    )
