import base64
import io
import os
import sys

from PIL import Image
from fastapi.testclient import TestClient

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.main import app  # noqa: E402


def _jpeg_base64() -> str:
    img = Image.new("RGB", (720, 960), color=(255, 247, 240))
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=70)
    return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()


client = TestClient(app)


def test_health():
    resp = client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["ok"] is True
    assert "service" in body


def test_compose_rule_fallback():
    resp = client.post(
        "/v1/compose",
        headers={"X-Device-Id": "test-device-1"},
        json={
            "image": _jpeg_base64(),
            "mode": "portrait",
            "device": {"lens": "wide", "zoom": 1.0, "aspect": "3:4"},
            "tilt": -10,
            "roll": 2.0,
        },
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["subject_box"][2] > 0
    assert body["target_box"][2] > 0
    assert body["hint"]
    assert body["source"] in {"rule", "fallback"}


def test_compose_rejects_bad_image():
    resp = client.post(
        "/v1/compose",
        headers={"X-Device-Id": "test-device-2"},
        json={"image": "not-a-real-base64", "mode": "portrait"},
    )
    assert resp.status_code == 400


def test_dedup_same_request():
    payload = {
        "image": _jpeg_base64(),
        "mode": "landscape",
        "device": {"lens": "wide", "zoom": 1.0, "aspect": "3:4"},
        "tilt": 0,
        "roll": 0,
    }
    first = client.post("/v1/compose", headers={"X-Device-Id": "test-device-3"}, json=payload)
    second = client.post("/v1/compose", headers={"X-Device-Id": "test-device-3"}, json=payload)
    assert first.status_code == 200
    assert second.status_code == 200


def test_scan_returns_doka_camera_data():
    img = Image.new("RGB", (900, 1200), color=(232, 220, 205))
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=70)
    files = {"file": ("frame.jpg", buf.getvalue(), "image/jpeg")}
    data = {
        "shoot_type": "portrait",
        "direction": "portrait",
        "comp_scene": "portrait",
        "subject_box": "[0.34,0.18,0.28,0.56]",
        "subject_kind": "person",
        "zoom": "1.0",
        "timestamp": "1700",
    }
    resp = client.post("/v1/scan", files=files, data=data)
    assert resp.status_code == 200
    body = resp.json()
    assert body["code"] == 0
    d = body["data"]
    assert d["PredictSubAreaPicURL"].endswith(".jpg")
    assert d["SubAreaRectNorm"]["W"] > 0
    assert d["ComposeReason"]


def test_persona_falls_back_to_local_line():
    resp = client.post(
        "/v1/persona/line",
        json={"scene": "portrait", "distance": 1.7, "subject_height": 0.55},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["name"] == "流小萤"
    assert body["line"]
    assert body["source"] in {"local", "model"}
