"""Bounded LAN bridge. Only the host process holds the cloud credential."""
import argparse
import collections
import io
import json
import multiprocessing as mp
import os
from pathlib import Path
import socket
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "common"))
from protocol import (MAX_BODY, ProtocolError, fallback, jpeg_hash, normalize_semantic_for_detector,
                      response_for, strict_loads, validate_request, validate_semantic)


def cloud_worker(pipe, options, jpeg, context):
    reviewer = None
    try:
        from PIL import Image
        from remote_qwen_semantic_reviewer import RemoteQwenSemanticReviewer
        reviewer = RemoteQwenSemanticReviewer(**options)
        image = Image.open(io.BytesIO(jpeg)).convert("RGB")
        value = reviewer.review(target_crop=image, structured_info=context)
        pipe.send({"semantic": validate_semantic(value), "info": reviewer.resource_info})
    except Exception:
        info = dict(reviewer.resource_info) if reviewer is not None else {"request_attempted": False}
        info.update(status="fallback", response_valid=False, error_code="INVALID_MODEL_RESPONSE")
        pipe.send({"semantic": fallback(), "info": info})
    finally:
        pipe.close()


class Bridge:
    def __init__(self, args):
        self.args = args
        self.lock = threading.Lock()
        self.busy = threading.Semaphore(1)
        self.cache = collections.OrderedDict()
        self.attempts = 0
        self.completed = 0
        from remote_qwen_semantic_reviewer import _read_api_key
        self.key = "" if args.mode == "mock" else (os.environ.get("QWEN_API_KEY", "") or os.environ.get("DASHSCOPE_API_KEY", "") or _read_api_key(args.key_file))
        self.log_path = Path(args.log)
        self.log_path.parent.mkdir(parents=True, exist_ok=True)

    def log(self, record):
        # Records are selected explicitly; no HTTP body, headers or image data.
        with self.lock:
            with self.log_path.open("a", encoding="utf8") as stream:
                stream.write(json.dumps(record, ensure_ascii=False, allow_nan=False) + "\n")

    def review(self, task, jpeg):
        started = time.monotonic()
        identity = task["request_id"]
        import hashlib
        fingerprint = hashlib.sha256(json.dumps(task, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        with self.lock:
            cached = self.cache.get(identity)
            if cached:
                if cached[0] != fingerprint:
                    return 409, {"error_code": "REQUEST_ID_CONFLICT"}
                value = dict(cached[1])
                value["meta"] = dict(value["meta"], cached=True)
                return 200, value
        if not self.busy.acquire(False):
            return 429, {"error_code": "BUSY"}
        try:
            meta = {"provider": "mock" if self.args.mode == "mock" else "qwen_api", "usage": None}
            if self.args.mode == "remote" and not self.key:
                value = fallback("semantic reviewer API key unavailable")
                meta.update(request_status="fallback", error_code="MISSING_KEY", request_attempted=False)
            elif self.attempts >= self.args.max_requests:
                value = fallback("semantic request budget exhausted")
                meta.update(request_status="fallback", error_code="REQUEST_BUDGET", request_attempted=False)
            else:
                self.attempts += 1
                if self.args.mode == "mock":
                    value = {"verdict": "CONFIRM", "reason_code": "FLAME" if task["detector"]["class_id"] == 0 else "SMOKE",
                             "evidence": "mock transport response; no cloud classification", "confidence": 0.75}
                    meta.update(request_status="completed", request_attempted=False, is_mock=True)
                else:
                    value, info = self.remote(task, jpeg)
                    status = "completed" if info.get("response_valid") else "fallback"
                    meta.update(request_status=status, request_attempted=bool(info.get("request_attempted")), usage=info.get("usage"))
                    for key in ("prompt_version", "prompt_sha256"):
                        if key in info:
                            meta[key] = info[key]
                    if status == "fallback":
                        meta["error_code"] = info.get("error_code", "UPSTREAM_UNAVAILABLE")
            raw_semantic = dict(value)
            normalized = normalize_semantic_for_detector(value, task["detector"]["class_name"])
            meta["semantic_normalized"] = normalized != value
            meta["detection_policy"] = "advisory_only_retain_yolo_detections"
            meta["qwen_suggestion_applied"] = False
            value = normalized
            meta["latency_ms"] = round((time.monotonic() - started) * 1000, 3)
            reply = response_for(task, value, meta)
            with self.lock:
                self.completed += 1
                self.cache[identity] = (fingerprint, reply)
                while len(self.cache) > 512:
                    self.cache.popitem(last=False)
            self.log({"request_id": identity, "event_id": task["event_id"], "frame_id": task["frame_id"],
                      "jpeg_sha256": jpeg_hash(jpeg), "jpeg_bytes": len(jpeg),
                      "raw_semantic": raw_semantic, "normalized_semantic": value,
                      "meta": meta, "attempt_count": self.attempts})
            return 200, reply
        finally:
            self.busy.release()

    def remote(self, task, jpeg):
        context = {"target_class": task["detector"]["class_name"]}
        options = dict(endpoint=self.args.endpoint, model=self.args.model, api_key=self.key,
                       enabled=True, timeout_seconds=self.args.cloud_timeout, max_tokens=256,
                       enable_thinking=False)
        ctx = mp.get_context("spawn")
        parent, child = ctx.Pipe(False)
        process = ctx.Process(target=cloud_worker, args=(child, options, jpeg, context), daemon=True)
        process.start()
        child.close()
        try:
            if parent.poll(self.args.cloud_timeout + 0.5):
                result = parent.recv()
                return validate_semantic(result["semantic"]), result["info"]
            return fallback("semantic reviewer timeout"), {"error_code": "UPSTREAM_TIMEOUT", "request_attempted": True}
        except (EOFError, ValueError, KeyError, TypeError):
            return fallback(), {"error_code": "INVALID_MODEL_RESPONSE", "request_attempted": True}
        finally:
            if process.is_alive():
                process.terminate()
            process.join(timeout=1)
            if process.is_alive():
                process.kill()
                process.join(timeout=1)
            process.close()
            parent.close()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, *_):
        pass

    def setup(self):
        super().setup()
        self.connection.settimeout(3)

    def send_json(self, status, value):
        raw = json.dumps(value, ensure_ascii=False, allow_nan=False).encode("utf8")
        try:
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(raw)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(raw)
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass

    def do_GET(self):
        if self.path != "/healthz":
            return self.send_json(404, {"error_code": "NOT_FOUND"})
        bridge = self.server.bridge
        return self.send_json(200, {"status": "ok", "service": "fire-qwen-bridge", "mode": bridge.args.mode,
                                   "qwen_configured": bool(bridge.key), "review_attempts": bridge.attempts,
                                   "instance_id": getattr(bridge.args, "instance_id", "manual")})

    def do_POST(self):
        if self.path != "/v1/semantic-review":
            return self.send_json(404, {"error_code": "NOT_FOUND"})
        try:
            if self.headers.get_content_type() != "application/json":
                return self.send_json(415, {"error_code": "BAD_CONTENT_TYPE"})
            if self.headers.get("Transfer-Encoding"):
                return self.send_json(400, {"error_code": "BAD_REQUEST"})
            length = int(self.headers.get("Content-Length", "-1"))
            if length < 1:
                return self.send_json(400, {"error_code": "BAD_REQUEST"})
            if length > MAX_BODY:
                return self.send_json(413, {"error_code": "IMAGE_TOO_LARGE"})
            body = self.rfile.read(length)
            if len(body) != length:
                raise ProtocolError("incomplete request")
            task = strict_loads(body)
            jpeg = validate_request(task)
            if self.headers.get("X-Request-ID") != task["request_id"]:
                raise ProtocolError("request header id")
            from PIL import Image
            with Image.open(io.BytesIO(jpeg)) as image:
                if image.format != "JPEG" or max(image.size) > 640 or min(image.size) < 1:
                    raise ProtocolError("JPEG dimensions")
                image.load()
            status, value = self.server.bridge.review(task, jpeg)
            self.send_json(status, value)
        except (ValueError, TypeError, KeyError, OSError, UnicodeError, socket.timeout):
            self.send_json(400, {"error_code": "BAD_REQUEST"})
        except Exception:
            self.send_json(503, {"error_code": "INTERNAL_ERROR"})


def make_server(args):
    server = ThreadingHTTPServer((args.bind, args.port), Handler)
    server.daemon_threads = True
    server.bridge = Bridge(args)
    return server


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bind", default="192.168.126.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--mode", choices=["mock", "remote"], default="mock")
    parser.add_argument("--key-file", default=str(Path(__file__).resolve().parents[1] / "config" / "qwen.env"))
    parser.add_argument("--endpoint", default="https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")
    parser.add_argument("--model", default="qwen3.8-flash")
    parser.add_argument("--max-requests", type=int, default=8)
    parser.add_argument("--cloud-timeout", type=float, default=12)
    parser.add_argument("--log", required=True)
    parser.add_argument("--instance-id", default="manual")
    args = parser.parse_args()
    if args.cloud_timeout <= 0 or args.cloud_timeout > 12 or args.max_requests < 1:
        parser.error("invalid limits")
    server = make_server(args)
    print(json.dumps({"service": "fire-qwen-bridge", "bind": args.bind, "port": args.port,
                      "mode": args.mode, "qwen_configured": bool(server.bridge.key)}), flush=True)
    try:
        server.serve_forever(poll_interval=0.1)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
