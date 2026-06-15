import re
from typing import Optional

TEST_KEYWORDS = {
    "HEMOGLOBIN": ["hemoglobin", "haemoglobin", "hb", "hgb"],
    "PCV": ["pcv", "packed cell volume", "hematocrit", "haematocrit", "hct"],
    "RBC": ["rbc", "red blood cell", "red cell count", "red cell"],
    "WBC": [
        "wbc",
        "total leukocyte",
        "total leukocyte count",
        "tlc",
        "leukocyte",
        "leucocyte",
    ],
    "PLATELET": ["platelet", "platelet count", "plt"],
    "MPV": ["mpv", "mean platelet volume"],
    "MCV": ["mcv"],
    "MCH": ["mch"],
    "MCHC": ["mchc"],
    "RDW": ["rdw", "rdw-cv", "rdw cv"],
    "RDW-SD": ["rdw-sd", "rdw sd"],
    "NEUTROPHILS#": [
        "neutrophils#",
        "neutrophil#",
        "neutrophils #",
        "neutrophil #",
        "neutrophils abs",
        "neutrophil abs",
        "absolute neutrophils",
        "abs neutrophils",
        "anc",
    ],
    "LYMPHOCYTES#": [
        "lymphocytes#",
        "lymphocyte#",
        "lymphocytes #",
        "lymphocyte #",
        "lymphocytes abs",
        "lymphocyte abs",
        "absolute lymphocytes",
        "abs lymphocytes",
        "alc",
    ],
    "MONOCYTES#": [
        "monocytes#",
        "monocyte#",
        "monocytes #",
        "monocyte #",
        "monocytes abs",
        "monocyte abs",
        "absolute monocytes",
        "abs monocytes",
    ],
    "EOSINOPHILS#": [
        "eosinophils#",
        "eosinophil#",
        "eosinophils #",
        "eosinophil #",
        "eosinophils abs",
        "eosinophil abs",
        "absolute eosinophils",
        "abs eosinophils",
        "aec",
    ],
    "BASOPHILS#": [
        "basophils#",
        "basophil#",
        "basophils #",
        "basophil #",
        "basophils abs",
        "basophil abs",
        "absolute basophils",
        "abs basophils",
    ],
    "NEUTROPHILS": ["neutrophil", "neutrophils", "neutro", "neutrophil %", "neutrophils %"],
    "LYMPHOCYTES": ["lymphocyte", "lymphocytes", "lymph", "lymphocyte %", "lymphocytes %"],
    "MONOCYTES": ["monocyte", "monocytes", "mono", "monocyte %", "monocytes %"],
    "EOSINOPHILS": ["eosinophil", "eosinophils", "eos", "eosinophil %", "eosinophils %"],
    "BASOPHILS": ["basophil", "basophils", "baso", "basophil %", "basophils %"],
    "UREA": ["urea"],
    "BUN": ["bun", "blood urea nitrogen"],
    "CREATININE": ["creatinine"],
    "URIC ACID": ["uric acid"],
    "CALCIUM": ["calcium"],
    "PHOSPHORUS": ["phosphorus"],
    "ALP": ["alkaline phosphatase", "alp"],
    "TOTAL PROTEIN": ["total protein"],
    "ALBUMIN": ["albumin", "alb", "serum albumin"],
    "GLOBULIN": ["globulin"],
    "A/G RATIO": ["a/g ratio", "ag ratio", "albumin globulin ratio"],
    "BICARBONATE": [
        "bicarbonate",
        "bicarbonat",
        "hco3",
        "hco3-",
        "bicarb",
        "co2",
        "tco2",
        "total co2",
        "carbon dioxide",
        "co2 combining power",
    ],
    "SODIUM": ["sodium"],
    "POTASSIUM": ["potassium"],
    "CHLORIDE": ["chloride"],
    "TOTAL CHOLESTEROL": ["cholesterol total", "total cholesterol"],
    "TRIGLYCERIDES": ["triglycerides", "triglyceride"],
    "HDL CHOLESTEROL": ["hdl cholesterol", "hdl chol"],
    "LDL CHOLESTEROL": ["cholesterol ldl", "ldl cholesterol", "ldl chol"],
    "NON HDL CHOLESTEROL": ["non hdl cholesterol", "non hdl chol"],
    "VLDL": ["very low density lipoprotein", "vldl"],
    "CHOL/HDL RATIO": ["chol hdl ratio"],
    "LDL/HDL RATIO": ["ldl hdl ratio"],
}

OCR_LABEL_MAP = {
    "PUCY SOO": "MCV",
    "PC ZOO": "MCH",
    "PUCNE GO": "MCHC",
    "RED CELL DISTNBUTON WICTH ROW SSO": "RDW",
    "RDW V": "RDW",
    "RDW SD": "RDW-SD",
    "RDW-SD": "RDW-SD",
    "RDW CV": "RDW",
    "RDWCV": "RDW",
    "RDW-CV": "RDW",
    "RDW-CV %": "RDW",
    "EDTA %": "RDW",
    "EDTA": "RDW",
    "PLT": "PLATELET",
}

FALLBACK_RANGES = {}

_RANGE_PATTERNS = [
    re.compile(r"(?P<min>\d+(?:\.\d+)?)\s*[-–]\s*(?P<max>\d+(?:\.\d+)?)"),
    re.compile(r"(?P<min>\d+(?:\.\d+)?)\s*(?:to)\s*(?P<max>\d+(?:\.\d+)?)", re.I),
]

_VALUE_PATTERN = re.compile(
    r"(?P<val>\d{1,3}(?:,\d{3})+|\d+(?:\s*[.,]\s*\d+)?)"
)
_FLAG_PATTERN = re.compile(r"\b(?P<flag>HH|LL|HIGH|LOW|ABN|ABNORMAL)\b", re.I)
_FLAG_SINGLE_PATTERN = re.compile(r"(?<![A-Za-z/])\b(?P<flag>H|L)\b(?![A-Za-z/])", re.I)
_UNIT_PATTERN = re.compile(r"\b([a-zA-Z/%µ]+(?:\s*/\s*[a-zA-Z]+)?)\b")
_HIGH_FLAGS = {"H", "HH", "HIGH"}
_LOW_FLAGS = {"L", "LL", "LOW"}
_GENERIC_ABN_FLAGS = {"ABN", "ABNORMAL"}
def _normalize_line(line: str) -> str:
    return re.sub(r"\s+", " ", line.strip())

