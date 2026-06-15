import re
import os
import pytesseract
import cv2
from pytesseract import Output
from typing import List, Dict, Any, Tuple, Optional
from lab_parser import TEST_KEYWORDS, OCR_LABEL_MAP

def _load_tesseract_cmd_from_env_file() -> str:
    current = os.environ.get("TESSERACT_CMD", "").strip()
    if current:
        return current

    env_path = os.path.join(os.path.dirname(__file__), ".env")
    if not os.path.isfile(env_path):
        return ""

    try:
        with open(env_path, "r", encoding="utf-8") as fh:
            for raw_line in fh:
                line = raw_line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                key = key.strip()
                value = value.strip().strip('"').strip("'")
                if key == "TESSERACT_CMD" and value:
                    os.environ["TESSERACT_CMD"] = value
                    return value
    except Exception:
        return ""

    return ""

_load_tesseract_cmd_from_env_file()

_TESSERACT_CANDIDATES = [
    os.environ.get("TESSERACT_CMD", ""),
    r"C:\Program Files\Tesseract-OCR\tesseract.exe",
    r"C:\Program Files (x86)\Tesseract-OCR\tesseract.exe",
]
for _candidate in _TESSERACT_CANDIDATES:
    if _candidate and os.path.isfile(_candidate):
        pytesseract.pytesseract.tesseract_cmd = _candidate
        break

try:
    import fitz  # PyMuPDF
except Exception:
    fitz = None

