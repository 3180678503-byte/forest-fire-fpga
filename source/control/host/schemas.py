"""Strict four-field semantic verdict contract for the optional Qwen reviewer."""
from __future__ import annotations
import json, math, re
from typing import Any, Dict, Mapping

SEMANTIC_FIELDS = ("verdict", "reason_code", "evidence", "confidence")
VERDICTS = {"CONFIRM", "REJECT", "UNCERTAIN"}
REASON_CODES = {"FLAME", "SMOKE", "FOG", "REFLECTION", "UNKNOWN"}
SEMANTIC_JSON_SCHEMA: Dict[str, Any] = {
    "$schema": "https://json-schema.org/draft/2020-12/schema", "type": "object",
    "additionalProperties": False, "required": list(SEMANTIC_FIELDS),
    "properties": {"verdict": {"type": "string", "enum": sorted(VERDICTS)}, "reason_code": {"type": "string", "enum": sorted(REASON_CODES)}, "evidence": {"type": "string"}, "confidence": {"type": "number", "minimum": 0.0, "maximum": 1.0}},
}

class SemanticJSONError(ValueError):
    pass

def _confidence(value: Any) -> float:
    if isinstance(value, bool): raise SemanticJSONError("confidence must be a number in [0, 1]")
    if isinstance(value, str):
        try: value = float(value.strip())
        except ValueError as exc: raise SemanticJSONError("confidence must be a number in [0, 1]") from exc
    if not isinstance(value, (int, float)) or not math.isfinite(float(value)) or not 0.0 <= float(value) <= 1.0:
        raise SemanticJSONError("confidence must be a number in [0, 1]")
    return round(float(value), 6)

def validate_semantic_result(value: Mapping[str, Any]) -> Dict[str, Any]:
    if not isinstance(value, Mapping): raise SemanticJSONError("semantic result must be an object")
    missing = [f for f in SEMANTIC_FIELDS if f not in value]
    if missing: raise SemanticJSONError("missing semantic fields: %s" % ", ".join(missing))
    extra = sorted(set(value) - set(SEMANTIC_FIELDS))
    if extra: raise SemanticJSONError("unexpected semantic fields: %s" % ", ".join(extra))
    verdict, reason, evidence = value["verdict"], value["reason_code"], value["evidence"]
    if not isinstance(verdict, str) or verdict.strip().upper() not in VERDICTS: raise SemanticJSONError("verdict enum invalid")
    if not isinstance(reason, str) or reason.strip().upper() not in REASON_CODES: raise SemanticJSONError("reason_code enum invalid")
    if not isinstance(evidence, str): raise SemanticJSONError("evidence must be a string")
    return {"verdict": verdict.strip().upper(), "reason_code": reason.strip().upper(), "evidence": evidence, "confidence": _confidence(value["confidence"])}

def safe_semantic_fallback(reason: str, status: str = "error") -> Dict[str, Any]:
    return {"verdict": "UNCERTAIN", "reason_code": "UNKNOWN", "evidence": str(reason).strip() or "semantic reviewer unavailable", "confidence": 0.0}

def _remove_thinking(text: str) -> str:
    text = re.sub(r"<think>.*?</think>", "", text, flags=re.IGNORECASE | re.DOTALL)
    return re.sub(r"<think>.*$", "", text, flags=re.IGNORECASE | re.DOTALL).strip()

def extract_json_object(raw_text: str) -> Dict[str, Any]:
    if not isinstance(raw_text, str) or not raw_text.strip(): raise SemanticJSONError("empty semantic response")
    text = _remove_thinking(raw_text)
    for start, char in enumerate(text):
        if char != "{": continue
        depth, quoted, escaped = 0, False, False
        for end in range(start, len(text)):
            current = text[end]
            if quoted:
                if escaped: escaped = False
                elif current == "\\": escaped = True
                elif current == '"': quoted = False
                continue
            if current == '"': quoted = True
            elif current == "{": depth += 1
            elif current == "}":
                depth -= 1
                if depth == 0:
                    try: value = json.loads(text[start:end + 1])
                    except json.JSONDecodeError: break
                    if isinstance(value, dict): return value
                    break
    raise SemanticJSONError("no complete balanced JSON object found")

def parse_qwen_json(raw_text: str) -> Dict[str, Any]: return validate_semantic_result(extract_json_object(raw_text))
def json_line(value: Mapping[str, Any]) -> str: return json.dumps(dict(value), ensure_ascii=False, sort_keys=True, separators=(",", ":"))
__all__ = ["SEMANTIC_FIELDS", "SEMANTIC_JSON_SCHEMA", "SemanticJSONError", "extract_json_object", "json_line", "parse_qwen_json", "safe_semantic_fallback", "validate_semantic_result"]
