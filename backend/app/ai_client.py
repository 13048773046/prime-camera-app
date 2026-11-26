from __future__ import annotations

import json
import re
from typing import Any

import httpx

from .config import Settings
from .schemas import ComposeRequest


SYSTEM_PROMPT = """你是相机构图顾问。分析用户上传的取景画面，只输出 JSON，不要输出解释、Markdown 或代码块。
字段：subject(person/group/object/scene/unknown)、subject_box([x,y,w,h] 归一化)、target_box([x,y,w,h])、target_zoom(0.5-3)、horizon_fix(度)、hint(一句不超过16字的可执行口令)、reasons(最多两条)、confidence(0-1)。"""


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
    if len(hint) > 16:
        hint = hint[:16]
    reasons = payload.get("reasons") or fallback["reasons"]
    if not isinstance(reasons, list):
        reasons = [str(reasons)] if reasons else []
    reasons = [str(x) for x in reasons][:2]

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


async def analyze_with_model(request: ComposeRequest, settings: Settings, fallback: dict[str, Any]) -> dict[str, Any] | None:
    if not settings.ai_api_key:
        return None

    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {
            "role": "user",
            "content": [
                {"type": "text", "text": f"模式：{request.mode}；镜头：{request.device.lens}；变焦：{request.device.zoom}；姿态：tilt={request.tilt}, roll={request.roll}"},
                {"type": "image_url", "image_url": {"url": request.image}},
            ],
        },
    ]
    body = {
        "model": settings.ai_model,
        "messages": messages,
        "reasoning_effort": settings.ai_reasoning_effort,
        "max_tokens": settings.ai_max_tokens,
        "temperature": settings.ai_temperature,
        "response_format": {"type": "json_object"},
    }

    try:
        async with httpx.AsyncClient(timeout=settings.ai_timeout_seconds) as client:
            resp = await client.post(
                f"{settings.ai_api_base}/chat/completions",
                headers={"Authorization": f"Bearer {settings.ai_api_key}", "Content-Type": "application/json"},
                json=body,
            )
            resp.raise_for_status()
            data = resp.json()
        content = (data.get("choices") or [{}])[0].get("message", {}).get("content", "")
        if not content:
            return None
        payload = _extract_json(content)
        return _normalize_model_payload(payload, fallback)
    except Exception:
        return None