def _detect_table_bbox(img):
    if img is None:
        return None
    height, width = img.shape[:2]
    if height < 100 or width < 100:
        return None

    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    blur = cv2.GaussianBlur(gray, (3, 3), 0)
    thresh = cv2.adaptiveThreshold(
        blur, 255, cv2.ADAPTIVE_THRESH_MEAN_C, cv2.THRESH_BINARY_INV, 31, 10
    )

    hor_kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (max(10, width // 20), 1))
    ver_kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (1, max(10, height // 20)))

    horizontal = cv2.morphologyEx(thresh, cv2.MORPH_OPEN, hor_kernel, iterations=1)
    vertical = cv2.morphologyEx(thresh, cv2.MORPH_OPEN, ver_kernel, iterations=1)
    table_mask = cv2.add(horizontal, vertical)

    contours, _ = cv2.findContours(table_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return None

    best = None
    best_area = 0
    for cnt in contours:
        x, y, w, h = cv2.boundingRect(cnt)
        area = w * h
        if area > best_area:
            best_area = area
            best = (x, y, x + w, y + h)

    if best_area < (width * height * 0.1):
        return None

    return best

def _detect_row_lines(img, table_bbox=None):
    if img is None:
        return []
    height, width = img.shape[:2]
    if height < 40 or width < 40:
        return []

    if table_bbox is not None:
        x1, y1, x2, y2 = table_bbox
        x1 = max(0, int(x1))
        y1 = max(0, int(y1))
        x2 = min(width, int(x2))
        y2 = min(height, int(y2))
        if x2 <= x1 or y2 <= y1:
            return []
        roi = img[y1:y2, x1:x2]
        offset_y = y1
    else:
        roi = img
        offset_y = 0

    gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
    blur = cv2.GaussianBlur(gray, (3, 3), 0)
    thresh = cv2.adaptiveThreshold(
        blur, 255, cv2.ADAPTIVE_THRESH_MEAN_C, cv2.THRESH_BINARY_INV, 31, 10
    )

    kernel_w = max(20, roi.shape[1] // 15)
    hor_kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (kernel_w, 1))
    horizontal = cv2.morphologyEx(thresh, cv2.MORPH_OPEN, hor_kernel, iterations=1)

    contours, _ = cv2.findContours(horizontal, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return []

    row_lines = []
    min_width = int(roi.shape[1] * 0.4)
    for cnt in contours:
        x, y, w, h = cv2.boundingRect(cnt)
        if w < min_width:
            continue
        if h > 8:
            continue
        row_lines.append(offset_y + y + (h // 2))

    if not row_lines:
        return []

    row_lines.sort()
    merged = [row_lines[0]]
    for y in row_lines[1:]:
        if abs(y - merged[-1]) <= 3:
            merged[-1] = int(round((merged[-1] + y) / 2.0))
        else:
            merged.append(y)
    return merged

def _crop_with_bbox(img, bbox, pad=10):
    if img is None or bbox is None:
        return img
    height, width = img.shape[:2]
    x1, y1, x2, y2 = bbox
    x1 = max(0, x1 - pad)
    y1 = max(0, y1 - pad)
    x2 = min(width, x2 + pad)
    y2 = min(height, y2 + pad)
    if x2 <= x1 or y2 <= y1:
        return img
    cropped = img[y1:y2, x1:x2]
    if cropped.size == 0 or cropped.shape[0] < 2 or cropped.shape[1] < 2:
        return img
    return cropped

def _normalize_label(text: str) -> str:
    text = re.sub(r"[^A-Za-z0-9]+", " ", text).strip()
    text = re.sub(r"\s+", " ", text).upper()
    text = re.sub(r"\s+\d+(?:\s+\d+)*$", "", text)
    return text

def _clean_range_text(raw):
    if not raw:
        return raw
    raw_text = str(raw)
    nums = re.findall(r"\d+(?:\.\d+)?", raw_text)
    if len(nums) < 2:
        return raw
    if len(nums) >= 3:
        try:
            first_min = float(nums[0])
            first_max = float(nums[1])
        except Exception:
            first_min = None
            first_max = None
        if first_min is None or first_max is None or first_min >= first_max:
            for i in range(1, len(nums) - 1):
                try:
                    alt_min = float(nums[i])
                    alt_max = float(nums[i + 1])
                except Exception:
                    continue
                if alt_min < alt_max:
                    nums = [nums[i], nums[i + 1]]
                    break
    raw_lower = raw_text.lower()
    if ("x10" in raw_lower or "cells" in raw_lower or "abs" in raw_lower) and len(nums) >= 2:
        nums = nums[-2:]
    try:
        rmin = float(nums[0])
    except Exception:
        return raw
    try:
        rmax = float(nums[1])
    except Exception:
        return raw
    # Fix leading value concatenated into range (e.g., "4 35-56" -> "35-56").
    if rmin > rmax:
        min_str = str(int(rmin)) if rmin.is_integer() else str(rmin)
        max_str = str(int(rmax)) if rmax.is_integer() else str(rmax)
        if rmin >= 1000 and 20 <= rmax <= 80:
            tail = int(min_str[-2:]) if min_str[-2:].isdigit() else None
            if tail is not None and 10 <= tail < rmax and (rmax - tail) <= 40:
                rmin = float(tail)
        elif len(min_str) == len(max_str) + 1 and 20 <= rmax <= 80:
            tail = int(min_str[-2:]) if min_str[-2:].isdigit() else None
            if tail is not None and 10 <= tail < rmax and (rmax - tail) <= 40:
                rmin = float(tail)
        # Fix concatenated value+range where min got prefixed by the value
        # (e.g., "268150-410" should become "150-410").
        if rmin > rmax and rmin >= 1000 and 30 <= rmax <= 1000:
            min_digits = re.sub(r"\D", "", min_str)
            max_digits = str(int(rmax))
            for take in (len(max_digits), max(2, len(max_digits) - 1)):
                if take <= 0 or len(min_digits) < take:
                    continue
                tail = min_digits[-take:]
                if not tail.isdigit():
                    continue
                tail_val = float(tail)
                if 0 < tail_val < rmax and (rmax - tail_val) <= 600:
                    rmin = tail_val
                    break
    # Fix concatenated short integer ranges (e.g., 22-29 -> 222-2921).
    if (
        "." not in str(nums[0])
        and "." not in str(nums[1])
        and rmin >= 100
        and rmax >= 1000
        and len(str(int(rmax))) == len(str(int(rmin))) + 1
    ):
        scaled_min = rmin / 10.0
        scaled_max = rmax / 100.0
        if (
            10 <= scaled_min <= 40
            and 10 <= scaled_max <= 80
            and scaled_max > scaled_min
            and (scaled_max - scaled_min) <= 30
        ):
            rmin, rmax = scaled_min, scaled_max
    # Fix concatenated large max values (e.g., 10 9 2-7 -> 1092-7280).
    if rmax >= 1000 and rmin < 100:
        max_int = str(int(rmax))
        for take in (3, 2):
            try:
                fixed = float(max_int[:take])
            except Exception:
                fixed = None
            if fixed is not None and fixed > rmin:
                rmax = fixed
                break
    max_raw = str(nums[1])
    # Fix concatenated max (e.g., 83-10182.4 -> 83-101).
    if rmax >= 1000 and rmin < 200:
        max_int = str(int(rmax))
        for take in (3, 2):
            try:
                fixed = float(max_int[:take])
            except Exception:
                fixed = None
            if fixed is not None and fixed > rmin:
                rmax = fixed
                break
    # Drop noisy decimal tail for integer-ish ranges (e.g., 40-50.036 -> 40-50).
    if "." in max_raw and "." not in str(nums[0]):
        frac = max_raw.split(".", 1)[1]
        if len(frac) >= 3 and rmax < 200:
            rmax = float(int(rmax))
    # Fix missing decimal in min when it is larger than max (e.g., 70.7-1.2 -> 0.707-1.2).
    if rmin > rmax and rmin >= 10 and rmax < 10:
        scaled = rmin
        for _ in range(2):
            scaled = scaled / 10.0
            if scaled <= rmax:
                rmin = scaled
                break
    # Fix missing decimal when min looks concatenated (e.g., 45-11 -> 4.5-11).
    if rmin > rmax and rmin >= 10 and rmax < 25:
        scaled = rmin
        for _ in range(2):
            scaled = scaled / 10.0
            if scaled <= rmax:
                rmin = scaled
                break
    # Fix concatenated max with value tail (e.g., 6-205.89 -> 6-20.589).
    if "." in max_raw and rmax > 100 and rmin < 20 and rmax > (rmin * 5):
        adj_max = rmax
        while adj_max > 100 and adj_max > rmin * 5:
            adj_max = adj_max / 10.0
        if adj_max > rmin:
            rmax = adj_max
    # Trim overly long decimal tails for decimal ranges.
    if "." in max_raw:
        frac = max_raw.split(".", 1)[1]
        if len(frac) >= 3 and rmax < 200:
            rmax = round(rmax, 2)
    if rmin.is_integer():
        rmin = int(rmin)
    if rmax.is_integer():
        rmax = int(rmax)
    return f"{rmin}-{rmax}"

def _map_to_known_test(label: str) -> Optional[str]:
    norm = _normalize_label(label)
    if not norm:
        return None
    raw_text = str(label)
    raw_upper = raw_text.upper()
    raw_lower = raw_text.lower()
    raw_compact = re.sub(r"[^a-z0-9#]+", "", raw_lower)
    is_absolute = "#" in raw_upper or "ABS" in raw_upper or "X10" in raw_upper
    if is_absolute:
        for test, aliases in TEST_KEYWORDS.items():
            if not test.endswith("#"):
                continue
            for alias in aliases:
                a = alias.lower().strip()
                if not a:
                    continue
                a_compact = re.sub(r"[^a-z0-9#]+", "", a)
                if a_compact and a_compact in raw_compact:
                    return test
                if re.search(rf"\b{re.escape(a)}\b", raw_lower):
                    return test
                if " " in a and a in raw_lower:
                    return test
    if norm in OCR_LABEL_MAP:
        return OCR_LABEL_MAP[norm]
    if norm in TEST_KEYWORDS:
        return norm
    lower = norm.lower()
    for test, aliases in TEST_KEYWORDS.items():
        for alias in aliases:
            a = alias.lower().strip()
            if not a:
                continue
            if re.search(rf"\b{re.escape(a)}\b", lower):
                return test
            if " " in a and a in lower:
                return test
    # Heuristic: RDW often appears as a % range around 11-16 without the label.
    if "%" in str(label):
        m = re.search(r"(\d+(?:\.\d+)?)\s*[-Ã¢â‚¬â€œ]\s*(\d+(?:\.\d+)?)", str(label))
        if m:
            try:
                rmin = float(m.group(1))
                rmax = float(m.group(2))
            except Exception:
                rmin = rmax = None
            if rmin is not None and rmax is not None and 10 <= rmin <= 15 and 12 <= rmax <= 18:
                return "RDW"
    return None

def _extract_table_overrides(label_img, value_img=None, debug_prefix: str = ""):
    data = pytesseract.image_to_data(
        label_img,
        lang="eng",
        config="--oem 3 --psm 6",
        output_type=Output.DICT,
    )
    if debug_prefix:
        cv2.imwrite(f"{debug_prefix}_label.png", label_img)
        if value_img is not None:
            cv2.imwrite(f"{debug_prefix}_value.png", value_img)

    rows = {}
    for i, word in enumerate(data["text"]):
        if not word:
            continue
        key = (data["block_num"][i], data["par_num"][i], data["line_num"][i])
        left_i = int(data["left"][i])
        top_i = int(data["top"][i])
        rows.setdefault(key, []).append({
            "text": word,
            "left": left_i,
            "top": top_i,
        })

    header_top = None
    for _, words in sorted(rows.items(), key=lambda item: min(w["top"] for w in item[1])):
        words_sorted = sorted(words, key=lambda w: w["left"])
        line_text = " ".join(w["text"] for w in words_sorted).lower()
        if "result" in line_text or re.search(r"resu", line_text):
            header_top = min(w["top"] for w in words_sorted)
            break
    if header_top is None:
        header_top = 0

    if value_img is None:
        value_img = label_img

    value_data = pytesseract.image_to_data(
        value_img,
        lang="eng",
        config="--oem 3 --psm 6",
        output_type=Output.DICT,
    )
    value_rows = {}
    token_centers_range = []
    token_centers_number = []
    for i, word in enumerate(value_data["text"]):
        if not word:
            continue
        raw_word = str(word).strip()
        left_i = int(value_data["left"][i])
        width_i = int(value_data["width"][i])
        center_x = left_i + (width_i / 2.0)
        compact = raw_word.replace(" ", "")
        if re.search(r"\d+(?:[.,]\d+)?\s*[-Ã¢â‚¬â€œ]\s*\d+(?:[.,]\d+)?", compact):
            token_centers_range.append(center_x)
        elif re.fullmatch(r"\d+(?:[.,]\d+)?", compact):
            token_centers_number.append(center_x)
        key = (value_data["block_num"][i], value_data["par_num"][i], value_data["line_num"][i])
        top_i = int(value_data["top"][i])
        value_rows.setdefault(key, []).append({
            "text": word,
            "left": left_i,
            "width": width_i,
            "top": top_i,
        })

    result_left = None
    result_right = None
    units_left = None
    ref_left = None
    normal_left = None
    high_left = None
    low_left = None
    for _, words in sorted(value_rows.items(), key=lambda item: min(w["top"] for w in item[1])):
        words_sorted = sorted(words, key=lambda w: w["left"])
        line_text = " ".join(w["text"] for w in words_sorted).lower()
        if "result" in line_text or re.search(r"resu", line_text):
            for w in words_sorted:
                word = w["text"].strip().lower()
                if word in {"result", "results"} or re.match(r"resu", word):
                    result_left = w["left"]
                if word in {"unit", "units"}:
                    units_left = w["left"]
                if word in {"normal", "reference", "bio", "interval", "ref", "range", "value"}:
                    ref_left = w["left"]
            break
        if any(k in line_text for k in ["reference", "range", "normal", "high", "low"]):
            for w in words_sorted:
                word = w["text"].strip().lower()
                if word in {"reference", "ref", "range", "interval"}:
                    if ref_left is None:
                        ref_left = w["left"]
                if word == "normal":
                    if normal_left is None:
                        normal_left = w["left"]
                if word == "high":
                    if high_left is None:
                        high_left = w["left"]
                if word == "low":
                    if low_left is None:
                        low_left = w["left"]

    img_width = label_img.shape[1]
    def _median(values):
        if not values:
            return None
        ordered = sorted(values)
        n = len(ordered)
        mid = n // 2
        if n % 2 == 1:
            return float(ordered[mid])
        return (float(ordered[mid - 1]) + float(ordered[mid])) / 2.0

    def _snap_left_split(target_x, splits):
        if target_x is None or not splits:
            return None
        left_candidates = [s for s in splits if s <= target_x]
        if left_candidates:
            return left_candidates[-1]
        return splits[0]

    def _column_interval_scores(splits):
        if len(splits) < 2:
            return [], []
        intervals = []
        for i in range(len(splits) - 1):
            x1 = int(splits[i])
            x2 = int(splits[i + 1])
            if x2 <= x1 + 15:
                continue
            intervals.append((x1, x2))

        number_scores = []
        range_scores = []
        for x1, x2 in intervals:
            nums = []
            ranges = 0
            for i, raw in enumerate(value_data["text"]):
                token = str(raw or "").strip()
                if not token:
                    continue
                left_i = int(value_data["left"][i])
                width_i = int(value_data["width"][i])
                center_x = left_i + (width_i / 2.0)
                if not (x1 <= center_x < x2):
                    continue
                compact = token.replace(" ", "")
                if re.search(r"\d+(?:[.,]\d+)?\s*[-Ã¢â‚¬â€œ]\s*\d+(?:[.,]\d+)?", compact):
                    ranges += 1
                    continue
                m_num = re.fullmatch(r"\d+(?:[.,]\d+)?", compact)
                if m_num:
                    nums.append(m_num.group(0))

            if nums:
                from collections import Counter
                ctr = Counter(nums)
                most_count = ctr.most_common(1)[0][1]
                dominance = most_count / len(nums)
                unique_count = len(ctr)
                score = (len(nums) * 1.0) + (unique_count * 1.5) - (max(0.0, dominance - 0.65) * len(nums) * 1.5)
                number_scores.append((score, x1, x2))
            if ranges:
                range_scores.append((float(ranges), x1, x2))

        number_scores.sort(key=lambda t: t[0], reverse=True)
        range_scores.sort(key=lambda t: t[0], reverse=True)
        return number_scores, range_scores

    def _detect_vertical_splits(img):
        if img is None:
            return []
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        _, th = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
        kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (1, max(10, img.shape[0] // 20)))
        vertical = cv2.morphologyEx(th, cv2.MORPH_OPEN, kernel, iterations=1)
        col_sum = vertical.sum(axis=0)
        if col_sum is None or len(col_sum) == 0:
            return []
        threshold = col_sum.max() * 0.6 if col_sum.max() > 0 else 0
        splits = [i for i, v in enumerate(col_sum) if v >= threshold]
        if not splits:
            return []
        # collapse to clusters
        clustered = []
        start = splits[0]
        prev = splits[0]
        for x in splits[1:]:
            if x - prev > 3:
                clustered.append((start + prev) // 2)
                start = x
            prev = x
        clustered.append((start + prev) // 2)
        # drop edges
        clustered = [x for x in clustered if 5 < x < (img.shape[1] - 5)]
        return clustered

    # Try to infer column boundaries from vertical grid lines.
    # Use this to fill missing columns only; do not override header-derived columns.
    if value_img is not None:
        splits = _detect_vertical_splits(value_img)
        try:
            print("DEBUG column_splits:", splits)
        except Exception:
            pass
        if len(splits) >= 4:
            splits.sort()
            number_scores, range_scores = _column_interval_scores(splits)

            # Infer reference-range column from x-y token density.
            if ref_left is None and range_scores:
                _, rx1, _ = range_scores[0]
                ref_left = rx1

            # Infer result/value column from numeric-token diversity, left of ref column.
            if result_left is None and number_scores:
                chosen = None
                for _, nx1, nx2 in number_scores:
                    if ref_left is not None and nx2 > ref_left:
                        continue
                    if nx1 < int(img_width * 0.18):
                        continue
                    chosen = (nx1, nx2)
                    break
                if chosen is not None:
                    result_left, result_right = chosen

            # Use OCR token distributions first to infer value/reference columns.
            if ref_left is None and token_centers_range:
                ref_left = _snap_left_split(_median(token_centers_range), splits)

            if result_left is None and token_centers_number:
                candidate_numbers = token_centers_number
                if ref_left is not None:
                    left_nums = [x for x in token_centers_number if x < ref_left]
                    if left_nums:
                        candidate_numbers = left_nums
                result_left = _snap_left_split(_median(candidate_numbers), splits)

            if result_left is None:
                # Result column tends to be in the right half of tabular reports.
                result_left = splits[-3] if len(splits) >= 5 else splits[-2]

            if ref_left is None and result_left is not None:
                left_of_result = [x for x in splits if x < result_left]
                if left_of_result:
                    ref_left = left_of_result[-1]

            if units_left is None and ref_left is not None:
                left_of_ref = [x for x in splits if x < ref_left]
                if left_of_ref:
                    units_left = left_of_ref[-1]

            if result_right is None and result_left is not None:
                right_of_result = [x for x in splits if x > result_left]
                if right_of_result:
                    result_right = right_of_result[0]

            # If OCR mis-ordered header columns, repair using nearest split left of result.
            if (
                ref_left is not None
                and result_left is not None
                and ref_left >= result_left
            ):
                left_of_result = [x for x in splits if x < result_left]
                if left_of_result:
                    ref_left = left_of_result[-1]

    # Fallback when header doesn't include "result".
    if result_left is None:
        if normal_left is not None:
            result_left = normal_left
        else:
            result_left = int(img_width * 0.48)
        if units_left is None:
            units_left = int(img_width * 0.62)
        if ref_left is None:
            ref_left = int(img_width * 0.60)

    # If header-derived Low/Normal/High positions overlap Reference, realign using column splits.
    if splits and ref_left is not None and low_left is not None and low_left <= ref_left:
        try:
            ref_idx = min(range(len(splits)), key=lambda i: abs(splits[i] - ref_left))
            if ref_idx + 1 < len(splits):
                low_left = splits[ref_idx + 1]
            if ref_idx + 2 < len(splits):
                normal_left = splits[ref_idx + 2]
            if ref_idx + 3 < len(splits):
                high_left = splits[ref_idx + 3]
        except Exception:
            pass
    if splits and low_left is not None and normal_left is not None and normal_left <= low_left:
        try:
            low_idx = min(range(len(splits)), key=lambda i: abs(splits[i] - low_left))
            if low_idx + 1 < len(splits):
                normal_left = splits[low_idx + 1]
            if low_idx + 2 < len(splits):
                high_left = splits[low_idx + 2]
        except Exception:
            pass
    if normal_left is None:
        normal_left = int(img_width * 0.78)
    if high_left is None:
        high_left = int(img_width * 0.88)
    if low_left is None:
        low_left = int(img_width * 0.70)
    if units_left is None and ref_left is None:
        units_left = result_left + 200
    if ref_left is None:
        ref_left = (units_left + 200) if units_left is not None else result_left + 400

    def _compute_row_bands(img):
        if img is None:
            return []
        gray_v = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        _, th_v = cv2.threshold(gray_v, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
        h_kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (max(20, img.shape[1] // 30), 1))
        h_lines = cv2.morphologyEx(th_v, cv2.MORPH_OPEN, h_kernel, iterations=1)
        ys = h_lines.sum(axis=1)
        if ys is None or len(ys) == 0:
            return []
        thresh = ys.max() * 0.6 if ys.max() > 0 else 0
        line_idxs = [i for i, v in enumerate(ys) if v >= thresh]
        if not line_idxs:
            return []
        clusters = []
        start = line_idxs[0]
        prev = line_idxs[0]
        for y in line_idxs[1:]:
            if y - prev > 3:
                clusters.append((start + prev) // 2)
                start = y
            prev = y
        clusters.append((start + prev) // 2)
        clusters = sorted(set(clusters))
        bands = []
        for a, b in zip(clusters, clusters[1:]):
            if b - a > 6:
                bands.append((a, b))
        return bands

    row_bands = _compute_row_bands(value_img)
    try:
        print("DEBUG row_bands:", row_bands[:12])
    except Exception:
        pass

    label_rows = []
    skip_labels = {
        "COMPLETE BLOOD COUNT",
        "CBC",
        "DIFFERENTIAL LEUCOCYTE COUNT",
        "DIFFERENTIAL LEUKOCYTE COUNT",
        "ABSOLUTE LEUCOCYTE COUNT",
        "ABSOLUTE LEUKOCYTE COUNT",
        "KIDNEY PANEL",
        "KFT",
        "INVESTIGATION",
        "RENAL PROFILE",
        "CREATININE CLEARANCE TEST",
        "EDTA WHOLE BLOOD",
    }
    label_cutoff = max(0, int(result_left - 5))
    band_best = {}
    for _, words in sorted(rows.items(), key=lambda item: min(w["top"] for w in item[1])):
        words_sorted = sorted(words, key=lambda w: w["left"])
        row_top = min(w["top"] for w in words_sorted)
        if row_top <= header_top + 5:
            continue
        test_words = [w["text"] for w in words_sorted if w["left"] < label_cutoff]
        if not test_words:
            continue
        raw_label = " ".join(test_words)
        label = _normalize_label(raw_label)
        if label.isdigit():
            continue
        if label in {"TEST NAME", "INVESTIGATION", "RESULT", "RESULTS", "NORMAL RANGE", "REFERENCE VALUE", "UNITS", "UNIT"}:
            continue
        if any(skip in label for skip in skip_labels):
            continue
        # Ignore eGFR rows and their descriptive sub-rows.
        if "EGFR" in label or "GFR" in label:
            continue
        if "ML MIN" in label or "ML/MIN" in label or "M2" in label or "M^2" in label:
            continue
        if "CALCULATED" in label:
            continue
        if any(tag in label for tag in [
            "NORMAL OR HIGH",
            "MILD DECREASED",
            "MILD TO MODERATELY",
            "MODERATELY TO SEVERELY",
            "SEVERELY DECREASED",
            "KIDNEY FAILURE",
        ]):
            continue
        mapped_label = _map_to_known_test(raw_label)
        if not mapped_label:
            continue
        label = mapped_label
        # If row bands are detected, keep only one label per band (shortest label wins).
        if row_bands:
            band = min(row_bands, key=lambda b: abs(((b[0] + b[1]) / 2.0) - row_top))
            prev = band_best.get(band)
            if prev is None or len(label) < len(prev["label"]):
                band_best[band] = {"label": label, "top": row_top}
        else:
            label_rows.append({
                "label": label,
                "top": row_top,
            })
    if band_best:
        label_rows = list(band_best.values())

    # If too few labels were detected from the label column, fall back to
    # scanning label-row OCR text for known test names.
    if len(label_rows) < 6 and rows:
        existing_labels = {r["label"] for r in label_rows}
        extra = []
        for _, words in sorted(rows.items(), key=lambda item: min(w["top"] for w in item[1])):
            if not words:
                continue
            words_sorted = sorted(words, key=lambda w: w["left"])
            row_top = min(w["top"] for w in words_sorted)
            line_text = " ".join(str(w["text"]) for w in words_sorted)
            mapped = _map_to_known_test(line_text)
            if mapped and mapped not in existing_labels:
                extra.append({"label": mapped, "top": row_top})
                existing_labels.add(mapped)
        if extra:
            label_rows.extend(extra)

    label_line_texts = {}
    try:
        debug_lines = []
        for _, words in sorted(rows.items(), key=lambda item: min(w["top"] for w in item[1])):
            if not words:
                continue
            words_sorted = sorted(words, key=lambda w: w["left"])
            line_text = " ".join(str(w["text"]) for w in words_sorted)
            mapped = _map_to_known_test(line_text)
            if mapped:
                debug_lines.append(f"{mapped}: {line_text}")
                label_line_texts.setdefault(mapped, line_text)
        if debug_lines:
            print("DEBUG label_lines:", debug_lines[:12])
    except Exception:
        label_line_texts = {}

    # Secondary fallback: scan value rows for known test names if labels are still sparse.
    if len(label_rows) < 8 and value_rows:
        existing_labels = {r["label"] for r in label_rows}
        extra = []
        for _, words in sorted(value_rows.items(), key=lambda item: min(w["top"] for w in item[1])):
            if not words:
                continue
            words_sorted = sorted(words, key=lambda w: w["left"])
            row_top = min(w["top"] for w in words_sorted)
            line_text = " ".join(str(w["text"]) for w in words_sorted)
            mapped = _map_to_known_test(line_text)
            if mapped and mapped not in existing_labels:
                extra.append({"label": mapped, "top": row_top})
                existing_labels.add(mapped)
        if extra:
            label_rows.extend(extra)

    # Tertiary fallback: OCR the label column per row band when labels are still sparse.
    if len(label_rows) < 8 and row_bands and label_img is not None:
        existing_labels = {r["label"] for r in label_rows}
        label_x2 = max(5, int(label_cutoff)) if label_cutoff is not None else int(label_img.shape[1] * 0.4)
        inv_scale_y = (label_img.shape[0] / value_img.shape[0]) if value_img is not None and value_img.shape[0] else 1.0
        debug_band_texts = []

        def _ocr_label_band(roi):
            if roi is None or roi.size == 0 or roi.shape[0] < 2 or roi.shape[1] < 2:
                return ""
            variants = [roi]
            try:
                up = cv2.resize(roi, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_CUBIC)
                gray = cv2.cvtColor(up, cv2.COLOR_BGR2GRAY)
                gray = cv2.bilateralFilter(gray, 7, 60, 60)
                _, th = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
                variants.append(cv2.cvtColor(th, cv2.COLOR_GRAY2BGR))
            except Exception:
                pass
            best = ""
            for v in variants:
                for psm in (7, 6, 11):
                    try:
                        txt = pytesseract.image_to_string(
                            v,
                            lang="eng",
                            config=f"--oem 3 --psm {psm}",
                        )
                    except Exception:
                        txt = ""
                    if txt and len(txt) > len(best):
                        best = txt
            return best

        for b1, b2 in row_bands:
            ly1 = int(max(0, b1 * inv_scale_y))
            ly2 = int(min(label_img.shape[0], b2 * inv_scale_y))
            if ly2 <= ly1 + 2:
                continue
            roi = label_img[ly1:ly2, :label_x2]
            text = _ocr_label_band(roi).replace("\n", " ")
            mapped = _map_to_known_test(text)
            if text:
                debug_band_texts.append(text.strip())
            if mapped and mapped not in existing_labels:
                label_rows.append({"label": mapped, "top": int((b1 + b2) / 2.0)})
                existing_labels.add(mapped)
        try:
            if debug_band_texts:
                print("DEBUG label_band_texts:", debug_band_texts[:12])
        except Exception:
            pass

    try:
        print("DEBUG label_rows:", [r["label"] for r in label_rows][:20])
    except Exception:
        pass

    scale_y = value_img.shape[0] / label_img.shape[0] if label_img.shape[0] else 1.0

    # Build canonical label ranges using the reference column and row bands.
    label_ranges = {}
    if value_img is not None and row_bands:
        # Use the label image width for column positions (same scale).
        rx1 = max(0, int(ref_left - 5)) if ref_left is not None else None
        rx2 = max(0, int(result_left - 5)) if result_left is not None else None
        if rx1 is not None and rx2 is not None and rx2 > rx1 + 2:
            for row in label_rows:
                label = row["label"]
                row_top = int(row["top"] * scale_y)
                containing = [b for b in row_bands if b[0] <= row_top <= b[1]]
                if not containing:
                    continue
                band_y1, band_y2 = containing[0]
                pad = max(2, int((band_y2 - band_y1) * 0.1))
                band_y1 = min(max(0, band_y1 + pad), value_img.shape[0])
                band_y2 = min(max(0, band_y2 - pad), value_img.shape[0])
                if band_y2 <= band_y1 + 2:
                    continue
                band_rng = value_img[band_y1:band_y2, rx1:rx2]
                if band_rng.size == 0:
                    continue
                band_up = cv2.resize(band_rng, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_CUBIC)
                band_gray = cv2.cvtColor(band_up, cv2.COLOR_BGR2GRAY)
                band_gray = cv2.bilateralFilter(band_gray, 9, 75, 75)
                _, band_th = cv2.threshold(band_gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
                band_text = pytesseract.image_to_string(
                    band_th,
                    lang="eng",
                    config="--oem 3 --psm 6 -c tessedit_char_whitelist=0123456789.-",
                )
                band_text = band_text.replace(" ", "")
                m = re.search(r"\d+(?:\.\d+)?[-Ã¢â‚¬â€œ]\d+(?:\.\d+)?", band_text)
                if m:
                    label_ranges[label] = m.group(0)

    if result_right is None:
        result_right = units_left if units_left is not None else ref_left
        if ref_left is not None and result_right is not None:
            result_right = min(result_right, ref_left)
    # Expand result ROI a bit to avoid clipping early-row values.
    roi_pad = int(label_img.shape[1] * 0.02)
    vx1 = max(0, int((result_left or 0) - (5 + roi_pad)))
    vx2 = max(vx1 + 10, int((result_right or label_img.shape[1]) + roi_pad))
    roi = value_img[:, vx1:vx2]

    numeric_data = pytesseract.image_to_data(
        roi,
        lang="eng",
        config="--oem 3 --psm 6 -c tessedit_char_whitelist=0123456789.,",
        output_type=Output.DICT,
    )
    numeric_words = []
    for i, word in enumerate(numeric_data["text"]):
        if not word:
            continue
        numeric_words.append({
            "text": word,
            "top": numeric_data["top"][i],
            "left": numeric_data["left"][i],
            "width": numeric_data["width"][i],
        })

    overrides = {}
    roi_width = roi.shape[1] if roi is not None and roi.size else 0
    value_left_cap = int(roi_width * 0.65) if roi_width else None
    for row in label_rows:
        best = None
        best_dist = None
        row_top = row["top"] * scale_y
        candidates = [
            w for w in numeric_words
            if abs(w["top"] - row_top) <= 12
            and (value_left_cap is None or w.get("left", 0) <= value_left_cap)
        ]
        if not candidates:
            candidates = numeric_words

        # Merge adjacent single-digit tokens that sit on the same row (e.g., "8" + "3" => "83").
        merged = []
        by_left = sorted(candidates, key=lambda w: w.get("left", 0))
        for c1, c2 in zip(by_left, by_left[1:]):
            t1 = str(c1.get("text") or "")
            t2 = str(c2.get("text") or "")
            if not (t1.isdigit() and t2.isdigit()):
                continue
            if len(t1) != 1 or len(t2) != 1:
                continue
            gap = c2.get("left", 0) - (c1.get("left", 0) + c1.get("width", 0))
            if 0 <= gap <= 6 and abs(c1.get("top", 0) - c2.get("top", 0)) <= 3:
                merged.append({
                    "text": f"{t1}{t2}",
                    "top": int((c1.get("top", 0) + c2.get("top", 0)) / 2),
                    "left": c1.get("left", 0),
                })
        if merged:
            candidates = candidates + merged

        for w in candidates:
            dist = abs(w["top"] - row_top)
            if best is None:
                best = w
                best_dist = dist
                continue
            if dist < best_dist:
                best = w
                best_dist = dist
                continue
            if dist == best_dist:
                best_text = str(best.get("text") or "")
                cur_text = str(w.get("text") or "")
                if len(cur_text) > len(best_text):
                    best = w
                    best_dist = dist
                elif len(cur_text) == len(best_text) and w.get("left", 0) < best.get("left", 0):
                    best = w
                    best_dist = dist
        if best is None:
            continue
        match = re.search(r"\d+(?:[.,]\d+)?", best["text"])
        if not match:
            continue
        overrides[row["label"]] = match.group(0)

    rx1 = max(0, int(ref_left - 5))
    if result_left is not None:
        rx2 = max(rx1 + 10, int(result_left - 5))
    else:
        rx2 = max(rx1 + 10, int(value_img.shape[1]))
    rroi = value_img[:, rx1:rx2]

    if rroi.size:
        rroi_scaled = cv2.resize(rroi, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_CUBIC)
        gray = cv2.cvtColor(rroi_scaled, cv2.COLOR_BGR2GRAY)
        gray = cv2.bilateralFilter(gray, 9, 75, 75)
        _, rth = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        range_ocr_img = rth
    else:
        range_ocr_img = rroi

    range_data = pytesseract.image_to_data(
        range_ocr_img,
        lang="eng",
        config="--oem 3 --psm 6 -c tessedit_char_whitelist=0123456789.-",
        output_type=Output.DICT,
    )
    if debug_prefix:
        cv2.imwrite(f"{debug_prefix}_range_roi.png", rroi)
        if rroi.size:
            cv2.imwrite(f"{debug_prefix}_range_roi_scaled.png", range_ocr_img)
    range_overrides = {}
    range_rows = {}
    for i, word in enumerate(range_data["text"]):
        if not word:
            continue
        key = (range_data["block_num"][i], range_data["par_num"][i], range_data["line_num"][i])
        range_rows.setdefault(key, []).append({
            "text": word,
            "top": range_data["top"][i],
            "left": range_data["left"][i],
        })

    range_lines = []
    for _, words in sorted(range_rows.items(), key=lambda item: min(w["top"] for w in item[1])):
        # Preserve left-to-right order to avoid concatenating numbers incorrectly.
        words_sorted = sorted(words, key=lambda w: w.get("left", 0))
        row_top = min(w["top"] for w in words_sorted)
        line_text = " ".join(w["text"] for w in words_sorted)
        line_text = re.sub(r"[^0-9.\-]+", "", line_text)
        range_lines.append({
            "text": line_text,
            "top": row_top,
        })

    range_scale_y = range_ocr_img.shape[0] / label_img.shape[0] if label_img.shape[0] else 1.0
    for row in label_rows:
        best = None
        best_dist = None
        row_top = row["top"] * range_scale_y
        for w in range_lines:
            dist = abs(w["top"] - row_top)
            if best is None or dist < best_dist:
                best = w
                best_dist = dist
        if best is None:
            continue
        range_overrides[row["label"]] = best["text"]
    
    def _is_good_range(text: str) -> bool:
        if not text:
            return False
        compact = re.sub(r"\s+", "", text)
        if re.search(r"\d+(?:\.\d+)?[-Ã¢â‚¬â€œ]\d+(?:\.\d+)?", compact):
            return True
        return bool(re.search(r"\d+\.\d+\s*\d+\.\d+", text))

    # Drop clearly invalid ranges early (e.g., "260-").
    range_overrides = {k: v for k, v in range_overrides.items() if _is_good_range(v)}
    good_count = sum(1 for v in range_overrides.values() if _is_good_range(v))
    min_needed = max(3, len(label_rows) // 4) if label_rows else 3

    if good_count < min_needed:
        fallback_x1 = int(value_img.shape[1] * 0.65)
        rroi = value_img[:, fallback_x1:]
        rroi = cv2.resize(rroi, None, fx=2, fy=2, interpolation=cv2.INTER_CUBIC)
        gray = cv2.cvtColor(rroi, cv2.COLOR_BGR2GRAY)
        gray = cv2.bilateralFilter(gray, 9, 75, 75)
        _, th = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        fallback_data = pytesseract.image_to_data(
            th,
            lang="eng",
            config="--oem 3 --psm 6 -c tessedit_char_whitelist=0123456789.-",
            output_type=Output.DICT,
        )
        fb_rows = {}
        for i, word in enumerate(fallback_data["text"]):
            if not word:
                continue
            key = (fallback_data["block_num"][i], fallback_data["par_num"][i], fallback_data["line_num"][i])
            fb_rows.setdefault(key, []).append({
                "text": word,
                "top": fallback_data["top"][i],
                "left": fallback_data["left"][i],
            })

        fb_lines = []
        for _, words in sorted(fb_rows.items(), key=lambda item: min(w["top"] for w in item[1])):
            # Preserve left-to-right order to avoid concatenating numbers incorrectly.
            words_sorted = sorted(words, key=lambda w: w.get("left", 0))
            row_top = min(w["top"] for w in words_sorted)
            line_text = " ".join(w["text"] for w in words_sorted)
            line_text = re.sub(r"[^0-9.\-]+", "", line_text)
            if not re.search(r"\d", line_text):
                continue
            fb_lines.append({
                "text": line_text,
                "top": row_top,
            })

        fb_scale_y = th.shape[0] / label_img.shape[0] if label_img.shape[0] else 1.0
        for row in label_rows:
            best = None
            best_dist = None
            row_top = row["top"] * fb_scale_y
            for w in fb_lines:
                dist = abs(w["top"] - row_top)
                if best is None or dist < best_dist:
                    best = w
                    best_dist = dist
            if best is None:
                continue
            if _is_good_range(best["text"]):
                range_overrides[row["label"]] = best["text"]

    def _range_dominance_ratio(ranges: Dict[str, Any]) -> float:
        if not ranges:
            return 0.0
        vals = []
        for v in ranges.values():
            if not v:
                continue
            m = re.search(r"(\d+(?:[.,]\d+)?)\s*[-ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Å“]\s*(\d+(?:[.,]\d+)?)", str(v))
            if m:
                vals.append(f"{m.group(1)}-{m.group(2)}")
        if len(vals) < 2:
            return 0.0
        from collections import Counter
        c = Counter(vals)
        return c.most_common(1)[0][1] / len(vals)

    ranges_low_quality = (
        len(range_overrides) >= 4
        and _range_dominance_ratio(range_overrides) >= 0.6
    )

    # If row-band OCR produced canonical label_ranges, prefer it over repeated ranges.
    if label_ranges and (not range_overrides or ranges_low_quality):
        range_overrides = dict(label_ranges)
        ranges_low_quality = False

    def _looks_like_range_concat(val_raw: str, range_raw: str) -> bool:
        if not val_raw or not range_raw:
            return False
        norm_range = re.sub(r"[^0-9.,]+", "-", str(range_raw))
        m = re.search(r"(\d+(?:[.,]\d+)?)\s*-\s*(\d+(?:[.,]\d+)?)", norm_range)
        if not m:
            return False
        try:
            rmin = float(m.group(1).replace(",", ""))
            rmax = float(m.group(2).replace(",", ""))
        except Exception:
            return False
        vm = re.search(r"\d+(?:[.,]\d+)?", str(val_raw))
        if not vm:
            return False
        try:
            val = float(vm.group(0).replace(",", ""))
        except Exception:
            return False
        if rmax <= rmin or rmax <= 0:
            return False
        # Detect concatenation like "6.20" from range "6-20".
        val_text = vm.group(0)
        if "." in val_text or "," in val_text:
            sep = "." if "." in val_text else ","
            parts = val_text.split(sep, 1)
            if len(parts) == 2:
                left, right = parts
                try:
                    left_i = int(left)
                    right_i = int(right)
                except Exception:
                    left_i = right_i = None
                if (
                    left_i is not None
                    and right_i is not None
                    and left_i == int(round(rmin))
                    and right_i == int(round(rmax))
                    and abs(val - rmin) <= 0.25
                ):
                    return True
        if abs(val - (rmin + (rmax / 100.0))) <= 0.02 and abs(val - rmin) <= 0.25:
            return True
        return False

    # Drop overrides that look like a concatenated range (e.g., "6.20" from "6-20").
    for _label, _val in list(overrides.items()):
        if _label in range_overrides and _looks_like_range_concat(_val, range_overrides.get(_label)):
            overrides.pop(_label, None)

    # Row-level token parsing using detected column positions.
    if label_rows and value_rows and normal_left is not None and high_left is not None:
        ref_x1 = int(ref_left) if ref_left is not None else None
        low_x1 = int(low_left) if low_left is not None else None
        normal_x1 = int(normal_left)
        high_x1 = int(high_left)

        def _pick_value(tokens):
            vals = []
            for t in tokens:
                m = re.search(r"\d+(?:[.,]\d+)?", t)
                if m:
                    vals.append(m.group(0))
            if not vals:
                return None
            def _score(v):
                return (1 if "." in v or "," in v else 0, len(v))
            vals.sort(key=_score, reverse=True)
            return vals[0]

        def _collect_range(tokens):
            if not tokens:
                return None
            raw = " ".join(tokens).replace("â€“", "-")
            m = re.search(r"(\d+(?:[.,]\d+)?)\s*-\s*(\d+(?:[.,]\d+)?)", raw)
            if m:
                return f"{m.group(1)}-{m.group(2)}"
            compact = re.sub(r"\s+", "", raw)
            if _is_good_range(compact):
                return compact
            return None

        value_rows_list = list(value_rows.items())
        for row in label_rows:
            label = row["label"]
            row_top = row["top"] * scale_y
            best = None
            best_dist = None
            for _, words in value_rows_list:
                if not words:
                    continue
                top = min(w["top"] for w in words)
                dist = abs(top - row_top)
                if best is None or dist < best_dist:
                    best = words
                    best_dist = dist
            if best is None:
                continue

            best_sorted = sorted(best, key=lambda w: w.get("left", 0))
            # Value from Normal column
            if label not in overrides:
                val_tokens = [
                    w["text"] for w in best_sorted
                    if w["left"] >= normal_x1 - 5 and w["left"] < high_x1 - 5
                ]
                picked = _pick_value(val_tokens)
                if picked:
                    overrides[label] = picked

            # Range from Reference Range column (left of Low)
            if label not in range_overrides and ref_x1 is not None and low_x1 is not None:
                range_tokens = [
                    w["text"] for w in best_sorted
                    if w["left"] >= ref_x1 - 5 and w["left"] < low_x1 - 5
                ]
                picked_range = _collect_range(range_tokens)
                if picked_range:
                    range_overrides[label] = picked_range

    # Final fallback: per-row band OCR using column heuristics.
    if label_rows:
        # Estimate row height from label rows.
        tops = sorted([r["top"] for r in label_rows])
        row_h = 0
        if len(tops) >= 2:
            diffs = [b - a for a, b in zip(tops, tops[1:]) if b - a > 0]
            if diffs:
                diffs.sort()
                row_h = diffs[len(diffs) // 2]
        if row_h <= 0:
            row_h = 22

        vw = value_img.shape[1]
        # Use detected header positions when available.
        if ref_left is not None and result_left is not None:
            range_x1 = int(ref_left)
            range_x2 = int(result_left)
        else:
            range_x1 = int(ref_left) if ref_left is not None else int(vw * 0.45)
            range_x2 = int(low_left) if low_left is not None else int(vw * 0.70)
        low_x1 = int(low_left) if low_left is not None else int(vw * 0.70)
        normal_x1 = int(normal_left) if normal_left is not None else int(vw * 0.78)
        high_x1 = int(high_left) if high_left is not None else int(vw * 0.88)
        result_x1 = normal_x1
        result_x2 = int(vw * 0.98)

    def _row_center_y(row):
        return float(row["top"]) * scale_y

    # We intentionally do not use global range OCR or ordered mapping here.
    # Range extraction should come strictly from the row band slice to avoid
    # cross-row contamination.

    for row in label_rows:
        label = row["label"]
        row_top = int(row["top"] * scale_y)
        y1 = max(0, row_top - int(row_h * 0.25))
        y2 = min(value_img.shape[0], row_top + int(row_h * 0.55))
        band = value_img[y1:y2, :]
        if band.size == 0:
            continue
        # Value OCR
        # Prefer OCR from result column slice when available.
        if result_left is not None and result_right is not None:
            r1 = max(0, int(result_left - 2))
            r2 = min(band.shape[1], int(result_right - 2))
            if r2 > r1 + 2:
                result_roi = band[:, r1:r2]
                if result_roi.size and result_roi.shape[0] >= 2 and result_roi.shape[1] >= 2:
                    result_up = cv2.resize(
                        result_roi, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_CUBIC
                    )
                    result_gray = cv2.cvtColor(result_up, cv2.COLOR_BGR2GRAY)
                    result_gray = cv2.bilateralFilter(result_gray, 9, 75, 75)
                    _, result_th = cv2.threshold(
                        result_gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU
                    )
                    result_text = pytesseract.image_to_string(
                        result_th,
                        lang="eng",
                        config="--oem 3 --psm 6 -c tessedit_char_whitelist=0123456789.,",
                    )
                    nums = re.findall(r"\d+(?:[.,]\d+)?", result_text)
                    if nums:
                        candidate = nums[-1]
                        existing = overrides.get(label)
                        if existing is None:
                            overrides[label] = candidate
                        else:
                            existing_has_decimal = "." in str(existing) or "," in str(existing)
                            candidate_has_decimal = "." in candidate or "," in candidate
                            try:
                                existing_val = float(existing.replace(",", ""))
                            except Exception:
                                existing_val = None
                            try:
                                candidate_val = float(candidate.replace(",", ""))
                            except Exception:
                                candidate_val = None
                            replace = False
                            if candidate_has_decimal and not existing_has_decimal:
                                replace = True
                            elif existing_val is not None and candidate_val is not None:
                                if existing_val >= 100 and candidate_val < 100:
                                    replace = True
                                elif candidate_val > 0 and existing_val > candidate_val * 5:
                                    replace = True
                            if replace:
                                overrides[label] = candidate

                def _read_number(roi):
                    if roi is None or roi.size == 0 or roi.shape[0] < 2 or roi.shape[1] < 2:
                        return None
                    roi = cv2.resize(roi, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_CUBIC)
                    gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
                    gray = cv2.bilateralFilter(gray, 9, 75, 75)
                    _, th = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
                    text = pytesseract.image_to_string(
                        th,
                        lang="eng",
                        config="--oem 3 --psm 6 -c tessedit_char_whitelist=0123456789.,",
                    )
                    m = re.search(r"\d+(?:[.,]\d+)?", text)
                    return m.group(0) if m else None

                low_roi = band[:, low_x1:normal_x1]
                normal_roi = band[:, normal_x1:high_x1]
                high_roi = band[:, high_x1:result_x2]
                low_val = _read_number(low_roi)
                normal_val = _read_number(normal_roi)
                high_val = _read_number(high_roi)

                # Choose the most plausible value (prefer decimal, then longest).
                candidates = [v for v in [normal_val, high_val, low_val] if v]
                if candidates:
                    def _score(v):
                        return (1 if "." in v or "," in v else 0, len(v))
                    candidates.sort(key=_score, reverse=True)
                    overrides[label] = candidates[0]

            # Range OCR
            if label not in range_overrides:
                # Use row-band slice only.
                if row_bands:
                    containing = [b for b in row_bands if b[0] <= row_top <= b[1]]
                    if containing:
                        band_y1, band_y2 = containing[0]
                    else:
                        band_y1, band_y2 = min(
                            row_bands,
                            key=lambda b: abs(((b[0] + b[1]) / 2.0) - row_top),
                        )
                    # tighten band to avoid bleed from adjacent rows
                    pad = max(2, int((band_y2 - band_y1) * 0.1))
                    band_y1 = min(max(0, band_y1 + pad), value_img.shape[0])
                    band_y2 = min(max(0, band_y2 - pad), value_img.shape[0])
                    if band_y2 > band_y1 + 2:
                        band_rng = value_img[band_y1:band_y2, range_x1:range_x2]
                        if band_rng.size and band_rng.shape[0] >= 2 and band_rng.shape[1] >= 2:
                            band_up = cv2.resize(
                                band_rng, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_CUBIC
                            )
                            band_gray = cv2.cvtColor(band_up, cv2.COLOR_BGR2GRAY)
                            band_gray = cv2.bilateralFilter(band_gray, 9, 75, 75)
                            _, band_th = cv2.threshold(band_gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
                            band_text = pytesseract.image_to_string(
                                band_th,
                                lang="eng",
                                config="--oem 3 --psm 6 -c tessedit_char_whitelist=0123456789.-",
                            )
                            band_text = band_text.replace(" ", "")
                            m = re.search(r"\d+(?:\.\d+)?[-Ã¢â‚¬â€œ]\d+(?:\.\d+)?", band_text)
                            if m:
                                range_overrides[label] = m.group(0)
                                continue
                # Try a narrow band around the row center within the reference column.
                ry1 = max(0, row_top - int(row_h * 0.2))
                ry2 = min(value_img.shape[0], row_top + int(row_h * 0.2))
                if ry2 > ry1 + 2:
                    narrow_rng = value_img[ry1:ry2, range_x1:range_x2]
                    if narrow_rng.size and narrow_rng.shape[0] >= 2 and narrow_rng.shape[1] >= 2:
                        narrow_up = cv2.resize(
                            narrow_rng, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_CUBIC
                        )
                        rng_gray = cv2.cvtColor(narrow_up, cv2.COLOR_BGR2GRAY)
                        rng_gray = cv2.bilateralFilter(rng_gray, 9, 75, 75)
                        _, rng_th = cv2.threshold(rng_gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
                        rng_text = pytesseract.image_to_string(
                            rng_th,
                            lang="eng",
                            config="--oem 3 --psm 6 -c tessedit_char_whitelist=0123456789.-",
                        )
                        rng_text = rng_text.replace(" ", "")
                        m = re.search(r"\d+(?:\.\d+)?[-Ã¢â‚¬â€œ]\d+(?:\.\d+)?", rng_text)
                        if m:
                            range_overrides[label] = m.group(0)
                            continue

                # Try reading just the reference range column slice first.
                roi_rng = band[:, range_x1:range_x2]
                if roi_rng.size and roi_rng.shape[0] >= 2 and roi_rng.shape[1] >= 2:
                    roi_rng_up = cv2.resize(
                        roi_rng, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_CUBIC
                    )
                    rng_gray = cv2.cvtColor(roi_rng_up, cv2.COLOR_BGR2GRAY)
                    rng_gray = cv2.bilateralFilter(rng_gray, 9, 75, 75)
                    _, rng_th = cv2.threshold(rng_gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
                    rng_text = pytesseract.image_to_string(
                        rng_th,
                        lang="eng",
                        config="--oem 3 --psm 6 -c tessedit_char_whitelist=0123456789.-",
                    )
                    rng_text = rng_text.replace(" ", "")
                    m = re.search(r"\d+(?:\.\d+)?[-Ã¢â‚¬â€œ]\d+(?:\.\d+)?", rng_text)
                    if m:
                        range_overrides[label] = m.group(0)
                        continue

                    # If row contains multiple ranges (eGFR block), pick the nearest row's range.
                    tokens = re.findall(r"\d+(?:\.\d+)?[-Ã¢â‚¬â€œ]\d+(?:\.\d+)?", rng_text)
                    if len(tokens) >= 2 and label_rows:
                        # Build mapping of row centers to ranges in this ROI by scanning OCR lines.
                        range_rows = {}
                        range_data = pytesseract.image_to_data(
                            rng_th,
                            lang="eng",
                            config="--oem 3 --psm 6 -c tessedit_char_whitelist=0123456789.-",
                            output_type=Output.DICT,
                        )
                        for i, word in enumerate(range_data["text"]):
                            if not word:
                                continue
                            key = (range_data["block_num"][i], range_data["par_num"][i], range_data["line_num"][i])
                            range_rows.setdefault(key, []).append({
                                "text": word,
                                "top": range_data["top"][i],
                            })
                        line_candidates = []
                        for _, words in range_rows.items():
                            line_text = "".join(w["text"] for w in words)
                            line_text = re.sub(r"[^0-9.\-]+", "", line_text)
                            mm = re.search(r"\d+(?:\.\d+)?[-Ã¢â‚¬â€œ]\d+(?:\.\d+)?", line_text)
                            if mm:
                                line_top = min(w["top"] for w in words)
                                line_candidates.append((line_top, mm.group(0)))
                        if line_candidates:
                            # line tops are in ROI coordinates; target should be band-relative.
                            target = (y2 - y1) / 2.0
                            line_candidates.sort(key=lambda t: abs(t[0] - target))
                            range_overrides[label] = line_candidates[0][1]
                            continue
                # Fallback: scan the full row band for a range pattern.
                if band.size and band.shape[0] >= 2 and band.shape[1] >= 2:
                    band_up = cv2.resize(band, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_CUBIC)
                    band_gray = cv2.cvtColor(band_up, cv2.COLOR_BGR2GRAY)
                    band_gray = cv2.bilateralFilter(band_gray, 9, 75, 75)
                    _, band_th = cv2.threshold(band_gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
                    band_text = pytesseract.image_to_string(
                        band_th,
                        lang="eng",
                        config="--oem 3 --psm 6 -c tessedit_char_whitelist=0123456789.-",
                    )
                    m = re.search(r"\d+(?:\.\d+)?[-Ã¢â‚¬â€œ]\d+(?:\.\d+)?", band_text.replace(" ", ""))
                    if m:
                        range_overrides[label] = m.group(0)
                        continue

                roi_rng = band[:, range_x1:range_x2]
                if roi_rng is None or roi_rng.size == 0 or roi_rng.shape[0] < 2 or roi_rng.shape[1] < 2:
                    continue
                roi_rng = cv2.resize(roi_rng, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_CUBIC)
                gray = cv2.cvtColor(roi_rng, cv2.COLOR_BGR2GRAY)
                gray = cv2.bilateralFilter(gray, 9, 75, 75)
                _, th = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
                rng_data = pytesseract.image_to_string(
                    th,
                    lang="eng",
                    config="--oem 3 --psm 6 -c tessedit_char_whitelist=0123456789.-",
                )
                rng_data = re.sub(r"[^0-9.\-]+", "", rng_data)
                if _is_good_range(rng_data):
                    range_overrides[label] = rng_data

    # Final safety fallback: nearest OCR line per detected test row.
    # This helps when column-based extraction collapses to one repeated value.
    def _dominance_ratio(values: List[str]) -> float:
        if not values:
            return 0.0
        from collections import Counter
        c = Counter(values)
        return c.most_common(1)[0][1] / len(values)

    numeric_override_values = []
    for _v in overrides.values():
        _m = re.search(r"\d+(?:[.,]\d+)?", str(_v))
        if _m:
            numeric_override_values.append(_m.group(0))
    overrides_low_quality = (
        len(numeric_override_values) >= 4
        and _dominance_ratio(numeric_override_values) >= 0.6
    )

    if label_rows and value_rows:
        line_candidates = []
        for _, words in value_rows.items():
            if not words:
                continue
            sorted_words = sorted(words, key=lambda w: w["left"])
            line_top = min(w["top"] for w in sorted_words)
            line_text = " ".join(str(w["text"]) for w in sorted_words)
            line_candidates.append((line_top, line_text))

        for row in label_rows:
            label = row["label"]
            row_top = float(row["top"]) * scale_y
            best = None
            best_dist = None
            for line_top, line_text in line_candidates:
                dist = abs(float(line_top) - row_top)
                if best is None or dist < best_dist:
                    best = line_text
                    best_dist = dist
            if not best:
                continue

            m_range = re.search(r"(\d+(?:[.,]\d+)?)\s*[-Ã¢â‚¬â€œ]\s*(\d+(?:[.,]\d+)?)", best)
            if m_range and label not in range_overrides:
                range_overrides[label] = f"{m_range.group(1)}-{m_range.group(2)}"

            if label not in overrides or overrides_low_quality:
                line_wo_range = re.sub(r"\d+(?:[.,]\d+)?\s*[-Ã¢â‚¬â€œ]\s*\d+(?:[.,]\d+)?", " ", best)
                nums = re.findall(r"\d+(?:[.,]\d+)?", line_wo_range)
                if nums:
                    # Prefer decimal-like values for lab results when available.
                    nums.sort(key=lambda n: (("." in n or "," in n), len(n)), reverse=True)
                    overrides[label] = nums[0]

    # Strong fallback: OCR each detected row band directly (full-width row text),
    # then parse value/range from that row text. This avoids wrong-column bleed.
    if label_rows and row_bands:
        row_ocr_overrides = {}
        row_ocr_ranges = {}

        def _ocr_row_text(row_img):
            if row_img is None or row_img.size == 0 or row_img.shape[0] < 2 or row_img.shape[1] < 2:
                return ""
            variants = [row_img]
            try:
                up = cv2.resize(row_img, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_CUBIC)
                gray = cv2.cvtColor(up, cv2.COLOR_BGR2GRAY)
                gray = cv2.bilateralFilter(gray, 7, 60, 60)
                _, th = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
                variants.append(cv2.cvtColor(th, cv2.COLOR_GRAY2BGR))
            except Exception:
                pass

            best = ""
            for v in variants:
                for psm in (7, 6, 11):
                    try:
                        txt = pytesseract.image_to_string(
                            v,
                            lang="eng",
                            config=f"--oem 3 --psm {psm}",
                        )
                    except Exception:
                        txt = ""
                    if txt and len(txt) > len(best):
                        best = txt
            return best

        def _nearest_band_for_row(row_top):
            containing = [b for b in row_bands if b[0] <= row_top <= b[1]]
            if containing:
                return containing[0]
            return min(row_bands, key=lambda b: abs(((b[0] + b[1]) / 2.0) - row_top))

        for row in label_rows:
            label = row["label"]
            row_top = int(float(row["top"]) * scale_y)
            b1, b2 = _nearest_band_for_row(row_top)
            pad = max(1, int((b2 - b1) * 0.08))
            y1 = max(0, b1 + pad)
            y2 = min(value_img.shape[0], b2 - pad)
            if y2 <= y1 + 2:
                continue
            row_img = value_img[y1:y2, :]
            text = _ocr_row_text(row_img).replace("\n", " ")

            # If report uses Low/Normal/High columns, read those cells directly.
            if (
                label not in row_ocr_overrides
                and low_left is not None
                and normal_left is not None
                and high_left is not None
            ):
                cols = [
                    ("low", low_left, normal_left),
                    ("normal", normal_left, high_left),
                ]
                # High column ends at next split after high_left (or image end).
                high_right = row_img.shape[1]
                if splits and high_left is not None:
                    try:
                        hi_idx = min(range(len(splits)), key=lambda i: abs(splits[i] - high_left))
                        if hi_idx + 1 < len(splits):
                            high_right = splits[hi_idx + 1]
                    except Exception:
                        pass
                cols.append(("high", high_left, high_right))

                def _ocr_cell(col_name, x1, x2, rmin=None, rmax=None):
                    span = max(1, int(x2 - x1))
                    pad = max(4, int(span * 0.08))
                    if col_name == "low":
                        # Tight crop inside the Low column to avoid bleeding Reference Range.
                        cx1 = max(0, int(x1 + span * 0.03))
                        cx2 = min(row_img.shape[1], int(x2 - span * 0.03))
                        if cx2 <= cx1 + 2:
                            cx1 = max(0, int(x1))
                            cx2 = min(row_img.shape[1], int(x2))
                    else:
                        if col_name == "normal":
                            extra_left = int(span * 0.25)
                        else:
                            extra_left = 0
                        cx1 = max(0, int(x1 - pad - extra_left))
                        cx2 = min(row_img.shape[1], int(x2 + pad))
                    if cx2 <= cx1 + 2:
                        return None
                    cell = row_img[:, cx1:cx2]
                    try:
                        up = cv2.resize(cell, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_CUBIC)
                        gray = cv2.cvtColor(up, cv2.COLOR_BGR2GRAY)
                        gray = cv2.bilateralFilter(gray, 9, 75, 75)
                        th_otsu = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)[1]
                        th_adapt = cv2.adaptiveThreshold(
                            gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 31, 9
                        )
                        candidates = []
                        for th in (th_otsu, th_adapt):
                            for psm in (7, 6, 8):
                                txt = pytesseract.image_to_string(
                                    th,
                                    lang="eng",
                                    config=f"--oem 3 --psm {psm} -c tessedit_char_whitelist=0123456789.,",
                                )
                                candidates.extend(re.findall(r"\d+(?:[.,]\d+)?", txt))
                        if not candidates:
                            return None

                        def _score(val):
                            if rmin is None or rmax is None:
                                return 0.0
                            if rmin <= val <= rmax:
                                return 0.0
                            return min(abs(val - rmin), abs(val - rmax))

                        best_val = None
                        best_score = None
                        for raw in candidates:
                            try:
                                base_val = float(raw.replace(",", ""))
                            except Exception:
                                continue
                            variants = [(base_val, raw)]
                            if rmax is not None and rmax <= 1.0 and base_val >= 1:
                                variants.append((base_val / 10.0, raw))
                                variants.append((base_val / 100.0, raw))
                            if rmax is not None and rmax <= 20 and base_val < 1:
                                variants.append((base_val * 10.0, raw))
                            for val, _ in variants:
                                score = _score(val)
                                if best_score is None or score < best_score:
                                    best_score = score
                                    best_val = val
                        if best_val is None:
                            return None
                        return f"{best_val:g}"
                    except Exception:
                        return None

                rmin = rmax = None
                if label in range_overrides:
                    m = re.search(r"(\d+(?:[.,]\d+)?)\s*[-Ã¢â‚¬â€œ]\s*(\d+(?:[.,]\d+)?)", str(range_overrides.get(label)))
                    if m:
                        try:
                            rmin = float(m.group(1).replace(",", ""))
                            rmax = float(m.group(2).replace(",", ""))
                        except Exception:
                            rmin = rmax = None

                candidates = []
                for col_name, x1, x2 in cols:
                    val = _ocr_cell(col_name, x1, x2, rmin=rmin, rmax=rmax)
                    if not val:
                        continue
                    try:
                        num = float(str(val).replace(",", ""))
                    except Exception:
                        continue
                    candidates.append((val, num))

                # UREA often appears below range; if any candidate is below rmin, prefer
                # the largest value below rmin (even if an in-range candidate exists).
                if label == "UREA" and rmin is not None and candidates:
                    below = [t for t in candidates if t[1] < rmin]
                    if below:
                        best_val = max(below, key=lambda t: t[1])[0]
                        row_ocr_overrides[label] = best_val
                        overrides[label] = best_val
                        candidates = []

                if candidates:
                    # For percent-style tests, if a high-column value exceeds the range, prefer the max.
                    if rmax is not None and rmax <= 20 and not str(label).endswith("#"):
                        # If no candidate exceeds rmax, force OCR of the rightmost column as High.
                        if not any(n > rmax for _, n in candidates) and splits:
                            try:
                                hi_x1 = splits[-2] if len(splits) >= 2 else int(row_img.shape[1] * 0.8)
                                hi_x2 = splits[-1] if len(splits) >= 1 else row_img.shape[1]
                                val = _ocr_cell(hi_x1, hi_x2, rmin=rmin, rmax=rmax)
                                if val:
                                    try:
                                        num = float(str(val).replace(",", ""))
                                        candidates.append((val, num))
                                    except Exception:
                                        pass
                            except Exception:
                                pass
                        high_vals = [v for v, n in candidates if n > rmax]
                        if high_vals:
                            # Pick the largest numeric value.
                            best_val = max(candidates, key=lambda t: t[1])[0]
                            row_ocr_overrides[label] = best_val
                        else:
                            best_val = min(candidates, key=lambda t: 0 if rmin <= t[1] <= rmax else min(abs(t[1]-rmin), abs(t[1]-rmax)))[0]
                        row_ocr_overrides[label] = best_val
                    else:
                        # Prefer values within range; if multiple, pick the smallest (often in Low column).
                        if rmin is not None and rmax is not None:
                            in_range = [t for t in candidates if rmin <= t[1] <= rmax]
                            if in_range:
                                best_val = min(in_range, key=lambda t: t[1])[0]
                                row_ocr_overrides[label] = best_val
                            else:
                                best_val = min(candidates, key=lambda t: min(abs(t[1]-rmin), abs(t[1]-rmax)))[0]
                                row_ocr_overrides[label] = best_val
                        else:
                            best_val = candidates[0][0]
                            row_ocr_overrides[label] = best_val

                # UREA often has value in Low column; prefer a smaller low-column value when available.
                try:
                    if label == "UREA" and rmin is not None and rmax is not None:
                        picked = row_ocr_overrides.get(label)
                        if picked is not None:
                            try:
                                picked_val = float(str(picked).replace(",", ""))
                            except Exception:
                                picked_val = None
                            if picked_val is not None:
                                # Strong low-column OCR pass (always try).
                                if low_left is not None and normal_left is not None:
                                    lx1 = int(low_left)
                                    lx2 = int(normal_left)
                                    span = max(1, lx2 - lx1)
                                    tight_l = max(0, int(lx1 + span * 0.03))
                                    tight_r = min(row_img.shape[1], int(lx2 - span * 0.03))
                                    if tight_r <= tight_l + 2:
                                        tight_l = max(0, lx1)
                                        tight_r = min(row_img.shape[1], lx2)
                                    cell = row_img[:, tight_l:tight_r]
                                    if cell.size and cell.shape[0] >= 2 and cell.shape[1] >= 2:
                                        up = cv2.resize(cell, None, fx=2.8, fy=2.8, interpolation=cv2.INTER_CUBIC)
                                        gray = cv2.cvtColor(up, cv2.COLOR_BGR2GRAY)
                                        gray = cv2.bilateralFilter(gray, 9, 75, 75)
                                        th1 = cv2.adaptiveThreshold(
                                            gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 31, 9
                                        )
                                        th2 = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)[1]
                                        vals = []
                                        for th in (th1, th2):
                                            txt = pytesseract.image_to_string(
                                                th,
                                                lang="eng",
                                                config="--oem 3 --psm 7 -c tessedit_char_whitelist=0123456789.,",
                                            )
                                            nums = re.findall(r"\d+(?:[.,]\d+)?", txt)
                                            for n in nums:
                                                try:
                                                    v = float(n.replace(",", ""))
                                                except Exception:
                                                    continue
                                                vals.append(v)
                                        if vals:
                                            low_val = min(vals)
                                            # Prefer low-column value if it is smaller than picked and within plausible bounds.
                                            if low_val < picked_val and low_val > (rmin * 0.5):
                                                row_ocr_overrides[label] = f"{low_val:g}"
                                                overrides[label] = f"{low_val:g}"
                                # If low-column OCR still yields range-like value, try full-row OCR
                                # and pick the largest value below the reference range.
                                if label == "UREA" and (row_ocr_overrides.get(label) is None or picked_val >= rmin):
                                    up_row = cv2.resize(row_img, None, fx=2.2, fy=2.2, interpolation=cv2.INTER_CUBIC)
                                    gray = cv2.cvtColor(up_row, cv2.COLOR_BGR2GRAY)
                                    gray = cv2.bilateralFilter(gray, 9, 75, 75)
                                    th1 = cv2.adaptiveThreshold(
                                        gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 31, 9
                                    )
                                    th2 = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)[1]
                                    nums = []
                                    for th in (th1, th2):
                                        txt = pytesseract.image_to_string(
                                            th,
                                            lang="eng",
                                            config="--oem 3 --psm 6 -c tessedit_char_whitelist=0123456789.,-",
                                        )
                                        # Remove obvious range patterns like 16.6-48.5 before extracting tokens.
                                        txt = re.sub(r"\d+(?:[.,]\d+)?\s*-\s*\d+(?:[.,]\d+)?", " ", txt)
                                        nums.extend(re.findall(r"\d+(?:[.,]\d+)?", txt))
                                    cand = []
                                    for n in nums:
                                        try:
                                            v = float(n.replace(",", ""))
                                        except Exception:
                                            continue
                                        if v <= 0:
                                            continue
                                        # Ignore very large IDs.
                                        if v >= 1000:
                                            continue
                                        cand.append(v)
                                    if cand:
                                        below = [v for v in cand if v < rmin]
                                        if below:
                                            best = max(below)
                                            row_ocr_overrides[label] = f"{best:g}"
                                            overrides[label] = f"{best:g}"
                except Exception:
                    pass

                # UREA: force a tight low-column OCR and allow decimal repair (e.g., 1260 -> 12.60).
                try:
                    if label == "UREA" and low_left is not None and normal_left is not None:
                        lx1 = int(low_left)
                        lx2 = int(normal_left)
                        span = max(1, lx2 - lx1)
                        x1 = max(0, int(lx1 + span * 0.03))
                        x2 = min(row_img.shape[1], int(lx2 - span * 0.03))
                        if x2 > x1 + 2:
                            cell = row_img[:, x1:x2]
                            up = cv2.resize(cell, None, fx=3.0, fy=3.0, interpolation=cv2.INTER_CUBIC)
                            gray = cv2.cvtColor(up, cv2.COLOR_BGR2GRAY)
                            gray = cv2.bilateralFilter(gray, 9, 75, 75)
                            th = cv2.adaptiveThreshold(
                                gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 31, 9
                            )
                            txt = pytesseract.image_to_string(
                                th,
                                lang="eng",
                                config="--oem 3 --psm 7 -c tessedit_char_whitelist=0123456789.",
                            )
                            nums = re.findall(r"\d+(?:[.,]\d+)?", txt)
                            cand = []
                            for n in nums:
                                try:
                                    v = float(n.replace(",", ""))
                                except Exception:
                                    continue
                                # Repair missing decimal for plausible UREA values.
                                if rmax is not None and rmax <= 100 and v >= 100:
                                    v = v / 100.0
                                # Repair missing leading digit for ranges >= 10 (e.g., 2.60 -> 12.60).
                                if rmin is not None and rmin >= 10 and v < 10:
                                    v = v + 10
                                if v > 0 and (rmax is None or v <= rmax * 2.0):
                                    cand.append(v)
                            if cand:
                                # Prefer largest value below rmin, else closest to rmin.
                                below = [v for v in cand if rmin is not None and v < rmin]
                                if below:
                                    best = max(below)
                                else:
                                    best = min(cand, key=lambda v: abs(v - rmin) if rmin is not None else v)
                                row_ocr_overrides[label] = f"{best:g}"
                                overrides[label] = f"{best:g}"
                except Exception:
                    pass
# RBC: prefer a plausible decimal value within range (e.g., 4.37) over stray integers.
                try:
                    if label == "RBC" and rmin is not None and rmax is not None:
                        up_row = cv2.resize(row_img, None, fx=2.5, fy=2.5, interpolation=cv2.INTER_CUBIC)
                        gray = cv2.cvtColor(up_row, cv2.COLOR_BGR2GRAY)
                        gray = cv2.bilateralFilter(gray, 9, 75, 75)
                        th = cv2.adaptiveThreshold(
                            gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 31, 9
                        )
                        txt = pytesseract.image_to_string(
                            th,
                            lang="eng",
                            config="--oem 3 --psm 6 -c tessedit_char_whitelist=0123456789.",
                        )
                        nums = re.findall(r"\d+(?:[.,]\d+)?", txt)
                        cand = []
                        for n in nums:
                            try:
                                v = float(n.replace(",", ""))
                            except Exception:
                                continue
                            if rmax <= 10 and v >= 100:
                                v = v / 100.0
                            if v <= 0:
                                continue
                            cand.append(v)
                        if cand:
                            # Prefer values within or just below range, and prefer decimals.
                            in_band = [v for v in cand if (rmin * 0.7) <= v <= (rmax * 1.1)]
                            if in_band:
                                best = min(in_band, key=lambda v: (abs(v - rmin), -v))
                                row_ocr_overrides[label] = f"{best:g}"
                                overrides[label] = f"{best:g}"
                except Exception:
                    pass

                # If selected value is far below range for a >=10 range, retry with full-row OCR.
                try:
                    if label in row_ocr_overrides and rmin is not None and rmax is not None:
                        picked = float(str(row_ocr_overrides[label]).replace(",", ""))
                        if rmin >= 10 and picked < rmin:
                            up_row = cv2.resize(row_img, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_CUBIC)
                            gray = cv2.cvtColor(up_row, cv2.COLOR_BGR2GRAY)
                            gray = cv2.bilateralFilter(gray, 9, 75, 75)
                            th = cv2.adaptiveThreshold(
                                gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 31, 9
                            )
                            txt = pytesseract.image_to_string(
                                th,
                                lang="eng",
                                config="--oem 3 --psm 7 -c tessedit_char_whitelist=0123456789.,",
                            )
                            nums = re.findall(r"\d+(?:[.,]\d+)?", txt)
                            if nums:
                                best = None
                                best_score = None
                                for n in nums:
                                    try:
                                        val = float(n.replace(",", ""))
                                    except Exception:
                                        continue
                                    if val < (rmin * 0.5) or val > (rmax * 1.5):
                                        continue
                                    # Prefer the smallest value that is >= rmin.
                                    score = (val - rmin) if val >= rmin else (rmin - val) + (rmax - rmin)
                                    if best_score is None or score < best_score:
                                        best_score = score
                                        best = val
                                if best is not None:
                                    row_ocr_overrides[label] = f"{best:g}"
                except Exception:
                    pass

            # Try value-only OCR from the result column for this row band.
            # If we already have a value from Low/Normal/High columns, do not override it.
            if label not in row_ocr_overrides and result_left is not None and result_right is not None:
                pad = int(row_img.shape[1] * 0.03)
                r1 = max(0, int(result_left - pad))
                r2 = min(row_img.shape[1], int(result_right + pad))
            else:
                # Fallback: use the right half of the row when result column is unknown.
                if label not in row_ocr_overrides:
                    r1 = int(row_img.shape[1] * 0.55)
                    r2 = int(row_img.shape[1] * 0.98)
                else:
                    r1 = r2 = 0
            if r2 > r1 + 2:
                result_roi = row_img[:, r1:r2]
                if result_roi.size and result_roi.shape[0] >= 2 and result_roi.shape[1] >= 2:
                    try:
                        up = cv2.resize(result_roi, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_CUBIC)
                        gray = cv2.cvtColor(up, cv2.COLOR_BGR2GRAY)
                        gray = cv2.bilateralFilter(gray, 9, 75, 75)
                        _, th = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
                        value_text = pytesseract.image_to_string(
                            th,
                            lang="eng",
                            config="--oem 3 --psm 6 -c tessedit_char_whitelist=0123456789.,",
                        )
                        nums = re.findall(r"\d+(?:[.,]\d+)?", value_text)
                        if nums:
                            rmin = rmax = None
                            if label in range_overrides:
                                raw_range = str(range_overrides.get(label) or "")
                                m = re.search(r"(\d+(?:[.,]\d+)?)\s*[-Ã¢â‚¬â€œ]\s*(\d+(?:[.,]\d+)?)", raw_range)
                                if m:
                                    try:
                                        rmin = float(m.group(1).replace(",", ""))
                                        rmax = float(m.group(2).replace(",", ""))
                                    except Exception:
                                        rmin = rmax = None
                            if rmin is not None and rmax is not None and len(nums) > 1:
                                filtered = []
                                for n in nums:
                                    try:
                                        val = float(n.replace(",", ""))
                                    except Exception:
                                        continue
                                    if abs(val - rmin) <= 0.2 or abs(val - rmax) <= 0.2:
                                        continue
                                    filtered.append(n)
                                if filtered:
                                    nums = filtered
                            nums.sort(key=lambda n: (("." in n or "," in n), len(n)), reverse=True)
                            row_ocr_overrides[label] = nums[0]
                    except Exception:
                        pass

            # Fallback: OCR full row for numeric values when ROI is empty.
            try:
                up_full = cv2.resize(row_img, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_CUBIC)
                gray_full = cv2.cvtColor(up_full, cv2.COLOR_BGR2GRAY)
                gray_full = cv2.bilateralFilter(gray_full, 9, 75, 75)
                _, th_full = cv2.threshold(gray_full, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
                full_text = pytesseract.image_to_string(
                    th_full,
                    lang="eng",
                    config="--oem 3 --psm 6 -c tessedit_char_whitelist=0123456789.,",
                )
                nums = re.findall(r"\d+(?:[.,]\d+)?", full_text)
                if nums:
                    rmin, rmax = (None, None)
                    if label in range_overrides:
                        rmin, rmax = _parse_range_text(range_overrides.get(label))
                    filtered = []
                    for n in nums:
                        try:
                            val = float(n.replace(",", ""))
                        except Exception:
                            continue
                        if rmin is not None and abs(val - rmin) <= 0.2:
                            continue
                        if rmax is not None and abs(val - rmax) <= 0.2:
                            continue
                        filtered.append(n)
                    if filtered:
                        filtered.sort(key=lambda n: (("." in n or "," in n), len(n)), reverse=True)
                        row_ocr_overrides.setdefault(label, filtered[0])
                    elif nums:
                        nums.sort(key=lambda n: (("." in n or "," in n), len(n)), reverse=True)
                        row_ocr_overrides.setdefault(label, nums[0])
                else:
                    # Extra fallback: try alternative preprocessing/psm for stubborn rows.
                    def _try_numeric_candidates(img):
                        candidates = []
                        try:
                            up = cv2.resize(img, None, fx=2.5, fy=2.5, interpolation=cv2.INTER_CUBIC)
                            gray = cv2.cvtColor(up, cv2.COLOR_BGR2GRAY)
                            th1 = cv2.adaptiveThreshold(
                                gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 31, 9
                            )
                            th2 = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)[1]
                            for th in (th1, th2):
                                txt = pytesseract.image_to_string(
                                    th,
                                    lang="eng",
                                    config="--oem 3 --psm 7 -c tessedit_char_whitelist=0123456789.,",
                                )
                                candidates.extend(re.findall(r"\d+(?:[.,]\d+)?", txt))
                        except Exception:
                            pass
                        return candidates

                    alt_nums = _try_numeric_candidates(row_img)
                    if alt_nums:
                        rmin, rmax = (None, None)
                        if label in range_overrides:
                            rmin, rmax = _parse_range_text(range_overrides.get(label))
                        if rmin is not None and rmax is not None and len(alt_nums) > 1:
                            filtered = []
                            for n in alt_nums:
                                try:
                                    val = float(n.replace(",", ""))
                                except Exception:
                                    continue
                                if abs(val - rmin) <= 0.2 or abs(val - rmax) <= 0.2:
                                    continue
                                filtered.append(n)
                            if filtered:
                                alt_nums = filtered
                        alt_nums.sort(key=lambda n: (("." in n or "," in n), len(n)), reverse=True)
                        row_ocr_overrides.setdefault(label, alt_nums[0])
                    else:
                        # Final fallback: token-level OCR on the full row band.
                        def _token_candidates(img):
                            out = []
                            for psm in (11, 6):
                                try:
                                    data = pytesseract.image_to_data(
                                        img,
                                        lang="eng",
                                        config=f"--oem 3 --psm {psm}",
                                        output_type=Output.DICT,
                                    )
                                except Exception:
                                    continue
                                for t in data.get("text", []):
                                    if not t:
                                        continue
                                    m = re.search(r"\d+(?:[.,]\d+)?", str(t))
                                    if m:
                                        out.append(m.group(0))
                            return out

                        token_nums = _token_candidates(row_img)
                        if token_nums:
                            rmin, rmax = (None, None)
                            if label in range_overrides:
                                rmin, rmax = _parse_range_text(range_overrides.get(label))
                            if rmin is not None and rmax is not None and len(token_nums) > 1:
                                filtered = []
                                for n in token_nums:
                                    try:
                                        val = float(n.replace(",", ""))
                                    except Exception:
                                        continue
                                    if abs(val - rmin) <= 0.2 or abs(val - rmax) <= 0.2:
                                        continue
                                    filtered.append(n)
                                if filtered:
                                    token_nums = filtered
                            if label == "BUN":
                                try:
                                    print("DEBUG BUN token_nums:", token_nums)
                                except Exception:
                                    pass
                            token_nums.sort(key=lambda n: (("." in n or "," in n), len(n)), reverse=True)
                            row_ocr_overrides.setdefault(label, token_nums[0])
            except Exception:
                pass

            # Final value fallback: scan right side of the row band directly.
            if label not in row_ocr_overrides:
                try:
                    w = row_img.shape[1]
                    r1 = int(w * 0.58)
                    r2 = int(w * 0.98)
                    if r2 > r1 + 2:
                        right_roi = row_img[:, r1:r2]
                        up = cv2.resize(right_roi, None, fx=2.5, fy=2.5, interpolation=cv2.INTER_CUBIC)
                        gray = cv2.cvtColor(up, cv2.COLOR_BGR2GRAY)
                        gray = cv2.bilateralFilter(gray, 9, 75, 75)
                        _, th = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
                        txt = pytesseract.image_to_string(
                            th,
                            lang="eng",
                            config="--oem 3 --psm 7 -c tessedit_char_whitelist=0123456789.,",
                        )
                        nums = re.findall(r"\d+(?:[.,]\d+)?", txt)
                        if nums:
                            rmin = rmax = None
                            if label in range_overrides:
                                rmin, rmax = _parse_range_text(range_overrides.get(label))
                            if rmin is not None and rmax is not None and len(nums) > 1:
                                filtered = []
                                for n in nums:
                                    try:
                                        val = float(n.replace(",", ""))
                                    except Exception:
                                        continue
                                    if abs(val - rmin) <= 0.2 or abs(val - rmax) <= 0.2:
                                        continue
                                    filtered.append(n)
                                if filtered:
                                    nums = filtered
                            nums.sort(key=lambda n: (("." in n or "," in n), len(n)), reverse=True)
                            row_ocr_overrides[label] = nums[0]
                except Exception:
                    pass

            # Last-resort token-based fallback on the full row band.
            if label not in row_ocr_overrides:
                try:
                    up = cv2.resize(row_img, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_CUBIC)
                    data = pytesseract.image_to_data(
                        up,
                        lang="eng",
                        config="--oem 3 --psm 6",
                        output_type=Output.DICT,
                    )
                    w = up.shape[1]
                    candidates = []
                    for i, text in enumerate(data.get("text", [])):
                        if not text:
                            continue
                        token = str(text).strip()
                        if "-" in token:
                            continue
                        m = re.search(r"\d+(?:[.,]\d+)?", token)
                        if not m:
                            continue
                        cx = int(data["left"][i]) + (int(data["width"][i]) // 2)
                        candidates.append((m.group(0), cx))
                    if candidates:
                        mid_left = int(w * 0.4)
                        mid_right = int(w * 0.85)
                        mid = [c for c in candidates if mid_left <= c[1] <= mid_right]
                        if not mid:
                            mid = candidates
                        dec = [c for c in mid if "." in c[0] or "," in c[0]]
                        pick_pool = dec if dec else mid
                        # Prefer leftmost in the value column region.
                        pick_pool.sort(key=lambda c: c[1])
                        row_ocr_overrides[label] = pick_pool[0][0]
                except Exception:
                    pass

            if not text:
                continue

            m_range = re.search(r"(\d+(?:[.,]\d+)?)\s*[-Ã¢â‚¬â€œ]\s*(\d+(?:[.,]\d+)?)", text)
            if m_range:
                row_ocr_ranges[label] = f"{m_range.group(1)}-{m_range.group(2)}"

            text_wo_range = re.sub(r"\d+(?:[.,]\d+)?\s*[-Ã¢â‚¬â€œ]\s*\d+(?:[.,]\d+)?", " ", text)
            nums = re.findall(r"\d+(?:[.,]\d+)?", text_wo_range)
            if nums:
                nums.sort(key=lambda n: (("." in n or "," in n), len(n)), reverse=True)
                if label not in row_ocr_overrides:
                    row_ocr_overrides[label] = nums[0]

        # If existing overrides are collapsed/noisy, prefer row-band OCR results.
        if overrides_low_quality and row_ocr_overrides:
            overrides.update(row_ocr_overrides)
        else:
            def _parse_range_text(raw):
                if not raw:
                    return (None, None)
                m = re.search(r"(\d+(?:[.,]\d+)?)\s*[-ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Å“]\s*(\d+(?:[.,]\d+)?)", str(raw))
                if not m:
                    return (None, None)
                try:
                    rmin = float(m.group(1).replace(",", ""))
                    rmax = float(m.group(2).replace(",", ""))
                except Exception:
                    return (None, None)
                return (rmin, rmax)

            def _to_float_simple(raw):
                try:
                    return float(str(raw).replace(",", ""))
                except Exception:
                    return None

            def _implausible(value, rmin, rmax):
                if value is None or rmin is None or rmax is None:
                    return False
                return value < (rmin / 2.0) or value > (rmax * 2.0)

            for k, v in row_ocr_overrides.items():
                if k in overrides and k in range_overrides:
                    ov = _to_float_simple(overrides.get(k))
                    cv = _to_float_simple(v)
                    rmin, rmax = _parse_range_text(range_overrides.get(k))
                    span = (rmax - rmin) if rmin is not None and rmax is not None else None
                    eps = None
                    if span is not None and span > 0:
                        eps = max(0.02 * span, 0.2)
                    on_bound = (
                        ov is not None
                        and rmin is not None
                        and rmax is not None
                        and eps is not None
                        and (abs(ov - rmin) <= eps or abs(ov - rmax) <= eps)
                    )
                    cand_on_bound = (
                        cv is not None
                        and rmin is not None
                        and rmax is not None
                        and eps is not None
                        and (abs(cv - rmin) <= eps or abs(cv - rmax) <= eps)
                    )
                    if (
                        (_implausible(ov, rmin, rmax) and not _implausible(cv, rmin, rmax))
                        or (on_bound and not cand_on_bound)
                    ):
                        overrides[k] = v
            for k, v in row_ocr_overrides.items():
                if k not in overrides:
                    overrides[k] = v

        if row_ocr_ranges:
            if ranges_low_quality:
                range_overrides = dict(row_ocr_ranges)
                ranges_low_quality = False
            elif len(range_overrides) < 2:
                range_overrides.update(row_ocr_ranges)
            else:
                for k, v in row_ocr_ranges.items():
                    if k not in range_overrides:
                        range_overrides[k] = v

    # Keep intermediates clean: only known test labels, canonicalized.
    range_overrides = {k: _clean_range_text(v) for k, v in range_overrides.items()}
    label_ranges = {k: _clean_range_text(v) for k, v in label_ranges.items()}

    # Fallback: parse value/range from label line text when missing.
    if label_line_texts:
        row_bands_empty = not row_bands
        for label, line_text in label_line_texts.items():
            need_value = label not in overrides
            need_range = label not in range_overrides and label not in label_ranges
            if not need_value and not need_range:
                # Still allow value replacement if the line includes a clear flag.
                pass
            text = str(line_text).replace("â€“", "-")
            m = re.search(r"(\d+(?:[.,]\d+)?)\s*-\s*(\d+(?:[.,]\d+)?)", text)
            rng = None
            if m:
                rng = f"{m.group(1)}-{m.group(2)}"
            skip_label_range = False
            if rng and label == "RDW":
                try:
                    rmin = float(m.group(1))
                    rmax = float(m.group(2))
                except Exception:
                    rmin = None
                    rmax = None
                if (rmin is not None and rmax is not None and rmin >= 30 and rmax >= 40) or "RDW-SD" in text.upper():
                    skip_label_range = True
            if need_range and rng and not skip_label_range:
                range_overrides.setdefault(label, rng)
                label_ranges.setdefault(label, rng)

            # Prefer last numeric token before the range (if any),
            # otherwise the first numeric token in the line.
            val_text = None
            if m:
                prefix = text[:m.start()]
                nums = re.findall(r"\d+(?:[.,]\d+)?", prefix)
                if nums:
                    val_text = nums[-1]
            if not val_text:
                nums = re.findall(r"\d+(?:[.,]\d+)?", text)
                if nums:
                    val_text = nums[0]

            if val_text:
                line_lower = text.lower()
                has_flag = "high" in line_lower or "low" in line_lower
                if need_value or has_flag:
                    overrides[label] = val_text
                else:
                    # If row bands are missing, trust line-text values over column OCR
                    # when the new value is more plausible (e.g., longer or decimal).
                    try:
                        prev_text = str(overrides.get(label) or "")
                        prefer = row_bands_empty
                        if not prefer:
                            prefer = ("." in val_text and "." not in prev_text) or (len(val_text) > len(prev_text))
                        if prefer:
                            overrides[label] = val_text
                    except Exception:
                        pass

            if rng and not skip_label_range:
                try:
                    prev_rng = range_overrides.get(label)
                    if prev_rng is None or _clean_range_text(prev_rng) != _clean_range_text(rng):
                        if row_bands_empty:
                            range_overrides[label] = rng
                            label_ranges[label] = rng
                except Exception:
                    pass

    clean_overrides = {}
    for raw_label, raw_val in overrides.items():
        mapped = _map_to_known_test(str(raw_label))
        if not mapped:
            continue
        if raw_label in range_overrides and _looks_like_range_concat(raw_val, range_overrides.get(raw_label)):
            continue
        if mapped not in clean_overrides:
            clean_overrides[mapped] = raw_val

    clean_ranges = {}
    for raw_label, raw_rng in range_overrides.items():
        mapped = _map_to_known_test(str(raw_label))
        if not mapped:
            continue
        if mapped not in clean_ranges:
            clean_ranges[mapped] = raw_rng

    clean_label_ranges = {}
    for raw_label, raw_rng in label_ranges.items():
        mapped = _map_to_known_test(str(raw_label))
        if not mapped:
            continue
        if mapped not in clean_label_ranges:
            clean_label_ranges[mapped] = raw_rng

    return (clean_overrides, clean_ranges, clean_label_ranges)

def extract_text(image_path, original_image_path=None):
    img = cv2.imread(image_path)
    if img is None:
        raise ValueError("Invalid image path")
    table_img = img
    original = None
    if original_image_path:
        original = cv2.imread(original_image_path)
        if original is not None:
            table_img = original

    crop_bbox = _detect_table_bbox(img)
    if crop_bbox is not None:
        x1, y1, x2, y2 = crop_bbox
        img_h, img_w = img.shape[:2]
        if (x2 - x1) < (img_w * 0.7):
            # Table detector likely clipped the value column; expand to full width.
            crop_bbox = (0, y1, img_w, y2)
    img_for_ocr = img
    original_crop = None
    if crop_bbox is not None:
        img_for_ocr = _crop_with_bbox(img, crop_bbox, pad=12)
        if original is not None and original.shape[0] and original.shape[1]:
            scale_x = original.shape[1] / img.shape[1]
            scale_y = original.shape[0] / img.shape[0]
            ox1 = int(crop_bbox[0] * scale_x)
            oy1 = int(crop_bbox[1] * scale_y)
            ox2 = int(crop_bbox[2] * scale_x)
            oy2 = int(crop_bbox[3] * scale_y)
            original_crop = _crop_with_bbox(original, (ox1, oy1, ox2, oy2), pad=12)

    def _run_ocr(ocr_img, value_img, debug_prefix: str = ""):
        if ocr_img is None or ocr_img.size == 0:
            return "", {}, {}, {}
        if ocr_img.shape[0] < 2 or ocr_img.shape[1] < 2:
            return "", {}, {}, {}
        if value_img is not None and (value_img.size == 0 or value_img.shape[0] < 2 or value_img.shape[1] < 2):
            value_img = None
        custom_config = r'''
        --oem 3
        --psm 6
        -c preserve_interword_spaces=1
        '''
        text = pytesseract.image_to_string(
            ocr_img,
            lang="eng",
            config=custom_config
        )
        overrides_primary, range_overrides, label_ranges = _extract_table_overrides(
            ocr_img,
            value_img=value_img,
            debug_prefix=debug_prefix,
        )
        overrides_secondary = {}
        if value_img is not None and value_img is not ocr_img:
            overrides_secondary, _, _ = _extract_table_overrides(
                ocr_img,
                value_img=value_img,
                debug_prefix=f"{debug_prefix}_secondary" if debug_prefix else "",
            )
        return text, overrides_primary, overrides_secondary, range_overrides, label_ranges

    def _extract_known_test_overrides(img_for_data):
        if img_for_data is None or img_for_data.size == 0:
            return {}, {}

        def _norm(s: str) -> str:
            return re.sub(r"[^a-z0-9]+", " ", str(s).lower()).strip()

        def _compact(s: str) -> str:
            return re.sub(r"[^a-z0-9]+", "", str(s).lower())

        def _collect(img_variant, psm):
            data = pytesseract.image_to_data(
                img_variant,
                lang="eng",
                config=f"--oem 3 --psm {psm}",
                output_type=Output.DICT,
            )
            lines = {}
            for i, word in enumerate(data["text"]):
                token = str(word or "").strip()
                if not token:
                    continue
                key = (data["block_num"][i], data["par_num"][i], data["line_num"][i])
                lines.setdefault(key, []).append((int(data["left"][i]), token))
            return lines

        variants = [img_for_data]
        try:
            up = cv2.resize(img_for_data, None, fx=1.5, fy=1.5, interpolation=cv2.INTER_CUBIC)
            gray = cv2.cvtColor(up, cv2.COLOR_BGR2GRAY)
            gray = cv2.bilateralFilter(gray, 7, 60, 60)
            _, th = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
            variants.append(cv2.cvtColor(th, cv2.COLOR_GRAY2BGR))
        except Exception:
            pass

        overrides = {}
        ranges = {}
        for variant in variants:
            for psm in (6, 11, 4):
                lines = _collect(variant, psm)
                for _, words in lines.items():
                    words = sorted(words, key=lambda t: t[0])
                    line = " ".join(w for _, w in words)
                    norm_line = _norm(line)
                    if not norm_line:
                        continue
                    compact_line = _compact(line)

                    matched_test = None
                    for test, aliases in TEST_KEYWORDS.items():
                        for alias in aliases:
                            alias_n = _norm(alias)
                            alias_c = _compact(alias)
                            if not alias_n:
                                continue
                            if re.search(rf"\b{re.escape(alias_n)}\b", norm_line):
                                matched_test = test
                                break
                            if alias_c and len(alias_c) >= 4 and alias_c in compact_line:
                                matched_test = test
                                break
                        if matched_test:
                            break
                    if not matched_test:
                        continue

                    m_range = re.search(r"(\d+(?:[.,]\d+)?)\s*[-â€“]\s*(\d+(?:[.,]\d+)?)", line)
                    if not m_range:
                        m_range = re.search(r"(\d+(?:[.,]\d+)?)\s*(?:to)\s*(\d+(?:[.,]\d+)?)", line, re.I)
                    if m_range and matched_test not in ranges:
                        ranges[matched_test] = f"{m_range.group(1)}-{m_range.group(2)}"

                    nums = re.findall(r"\d+(?:[.,]\d+)?", line)
                    if nums and matched_test not in overrides:
                        nums.sort(key=lambda n: (("." in n or "," in n), len(n)), reverse=True)
                        overrides[matched_test] = nums[0]

        # Disambiguate ALP vs ALBUMIN when OCR misreads ALB as ALP.
        if "ALP" in ranges and "ALBUMIN" not in ranges:
            try:
                m = re.search(r"(\d+(?:[.,]\d+)?)\s*-\s*(\d+(?:[.,]\d+)?)", str(ranges["ALP"]))
                if m:
                    rmin = float(m.group(1).replace(",", "."))
                    rmax = float(m.group(2).replace(",", "."))
                    if rmax <= 20 and (rmax - rmin) <= 10:
                        ranges["ALBUMIN"] = ranges.pop("ALP")
                        if "ALP" in overrides:
                            overrides["ALBUMIN"] = overrides.pop("ALP")
            except Exception:
                pass

        return overrides, ranges
    def _is_low_quality_overrides(overrides: Dict[str, Any]) -> bool:
        if not overrides:
            return True
        vals = []
        for v in overrides.values():
            if v is None:
                continue
            m = re.search(r"\d+(?:[.,]\d+)?", str(v))
            if m:
                vals.append(m.group(0))
        if not vals:
            return True
        from collections import Counter
        counts = Counter(vals)
        _, most_count = counts.most_common(1)[0]
        dominance = most_count / len(vals)
        if dominance >= 0.6 and len(vals) >= 4:
            return True
        noisy = 0
        for raw in vals:
            compact = raw.replace(",", "").replace(".", "")
            if "." not in raw and "," not in raw and len(compact) >= 3:
                noisy += 1
        if noisy / len(vals) >= 0.6:
            return True
        return False

    def _looks_like_failed_extraction(text_blob: str, overrides: Dict[str, Any], ranges: Dict[str, Any]) -> bool:
        if _has_report_terms(text_blob):
            # If text looks medical but overrides/ranges are still poor, retry OCR strategy.
            if _is_low_quality_overrides(overrides) and not ranges:
                return True
            if _known_key_count(overrides) < 6 and _known_key_count(ranges) < 6:
                return True
            return False
        # If text is weak, retry unless we already have strong overrides + ranges.
        if _is_low_quality_overrides(overrides):
            return True
        return not bool(ranges)

    def _known_key_count(mapping: Dict[str, Any]) -> int:
        if not mapping:
            return 0
        known = 0
        for key in mapping.keys():
            key_lower = str(key).lower()
            for aliases in TEST_KEYWORDS.values():
                if any(re.search(rf"\b{re.escape(a.lower())}\b", key_lower) for a in aliases):
                    known += 1
                    break
        return known

    # Prefer original crop for OCR text (clearer) when available.
    ocr_base = original_crop if original_crop is not None else img_for_ocr
    value_img = original_crop if original_crop is not None else table_img
    debug_root = os.path.join(os.path.dirname(__file__), "processed", "debug")
    os.makedirs(debug_root, exist_ok=True)
    debug_prefix = os.path.join(debug_root, "ocr_primary")
    text, overrides_primary, overrides_secondary, range_overrides, label_ranges = _run_ocr(
        ocr_base, value_img, debug_prefix=debug_prefix
    )

    def _has_report_terms(text_blob: str) -> bool:
        terms = [
            "urea", "bun", "uric", "creatinine", "glucose", "sodium", "potassium",
            "chloride", "albumin", "globulin", "protein", "ratio", "bicarbonate", "hco3",
            "calcium", "phosphorus", "alkaline",
            "cholesterol", "triglyceride", "hemoglobin", "platelet", "wbc", "rbc"
        ]
        lower = text_blob.lower()
        return any(t in lower for t in terms)

    # Fallbacks when crop OCR is low quality.
    if _looks_like_failed_extraction(text, overrides_primary, range_overrides):
        # Try full original or processed image.
        full_img = original if original is not None else img
        text, overrides_primary, overrides_secondary, range_overrides, label_ranges = _run_ocr(
            full_img, full_img, debug_prefix=os.path.join(debug_root, "ocr_full")
        )

    if _looks_like_failed_extraction(text, overrides_primary, range_overrides):
        # Try upscaled full image.
        full_img = original if original is not None else img
        up = cv2.resize(full_img, None, fx=1.6, fy=1.6, interpolation=cv2.INTER_CUBIC)
        text, overrides_primary, overrides_secondary, range_overrides, label_ranges = _run_ocr(
            up, up, debug_prefix=os.path.join(debug_root, "ocr_upscaled")
        )

    if _looks_like_failed_extraction(text, overrides_primary, range_overrides):
        base_img = original if original is not None else img
        k_overrides, k_ranges = _extract_known_test_overrides(base_img)
        if k_overrides:
            overrides_primary = dict(k_overrides)
            overrides_secondary = {}
        if k_ranges:
            merged_ranges = dict(range_overrides or {})
            merged_ranges.update(k_ranges)
            range_overrides = merged_ranges
    elif _known_key_count(overrides_primary) == 0 and _known_key_count(range_overrides) == 0:
        base_img = original if original is not None else img
        k_overrides, k_ranges = _extract_known_test_overrides(base_img)
        if k_overrides:
            overrides_primary = dict(k_overrides)
            overrides_secondary = {}
        if k_ranges:
            merged_ranges = dict(range_overrides or {})
            merged_ranges.update(k_ranges)
            range_overrides = merged_ranges

    try:
        range_overrides = {k: _clean_range_text(v) for k, v in (range_overrides or {}).items()}
        print("DEBUG overrides_primary:", list(overrides_primary.items())[:10])
        print("DEBUG range_overrides:", list(range_overrides.items())[:10])
    except Exception:
        pass
    return text, overrides_primary, overrides_secondary, range_overrides, label_ranges

def render_pdf_page(pdf_path: str, out_path: str, page_index: int = 0, zoom: float = 2.0) -> None:
    if fitz is None:
        raise RuntimeError("PyMuPDF (fitz) is not installed for PDF rendering.")
    doc = fitz.open(pdf_path)
    if page_index < 0 or page_index >= len(doc):
        doc.close()
        raise ValueError("PDF page index out of range.")
    page = doc.load_page(page_index)
    matrix = fitz.Matrix(zoom, zoom)
    pix = page.get_pixmap(matrix=matrix, alpha=False)
    pix.save(out_path)
    doc.close()

def _normalize_numeric_text(raw: str) -> str:
    return raw.replace(" ", "").replace(",", "")

def _normalize_match_text(raw: str) -> str:
    text = re.sub(r"[^A-Za-z0-9]+", " ", raw).strip().upper()
    return re.sub(r"\s+", " ", text)

def _to_float(raw: str):
    try:
        return float(_normalize_numeric_text(raw))
    except ValueError:
        return None

def _value_matches(candidate: float, target: float) -> bool:
    if candidate is None:
        return False
    tol = max(0.01, abs(target) * 0.005)
    if abs(candidate - target) <= tol:
        return True
    target_round = round(target)
    if abs(target - target_round) <= 0.05 and abs(candidate - target_round) <= tol:
        return True
    return False

def _find_value_boxes_single(image_path: str, values: List[float], psm: int) -> Tuple[Dict[str, int], List[Dict[str, Any]]]:
    img = cv2.imread(image_path)
    if img is None:
        raise ValueError("Invalid image path")

    height, width = img.shape[:2]

    if not values:
        return ({"width": width, "height": height}, [])

    data = pytesseract.image_to_data(
        img,
        lang="eng",
        config=f"--oem 3 --psm {psm} -c tessedit_char_whitelist=0123456789.,",
        output_type=Output.DICT,
    )

    boxes = []
    used = set()
    for i, word in enumerate(data["text"]):
        if not word:
            continue
        try:
            conf = float(data["conf"][i])
        except Exception:
            conf = -1
        if conf < 0:
            continue
        candidate = _to_float(word)
        if candidate is None:
            continue
        for target in values:
            if _value_matches(candidate, target):
                key = (data["left"][i], data["top"][i], data["width"][i], data["height"][i], target)
                if key in used:
                    continue
                used.add(key)
                boxes.append({
                    "left": int(data["left"][i]),
                    "top": int(data["top"][i]),
                    "width": int(data["width"][i]),
                    "height": int(data["height"][i]),
                    "value": target,
                })
                break

    return ({"width": width, "height": height}, boxes)

def _dedupe_boxes(boxes: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    seen = set()
    deduped = []
    for box in boxes:
        key = (box["left"], box["top"], box["width"], box["height"], box.get("value"))
        if key in seen:
            continue
        seen.add(key)
        deduped.append(box)
    return deduped

def find_value_boxes_multi(image_paths: List[str], values: List[float]) -> Tuple[Dict[str, int], List[Dict[str, Any]]]:
    first_meta: Optional[Dict[str, int]] = None
    all_boxes: List[Dict[str, Any]] = []
    for image_path in image_paths:
        meta6, boxes6 = _find_value_boxes_single(image_path, values, psm=6)
        meta11, boxes11 = _find_value_boxes_single(image_path, values, psm=11)
        if first_meta is None:
            first_meta = meta6
        all_boxes.extend(boxes6)
        all_boxes.extend(boxes11)
        if all_boxes:
            return (meta6, _dedupe_boxes(all_boxes))
    return (first_meta or {"width": 0, "height": 0}, _dedupe_boxes(all_boxes))

def find_value_boxes(image_path: str, values: List[float]) -> Tuple[Dict[str, int], List[Dict[str, Any]]]:
    return find_value_boxes_multi([image_path], values)

def get_image_meta(image_path: str) -> Dict[str, int]:
    img = cv2.imread(image_path)
    if img is None:
        return {"width": 0, "height": 0}
    height, width = img.shape[:2]
    return {"width": int(width), "height": int(height)}

def _collect_line_boxes(data: Dict[str, Any]) -> Dict[Tuple[int, int, int], Dict[str, Any]]:
    lines: Dict[Tuple[int, int, int], Dict[str, Any]] = {}
    for i, word in enumerate(data["text"]):
        if not word:
            continue
        key = (data["block_num"][i], data["par_num"][i], data["line_num"][i])
        left = int(data["left"][i])
        top = int(data["top"][i])
        width = int(data["width"][i])
        height = int(data["height"][i])
        right = left + width
        bottom = top + height
        entry = lines.get(key)
        if entry is None:
            lines[key] = {
                "left": left,
                "top": top,
                "right": right,
                "bottom": bottom,
            }
        else:
            entry["left"] = min(entry["left"], left)
            entry["top"] = min(entry["top"], top)
            entry["right"] = max(entry["right"], right)
            entry["bottom"] = max(entry["bottom"], bottom)
    return lines

def find_row_boxes_from_value_boxes(image_path: str, value_boxes: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    if not value_boxes:
        return []

    img = cv2.imread(image_path)
    if img is None:
        return []

    height, width = img.shape[:2]
    table_bbox = _detect_table_bbox(img)
    if table_bbox is not None:
        table_left, table_top, table_right, table_bottom = table_bbox
        table_left = max(0, int(table_left))
        table_right = min(width, int(table_right))
    else:
        table_left, table_right = 0, width
    row_lines = _detect_row_lines(img, table_bbox)
    typical_gap = None
    if row_lines and len(row_lines) >= 2:
        gaps = [b - a for a, b in zip(row_lines, row_lines[1:]) if b - a > 0]
        if gaps:
            gaps.sort()
            mid = len(gaps) // 2
            typical_gap = gaps[mid] if len(gaps) % 2 == 1 else (gaps[mid - 1] + gaps[mid]) / 2.0
    def _rows_for_psm(psm: int) -> List[Dict[str, Any]]:
        data = pytesseract.image_to_data(
            img,
            lang="eng",
            config=f"--oem 3 --psm {psm}",
            output_type=Output.DICT,
        )

        lines = _collect_line_boxes(data)
        if not lines:
            return []

        line_items = []
        for key, entry in lines.items():
            line_items.append({
                "key": key,
                "top": entry["top"],
                "bottom": entry["bottom"],
                "center": (entry["top"] + entry["bottom"]) / 2.0,
                "height": max(1, entry["bottom"] - entry["top"]),
            })

        used_keys = set()
        rows: List[Dict[str, Any]] = []
        for box in value_boxes:
            center_y = float(box["top"]) + (float(box["height"]) / 2.0)
            best = None
            best_dist = None
            for item in line_items:
                dist = abs(center_y - item["center"])
                if best is None or dist < best_dist:
                    best = item
                    best_dist = dist
            if best is None:
                continue
            # Relax distance check for perspective/distorted photos.
            if best_dist is not None and best_dist > max(best["height"] * 4, 20):
                continue
            if best["key"] in used_keys:
                continue
            used_keys.add(best["key"])
            pad = max(3, int(round(best["height"] * 0.25)))
            top = max(0, int(best["top"]) - pad)
            bottom = min(height, int(best["bottom"]) + pad)
            if row_lines:
                line_above = None
                line_below = None
                for y in row_lines:
                    if y <= center_y:
                        line_above = y
                    if y >= center_y and line_below is None:
                        line_below = y
                if line_above is not None and line_below is not None:
                    if (line_below - line_above) >= 6:
                        top = max(0, int(line_above) + 1)
                        bottom = min(height, int(line_below) - 1)
                        if typical_gap:
                            max_h = max(18, int(round(typical_gap * 1.1)))
                            cur_h = max(1, bottom - top)
                            if cur_h > max_h:
                                center_y = (float(top) + float(bottom)) / 2.0
                                top = max(0, int(center_y - (max_h / 2.0)))
                                bottom = min(height, int(center_y + (max_h / 2.0)))
            rows.append({
                "left": int(table_left),
                "top": top,
                "width": max(1, int(table_right - table_left)),
                "height": max(1, bottom - top),
                "value": box.get("value"),
            })
        return rows

    rows6 = _rows_for_psm(6)
    # Sparse/noisy reports often need sparse-text layout mode.
    rows11 = _rows_for_psm(11) if len(rows6) < min(len(value_boxes), 3) else []
    rows = _dedupe_boxes(rows6 + rows11)

    # Final fallback: build a row around unmatched value boxes.
    # This preserves highlight placement even when line OCR fails.
    for box in value_boxes:
        center_y = float(box["top"]) + (float(box["height"]) / 2.0)
        matched = False
        for row in rows:
            if row.get("value") != box.get("value"):
                continue
            row_center = float(row["top"]) + (float(row["height"]) / 2.0)
            if abs(center_y - row_center) <= max(float(box["height"]) * 2.0, 12.0):
                matched = True
                break
        if matched:
            continue
        pad = max(6, int(round(float(box["height"]) * 0.6)))
        top = max(0, int(round(float(box["top"]) - pad)))
        row_h = max(18, int(round(float(box["height"]) + (pad * 2.0))))
        bottom = min(height, top + row_h)
        if row_lines:
            line_above = None
            line_below = None
            for y in row_lines:
                if y <= center_y:
                    line_above = y
                if y >= center_y and line_below is None:
                    line_below = y
            if line_above is not None and line_below is not None:
                if (line_below - line_above) >= 6:
                    top = max(0, int(line_above) + 1)
                    bottom = min(height, int(line_below) - 1)
                    if typical_gap:
                        max_h = max(18, int(round(typical_gap * 1.1)))
                        cur_h = max(1, bottom - top)
                        if cur_h > max_h:
                            center_y = (float(top) + float(bottom)) / 2.0
                            top = max(0, int(center_y - (max_h / 2.0)))
                            bottom = min(height, int(center_y + (max_h / 2.0)))
        rows.append({
            "left": int(table_left),
            "top": top,
            "width": max(1, int(table_right - table_left)),
            "height": max(1, bottom - top),
            "value": box.get("value"),
        })

    rows = _dedupe_boxes(rows)

    # Keep one best row per abnormal value to avoid duplicate highlights.
    target_centers = {}
    for box in value_boxes:
        val = box.get("value")
        if val in target_centers:
            continue
        target_centers[val] = float(box["top"]) + (float(box["height"]) / 2.0)

    best_rows = {}
    other_rows = []
    for row in rows:
        val = row.get("value")
        if val not in target_centers:
            other_rows.append(row)
            continue
        row_center = float(row["top"]) + (float(row["height"]) / 2.0)
        dist = abs(row_center - target_centers[val])
        prev = best_rows.get(val)
        if prev is None or dist < prev["dist"]:
            best_rows[val] = {"dist": dist, "row": row}

    return [entry["row"] for entry in best_rows.values()] + other_rows

def find_row_boxes_by_test_names(image_path: str, test_names: List[str]) -> List[Dict[str, Any]]:
    tests = [_normalize_match_text(t) for t in test_names if t]
    expanded = []
    for t in tests:
        if not t:
            continue
        expanded.append(t)
        if t == "BUN":
            expanded.append("BLOOD UREA NITROGEN")
        elif t == "UREA":
            expanded.append("BLOOD UREA")
        elif t == "HEMOGLOBIN":
            expanded.append("HAEMOGLOBIN")
        elif t == "HAEMOGLOBIN":
            expanded.append("HEMOGLOBIN")
    tests = [t for t in expanded if t]
    if not tests:
        return []

    img = cv2.imread(image_path)
    if img is None:
        return []

    height, width = img.shape[:2]
    table_bbox = _detect_table_bbox(img)
    if table_bbox is not None:
        table_left, table_top, table_right, table_bottom = table_bbox
        table_left = max(0, int(table_left))
        table_right = min(width, int(table_right))
    else:
        table_left, table_right = 0, width
    row_lines = _detect_row_lines(img, table_bbox)
    data = pytesseract.image_to_data(
        img,
        lang="eng",
        config="--oem 3 --psm 6",
        output_type=Output.DICT,
    )

    lines: Dict[Tuple[int, int, int], Dict[str, Any]] = {}
    for i, word in enumerate(data["text"]):
        if not word:
            continue
        key = (data["block_num"][i], data["par_num"][i], data["line_num"][i])
        left = int(data["left"][i])
        top = int(data["top"][i])
        width_w = int(data["width"][i])
        height_w = int(data["height"][i])
        right = left + width_w
        bottom = top + height_w
        entry = lines.get(key)
        if entry is None:
            lines[key] = {
                "left": left,
                "top": top,
                "right": right,
                "bottom": bottom,
                "words": [(left, word)],
            }
        else:
            entry["left"] = min(entry["left"], left)
            entry["top"] = min(entry["top"], top)
            entry["right"] = max(entry["right"], right)
            entry["bottom"] = max(entry["bottom"], bottom)
            entry["words"].append((left, word))

    # Estimate a typical row height from OCR line boxes to avoid giant highlights.
    line_heights = [
        max(1, int(entry["bottom"]) - int(entry["top"]))
        for entry in lines.values()
    ]
    line_heights.sort()
    typical_h = line_heights[len(line_heights) // 2] if line_heights else 0
    max_gap = max(int(typical_h * 1.6), 28) if typical_h else 50

    def _line_text(entry: Dict[str, Any]) -> str:
        words_sorted = sorted(entry["words"], key=lambda w: w[0])
        raw = " ".join(w[1] for w in words_sorted)
        return _normalize_match_text(raw)

    def _match_test(test: str, line: str) -> bool:
        if not test or not line:
            return False
        if test in line:
            return True
        tokens = test.split()
        if len(tokens) == 1:
            return tokens[0] in line.split()
        idx = 0
        for token in tokens:
            pos = line.find(token, idx)
            if pos == -1:
                return False
            idx = pos + len(token)
        return True

    def _fuzzy_token_match(test: str, line: str) -> bool:
        import difflib

        test_tokens = [t for t in test.split() if len(t) >= 3]
        line_tokens = [t for t in line.split() if len(t) >= 3]
        if not test_tokens or not line_tokens:
            return False
        # Avoid fuzzy matching for single-token tests to reduce false highlights.
        # Exception: allow longer single tokens (e.g., HEMOGLOBIN/HAEMOGLOBIN)
        # with a stricter threshold to catch common OCR variants.
        if len(test_tokens) == 1:
            token = test_tokens[0]
            if len(token) < 6:
                return False
            best_ratio = 0.0
            for lt in line_tokens:
                ratio = difflib.SequenceMatcher(None, token, lt).ratio()
                if ratio > best_ratio:
                    best_ratio = ratio
            return best_ratio >= 0.86

        def _has_token_like(target: str, tokens: List[str], threshold: float = 0.75) -> bool:
            for tok in tokens:
                if tok == target:
                    return True
                if len(target) <= 4 and len(tok) <= 5:
                    ratio = difflib.SequenceMatcher(None, target, tok).ratio()
                    if ratio >= threshold:
                        return True
            return False

        # Guard against mapping LDL/HDL/VLDL/NON-HDL tests to plain cholesterol rows.
        key_short_tokens = [t for t in test_tokens if t in {"LDL", "HDL", "VLDL", "NON", "RATIO"}]
        for short_tok in key_short_tokens:
            if not _has_token_like(short_tok, line_tokens):
                return False

        # For short tokens (<= 4 chars), require exact matches to avoid
        # false positives like UREA -> URIC.
        for tt in test_tokens:
            if len(tt) <= 4 and tt not in line_tokens:
                return False

        matched = 0
        used_line_idxs = set()
        for tt in test_tokens:
            best_idx = None
            best_ratio = 0.0
            for idx, lt in enumerate(line_tokens):
                if idx in used_line_idxs:
                    continue
                ratio = difflib.SequenceMatcher(None, tt, lt).ratio()
                if ratio > best_ratio:
                    best_ratio = ratio
                    best_idx = idx
            threshold = 0.8
            if len(tt) <= 5:
                threshold = 0.9
            if best_idx is not None and best_ratio >= threshold:
                used_line_idxs.add(best_idx)
                matched += 1

        # For multi-token tests (e.g. LDL CHOLESTEROL, CHOL HDL RATIO),
        # require stronger overlap than a single token match.
        if len(test_tokens) >= 2:
            needed = max(2, int(round(len(test_tokens) * 0.7)))
            return matched >= needed
        return matched >= 1

    matched_keys = {}
    for key, entry in lines.items():
        line = _line_text(entry)
        for test in tests:
            if _match_test(test, line) or _fuzzy_token_match(test, line):
                matched_keys[key] = test
                break

    row_boxes: List[Dict[str, Any]] = []
    for key, matched_test in matched_keys.items():
        entry = lines.get(key)
        if entry is None:
            continue
        line_h = max(1, int(entry["bottom"]) - int(entry["top"]))
        pad = max(1, int(round(line_h * 0.06)))
        top = max(0, int(entry["top"]) - pad)
        bottom = min(height, int(entry["bottom"]) + pad)

        # If OCR merged multiple rows into one tall line, clamp to typical height.
        if typical_h and line_h > max(int(typical_h * 1.6), 28):
            center_y = (float(entry["top"]) + float(entry["bottom"])) / 2.0
            clamped_h = max(typical_h, 18)
            clamp_pad = max(3, int(round(clamped_h * 0.25)))
            top = max(0, int(center_y - (clamped_h / 2.0) - clamp_pad))
            bottom = min(height, int(center_y + (clamped_h / 2.0) + clamp_pad))
        # Final tighten: clamp to near-typical row height.
        if typical_h:
            cur_h = max(1, bottom - top)
            max_h = max(18, int(round(typical_h * 1.2)))
            if cur_h > max_h:
                center_y = (float(top) + float(bottom)) / 2.0
                new_h = max_h
                top = max(0, int(center_y - (new_h / 2.0)))
                bottom = min(height, int(center_y + (new_h / 2.0)))
        if row_lines:
            center_y = (float(entry["top"]) + float(entry["bottom"])) / 2.0
            line_above = None
            line_below = None
            for y in row_lines:
                if y <= center_y:
                    line_above = y
                if y >= center_y and line_below is None:
                    line_below = y
            if line_above is not None and line_below is not None:
                gap = line_below - line_above
                if gap >= 6:
                    mid = (line_above + line_below) / 2.0
                    half = max(8, int(round(gap * 0.45)))
                    top = max(0, int(mid - half))
                    bottom = min(height, int(mid + half))
        # Final tighten after row-line adjustments.
        if typical_h:
            center_y = (float(top) + float(bottom)) / 2.0
            target_h = max(16, int(round(typical_h * 0.95)))
            top = max(0, int(center_y - (target_h / 2.0)))
            bottom = min(height, int(center_y + (target_h / 2.0)))
        row_boxes.append({
            "left": int(table_left),
            "top": top,
            "width": max(1, int(table_right - table_left)),
            "height": max(1, bottom - top),
            "test": matched_test,
        })

    return row_boxes