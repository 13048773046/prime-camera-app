from __future__ import annotations

import json
import re
from typing import Any

import httpx

from .config import Settings
from .persona import SYSTEM_PROMPT, local_line
from .schemas import ComposeRequest


def _extract_json(text: str) -> dict[str, Any]:
    text = text.strip()
    text = re.sub(r"^```(?:json)?|```$", "", text, flags=re.MULTILINE).strip()
    start = text.find("{")
    end = text.rfind("}")
    if start < 0 or end <= start:
        raise ValueError("模型未返回 JSON")
    return json.loads(text[start : end + 1])


def _normalize_model_payload(payload: dict[str, Any], fallback: dict[str, Any]) -> dict[str, Any]:
    def box(key: str) -> list[float]:
        value = payload.get(key) or fallback[key]
        if isinstance(value, list) and len(value) == 4:
            return [round(float(x), 4) for x in value]
        return fallback[key]

    hint = str(payload.get("hint") or fallback["hint"]).strip()
    if len(hint) > 28:
        hint = hint[:28]
    reasons = payload.get("reasons") or fallback["reasons"]
    if not isinstance(reasons, list):
        reasons = [str(reasons)] if reasons else []
    reasons = [str(x)[:20] for x in reasons][:2]

    confidence = float(payload.get("confidence") or fallback["confidence"])
    confidence = min(max(confidence, 0.0), 1.0)

    return {
        "subject": str(payload.get("subject") or fallback["subject"]),
        "subject_box": box("subject_box"),
        "target_box": box("target_box"),
        "target_zoom": min(max(float(payload.get("target_zoom") or fallback["target_zoom"]), 0.5), 3.0),
        "horizon_fix": float(payload.get("horizon_fix") or fallback["horizon_fix"]),
        "hint": hint or fallback["hint"],
        "reasons": reasons,
        "confidence": confidence,
        "source": "model",
    }


async def _chat(settings: Settings, messages: list[dict[str, Any]], *, max_tokens: int | None = None) -> str | None:
    if not settings.ai_api_key:
        return None
    body: dict[str, Any] = {
        "model": settings.ai_model,
        "messages": messages,
        "max_tokens": max_tokens or settings.ai_max_tokens,
        "temperature": settings.ai_temperature,
        "response_format": {"type": "json_object"},
    }
    if settings.ai_reasoning_effort:
        body["reasoning_effort"] = settings.ai_reasoning_effort
    try:
        async with httpx.AsyncClient(timeout=settings.ai_timeout_seconds) as client:
            resp = await client.post(
                f"{settings.ai_api_base}/chat/completions",
                headers={
                    "Authorization": f"Bearer {settings.ai_api_key}",
                    "Content-Type": "application/json",
                },
                json=body,
            )
            resp.raise_for_status()
            data = resp.json()
        return (data.get("choices") or [{}])[0].get("message", {}).get("content", "") or None
    except Exception:
        return None


async def analyze_with_model(
    request: ComposeRequest, settings: Settings, fallback: dict[str, Any]
) -> dict[str, Any] | None:
    """Let DeepSeek phrase the director's note around a deterministic plan.

    DeepSeek's public API is a text model, so we never send `image_url` here.
    The geometry stays local; the model only turns it into 流小萤's voice and
    may adjust the confidence. This is the same split Doka uses between its
    scan plan and its client-side rendering, adapted to a text-only provider.
    """
    brief = {
        "scene": request.mode,
        "lens": request.device.lens,
        "zoom": request.device.zoom,
        "tilt": request.tilt,
        "roll": request.roll,
        "subject_box": fallback.get("subject_box"),
        "target_box": fallback.get("target_box"),
        "local_hint": fallback.get("hint"),
        "local_reasons": fallback.get("reasons"),
    }
    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {
            "role": "user",
            "content": (
                "这是端侧视觉已经算好的构图方案，请不要改主体框和目标框，"
                "只把口令改写成流小萤会说的话，并给出最多两条理由。\n"
                + json.dumps(brief, ensure_ascii=False)
            ),
        },
    ]
    content = await _chat(settings, messages)
    if not content:
        return None
    try:
        payload = _extract_json(content)
    except Exception:
        return None
    return _normalize_model_payload(payload, fallback)


async def persona_line(payload: dict[str, Any], settings: Settings) -> tuple[str, str]:
    """Return (line, source). Falls back to the local director voice."""
    fallback = local_line(payload)
    content = await _chat(
        settings,
        [
            {"role": "system", "content": SYSTEM_PROMPT},
            {
                "role": "user",
                "content": (
                    "用一句话给这次拍摄口令，16 个汉字以内，直接可执行。\n"
                    + json.dumps(payload, ensure_ascii=False)
                ),
            },
        ],
        max_tokens=120,
    )
    if not content:
        return fallback, "local"
    try:
        parsed = _extract_json(content)
        line = str(parsed.get("hint") or parsed.get("line") or "").strip()
        if line:
            return line[:28], "model"
    except Exception:
        pass
    return fallback, "local"