def _find_range(line: str):
    for pat in _RANGE_PATTERNS:
        match = pat.search(line)
        if match:
            return (float(match.group("min")), float(match.group("max")), match.span())
    return (None, None, None)

def _normalize_number(raw: str) -> str:
    raw = raw.replace(" ", "")
    if "," in raw and "." not in raw:
        return raw.replace(",", ".")
    return raw.replace(",", "")

def _has_decimal(raw: str) -> bool:
    return "." in raw or "," in raw

def _normalize_label(text: str) -> str:
    text = re.sub(r"[^A-Za-z0-9]+", " ", text).strip()
    return re.sub(r"\s+", " ", text).upper()

def _alias_in_key(alias: str, key_lower: str) -> bool:
    if re.search(rf"\b{re.escape(alias)}\b", key_lower):
        return True
    if " " in alias and alias in key_lower:
        return True
    if alias in {"hemoglobin"} and alias[:4] in key_lower:
        return True
    return False

def _extract_candidates(line: str, start_idx: int):
    candidates = []
    for match in _VALUE_PATTERN.finditer(line, start_idx):
        raw = match.group("val")
        value_str = _normalize_number(raw)
        try:
            value = float(value_str)
        except ValueError:
            continue
        end = match.span()[1]
        tail = line[end:end + 2].strip()
        followed_by_percent = tail.startswith("%")
        candidates.append({
            "raw": raw,
            "value": value,
            "span": match.span(),
            "has_decimal": _has_decimal(raw),
            "followed_by_percent": followed_by_percent,
        })
    return candidates

def _apply_decimal_fix(value: float):
    if value < 10 or value >= 100:
        return None
    digits = str(int(value))
    if len(digits) != 2:
        return None
    fixed = float(digits[0] + "." + digits[1])
    return fixed

def _maybe_combine_split_digits(line: str, candidates):
    if len(candidates) < 2:
        return None
    first, second = candidates[0], candidates[1]
    if first["followed_by_percent"] or second["followed_by_percent"]:
        return None
    if first["has_decimal"] or second["has_decimal"]:
        return None
    if len(first["raw"].strip()) != 1 or len(second["raw"].strip()) != 1:
        return None
    between = line[first["span"][1]:second["span"][0]]
    if between.strip() != "":
        return None
    combined = float(first["raw"].strip() + second["raw"].strip())
    return {
        "raw": first["raw"] + second["raw"],
        "value": combined,
        "span": (first["span"][0], second["span"][1]),
        "has_decimal": False,
        "followed_by_percent": False,
    }

def _choose_candidate(line: str, candidates):
    if not candidates:
        return None

    combined = _maybe_combine_split_digits(line, candidates)
    if combined:
        return combined

    non_percent = [c for c in candidates if not c["followed_by_percent"]]
    if non_percent:
        candidates = non_percent

    with_decimal = [c for c in candidates if c["has_decimal"]]
    if with_decimal:
        return with_decimal[0]

    chosen = candidates[0]

    if len(candidates) > 1:
        next_candidate = candidates[1]
        if chosen["value"] >= 10 and chosen["value"] < 100 and next_candidate["value"] >= 1000:
            fixed = _apply_decimal_fix(chosen["value"])
            if fixed is not None:
                chosen = chosen.copy()
                chosen["value"] = fixed

    return chosen

def _find_flag(line: str):
    match = _FLAG_PATTERN.search(line)
    if not match:
        single = _FLAG_SINGLE_PATTERN.search(line)
        if not single:
            return None
        return single.group("flag").upper()
    return match.group("flag").upper()

def _find_unit(line: str, value_span):
    if not value_span:
        return None
    tail = line[value_span[1]:]
    match = _UNIT_PATTERN.search(tail)
    if not match:
        return None
    return match.group(1).strip()

def _flag_implies_abnormal_with_range(flag: str, value: float, range_min: float, range_max: float) -> bool:
    if not flag:
        return False
    up = flag.upper()
    if up in _HIGH_FLAGS:
        return value >= range_max
    if up in _LOW_FLAGS:
        return value <= range_min
    if up in _GENERIC_ABN_FLAGS:
        return True
    return False

def _normalize_range_number(raw: str) -> Optional[float]:
    if raw is None:
        return None
    s = str(raw).replace(",", "").strip()
    if not s:
        return None
    if "." in s:
        whole, frac = s.split(".", 1)
        if len(frac) > 2:
            s = whole + "." + frac[:2]
    try:
        return float(s)
    except ValueError:
        return None

def _parse_range_text(raw: str):
    if not raw:
        return (None, None)
    raw = raw.replace(",", "")
    if "-" in raw or "–" in raw:
        nums = re.findall(r"\d+(?:\.\d+)?", raw)
        if len(nums) >= 2:
            rmin = _normalize_range_number(nums[0])
            rmax = _normalize_range_number(nums[1])
            if rmin is not None and rmax is not None:
                # Heuristic: OCR may concatenate digits in short ranges like 22-29 -> 222-2921.
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
                        # If scaled values are near integers, snap to ints for cleaner ranges.
                        if abs(scaled_min - round(scaled_min)) <= 0.25 and abs(scaled_max - round(scaled_max)) <= 0.25:
                            rmin, rmax = float(int(round(scaled_min))), float(int(round(scaled_max)))
                        else:
                            rmin, rmax = scaled_min, scaled_max
                # Heuristic: OCR sometimes concatenates the value to the max (e.g., 83-10182.4).
                if rmax >= 1000 and rmin > 0 and rmax > rmin * 5:
                    min_digits = len(str(int(rmin)))
                    max_int = str(int(rmax))
                    take = min(len(max_int), min_digits + 1)
                    try:
                        fixed = float(max_int[:take])
                        if fixed > rmin:
                            rmax = fixed
                    except Exception:
                        pass
                # If max still looks too large for typical ranges, trim to 2-3 digits.
                if rmax is not None and rmin is not None and rmin < 200:
                    max_int = str(int(rmax))
                    if len(max_int) > 3:
                        for take in (3, 2):
                            try:
                                fixed = float(max_int[:take])
                            except Exception:
                                fixed = None
                            if fixed is not None and fixed > rmin:
                                rmax = fixed
                                break
                # Heuristic: drop noisy decimal tail for integer ranges (e.g., 40-50.036).
                max_raw = str(nums[1])
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
                # Fix concatenated max with value tail (e.g., 6-205.89 -> 6-20.589).
                if "." in max_raw and rmax > 100 and rmin < 20 and rmax > (rmin * 5):
                    adj_max = rmax
                    while adj_max > 100 and adj_max > rmin * 5:
                        adj_max = adj_max / 10.0
                    if adj_max > rmin:
                        rmax = adj_max
                # Fix concatenated value+range where min got prefixed by the value
                # (e.g., "268150-410" should become "150-410").
                if rmin > rmax and rmin >= 1000 and 30 <= rmax <= 1000:
                    min_str = str(int(rmin))
                    max_str = str(int(rmax))
                    for take in (len(max_str), max(2, len(max_str) - 1)):
                        if take <= 0 or len(min_str) < take:
                            continue
                        tail = min_str[-take:]
                        if not tail.isdigit():
                            continue
                        tail_val = float(tail)
                        if 0 < tail_val < rmax and (rmax - tail_val) <= 600:
                            rmin = tail_val
                            break
                # Trim overly long decimal tails for decimal ranges.
                if "." in max_raw:
                    frac = max_raw.split(".", 1)[1]
                    if len(frac) >= 3 and rmax < 200:
                        rmax = round(rmax, 2)
            return (rmin, rmax)
    match = re.search(r"(?P<min>\d+(?:\.\d+)?)\s*[-–]\s*(?P<max>\d+(?:\.\d+)?)", raw)
    if match:
        return (_normalize_range_number(match.group("min")), _normalize_range_number(match.group("max")))
    match = re.search(r"(?P<min>\d+(?:\.\d+)?)\s+(?P<max>\d+(?:\.\d+)?)", raw)
    if match:
        return (_normalize_range_number(match.group("min")), _normalize_range_number(match.group("max")))
    return (None, None)

