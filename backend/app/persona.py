from __future__ import annotations

from typing import Any

PERSONA_NAME = "林晓莹"
PERSONA_ROLE = "构图导演"

SYSTEM_PROMPT = """你是林晓莹，一位日系动漫风格的 AI 构图导演。你说话像一位耐心、懂行的摄影指导：
先看主体和光，再给一个能立刻执行的动作；不堆术语，不夸张，不卖萌。
只输出 JSON，不要 Markdown 或代码块。
字段：hint（不超过 16 个汉字，直接可执行）、reasons（最多两条，每条不超过 18 个汉字）、confidence（0-1）。"""


def _distance_hint(subject_height: float, target_height: float) -> str:
    if subject_height <= 0.01:
        return "先把主体完整放进画面"
    ratio = subject_height / max(target_height, 0.01)
    if ratio < 0.72:
        return "再靠近一点，让主体更完整"
    if ratio > 1.35:
        return "再退一点，给主体留出空间"
    return "保持这个距离，准备拍摄"


def local_reason(
    *,
    scene: str,
    subject_height: float,
    target_height: float,
    distance: float | None,
    tilt: float,
    roll: float,
    subject_kind: str = "person",
) -> str:
    """A deterministic, Doka-style one-line director note.

    It intentionally reads like a photographer talking, not like a system toast.
    """
    if abs(roll) >= 1.2:
        return "先把画面端平，再让我看构图"
    if subject_kind == "person" and scene == "portrait":
        if distance and distance > 0:
            return f"约 {distance:.1f} 米，上半身刚好落进 3:4"
        return _distance_hint(subject_height, target_height)
    if scene == "landscape":
        return "把地平线压到下三分之一，天空会更透气"
    if scene == "still":
        return "让主体占画面一半，留一点呼吸位"
    return _distance_hint(subject_height, target_height)


def local_line(payload: dict[str, Any]) -> str:
    return local_reason(
        scene=str(payload.get("scene") or payload.get("mode") or "portrait"),
        subject_height=float(payload.get("subject_height") or 0.6),
        target_height=float(payload.get("target_height") or 0.62),
        distance=float(payload["distance"]) if payload.get("distance") is not None else None,
        tilt=float(payload.get("tilt") or 0),
        roll=float(payload.get("roll") or 0),
        subject_kind=str(payload.get("subject_kind") or "person"),
    )


def clean_line(value: str, fallback: str) -> str:
    line = " ".join(str(value or "").split()).strip()
    if not line:
        return fallback
    return line[:28]
