from __future__ import annotations

from functools import lru_cache
from os import environ
from pydantic import BaseModel, Field


class Settings(BaseModel):
    app_name: str = "定焦 PRIME 构图服务"
    debug: bool = False
    api_prefix: str = "/v1"

    ai_api_base: str = Field(default="https://api.deepseek.com")
    ai_api_key: str = Field(default="")
    ai_model: str = Field(default="deepseek-chat")
    ai_timeout_seconds: float = 12.0
    ai_max_tokens: int = 800
    ai_temperature: float = 0.2
    ai_reasoning_effort: str = ""

    free_geometry_unlimited: bool = True
    deep_analysis_daily_limit: int = 3
    dedup_window_seconds: int = 3
    max_image_bytes: int = 8 * 1024 * 1024
    template_dir: str = "static/templates"
    min_confidence: float = 0.35

    cors_origins: list[str] = Field(default_factory=lambda: ["*"])


@lru_cache
def get_settings() -> Settings:
    return Settings(
        app_name=environ.get("PRIME_APP_NAME", "定焦 PRIME 构图服务"),
        debug=environ.get("PRIME_DEBUG", "0") == "1",
        ai_api_base=environ.get("AI_API_BASE", "https://api.deepseek.com").rstrip("/"),
        ai_api_key=environ.get("AI_API_KEY", "").strip(),
        ai_model=environ.get("AI_MODEL", "deepseek-chat"),
        ai_timeout_seconds=float(environ.get("AI_TIMEOUT_SECONDS", "12.0")),
        ai_max_tokens=int(environ.get("AI_MAX_TOKENS", "800")),
        ai_temperature=float(environ.get("AI_TEMPERATURE", "0.2")),
        ai_reasoning_effort=environ.get("AI_REASONING_EFFORT", ""),
        deep_analysis_daily_limit=int(environ.get("DEEP_ANALYSIS_DAILY_LIMIT", "3")),
        dedup_window_seconds=int(environ.get("COMPOSE_DEDUP_SECONDS", "3")),
        max_image_bytes=int(environ.get("MAX_IMAGE_BYTES", str(8 * 1024 * 1024))),
        min_confidence=float(environ.get("MIN_CONFIDENCE", "0.35")),
        template_dir=environ.get("TEMPLATE_DIR", "static/templates"),
        cors_origins=[x for x in environ.get("CORS_ORIGINS", "*").split(",") if x],
    )
