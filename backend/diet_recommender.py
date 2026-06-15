import json
import os
import urllib.request
import urllib.error
from typing import Dict, Any, List

OPENAI_API_URL = "https://api.openai.com/v1/chat/completions"


def _build_payload(abnormal_items: List[Dict[str, Any]]) -> Dict[str, Any]:
    model = os.environ.get("OPENAI_MODEL", "gpt-4o-mini")
    items = []
    for item in abnormal_items:
        items.append({
            "test": item.get("test"),
            "value": item.get("value"),
            "unit": item.get("unit"),
            "range_used": item.get("range_used"),
            "direction": item.get("abnormal_direction"),
        })

    system = (
        "You are a nutrition assistant. Provide general diet guidance only, "
        "not medical advice. Output must be valid JSON."
    )
    user = (
        "Generate diet recommendations for abnormal lab tests.\n"
        "Return JSON with keys:\n"
        "recommendations: list of {test, direction, focus[], limit[], notes[]}\n"
        "overall_notes: list of strings\n"
        "Use plain language and be conservative.\n"
        f"Abnormal tests: {json.dumps(items, ensure_ascii=False)}"
    )

    return {
        "model": model,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "temperature": 0.2,
        "response_format": {"type": "json_object"},
    }


def _post_json(url: str, payload: Dict[str, Any], api_key: str) -> Dict[str, Any]:
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read().decode("utf-8")
        return json.loads(raw)


def recommend_diet(abnormal_items: List[Dict[str, Any]]) -> Dict[str, Any]:
    if not abnormal_items:
        return {
            "recommendations": [],
            "overall_notes": [
                "No abnormal values were found.",
                "These are general nutrition suggestions, not medical advice.",
            ],
        }

    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        return {
            "recommendations": [],
            "overall_notes": [
                "Diet recommendations unavailable (missing OPENAI_API_KEY).",
                "These are general nutrition suggestions, not medical advice.",
            ],
        }

    payload = _build_payload(abnormal_items)

    try:
        data = _post_json(OPENAI_API_URL, payload, api_key)
        content = data["choices"][0]["message"]["content"]
        parsed = json.loads(content)
        if not isinstance(parsed, dict):
            raise ValueError("LLM response is not a JSON object.")
        parsed.setdefault("recommendations", [])
        parsed.setdefault(
            "overall_notes",
            ["These are general nutrition suggestions, not medical advice."],
        )
        return parsed
    except urllib.error.HTTPError as e:
        return {
            "recommendations": [],
            "overall_notes": [
                f"Diet recommendations unavailable (HTTP {e.code}).",
                "These are general nutrition suggestions, not medical advice.",
            ],
        }
    except Exception:
        return {
            "recommendations": [],
            "overall_notes": [
                "Diet recommendations unavailable (internal error).",
                "These are general nutrition suggestions, not medical advice.",
            ],
        }