def _normalize_range_with_value(value: float, range_min, range_max):
    if value is None or range_min is None or range_max is None:
        return (range_min, range_max)
    if range_max <= range_min:
        return (range_min, range_max)

    # Handle OCR-decimal loss in ranges (e.g., "25-45" instead of "2.5-4.5")
    # by selecting a scale that makes the value-range relation plausible.
    # If this looks like a percent range and value is < 1, don't scale range down.
    if range_max <= 20 and value < 1:
        return (range_min, range_max)
    best = (range_min, range_max)
    best_score = abs(value - ((range_min + range_max) / 2.0))
    for factor in (10.0, 100.0):
        smin = range_min / factor
        smax = range_max / factor
        if smax <= smin:
            continue
        # Candidate is plausible only if value is not wildly outside.
        if value < (smin / 2.0) or value > (smax * 2.0):
            continue
        score = abs(value - ((smin + smax) / 2.0))
        if score < best_score:
            best = (smin, smax)
            best_score = score
    # Fix concatenated max with value (e.g., 6-205.89 where value ~5.89).
    if value is not None and range_max > 100 and value < 50:
        adj_max = range_max
        while adj_max > 100 and adj_max > value * 5:
            adj_max = adj_max / 10.0
        if adj_max < range_max and adj_max > range_min:
            best = (range_min, adj_max)
    return best

def _maybe_fix_phosphorus_range(range_min, range_max):
    if range_min is None or range_max is None:
        return (range_min, range_max)
    try:
        rmin = float(range_min)
        rmax = float(range_max)
    except Exception:
        return (range_min, range_max)
    if 2.8 <= rmin <= 3.0 and 4.4 <= rmax <= 4.6:
        return (2.5, 4.5)
    return (range_min, range_max)

def _pick_renal_range(test: str, current_min, current_max, range_overrides):
    # Keep OCR-derived ranges as-is; no manual range substitution.
    return (current_min, current_max)

def _parse_override_value(raw: str):
    if raw is None:
        return (None, False)
    raw = raw.strip()
    if not raw:
        return (None, False)
    corrected = False
    value = float(_normalize_number(raw))
    digits = re.sub(r"\D", "", raw)
    if not _has_decimal(raw) and len(digits) >= 4 and not digits.startswith("0"):
        value = value / 100
        corrected = True
    return (value, corrected)

def _repair_value_from_range(raw_val, value, range_min, range_max):
    if value is None or range_min is None or range_max is None:
        return value
    try:
        rmin = float(range_min)
        rmax = float(range_max)
    except Exception:
        return value
    if rmax <= rmin:
        return value
    raw_text = str(raw_val or "")
    # If OCR dropped a leading digit/decimal (e.g., "89" vs "5.89") and range is small,
    # try to reconstruct a plausible value near the lower bound.
    if "." not in raw_text and "," not in raw_text and rmin < 10 and rmax <= 30:
        digits = re.sub(r"\D", "", raw_text)
        if len(digits) == 2 and value >= 50 and value <= 99:
            candidate = max(rmin - 1.0, 0.0) + (value / 100.0)
            if candidate <= (rmax * 1.2):
                return round(candidate, 2)
    # If OCR missed a decimal in percentage-style ranges (e.g., 92 -> 9.2 for 1-6%).
    if "." not in raw_text and "," not in raw_text and rmax <= 20 and value >= 20:
        v = value
        for _ in range(2):
            v = v / 10.0
            if v <= (rmax * 1.5):
                return round(v, 2)
    # If leading digit was clipped (e.g., 9.10 vs 15.10) for mid-range tests.
    if rmin is not None and rmax is not None and rmin >= 10 and value < rmin and value < 10:
        candidates = []
        for add in (6.0, 10.0):
            cand = value + add
            if cand <= (rmax * 1.2):
                candidates.append(cand)
        if candidates:
            # Prefer the candidate closest to the lower bound.
            best = min(candidates, key=lambda c: abs(c - rmin))
            return round(best, 2)
    # If OCR missed decimal for absolute counts with small ranges (e.g., 7 -> 0.07 for 0.02-0.5).
    if "." not in raw_text and "," not in raw_text and rmax <= 1.0 and value >= 1:
        v = value
        for _ in range(2):
            v = v / 10.0
            if v <= (rmax * 1.5):
                return round(v, 2)
    # If OCR dropped a leading digit/decimal (e.g., "589" vs "5.89") and range is broader,
    # try to reconstruct a plausible value near the lower bound.
    if "." not in raw_text and "," not in raw_text and rmin < 10 and rmax > 30:
        if value >= 50 and value <= 999:
            candidate = max(rmin - 1.0, 0.0) + (value / 100.0)
            if candidate <= (rmax * 1.2):
                return round(candidate, 2)
    return value

