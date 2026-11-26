from __future__ import annotations

import base64
import binascii
import io
from dataclasses import dataclass

from PIL import Image

from .schemas import ComposeRequest


@dataclass
class FrameInfo:
    width: int
    height: int
    has_image: bool


def decode_frame(image: str) -> FrameInfo:
    raw = image
    if raw.startswith("data:"):
        _, raw = raw.split(",", 1)
    try:
        data = base64.b64decode(raw, validate=False)
    except binascii.Error as exc:
        raise ValueError("image base64 解码失败") from exc
    if not data:
        raise ValueError("image 内容为空")
    try:
        with Image.open(io.BytesIO(data)) as img:
            return FrameInfo(width=img.width, height=img.height, has_image=True)
    except Exception as exc:
        raise ValueError("image 不是可读取的图片") from exc


def _clamp_box(box: list[float]) -> list[float]:
    x, y, w, h = box
    x = min(max(x, 0.0), 1.0)
    y = min(max(y, 0.0), 1.0)
    w = min(max(w, 0.0), 1.0 - x)
    h = min(max(h, 0.0), 1.0 - y)
    return [round(x, 4), round(y, 4), round(w, 4), round(h, 4)]


def rule_compose(request: ComposeRequest, frame: FrameInfo) -> dict:
    reasons: list[str] = []
    roll = request.roll
    tilt = request.tilt

    target_box = [0.33, 0.22, 0.34, 0.68]
    subject_box = target_box
    target_zoom = request.device.zoom
    horizon_fix = 0.0
    hint = "把主体放到画面中间"

    if abs(roll) >= 1.2:
        horizon_fix = round(-roll, 2)
        reasons.append("地平线倾斜")
        hint = "先把画面端平"

    if tilt <= -8:
        reasons.append("镜头偏高")
        hint = "镜头降到胸口"
    elif tilt >= 8:
        reasons.append("镜头偏低")
        hint = "镜头抬到胸口"

    if request.mode == "landscape":
        target_box = [0.28, 0.25, 0.44, 0.5]
        subject_box = target_box

    if not reasons:
        reasons.append("构图基本稳定")
        hint = "保持当前位置，准备拍摄"

    return {
        "subject": "person",
        "subject_box": _clamp_box(subject_box),
        "target_box": _clamp_box(target_box),
        "target_zoom": round(target_zoom, 2),
        "horizon_fix": horizon_fix,
        "hint": hint,
        "reasons": reasons[:2],
        "confidence": 0.62,
        "source": "rule",
    }
