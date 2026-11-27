from __future__ import annotations

import hashlib
import io
import json
import math
import time
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageOps, ImageStat


@dataclass
class FrameMetrics:
    width: int
    height: int
    brightness: float
    contrast: float
    skin_ratio: float
    skin_box: list[float] | None
    edge_center: tuple[float, float]


def _quantile(values: list[int], q: float) -> int:
    if not values:
        return 0
    values.sort()
    idx = min(len(values) - 1, max(0, int(q * len(values))))
    return values[idx]


def _skin_mask_box(image: Image.Image) -> tuple[float, list[float] | None]:
    """A tiny, dependency-free skin-tone detector.

    It is deliberately conservative: only used as a hint when the client did not
    send its on-device Vision subject box. The plan itself is still geometric.
    """
    small = image.convert("RGB").resize((64, 85))
    pixels = small.load()
    xs: list[int] = []
    ys: list[int] = []
    total = small.width * small.height
    for y in range(small.height):
        for x in range(small.width):
            r, g, b = pixels[x, y]
            cb = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b
            cr = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b
            if 72 <= cb <= 133 and 132 <= cr <= 178 and r > 45:
                xs.append(x)
                ys.append(y)
    if total == 0 or len(xs) / total < 0.025:
        return len(xs) / max(total, 1), None
    x0 = _quantile(xs, 0.03) / small.width
    x1 = (_quantile(xs, 0.97) + 1) / small.width
    y0 = _quantile(ys, 0.03) / small.height
    y1 = (_quantile(ys, 0.97) + 1) / small.height
    box = [x0, y0, max(0.0, x1 - x0), max(0.0, y1 - y0)]
    if box[2] < 0.05 or box[3] < 0.05:
        return len(xs) / total, None
    return len(xs) / total, [round(v, 4) for v in box]


def _edge_center(image: Image.Image) -> tuple[float, float]:
    """Find the busiest 8x8 cell; used as a fallback for non-human scenes."""
    gray = image.convert("L").resize((96, 128))
    edges = gray.filter(ImageFilter.FIND_EDGES)
    pixels = edges.load()
    cells: list[tuple[float, int, int]] = []
    for gy in range(8):
        for gx in range(8):
            total = 0
            for y in range(gy * 16, (gy + 1) * 16):
                for x in range(gx * 12, (gx + 1) * 12):
                    total += pixels[x, y]
            cells.append((total, gx, gy))
    _, gx, gy = max(cells)
    return (gx + 0.5) / 8, (gy + 0.5) / 8


def analyze_frame(data: bytes) -> tuple[Image.Image, FrameMetrics]:
    image = Image.open(io.BytesIO(data))
    image = ImageOps.exif_transpose(image).convert("RGB")
    stat = ImageStat.Stat(image.resize((64, 64)))
    brightness = sum(stat.mean) / 3 / 255
    contrast = sum(stat.stddev) / 3 / 255
    skin_ratio, skin_box = _skin_mask_box(image)
    cx, cy = _edge_center(image)
    metrics = FrameMetrics(
        width=image.width,
        height=image.height,
        brightness=round(brightness, 3),
        contrast=round(contrast, 3),
        skin_ratio=round(skin_ratio, 3),
        skin_box=skin_box,
        edge_center=(round(cx, 3), round(cy, 3)),
    )
    return image, metrics


def parse_box(value: str | None) -> list[float] | None:
    if not value:
        return None
    try:
        parsed = json.loads(value)
        if isinstance(parsed, list) and len(parsed) == 4:
            return _valid_box([float(v) for v in parsed])
    except Exception:
        pass
    parts = [p for p in value.replace(";", ",").split(",") if p.strip()]
    if len(parts) == 4:
        return _valid_box([float(p) for p in parts])
    return None


def _valid_box(box: list[float]) -> list[float] | None:
    x, y, w, h = box
    if not all(math.isfinite(v) for v in box):
        return None
    if w <= 0.01 or h <= 0.01:
        return None
    x = min(max(x, 0.0), 1.0)
    y = min(max(y, 0.0), 1.0)
    w = min(max(w, 0.02), 1.0 - x)
    h = min(max(h, 0.02), 1.0 - y)
    return [round(x, 4), round(y, 4), round(w, 4), round(h, 4)]


def _best_subject_box(metrics: FrameMetrics, subject_box: list[float] | None) -> tuple[list[float], str]:
    if subject_box:
        return subject_box, "client"
    if metrics.skin_box:
        return metrics.skin_box, "skin"
    # For a scene, use the busiest cell and a generous crop.
    cx, cy = metrics.edge_center
    return _valid_box([cx - 0.28, cy - 0.3, 0.56, 0.58]) or [0.2, 0.2, 0.6, 0.6], "edge"