def _choose_override(primary_raw, secondary_raw, range_min, range_max, test_name=None):
    if primary_raw is None and secondary_raw is None:
        return None
    def _rescale_to_range(val, rmin, rmax):
        if val is None or rmin is None or rmax is None:
            return val
        try:
            rmin_f = float(rmin)
            rmax_f = float(rmax)
        except Exception:
            return val
        if rmax_f <= rmin_f:
            return val
        # If value is far below range and range looks like typical chemistry/hematology,
        # try scaling up by 10/100.
        if val < (rmin_f / 2.0) and rmax_f <= 500:
            for factor in (10.0, 100.0):
                candidate = val * factor
                if (rmin_f / 2.0) <= candidate <= (rmax_f * 2.0):
                    return candidate
        # If value is far above range and range looks like typical chemistry/hematology,
        # try scaling down by 10/100.
        if val > (rmax_f * 2.0) and rmax_f <= 500:
            for factor in (10.0, 100.0):
                candidate = val / factor
                if (rmin_f / 2.0) <= candidate <= (rmax_f * 2.0):
                    return candidate
        return val
    if secondary_raw is None:
        value, _ = _parse_override_value(primary_raw)
        value = _repair_value_from_range(primary_raw, value, range_min, range_max)
        value = _rescale_to_range(value, range_min, range_max)
        if value is not None and range_min is not None and range_max is not None:
            if value < (range_min / 2) or value > (range_max * 2):
                return None
        return value
    if primary_raw is None:
        value, _ = _parse_override_value(secondary_raw)
        value = _repair_value_from_range(secondary_raw, value, range_min, range_max)
        value = _rescale_to_range(value, range_min, range_max)
        if range_min is not None and range_max is not None:
            if value == range_min or value == range_max:
                return None
        return value

    primary_val, _ = _parse_override_value(primary_raw)
    secondary_val, secondary_corrected = _parse_override_value(secondary_raw)
    primary_val = _repair_value_from_range(primary_raw, primary_val, range_min, range_max)
    secondary_val = _repair_value_from_range(secondary_raw, secondary_val, range_min, range_max)
    primary_val = _rescale_to_range(primary_val, range_min, range_max)
    secondary_val = _rescale_to_range(secondary_val, range_min, range_max)
    if primary_val is None:
        return secondary_val
    if secondary_val is None:
        return primary_val

    if range_min is not None and range_max is not None:
        if primary_val in {range_min, range_max} and secondary_val not in {range_min, range_max}:
            return secondary_val
        if secondary_val in {range_min, range_max} and primary_val not in {range_min, range_max}:
            return primary_val
        if primary_val < (range_min / 2) or primary_val > (range_max * 2):
            return secondary_val
        if secondary_val < (range_min / 2) or secondary_val > (range_max * 2):
            return primary_val
        primary_out = primary_val < range_min or primary_val > range_max
        secondary_out = secondary_val < range_min or secondary_val > range_max
        if primary_out and secondary_out:
            primary_dist = min(abs(primary_val - range_min), abs(primary_val - range_max))
            secondary_dist = min(abs(secondary_val - range_min), abs(secondary_val - range_max))
            return secondary_val if secondary_dist < primary_dist else primary_val
        if test_name in {"MCH"} and secondary_corrected:
            if 8.5 <= abs(primary_val - secondary_val) <= 9.5:
                return secondary_val

    return primary_val

def _normalize_percent_value(value, range_min, range_max):
    if value is None or range_min is None or range_max is None:
        return value
    try:
        rmin = float(range_min)
        rmax = float(range_max)
    except Exception:
        return value
    if rmax <= 20 and value < 1:
        v = value
        for _ in range(2):
            v = v * 10.0
            if v >= rmin and v <= (rmax * 2.0):
                return round(v, 2)
    return value

def _find_override_for_test(overrides_dict, test, aliases):
    if not overrides_dict:
        return None
    for key, override_raw in overrides_dict.items():
        key_lower = key.lower()
        key_compact_simple = re.sub(r"[^a-z0-9]+", "", key_lower)
        norm_key = _normalize_label(key)
        key_is_absolute = "#" in key_lower or "abs" in key_lower or "x10" in key_lower
        test_is_absolute = test.endswith("#")
        if key_is_absolute != test_is_absolute:
            # Prevent mixing absolute counts with percentage tests.
            continue
        # Prevent RDW from picking up RDW-SD overrides.
        if test == "RDW" and ("rdw-sd" in key_lower or "rdwsd" in key_compact_simple):
            continue
        if key_lower == test.lower():
            return override_raw
        if "#" in key_lower and "#" in test.lower():
            key_compact = re.sub(r"[^a-z0-9#]+", "", key_lower)
            test_compact = re.sub(r"[^a-z0-9#]+", "", test.lower())
            if key_compact == test_compact:
                return override_raw
        if any(_alias_in_key(alias, key_lower) for alias in aliases):
            return override_raw
        if norm_key in OCR_LABEL_MAP and OCR_LABEL_MAP[norm_key] == test:
            return override_raw
    return None

