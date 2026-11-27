from __future__ import annotations

import hashlib
from pathlib import Path

from fastapi import FastAPI, File, Form, Header, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles

from .ai_client import analyze_with_model, persona_line
from .config import get_settings
from .doka import analyze_frame, make_plan, parse_box, render_templates
from .geometry import decode_frame, rule_compose
from .persona import PERSONA_NAME, PERSONA_ROLE, local_reason
from .rate_limit import CounterStore
from .api_doka import app_router as doka_app_router
from .api_doka import router as doka_router
from .api_admin import router as admin_router
from . import store
from .schemas import (
    CameraFilterModel,
    ComposeRequest,
    ComposeResponse,
    HealthResponse,
    PersonaRequest,
    PersonaResponse,
    ScanData,
    ScanEnvelope,
    SubAreaRectModel,
)

settings = get_settings()
app = FastAPI(title=settings.app_name, version="0.2.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
backend_root = Path(__file__).resolve().parents[1]
template_dir = backend_root / settings.template_dir
template_dir.mkdir(parents=True, exist_ok=True)
app.include_router(doka_router, prefix="/ai_camera")
app.include_router(doka_app_router)
app.include_router(admin_router)
app.mount("/static", StaticFiles(directory=str(backend_root / "static")), name="static")

web_root = backend_root / "web"
web_root.mkdir(parents=True, exist_ok=True)
app.mount("/assets", StaticFiles(directory=str(web_root / "assets")), name="web-assets")
if (web_root / "h5").exists():
    app.mount("/h5", StaticFiles(directory=str(web_root / "h5"), html=True), name="h5")
if (web_root / "admin").exists():
    app.mount("/admin", StaticFiles(directory=str(web_root / "admin"), html=True), name="admin")


@app.get("/", include_in_schema=False)
async def landing():
    page = web_root / "index.html"
    if page.exists():
        return FileResponse(page)
    return RedirectResponse(url="/h5/")

counters = CounterStore(
    daily_limit=settings.deep_analysis_daily_limit,
    dedup_seconds=settings.dedup_window_seconds,
)


def _identity(request: Request, x_device_id: str | None) -> str:
    return x_device_id or request.client.host if request.client else "anonymous"


def _signature(payload: ComposeRequest) -> str:
    raw = f"{payload.mode}|{payload.device.lens}|{payload.device.zoom}|{payload.tilt}|{payload.roll}|{payload.image[-128:]}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _scene_from(shoot_type: str, direction: str, comp_scene: str) -> str:
    raw = f"{comp_scene} {direction} {shoot_type}".lower()
    if any(k in raw for k in ("landscape", "scene", "风景", "风光")):
        return "landscape"
    if any(k in raw for k in ("still", "object", "food", "静物", "美食")):
        return "still"
    if any(k in raw for k in ("portrait", "person", "人像", "人物")):
        return "portrait"
    return "general"


@app.get("/health", response_model=HealthResponse)
async def health() -> HealthResponse:
    return HealthResponse(
        ok=True,
        service=settings.app_name,
        ai_configured=bool(settings.ai_api_key),
        version=store.get_setting("app_version", "0.4.5"),
    )


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


@app.post("/v1/scan", response_model=ScanEnvelope)
async def scan(
    request: Request,
    file: UploadFile = File(..., description="当前取景 JPEG"),
    shoot_type: str = Form("preview"),
    direction: str = Form("portrait"),
    compose_times: int = Form(0),
    scan_focal_length: float = Form(1.0),
    ai_filter: str = Form(""),
    timestamp: str = Form(""),
    comp_scene: str = Form("auto"),
    recommend_mode: str = Form("auto"),
    ai_filter_preferences: str = Form(""),
    language: str = Form("zh"),
    region: str = Form("CN"),
    distribution: str = Form("store"),
    subject_box: str = Form(""),
    subject_kind: str = Form("person"),
    aspect: str = Form("3:4"),
    zoom: float = Form(1.0),
    tilt: float = Form(0.0),
    roll: float = Form(0.0),
    x_device_id: str | None = Header(default=None),
) -> ScanEnvelope:
    """Doka-compatible scan contract.

    Reverse-engineered from `AiCompositionController.uploadJpegForScan` and
    `ApiService.uploadFrame`: `POST ai_camera/v2` is multipart with the image
    plus shoot_type/direction/compose_times/scan_focal_length/ai_filter/
    timestamp/comp_scene/recommend_mode/language/region/distribution. The
    response is wrapped in `{code,message,data:<CameraData>}`.
    """
    if store.get_setting("maintenance", "0") == "1":
        raise HTTPException(status_code=503, detail="PRIME 正在维护，请稍后再试")
    raw = await file.read()
    if not raw:
        raise HTTPException(status_code=400, detail="空图片")
    store.log_event(
        "scan",
        {
            "scene": str(shoot_type or direction or comp_scene),
            "bytes": len(raw),
            "device": x_device_id or (request.client.host if request.client else ""),
        },
    )
    if len(raw) > settings.max_image_bytes:
        raise HTTPException(status_code=413, detail="图片过大")

    try:
        image, metrics = analyze_frame(raw)
    except Exception as exc:
        raise HTTPException(status_code=400, detail="无法读取 JPEG") from exc

    scene = _scene_from(shoot_type, direction, comp_scene)
    subject = parse_box(subject_box)
    # Use the client's Vision box first; fall back to a small skin/edge hint.
    plan = make_plan(
        metrics=metrics,
        subject_box=subject,
        subject_kind=subject_kind or "person",
        scene=scene,
        zoom=max(0.5, min(zoom or scan_focal_length or 1.0, 8.0)),
        aspect=0.75 if aspect == "3:4" else 0.5625,
    )
    rect = plan["rect"]
    clean_path, annotated_path = render_templates(
        image,
        rect,
        template_dir,
        salt=f"{comp_scene}|{compose_times}|{metrics.brightness}",
    )
    base = str(store.get_setting("public_base_url", str(request.base_url)) or request.base_url).rstrip("/")
    clean_url = f"{base}/static/templates/{Path(clean_path).name}"
    annotated_url = f"{base}/static/templates/{Path(annotated_path).name}"

    reason = local_reason(
        scene=scene,
        subject_height=plan["subject_box"][3],
        target_height=plan["target_height"],
        distance=plan["recommended_distance"],
        tilt=tilt,
        roll=roll,
        subject_kind=subject_kind,
    )

    box = plan["subject_box"]
    w, h = image.size
    left = [int(round(box[0] * w)), int(round(box[1] * h))]
    right = [int(round((box[0] + box[2]) * w)), int(round((box[1] + box[3]) * h))]

    filters: list[AiCameraFilter] = []
    if scene == "portrait":
        filters.append(CameraFilterModel(FilterName="清透", Reason="让肤色更干净，保留环境光"))
    elif scene == "landscape":
        filters.append(CameraFilterModel(FilterName="暖调", Reason="压住天空高光，让远处更有层次"))
    else:
        filters.append(CameraFilterModel(FilterName="原片", Reason="先保留真实颜色"))

    data = ScanData(
        ExifFocalLength=str(int(round(plan["recommended_zoom"] * 26))),
        BodyRange=plan["body_range"],
        PredictSubAreaPicURL=clean_url,
        PicWithPredictAreaLine=annotated_url,
        SubAreaSize=plan["sub_area_size"],
        LeftTopCrd=left,
        RightDownCrd=right,
        ComposeReason=reason,
        AiCameraFilter=filters[0],
        AiCameraFilters=filters,
        SubAreaRectNorm=SubAreaRectModel(
            X=rect[0], Y=rect[1], W=rect[2], H=rect[3]
        ),
    )
    return ScanEnvelope(code=0, message="ok", data=data)


@app.post("/ai_camera/v2", response_model=ScanEnvelope)
async def doka_scan(request: Request, authorization: str | None = Header(default=None)):
    """Doka `POST ai_camera/v2` 的同构入口。

    客户端字段名与 `/v1/scan` 完全一致；这里只做 multipart 解包后复用同一套
    几何/模板/文案逻辑，避免两套响应结构漂移。
    """
    form = await request.form()
    file = form.get("file")
    if file is None or not hasattr(file, "read"):
        raise HTTPException(status_code=400, detail="缺少 file")

    def as_int(name: str, default: int) -> int:
        try:
            return int(str(form.get(name, default)))
        except ValueError:
            return default

    def as_float(name: str, default: float) -> float:
        try:
            return float(str(form.get(name, default)))
        except ValueError:
            return default

    return await scan(
        request=request,
        file=file,
        shoot_type=str(form.get("shoot_type", "preview")),
        direction=str(form.get("direction", "portrait")),
        compose_times=as_int("compose_times", 0),
        scan_focal_length=as_float("scan_focal_length", 1.0),
        ai_filter=str(form.get("ai_filter", "")),
        timestamp=str(form.get("timestamp", "")),
        comp_scene=str(form.get("comp_scene", "auto")),
        recommend_mode=str(form.get("recommend_mode", "auto")),
        ai_filter_preferences=str(form.get("ai_filter_preferences", "")),
        language=str(form.get("language", "zh")),
        region=str(form.get("region", "CN")),
        distribution=str(form.get("distribution", "store")),
        subject_box=str(form.get("subject_box", "")),
        subject_kind=str(form.get("subject_kind", "person")),
        aspect=str(form.get("aspect", "3:4")),
        zoom=as_float("zoom", 1.0),
        tilt=as_float("tilt", 0.0),
        roll=as_float("roll", 0.0),
        x_device_id=request.headers.get("x-device-id"),
    )


@app.post("/v1/persona/line", response_model=PersonaResponse)
async def persona(payload: PersonaRequest) -> PersonaResponse:
    line, source = await persona_line(payload.model_dump(), settings)
    return PersonaResponse(
        name=store.get_setting("persona_name", PERSONA_NAME),
        role=store.get_setting("persona_role", PERSONA_ROLE),
        line=line,
        source=source,
    )
