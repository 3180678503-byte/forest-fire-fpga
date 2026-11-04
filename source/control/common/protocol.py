"""Versioned LAN contract shared by host and Python 3.8 board worker."""
import base64
import binascii
import datetime
import hashlib
import json
import math
import uuid

SCHEMA = "fire-semantic-review-1.0"
VERDICTS = {"CONFIRM", "REJECT", "UNCERTAIN"}
REASONS = {"FLAME", "SMOKE", "FOG", "REFLECTION", "UNKNOWN"}
MAX_JPEG = 1024 * 1024
MAX_BODY = 2 * 1024 * 1024


class ProtocolError(ValueError):
    pass


def _pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ProtocolError("duplicate JSON field")
        result[key] = value
    return result


def strict_loads(raw):
    def invalid(_):
        raise ProtocolError("non-finite JSON number")
    return json.loads(raw, parse_constant=invalid, object_pairs_hook=_pairs)


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def fallback(reason="semantic reviewer unavailable"):
    return {"verdict": "UNCERTAIN", "reason_code": "UNKNOWN",
            "evidence": reason[:512], "confidence": 0.0}


def validate_semantic(value):
    if not isinstance(value, dict) or set(value) != {"verdict", "reason_code", "evidence", "confidence"}:
        raise ProtocolError("semantic fields")
    if value["verdict"] not in VERDICTS or value["reason_code"] not in REASONS:
        raise ProtocolError("semantic enum")
    if not isinstance(value["evidence"], str) or len(value["evidence"]) > 512:
        raise ProtocolError("semantic evidence")
    if not number(value["confidence"]) or not 0 <= value["confidence"] <= 1:
        raise ProtocolError("semantic confidence")
    return value


def normalize_semantic_for_detector(value, class_name):
    """Apply detector-class consistency without allowing Qwen to change detections.

    A semantic answer is advisory. Inconsistent answers are downgraded to a
    safe UNCERTAIN result instead of being used as a delete instruction.
    """
    validate_semantic(value)
    if class_name not in {"fire", "smoke"}:
        raise ProtocolError("detector class")
    if value["verdict"] == "UNCERTAIN":
        return {**value, "reason_code": "UNKNOWN"}
    expected = "FLAME" if class_name == "fire" else "SMOKE"
    if value["verdict"] == "CONFIRM" and value["reason_code"] != expected:
        return fallback("semantic class consistency failure")
    if value["verdict"] == "REJECT" and value["reason_code"] not in {"FOG", "REFLECTION", "UNKNOWN"}:
        return fallback("semantic reject reason is not a valid negative reason")
    return dict(value)


def merge_advisory_result(detections, semantic):
    """Return a board-safe record; Qwen never removes or edits YOLO detections."""
    validate_semantic(semantic)
    return {
        "detections": list(detections),
        "qwen_review": dict(semantic),
        "qwen_suggestion_applied": False,
        "detection_count_preserved": True,
    }


