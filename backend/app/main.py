from __future__ import annotations

import hashlib

from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware

from .ai_client import analyze_with_model
from .config import get_settings
from .geometry import decode_frame, rule_compose
from .rate_limit import CounterStore
from .schemas import ComposeRequest, ComposeResponse, HealthResponse

settings = get_settings()
app = FastAPI(title=settings.app_name, version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
counters = CounterStore(
    daily_limit=settings.deep_analysis_daily_limit,
    dedup_seconds=settings.dedup_window_seconds,
)


def _identity(request: Request, x_device_id: str | None) -> str:
    return x_device_id or request.client.host if request.client else "anonymous"


def _signature(payload: ComposeRequest) -> str:
    raw = f"{payload.mode}|{payload.device.lens}|{payload.device.zoom}|{payload.tilt}|{payload.roll}|{payload.image[-128:]}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


@app.get("/health", response_model=HealthResponse)
async def health() -> HealthResponse:
    return HealthResponse(ok=True, service=settings.app_name, ai_configured=bool(settings.ai_api_key))


@app.post("/v1/compose", response_model=ComposeResponse)
async def compose(
    payload: ComposeRequest,
    request: Request,
    x_device_id: str | None = Header(default=None),
) -> ComposeResponse:
    if len(payload.image) > settings.max_image_bytes * 2:
        raise HTTPException(status_code=413, detail="image 超过大小限制")

    try:
        frame = decode_frame(payload.image)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    fallback = rule_compose(payload, frame)
    identity = _identity(request, x_device_id)
    allowed, reason = counters.allow_deep(identity, _signature(payload))

    if not allowed:
        fallback["source"] = "rule"
        fallback["reasons"].append("深度指挥暂不可用，已使用端侧规则")
        return ComposeResponse(**fallback)

    model_result = await analyze_with_model(payload, settings, fallback)
    if model_result is None:
        fallback["source"] = "fallback"
        return ComposeResponse(**fallback)

    if model_result["confidence"] < settings.min_confidence:
        fallback["source"] = "fallback"
        return ComposeResponse(**fallback)

    return ComposeResponse(**model_result)
