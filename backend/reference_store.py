import json
import os
import re
import tempfile
import threading
from typing import Any, Dict, Iterable, Optional

from lab_parser import TEST_KEYWORDS

_LOCK = threading.Lock()
_KNOWN_TESTS = set(TEST_KEYWORDS.keys())


def _normalize_label(text: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9#]+", " ", str(text or "")).strip().upper()
    return re.sub(r"\s+", " ", cleaned)

def _label_to_test(label: str) -> Optional[str]:
    raw_text = str(label or "")
    raw_upper = raw_text.upper()
    raw_lower = raw_text.lower()
    raw_compact = re.sub(r"[^a-z0-9#]+", "", raw_lower)
    is_absolute = "#" in raw_upper or "ABS" in raw_upper or "X10" in raw_upper
    normalized = _normalize_label(label)
    if not normalized:
        return None
    if normalized in _KNOWN_TESTS:
        return normalized

    lower = normalized.lower()
    if is_absolute:
        for test, aliases in TEST_KEYWORDS.items():
            if not test.endswith("#"):
                continue
            for alias in aliases:
                alias_lower = alias.lower().strip()
                if not alias_lower:
                    continue
                alias_compact = re.sub(r"[^a-z0-9#]+", "", alias_lower)
                if alias_compact and alias_compact in raw_compact:
                    return test
                if re.search(rf"\b{re.escape(alias_lower)}\b", raw_lower):
                    return test
                if " " in alias_lower and alias_lower in raw_lower:
                    return test

    for test, aliases in TEST_KEYWORDS.items():
        for alias in aliases:
            alias_lower = alias.lower()
            if re.search(rf"\b{re.escape(alias_lower)}\b", lower):
                return test
            if " " in alias_lower and alias_lower in lower:
                return test
    return None


def _default_store_path() -> str:
    override = os.environ.get("REFERENCE_RANGE_STORE")
    if override:
        return override
    base_dir = os.path.dirname(__file__)
    return os.path.join(base_dir, "processed", "reference_ranges.json")


def _default_raw_store_path() -> str:
    base_dir = os.path.dirname(__file__)
    return os.path.join(base_dir, "processed", "reference_ranges_all.json")


def _load_raw(path: str) -> Dict[str, Any]:
    if not os.path.exists(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        if isinstance(data, dict):
            return data
    except Exception:
        return {}
    return {}


def load_reference_ranges() -> Dict[str, Dict[str, Any]]:
    path = _default_store_path()
    with _LOCK:
        return _load_raw(path)


def _write_atomic(path: str, payload: Dict[str, Any]) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(
        prefix="ref_ranges_",
        suffix=".json",
        dir=os.path.dirname(path),
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, indent=2, sort_keys=True)
        os.replace(tmp_path, path)
    finally:
        if os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except Exception:
                pass


def update_reference_ranges(
    parsed_items: Iterable[Dict[str, Any]],
) -> Dict[str, Dict[str, Any]]:
    path = _default_store_path()
    with _LOCK:
        existing = _load_raw(path)
        current = {key: value for key, value in existing.items() if key in _KNOWN_TESTS}
        changed = len(current) != len(existing)

        for item in parsed_items:
            test = item.get("test")
            if test not in _KNOWN_TESTS:
                continue
            rng = item.get("range")
            if not test or not rng or len(rng) != 2:
                continue

            rmin, rmax = rng
            if rmin is None or rmax is None:
                continue
            if rmax <= rmin:
                continue

            payload = {
                "min": float(rmin),
                "max": float(rmax),
            }
            if item.get("unit"):
                payload["unit"] = item.get("unit")

            if test in current:
                existing_payload = current.get(test) or {}
                old_min = existing_payload.get("min")
                old_max = existing_payload.get("max")
                if old_min is None or old_max is None or old_max <= old_min:
                    current[test] = payload
                    changed = True
                    continue
                old_span = float(old_max) - float(old_min)
                new_span = float(rmax) - float(rmin)
                replace = False
                # If a percent-style test previously got scaled to <1, replace with >1 range.
                if not str(test).endswith("#") and float(old_max) < 1.0 and float(rmax) >= 1.0:
                    replace = True
                if float(old_max) > 200 and float(rmax) < 200:
                    replace = True
                elif new_span < old_span * 0.6:
                    replace = True
                elif float(rmax) < float(old_max) and new_span < old_span:
                    replace = True
                if replace:
                    current[test] = payload
                    changed = True
                continue

            current[test] = payload
            changed = True

        if changed:
            _write_atomic(path, current)
        return current


def update_reference_ranges_all(range_overrides: Dict[str, Any]) -> Dict[str, Dict[str, Any]]:
    path = _default_raw_store_path()
    with _LOCK:
        existing = _load_raw(path)
        current = {key: value for key, value in existing.items() if key in _KNOWN_TESTS}
        changed = len(current) != len(existing)

        def _clean_range_text(raw: str) -> str:
            if not raw:
                return raw
            text = str(raw)
            nums = re.findall(r"\d+(?:\.\d+)?", text)
            if len(nums) < 2:
                return text
            lower = text.lower()
            if any(tag in lower for tag in ["x10", "cells", "abs"]) and len(nums) >= 2:
                nums = nums[-2:]
            try:
                rmin = float(nums[0])
                rmax = float(nums[1])
            except Exception:
                return text
            # Fix concatenated large max (e.g., 6-205.89, 1092-7280).
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
            # Drop noisy decimal tail when min looks integer-like.
            if "." not in str(nums[0]) and rmax < 200:
                max_raw = str(nums[1])
                if "." in max_raw and len(max_raw.split(".", 1)[1]) >= 3:
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
            max_raw = str(nums[1])
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
            rmin_s = f"{rmin:g}"
            rmax_s = f"{rmax:g}"
            return f"{rmin_s}-{rmax_s}"

        for raw_label, raw_range in (range_overrides or {}).items():
            if raw_label is None:
                continue
            label = str(raw_label).strip()
            if not label:
                continue

            mapped_test = _label_to_test(label)
            if not mapped_test:
                continue

            upper = label.upper()
            if "EGFR" in upper or "GFR" in upper:
                continue
            if "ML MIN" in upper or "ML/MIN" in upper or "M2" in upper or "M^2" in upper:
                continue
            if "CALCULATED" in upper:
                continue
            if any(
                tag in upper
                for tag in [
                    "NORMAL OR HIGH",
                    "MILD DECREASED",
                    "MILD TO MODERATELY",
                    "MODERATELY TO SEVERELY",
                    "SEVERELY DECREASED",
                    "KIDNEY FAILURE",
                ]
            ):
                continue

            raw_text = str(raw_range) if raw_range is not None else ""
            clean_text = raw_text
            nums = re.findall(r"\d+(?:\.\d+)?", raw_text)
            if any(tag in raw_text.lower() for tag in ["x10", "cells", "abs"]):
                if len(nums) >= 2:
                    clean_text = f"{nums[-2]}-{nums[-1]}"
            elif len(nums) >= 2:
                # Fix concatenated large max (e.g., 1092-7280 -> 2-7).
                try:
                    rmin = float(nums[0])
                    rmax = float(nums[1])
                except Exception:
                    rmin = rmax = None
                if rmin is not None and rmax is not None and rmax >= 1000 and rmin < 100:
                    max_int = str(int(rmax))
                    for take in (3, 2):
                        try:
                            fixed = float(max_int[:take])
                        except Exception:
                            fixed = None
                        if fixed is not None and fixed > rmin:
                            rmax = fixed
                            break
                    if rmax is not None:
                        clean_text = f"{rmin:g}-{rmax:g}"
            clean_text = _clean_range_text(clean_text)
            payload: Dict[str, Any] = {
                "raw": clean_text,
                "source_label": label,
            }
            m = re.search(r"(\d+(?:\.\d+)?)\s*[-–]\s*(\d+(?:\.\d+)?)", clean_text)
            if m:
                try:
                    payload["min"] = float(m.group(1))
                    payload["max"] = float(m.group(2))
                except Exception:
                    pass
            if mapped_test == "PHOSPHORUS":
                try:
                    if payload.get("min") is not None and payload.get("max") is not None:
                        if 2.8 <= float(payload["min"]) <= 3.0 and 4.4 <= float(payload["max"]) <= 4.6:
                            payload["min"] = 2.5
                            payload["max"] = 4.5
                            payload["raw"] = "2.5-4.5"
                except Exception:
                    pass

            existing_payload = current.get(mapped_test) or {}
            old_min = existing_payload.get("min")
            old_max = existing_payload.get("max")
            new_min = payload.get("min")
            new_max = payload.get("max")
            if new_min is not None and new_max is not None and new_max <= new_min:
                continue

            replace = mapped_test not in current
            if not replace and (old_min is None or old_max is None or old_max <= old_min):
                replace = True
            if (
                not replace
                and new_min is not None
                and new_max is not None
                and new_max > new_min
            ):
                old_span = float(old_max) - float(old_min)
                new_span = float(new_max) - float(new_min)
                if float(old_max) > 200 and float(new_max) < 200:
                    replace = True
                elif str(mapped_test).endswith("#") and float(old_max) >= 1000 and float(new_max) < 200:
                    replace = True
                elif new_span < old_span * 0.6:
                    replace = True
                elif float(new_max) < float(old_max) and new_span < old_span:
                    replace = True

            if replace:
                current[mapped_test] = payload
                changed = True

        if changed:
            _write_atomic(path, current)
        return current