def validate_request(task):
    required = {"schema_version", "request_id", "event_id", "frame_id", "timestamp_utc", "detector", "evidence", "context"}
    if not isinstance(task, dict) or not required <= set(task) or set(task) - required - {"capture_meta"}:
        raise ProtocolError("request fields")
    if task["schema_version"] != SCHEMA:
        raise ProtocolError("schema version")
    if not isinstance(task["request_id"], str):
        raise ProtocolError("request id")
    try:
        uuid.UUID(task["request_id"])
    except (ValueError, TypeError, AttributeError):
        raise ProtocolError("request id")
    if not isinstance(task["event_id"], str) or not 1 <= len(task["event_id"]) <= 128:
        raise ProtocolError("event id")
    if type(task["frame_id"]) is not int or task["frame_id"] < 1:
        raise ProtocolError("frame id")
    if not isinstance(task["timestamp_utc"], str) or len(task["timestamp_utc"]) > 64:
        raise ProtocolError("timestamp")
    try:
        stamp = datetime.datetime.fromisoformat(task["timestamp_utc"].replace("Z", "+00:00"))
        if stamp.tzinfo is None:
            raise ValueError()
    except ValueError:
        raise ProtocolError("timestamp")
    d = task["detector"]
    if not isinstance(d, dict) or set(d) != {"model", "class_name", "class_id", "score", "score_semantics", "bbox_xyxy", "image_width", "image_height"}:
        raise ProtocolError("detector fields")
    if type(d["class_id"]) is not int or d["class_id"] not in (0, 1) or d["class_name"] != ("fire", "smoke")[d["class_id"]]:
        raise ProtocolError("detector class")
    if not isinstance(d["model"], str) or not 1 <= len(d["model"]) <= 128 or d["score_semantics"] != "uncalibrated_detector_score":
        raise ProtocolError("detector metadata")
    if not number(d["score"]) or not 0 <= d["score"] <= 1:
        raise ProtocolError("detector score")
    w, h = d["image_width"], d["image_height"]
    if type(w) is not int or type(h) is not int or not (1 <= w <= 8192 and 1 <= h <= 8192):
        raise ProtocolError("image dimensions")
    box = d["bbox_xyxy"]
    if not isinstance(box, list) or len(box) != 4 or not all(number(v) for v in box):
        raise ProtocolError("bbox")
    x1, y1, x2, y2 = box
    if not (0 <= x1 < x2 <= w and 0 <= y1 < y2 <= h):
        raise ProtocolError("bbox bounds")
    evidence = task["evidence"]
    if not isinstance(evidence, dict) or set(evidence) != {"image_mime", "image_encoding", "image_base64", "image_role"}:
        raise ProtocolError("evidence fields")
    if (evidence["image_mime"], evidence["image_encoding"], evidence["image_role"]) != ("image/jpeg", "base64", "target_crop"):
        raise ProtocolError("evidence format")
    encoded = evidence["image_base64"]
    if not isinstance(encoded, str) or len(encoded) > (MAX_JPEG + 2) // 3 * 4:
        raise ProtocolError("image too large")
    try:
        jpeg = base64.b64decode(encoded, validate=True)
    except (ValueError, binascii.Error):
        raise ProtocolError("base64")
    if not jpeg or len(jpeg) > MAX_JPEG:
        raise ProtocolError("image size")
    context = task["context"]
    allowed = {"gate_state", "consecutive_hits", "class_consistent", "bbox_iou_stability", "score_trend"}
    if not isinstance(context, dict) or set(context) != allowed:
        raise ProtocolError("context fields")
    if context["gate_state"] not in {"UNCERTAIN", "CONFIRMED", "CANDIDATE"}:
        raise ProtocolError("gate state")
    if type(context["consecutive_hits"]) is not int or not 0 <= context["consecutive_hits"] <= 1000000:
        raise ProtocolError("consecutive hits")
    if context["class_consistent"] is not None and type(context["class_consistent"]) is not bool:
        raise ProtocolError("class consistency")
    stability = context["bbox_iou_stability"]
    if stability is not None and (not number(stability) or not 0 <= stability <= 1):
        raise ProtocolError("bbox stability")
    if context["score_trend"] not in {None, "unknown", "stable", "up", "down"}:
        raise ProtocolError("score trend")
    capture = task.get("capture_meta", {})
    if not isinstance(capture, dict) or set(capture) - {"clock_synced", "monotonic_ns"}:
        raise ProtocolError("capture metadata")
    if "clock_synced" in capture and type(capture["clock_synced"]) is not bool:
        raise ProtocolError("clock sync flag")
    if "monotonic_ns" in capture and (type(capture["monotonic_ns"]) is not int or capture["monotonic_ns"] < 0):
        raise ProtocolError("capture clock")
    return jpeg


def response_for(task, semantic, meta):
    validate_semantic(semantic)
    return {"schema_version": SCHEMA, "request_id": task["request_id"],
            "event_id": task["event_id"], "frame_id": task["frame_id"],
            "semantic": semantic, "meta": meta}


def validate_response(reply, task):
    if not isinstance(reply, dict) or set(reply) != {"schema_version", "request_id", "event_id", "frame_id", "semantic", "meta"}:
        raise ProtocolError("response fields")
    for key in ("schema_version", "request_id", "event_id", "frame_id"):
        if type(reply[key]) is not type(task[key]) or reply[key] != task[key]:
            raise ProtocolError("response identity")
    validate_semantic(reply["semantic"])
    if not isinstance(reply["meta"], dict):
        raise ProtocolError("response metadata")
    return reply


def jpeg_hash(jpeg):
    return hashlib.sha256(jpeg).hexdigest()