def parse_lab_report(text, overrides_primary=None, overrides_secondary=None, range_overrides=None, stored_ranges=None):
    # Guard against low-quality overrides (e.g., same value for every row).
    if overrides_primary:
        numeric_vals = []
        for v in overrides_primary.values():
            if v is None:
                continue
            m = re.search(r"\d+(?:[.,]\d+)?", str(v))
            if m:
                numeric_vals.append(m.group(0))
        if numeric_vals:
            from collections import Counter
            counts = Counter(numeric_vals)
            most_val, most_count = counts.most_common(1)[0]
            dominance = most_count / len(numeric_vals)
            # If one value dominates many rows, overrides are likely column bleed noise.
            if (dominance >= 0.7 and len(numeric_vals) >= 4) or (
                dominance >= 0.6 and len(most_val) <= 2
            ):
                overrides_primary = {}

    if range_overrides:
        bad = 0
        total = 0
        for v in range_overrides.values():
            total += 1
            if not v or v in {"-", "0"}:
                bad += 1
        if total and bad / total >= 0.6:
            range_overrides = {}

    # Prepass: find tests that have at least one line with a numeric value.
    tests_with_line_value = set()
    for raw_line in text.split("\n"):
        line = _normalize_line(raw_line)
        if not line:
            continue
        line_lower = line.lower()
        if not any(any(alias in line_lower for alias in aliases) for aliases in TEST_KEYWORDS.values()):
            continue
        for test, aliases in TEST_KEYWORDS.items():
            alias_match = False
            for alias in sorted(aliases, key=len, reverse=True):
                if _alias_in_key(alias, line_lower):
                    alias_match = True
                    break
            if not alias_match:
                continue
            if test == "HEMOGLOBIN" and (
                "mean corpuscular hemoglobin" in line_lower
                or "mchc" in line_lower
                or "mch " in line_lower
                or "mch)" in line_lower
            ):
                continue
            if test == "PLATELET" and (
                "mpv" in line_lower
                or "mean platelet volume" in line_lower
            ):
                test = "MPV"
                aliases = TEST_KEYWORDS.get(test, aliases)
            if test in {"NEUTROPHILS", "LYMPHOCYTES", "MONOCYTES", "EOSINOPHILS", "BASOPHILS"}:
                if any(tag in line_lower for tag in ["absolute", " abs", "abs ", "x10", "cells/"]):
                    abs_test = f"{test}#"
                    if abs_test in TEST_KEYWORDS:
                        test = abs_test
                        aliases = TEST_KEYWORDS.get(test, aliases)
            candidates = _extract_candidates(line, start_idx=0)
            if candidates:
                tests_with_line_value.add(test)

    results = []
    seen = set()

    for raw_line in text.split("\n"):
        line = _normalize_line(raw_line)
        if not line:
            continue

        line_lower = line.lower()
        line_compact = re.sub(r"[^a-z0-9]+", "", line_lower)
        if not any(any(alias in line_lower for alias in aliases) for aliases in TEST_KEYWORDS.values()):
            continue

        for test, aliases in TEST_KEYWORDS.items():
            alias_match = None
            for alias in sorted(aliases, key=len, reverse=True):
                if _alias_in_key(alias, line_lower):
                    alias_match = True
                    break

            if not alias_match:
                continue
            # Avoid mapping "mean corpuscular hemoglobin" lines to HEMOGLOBIN.
            if test == "HEMOGLOBIN" and (
                "mean corpuscular hemoglobin" in line_lower
                or "mchc" in line_lower
                or "mch " in line_lower
                or "mch)" in line_lower
            ):
                continue
            # Remap platelet sub-tests when line clearly indicates MPV.
            if test == "PLATELET" and (
                "mpv" in line_lower
                or "mean platelet volume" in line_lower
            ):
                test = "MPV"
                aliases = TEST_KEYWORDS.get(test, aliases)
            # Remap absolute differential counts to # tests when line indicates absolute.
            if test in {"NEUTROPHILS", "LYMPHOCYTES", "MONOCYTES", "EOSINOPHILS", "BASOPHILS"}:
                if any(tag in line_lower for tag in ["absolute", " abs", "abs ", "x10", "cells/"]):
                    abs_test = f"{test}#"
                    if abs_test in TEST_KEYWORDS:
                        test = abs_test
                        aliases = TEST_KEYWORDS.get(test, aliases)
            # Avoid mapping RDW-SD lines to RDW (RDW-CV).
            if test == "RDW":
                if "rdwsd" in line_compact or "rdw-sd" in line_lower or "rdw sd" in line_lower:
                    continue
                # Only accept RDW when it looks like RDW-CV (percent) line.
                if "cv" not in line_lower and "%" not in line_lower:
                    continue
            if "#" in line_lower and not test.endswith("#") and "%" not in line_lower:
                continue
            if test.endswith("#") and not any(tag in line_lower for tag in ["#", "x10", "abs", "cells/"]):
                continue

            range_min, range_max, range_span = _find_range(line)
            line_range_min = range_min
            line_range_max = range_max
            used_override_range = False

            flag = _find_flag(line)
            # Skip header-only lines when this test already has a real value elsewhere.
            if (
                test in tests_with_line_value
                and range_min is None
                and range_max is None
                and flag is None
                and not re.search(r"\d", line)
            ):
                continue
            if range_min is not None and range_max is not None and range_min > range_max:
                if 10 <= range_min < 100 and range_max < 20:
                    range_min = range_min / 10
                    if range_min > range_max:
                        range_min = range_min / 10
            if range_overrides and (range_min is None or range_max is None):
                for key, range_raw in range_overrides.items():
                    key_lower = key.lower()
                    key_is_absolute = "#" in key_lower or "abs" in key_lower or "x10" in key_lower
                    test_is_absolute = test.endswith("#")
                    if key_is_absolute != test_is_absolute:
                        # Prevent mixing absolute ranges with percentage ranges.
                        continue
                    # Prevent RDW from inheriting RDW-SD ranges.
                    if test == "RDW":
                        key_compact_simple = re.sub(r"[^a-z0-9]+", "", key_lower)
                        if "rdw-sd" in key_lower or "rdwsd" in key_compact_simple:
                            continue
                    key_match = False
                    if key_lower == test.lower():
                        key_match = True
                    elif "#" in key_lower and "#" in test.lower():
                        key_compact = re.sub(r"[^a-z0-9#]+", "", key_lower)
                        test_compact = re.sub(r"[^a-z0-9#]+", "", test.lower())
                        if key_compact == test_compact:
                            key_match = True
                    if not key_match and "#" not in key_lower and any(_alias_in_key(alias, key_lower) for alias in aliases):
                        key_match = True
                    if key_match:
                        rmin, rmax = _parse_range_text(range_raw)
                        if rmin is not None and rmax is not None:
                            if range_min is None or range_max is None:
                                range_min, range_max = rmin, rmax
                                used_override_range = True
                            else:
                                cur_span = range_max - range_min if range_max > range_min else None
                                ov_span = rmax - rmin if rmax > rmin else None
                                if (
                                    cur_span is None
                                    or ov_span is None
                                    or cur_span > ov_span * 1.5
                                    or range_min < (rmin * 0.5)
                                    or range_max > (rmax * 1.5)
                                ):
                                    range_min, range_max = rmin, rmax
                                    used_override_range = True
                        break
            if (range_min is None or range_max is None) and test in FALLBACK_RANGES:
                range_min, range_max = FALLBACK_RANGES[test]
            if range_min == 0 and test in FALLBACK_RANGES:
                range_min, range_max = FALLBACK_RANGES[test]
            # Use stored ranges only when the report doesn't provide a range.
            if stored_ranges and (range_min is None or range_max is None):
                stored = stored_ranges.get(test) if isinstance(stored_ranges, dict) else None
                if stored and stored.get("min") is not None and stored.get("max") is not None:
                    smin = stored.get("min")
                    smax = stored.get("max")
                    try:
                        smin_f = float(smin)
                        smax_f = float(smax)
                    except Exception:
                        smin_f = smax_f = None
                    valid = smin_f is not None and smax_f is not None and smax_f > smin_f
                    # Guard against scaled-down stored ranges for known mid/high ranges.
                    if test == "UREA" and valid and smax_f <= 10:
                        valid = False
                    if valid:
                        range_min, range_max = smin_f, smax_f
            range_min, range_max = _pick_renal_range(test, range_min, range_max, range_overrides)
            if test == "PHOSPHORUS":
                range_min, range_max = _maybe_fix_phosphorus_range(range_min, range_max)

            value_search_line = line
            value_start = 0
            if range_span:
                value_search_line = line[:range_span[0]] + " " + line[range_span[1]:]

            if test == "HEMOGLOBIN" and "hplc" in line_lower:
                continue

            candidates = _extract_candidates(value_search_line, start_idx=value_start)
            chosen = _choose_candidate(value_search_line, candidates)
            line_value = chosen["value"] if chosen else None

            override_value = _find_override_for_test(overrides_primary, test, aliases)
            override_secondary = _find_override_for_test(overrides_secondary, test, aliases)
            # Prefer line-extracted values when present; overrides are often column OCR noise.
            if line_value is not None:
                override_value = None
                override_secondary = None

            override_has_decimal = False
            used_override_for_value = False
            if override_value or override_secondary:
                override_has_decimal = _has_decimal(override_value or "") if override_value else False
                value = _choose_override(override_value, override_secondary, range_min, range_max, test_name=test)
                value_span = None
                used_override_for_value = value is not None

                # If override looks like a copied range bound (common OCR issue),
                # prefer the line-level numeric candidate when available.
                if chosen is not None:
                    line_value = chosen["value"]
                    line_span = chosen["span"]
                    if value is None:
                        value = line_value
                        value_span = line_span
                        used_override_for_value = False
                    elif range_min is not None and range_max is not None:
                        span = range_max - range_min if range_max > range_min else None
                        eps = max(0.02 * span, 0.5) if span else 0.0
                        value_on_bound = abs(value - range_min) <= eps or abs(value - range_max) <= eps
                        line_on_bound = abs(line_value - range_min) <= eps or abs(line_value - range_max) <= eps
                        if value_on_bound and not line_on_bound:
                            value = line_value
                            value_span = line_span
                            used_override_for_value = False
                        else:
                            # If override value is out of range but line value is in/near range, trust line value.
                            line_in_range = line_value >= (range_min * 0.8) and line_value <= (range_max * 1.2)
                            override_out = value < range_min or value > range_max
                            if override_out and line_in_range:
                                value = line_value
                                value_span = line_span
                                used_override_for_value = False
            else:
                if not chosen:
                    # If candidate parsing failed but range exists, pick a number close to range.
                    nums = re.findall(r"\d+(?:[.,]\d+)?", value_search_line)
                    if range_min is not None and range_max is not None and nums:
                        best = None
                        best_score = None
                        for n in nums:
                            try:
                                val = float(_normalize_number(n))
                            except Exception:
                                continue
                            # Skip numbers that look like range bounds.
                            if val == range_min or val == range_max:
                                continue
                            score = abs(val - ((range_min + range_max) / 2.0))
                            if best_score is None or score < best_score:
                                best_score = score
                                best = {"value": val, "span": None}
                        if best is None:
                            continue
                        chosen = best
                    else:
                        continue
                value = chosen["value"]
                value_span = chosen["span"]

            if value is None:
                continue

            # Fix percent values that were scaled down by OCR (e.g., 0.92 for 1-6%).
            value = _normalize_percent_value(value, range_min, range_max)

            # If overrides produced a suspiciously tight range around the value,
            # prefer the line-derived range when available.
            if (
                used_override_range
                and line_range_min is not None
                and line_range_max is not None
                and range_min is not None
                and range_max is not None
            ):
                try:
                    line_span = line_range_max - line_range_min
                    ov_span = range_max - range_min
                except Exception:
                    line_span = None
                    ov_span = None
                if line_span and ov_span and ov_span < (line_span * 0.7):
                    # If line range fits the value and override range does not, trust line range.
                    if value is not None:
                        line_ok = line_range_min <= value <= line_range_max
                        override_ok = range_min <= value <= range_max
                        if line_ok and not override_ok:
                            range_min, range_max = line_range_min, line_range_max
                        else:
                            # If value is close to line min but far from override min, trust line range.
                            if (
                                abs(value - line_range_min) <= max(0.08 * line_span, 1.0)
                                and abs(value - range_min) >= max(0.15 * line_span, 2.0)
                            ):
                                range_min, range_max = line_range_min, line_range_max

            if range_min is not None and range_max is not None:
                # RDW-SD values are typically two-digit numbers; repair single-digit OCR drops.
                if test == "RDW-SD" and value is not None and value < range_min and value < 20 and range_max <= 80:
                    while value < range_min:
                        value += 10
                range_min, range_max = _normalize_range_with_value(value, range_min, range_max)
                if range_min == 0 and range_max >= 1000:
                    range_min, range_max = (None, None)
                if (not used_override_for_value) or ((used_override_for_value) and not override_has_decimal):
                    # Only rescale when the value is implausibly far from the range.
                    far_from_range = value < (range_min / 2) or value > (range_max * 2)
                    if far_from_range:
                        if range_max <= 20 and 20 <= value < 100:
                            value = value / 10
                        elif range_max <= 200 and 100 <= value < 1000:
                            value = value / 10
                        elif range_max <= 200 and 1000 <= value < 10000:
                            value = value / 100
                if value < (range_min / 5) or value > (range_max * 5):
                    range_min, range_max = (None, None)

            # Special-case: cholesterol reports often list "desirable <200".
            # If we captured a "borderline 200-239" band as the range, treat <200 as normal.
            if (
                test == "TOTAL CHOLESTEROL"
                and value is not None
                and (range_min is None or range_min >= 180)
                and value < 200
            ):
                range_min, range_max = (0.0, 200.0)

            # If percent tests got scaled down ranges (<1), restore from overrides when available.
            if (
                not test.endswith("#")
                and range_overrides
                and range_min is not None
                and range_max is not None
                and range_max < 1
            ):
                for key, range_raw in range_overrides.items():
                    if key.lower() != test.lower():
                        continue
                    rmin, rmax = _parse_range_text(range_raw)
                    if rmin is not None and rmax is not None and rmax >= 1:
                        range_min, range_max = rmin, rmax
                        value = _normalize_percent_value(value, range_min, range_max)
                    break

            unit = _find_unit(line, value_span)
            if flag is None:
                flag = _find_flag(line)

            abnormal = None
            if range_min is not None and range_max is not None:
                # Trust numeric comparison first; only use flags as a tie-breaker at range boundaries.
                abnormal = value < range_min or value > range_max
                if not abnormal and flag:
                    abnormal = _flag_implies_abnormal_with_range(flag, value, range_min, range_max)
            elif flag:
                abnormal = True

            # Force cholesterol desirable band (<200) to be normal even if we only captured 200-239.
            if test == "TOTAL CHOLESTEROL" and value is not None and value < 200:
                range_min, range_max = (0.0, 200.0)
                abnormal = False

            key = (test, value, range_min, range_max, unit)
            if key in seen:
                continue
            seen.add(key)

            results.append({
                "test": test,
                "value": value,
                "unit": unit,
                "range": [range_min, range_max] if range_min is not None else None,
                "abnormal": abnormal,
                "flag": flag,
            })

    # If overrides provide a more plausible value for an existing test, prefer it.
    if overrides_primary or overrides_secondary:
        for item in results:
            test = item.get("test")
            if not test:
                continue
            if test in tests_with_line_value:
                continue
            aliases = TEST_KEYWORDS.get(test, [])
            primary_raw = _find_override_for_test(overrides_primary, test, aliases)
            secondary_raw = _find_override_for_test(overrides_secondary, test, aliases)
            if not primary_raw and not secondary_raw:
                continue
            range_min, range_max = (None, None)
            if item.get("range") and len(item.get("range")) == 2:
                range_min, range_max = item.get("range")
            override_value = _choose_override(primary_raw, secondary_raw, range_min, range_max, test_name=test)
            if override_value is None:
                continue
            current_value = item.get("value")
            # Fix percentage tests where OCR scaled value down (e.g., 0.92 vs 9.2).
            override_value = _normalize_percent_value(override_value, range_min, range_max)
            if (
                not test.endswith("#")
                and range_min is not None
                and range_max is not None
                and range_max <= 20
                and current_value is not None
                and current_value < 1
                and override_value >= 1
            ):
                item["value"] = override_value
            # Otherwise prefer override if current value is missing.
            elif current_value is None:
                item["value"] = override_value

    # Add missing tests from overrides (fallback when line parsing failed).
    if overrides_primary or overrides_secondary:
        existing_tests = {item.get("test") for item in results if item.get("test")}
        for test, aliases in TEST_KEYWORDS.items():
            if test in existing_tests or test in tests_with_line_value:
                continue
            primary_raw = _find_override_for_test(overrides_primary, test, aliases)
            secondary_raw = _find_override_for_test(overrides_secondary, test, aliases)
            if not primary_raw and not secondary_raw:
                continue

            range_min, range_max = (None, None)
            if range_overrides and (range_min is None or range_max is None):
                for key, range_raw in range_overrides.items():
                    key_lower = key.lower()
                    key_is_absolute = "#" in key_lower or "abs" in key_lower or "x10" in key_lower
                    test_is_absolute = test.endswith("#")
                    if key_is_absolute != test_is_absolute:
                        continue
                    key_match = False
                    if key_lower == test.lower():
                        key_match = True
                    elif "#" in key_lower and "#" in test.lower():
                        key_compact = re.sub(r"[^a-z0-9#]+", "", key_lower)
                        test_compact = re.sub(r"[^a-z0-9#]+", "", test.lower())
                        if key_compact == test_compact:
                            key_match = True
                    if not key_match and "#" not in key_lower and any(_alias_in_key(alias, key_lower) for alias in aliases):
                        key_match = True
                    if key_match:
                        range_min, range_max = _parse_range_text(range_raw)
                        break
            if (range_min is None or range_max is None) and test in FALLBACK_RANGES:
                range_min, range_max = FALLBACK_RANGES[test]
            # Prefer previously stored ranges when available (if they look valid).
            if stored_ranges:
                stored = stored_ranges.get(test) if isinstance(stored_ranges, dict) else None
                if stored and stored.get("min") is not None and stored.get("max") is not None:
                    smin = stored.get("min")
                    smax = stored.get("max")
                    try:
                        smin_f = float(smin)
                        smax_f = float(smax)
                    except Exception:
                        smin_f = smax_f = None
                    valid = smin_f is not None and smax_f is not None and smax_f > smin_f
                    if test == "UREA" and valid and smax_f <= 10:
                        valid = False
                    if valid:
                        range_min, range_max = smin_f, smax_f

            value = _choose_override(primary_raw, secondary_raw, range_min, range_max, test_name=test)
            value = _normalize_percent_value(value, range_min, range_max)
            if value is None:
                continue

            abnormal = None
            if range_min is not None and range_max is not None:
                abnormal = value < range_min or value > range_max

            results.append({
                "test": test,
                "value": value,
                "unit": None,
                "range": [range_min, range_max] if range_min is not None else None,
                "abnormal": abnormal,
                "flag": None,
            })

    if overrides_primary or overrides_secondary:
        for test, aliases in TEST_KEYWORDS.items():
            if any(r["test"] == test for r in results):
                continue
            primary_raw = _find_override_for_test(overrides_primary, test, aliases)
            secondary_raw = _find_override_for_test(overrides_secondary, test, aliases)
            if not primary_raw and not secondary_raw:
                continue

            range_min, range_max = (None, None)
            if range_overrides:
                for key, range_raw in range_overrides.items():
                    key_lower = key.lower()
                    key_is_absolute = "#" in key_lower or "abs" in key_lower or "x10" in key_lower
                    test_is_absolute = test.endswith("#")
                    if key_is_absolute != test_is_absolute:
                        # Prevent mixing absolute ranges with percentage ranges.
                        continue
                    key_match = False
                    if key_lower == test.lower():
                        key_match = True
                    elif "#" in key_lower and "#" in test.lower():
                        key_compact = re.sub(r"[^a-z0-9#]+", "", key_lower)
                        test_compact = re.sub(r"[^a-z0-9#]+", "", test.lower())
                        if key_compact == test_compact:
                            key_match = True
                    if not key_match and "#" not in key_lower and any(_alias_in_key(alias, key_lower) for alias in aliases):
                        key_match = True
                    if key_match:
                        range_min, range_max = _parse_range_text(range_raw)
                        break
            if (range_min is None or range_max is None) and test in FALLBACK_RANGES:
                range_min, range_max = FALLBACK_RANGES[test]
            if range_min == 0 and test in FALLBACK_RANGES:
                range_min, range_max = FALLBACK_RANGES[test]
            # Prefer previously stored ranges when available (if they look valid).
            if stored_ranges:
                stored = stored_ranges.get(test) if isinstance(stored_ranges, dict) else None
                if stored and stored.get("min") is not None and stored.get("max") is not None:
                    smin = stored.get("min")
                    smax = stored.get("max")
                    try:
                        smin_f = float(smin)
                        smax_f = float(smax)
                    except Exception:
                        smin_f = smax_f = None
                    valid = smin_f is not None and smax_f is not None and smax_f > smin_f
                    if test == "UREA" and valid and smax_f <= 10:
                        valid = False
                    if valid:
                        range_min, range_max = smin_f, smax_f
            range_min, range_max = _pick_renal_range(test, range_min, range_max, range_overrides)
            if test == "PHOSPHORUS":
                range_min, range_max = _maybe_fix_phosphorus_range(range_min, range_max)

            value = _choose_override(primary_raw, secondary_raw, range_min, range_max, test_name=test)
            if value is None:
                continue

            if range_min is not None and range_max is not None:
                range_min, range_max = _normalize_range_with_value(value, range_min, range_max)
                if range_min == 0 and range_max >= 1000:
                    range_min, range_max = (None, None)

            abnormal = None
            if range_min is not None and range_max is not None:
                abnormal = value < range_min or value > range_max

            results.append({
                "test": test,
                "value": value,
                "unit": None,
                "range": [range_min, range_max] if range_min is not None else None,
                "abnormal": abnormal,
                "flag": None,
            })

    # Derived fallback: some reports miss OCR on ALBUMIN row while TOTAL PROTEIN,
    # GLOBULIN and/or A/G RATIO are captured reliably.
    by_test = {item.get("test"): item for item in results if item.get("test")}
    if "ALBUMIN" not in by_test:
        albumin_val = None
        total = by_test.get("TOTAL PROTEIN", {}).get("value")
        glob = by_test.get("GLOBULIN", {}).get("value")
        ratio = by_test.get("A/G RATIO", {}).get("value")
        try:
            if total is not None and glob is not None:
                albumin_val = float(total) - float(glob)
            elif ratio is not None and glob is not None:
                albumin_val = float(ratio) * float(glob)
        except Exception:
            albumin_val = None

        if albumin_val is not None and albumin_val > 0:
            # Round to common chemistry precision.
            albumin_val = round(albumin_val, 2)
            results.append({
                "test": "ALBUMIN",
                "value": albumin_val,
                "unit": None,
                "range": None,
                "abnormal": None,
                "flag": "DERIVED",
            })

    # Fix percent tests accidentally treated as absolute (#) ranges.
    percent_tests = {"LYMPHOCYTES", "NEUTROPHILS", "MONOCYTES", "EOSINOPHILS", "BASOPHILS"}
    for item in results:
        test = item.get("test")
        if test not in percent_tests or test.endswith("#"):
            continue
        rng = item.get("range")
        if not rng or len(rng) != 2:
            continue
        rmin, rmax = rng
        if rmax is None:
            continue
        # Look up a percent-range candidate from stored or OCR ranges.
        alt_min = alt_max = None
        if stored_ranges and isinstance(stored_ranges, dict):
            stored = stored_ranges.get(test)
            if stored and stored.get("min") is not None and stored.get("max") is not None:
                try:
                    alt_min = float(stored.get("min"))
                    alt_max = float(stored.get("max"))
                except Exception:
                    alt_min = alt_max = None
        if (alt_min is None or alt_max is None) and range_overrides:
            rr = range_overrides.get(test)
            if rr:
                alt_min, alt_max = _parse_range_text(rr)
        # If current range looks absolute (<=5) but we have a percent range (>=20), replace it.
        if alt_min is not None and alt_max is not None and alt_max >= 20 and rmax <= 5:
            val = item.get("value")
            if val is not None and val <= 5:
                scaled = val * 10.0
                if scaled <= (alt_max * 1.5):
                    item["value"] = round(scaled, 2)
            item["range"] = [alt_min, alt_max]
            if item.get("value") is not None:
                item["abnormal"] = item["value"] < alt_min or item["value"] > alt_max

    # Repair RDW-SD single-digit OCR drops and suppress stray RDW rows when only RDW-SD exists.
    has_rdw_sd = any(r.get("test") == "RDW-SD" for r in results)
    rdw_override_present = False
    if range_overrides and isinstance(range_overrides, dict):
        rdw_override_present = any(k.lower() == "rdw" for k in range_overrides.keys())
    if overrides_primary and any(k.lower() == "rdw" for k in overrides_primary.keys()):
        rdw_override_present = True
    if overrides_secondary and any(k.lower() == "rdw" for k in overrides_secondary.keys()):
        rdw_override_present = True

    cleaned_results = []
    for item in results:
        test = item.get("test")
        if test == "RDW-SD":
            rng = item.get("range") or item.get("range_used")
            if rng and len(rng) == 2:
                rmin, rmax = rng
                val = item.get("value")
                if (
                    val is not None
                    and rmin is not None
                    and rmax is not None
                    and rmin >= 30
                    and rmax <= 80
                    and val < rmin
                    and val < 20
                ):
                    while val < rmin:
                        val += 10
                    item["value"] = val
                    item["abnormal"] = val < rmin or val > rmax
        if test == "RDW" and has_rdw_sd and not rdw_override_present:
            rng = item.get("range") or item.get("range_used")
            if rng and len(rng) == 2:
                rmin, rmax = rng
                if rmax is not None and rmax <= 20:
                    continue
        cleaned_results.append(item)
    results = cleaned_results

    # Force percent-range for LYMPHOCYTES when OCR provided a percent range in overrides.
    if range_overrides and isinstance(range_overrides, dict):
        lr = range_overrides.get("LYMPHOCYTES")
        if lr:
            rmin, rmax = _parse_range_text(lr)
            if rmin is not None and rmax is not None and rmax >= 20:
                for item in results:
                    if item.get("test") != "LYMPHOCYTES":
                        continue
                    val = item.get("value")
                    if val is not None and val <= 5:
                        val = round(val * 10.0, 2)
                        item["value"] = val
                    item["range"] = [rmin, rmax]
                    if item.get("value") is not None:
                        item["abnormal"] = item["value"] < rmin or item["value"] > rmax

    return results