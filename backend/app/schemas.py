from __future__ import annotations

from typing import Literal
from pydantic import BaseModel, Field, field_validator


class DeviceState(BaseModel):
    lens: Literal["ultraWide", "wide", "tele"] = "wide"
    zoom: float = Field(default=1.0, ge=0.5, le=8.0)
    aspect: str = Field(default="3:4", pattern="^(3:4|9:16|1:1|4:3|16:9)$")


class ComposeRequest(BaseModel):
    image: str = Field(..., description="base64 JPEG，可带 data:image/jpeg;base64, 前缀")
    mode: Literal["portrait", "landscape"] = "portrait"
    device: DeviceState = Field(default_factory=DeviceState)
    tilt: float = Field(default=0.0, ge=-90, le=90)
    roll: float = Field(default=0.0, ge=-180, le=180)

    @field_validator("image")
    @classmethod
    def image_must_not_be_empty(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("image 不能为空")
        return value.strip()


class ComposeResponse(BaseModel):
    subject: str = "unknown"
    subject_box: list[float] = Field(default_factory=lambda: [0.0, 0.0, 0.0, 0.0])
    target_box: list[float] = Field(default_factory=lambda: [0.0, 0.0, 0.0, 0.0])
    target_zoom: float = 1.0
    horizon_fix: float = 0.0
    hint: str = "把主体放到画面中间"
    reasons: list[str] = Field(default_factory=list)
    confidence: float = 0.0
    source: Literal["rule", "model", "fallback"] = "rule"


class HealthResponse(BaseModel):
    ok: bool
    service: str
    ai_configured: bool
    version: str = "0.1.0"


class SubAreaRectModel(BaseModel):
    X: float = 0.0
    Y: float = 0.0
    W: float = 1.0
    H: float = 1.0


class CameraFilterModel(BaseModel):
    FilterName: str = ""
    Reason: str = ""


FilterModel = CameraFilterModel


class ScanData(BaseModel):
    # Doka `CameraData` uses PascalCase JSON keys. Keep them verbatim so the
    # reverse-engineered contract stays recognizable.
    ExifFocalLength: str = "26"
    BodyRange: str = "medium"
    PredictSubAreaPicURL: str = ""
    PicWithPredictAreaLine: str = ""
    SubAreaSize: str = "medium"
    LeftTopCrd: list[int] = Field(default_factory=lambda: [0, 0])
    RightDownCrd: list[int] = Field(default_factory=lambda: [0, 0])
    ComposeReason: str = ""
    AiCameraFilter: FilterModel | None = None
    AiCameraFilters: list[CameraFilterModel] = Field(default_factory=list)
    SubAreaRectNorm: SubAreaRectModel = Field(default_factory=SubAreaRectModel)


class ScanEnvelope(BaseModel):
    code: int = 0
    message: str = "ok"
    data: ScanData


class PersonaRequest(BaseModel):
    scene: str = "portrait"
    subject_kind: str = "person"
    subject_height: float = 0.6
    target_height: float = 0.62
    distance: float | None = None
    tilt: float = 0.0
    roll: float = 0.0
    mode: str = "portrait"


class PersonaResponse(BaseModel):
    name: str = "林晓莹"
    role: str = "构图导演"
    line: str
    source: Literal["local", "model"] = "local"