def make_plan(
    *,
    metrics: FrameMetrics,
    subject_box: list[float] | None,
    subject_kind: str,
    scene: str,
    zoom: float,
    aspect: float = 0.75,
) -> dict:
    box, box_source = _best_subject_box(metrics, subject_box)
    subject_h = box[3]
    subject_w = box[2]

    if scene == "portrait" and subject_kind == "person":
        target_h = 0.64 if subject_h < 0.55 else 0.58
        target_name = "上半身 3:4 人像"
    elif subject_kind == "group":
        target_h = 0.52
        target_name = "多人合影"
    elif scene == "still":
        target_h = 0.55
        target_name = "静物近景"
    elif scene == "landscape":
        target_h = 0.62
        target_name = "环境人像"
    else:
        target_h = 0.56
        target_name = "主体特写"

    crop_h = min(0.98, max(0.32, subject_h / max(target_h, 0.01)))
    crop_w = max(crop_h * aspect, subject_w * 1.18)
    crop_w = min(0.98, crop_w)
    crop_h = min(0.98, crop_w / aspect)

    # Doka keeps the subject on a third when there is room, instead of
    # unconditionally pinning it to the exact center.
    subj_cx = box[0] + subject_w / 2
    if subj_cx < 0.42:
        target_cx = 0.38
    elif subj_cx > 0.58:
        target_cx = 0.62
    else:
        target_cx = 0.50
    target_cy = 0.47

    x = min(max(target_cx - crop_w / 2, 0.0), 1.0 - crop_w)
    y = min(max(target_cy - crop_h / 2, 0.0), 1.0 - crop_h)
    rect = [round(x, 4), round(y, 4), round(crop_w, 4), round(crop_h, 4)]

    recommended_zoom = min(5.0, max(0.5, zoom * (target_h / max(subject_h, 0.05))))
    recommended_distance = round(1.75 * (subject_h / max(target_h, 0.05)), 1)
    recommended_distance = min(8.0, max(0.5, recommended_distance))
    if recommended_distance < 1.0:
        body_range = "close"
    elif recommended_distance > 3.2:
        body_range = "far"
    else:
        body_range = "medium"
    sub_area_size = "small" if crop_w < 0.55 else ("medium" if crop_w < 0.8 else "large")

    return {
        "rect": rect,
        "subject_box": box,
        "box_source": box_source,
        "target_height": target_h,
        "target_name": target_name,
        "recommended_zoom": round(recommended_zoom, 2),
        "recommended_distance": recommended_distance,
        "body_range": body_range,
        "sub_area_size": sub_area_size,
    }


def _template_id(image: Image.Image, rect: list[float], salt: str) -> str:
    h = hashlib.sha256()
    h.update(str(image.size).encode())
    h.update(str(rect).encode())
    h.update(salt.encode("utf-8", "ignore"))
    h.update(str(time.time_ns()).encode())
    return h.hexdigest()[:16]


def render_templates(
    image: Image.Image, rect: list[float], template_dir: Path, salt: str
) -> tuple[str, str]:
    """Return (clean_template_path, annotated_path), Doka-style.

    `PredictSubAreaPicURL` is a clean crop used as the reference template;
    `PicWithPredictAreaLine` keeps the full frame with the predicted area drawn.
    """
    template_dir.mkdir(parents=True, exist_ok=True)
    ident = _template_id(image, rect, salt)
    clean_path = template_dir / f"template_{ident}.jpg"
    annotated_path = template_dir / f"predict_{ident}.jpg"

    w, h = image.size
    x = int(round(rect[0] * w))
    y = int(round(rect[1] * h))
    cw = max(2, int(round(rect[2] * w)))
    ch = max(2, int(round(rect[3] * h)))
    crop = image.crop((x, y, min(w, x + cw), min(h, y + ch)))
    crop.thumbnail((540, 720), Image.Resampling.LANCZOS)
    canvas = Image.new("RGB", (540, 720), (12, 12, 14))
    ox = (540 - crop.width) // 2
    oy = (720 - crop.height) // 2
    canvas.paste(crop, (ox, oy))
    canvas.save(clean_path, "JPEG", quality=82, optimize=True)

    annotated = image.copy()
    annotated.thumbnail((720, 960), Image.Resampling.LANCZOS)
    scaled = [int(round(rect[0] * annotated.width)), int(round(rect[1] * annotated.height)),
              int(round(rect[2] * annotated.width)), int(round(rect[3] * annotated.height))]
    draw = ImageDraw.Draw(annotated)
    draw.rectangle(
        [scaled[0], scaled[1], scaled[0] + scaled[2], scaled[1] + scaled[3]],
        outline=(255, 215, 106),
        width=4,
    )
    annotated.save(annotated_path, "JPEG", quality=80, optimize=True)

    # Keep the directory bounded on a small deployment.
    files = sorted(template_dir.glob("*.jpg"), key=lambda p: p.stat().st_mtime, reverse=True)
    for old in files[60:]:
        try:
            old.unlink()
        except OSError:
            pass
    return str(clean_path), str(annotated_path)
