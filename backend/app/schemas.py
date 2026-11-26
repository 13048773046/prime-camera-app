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
