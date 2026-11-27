from __future__ import annotations

import hmac
from datetime import datetime, timedelta, timezone
from typing import Any

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from pydantic import BaseModel

from . import store

router = APIRouter(prefix="/admin/api", tags=["admin"])


def ok(data: Any = None, message: str = "ok") -> dict:
    return {"code": 0, "message": message, "data": data}


def fail(message: str, code: int = 1) -> dict:
    return {"code": code, "message": message, "data": None}


def admin_required(authorization: str | None = Header(default=None)) -> dict:
    admin = store.admin_by_token(authorization)
    if not admin:
        raise HTTPException(status_code=401, detail="管理员登录已失效")
    return admin


class LoginReq(BaseModel):
    username: str = ""
    password: str = ""


class DaysReq(BaseModel):
    days: int = 30


class StatusReq(BaseModel):
    disabled: bool = True


class RedeemGenerateReq(BaseModel):
    days: int = 30
    count: int = 10
    max_uses: int = 1
    expires_days: int = 365


class SettingsReq(BaseModel):
    values: dict[str, str] = {}


class PersonaReq(BaseModel):
    name: str = ""
    role: str = ""
    prompt: str = ""


@router.post("/login")
async def admin_login(req: LoginReq):
    username = req.username.strip()
    if not hmac.compare_digest(username.encode(), store.ADMIN_USER.encode()) or not hmac.compare_digest(
        req.password.encode(), store.ADMIN_PASSWORD.encode()
    ):
        store.log_event("admin_login_failed", {"username": username})
        return fail("管理员账号或密码错误")
    token = store.make_admin_token(username)
    store.log_event("admin_login", {"username": username})
    return ok(
        {
            "token": token,
            "name": username,
            "role": "owner",
            "public_base_url": store.get_setting("public_base_url", store.PUBLIC_BASE_URL),
        }
    )


@router.get("/retention_placeholder")
async def placeholder():
    return ok({})


@router.get("/overview")
async def overview(admin=Depends(admin_required)):
    data = store.overview()
    data.update(
        {
            "admin": admin,
            "public_base_url": store.get_setting("public_base_url", store.PUBLIC_BASE_URL),
            "maintenance": store.get_setting("maintenance", "0") == "1",
            "app_version": store.get_setting("app_version", "0.4.5"),
            "announcement": store.get_setting("announcement", ""),
        }
    )
    return ok(data)


@router.get("/users")
async def users(
    q: str = "",
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    admin=Depends(admin_required),
):
    rows = store.list_users(q=q, limit=limit, offset=offset)
    for row in rows:
        row["is_vip"] = bool(row.get("vip_expire_at"))
        row["status"] = "已删除" if row.get("deleted_at") else ("已禁用" if row.get("disabled_at") else "正常")
    return ok({"items": rows, "total": store.count_users(q), "limit": limit, "offset": offset})


@router.post("/users/{user_id}/vip")
async def grant_vip(user_id: str, req: DaysReq, admin=Depends(admin_required)):
    if not store.get_user(user_id):
        return fail("用户不存在")
    expire = store.set_vip(user_id, max(1, min(req.days, 3650)))
    store.log_event("admin_vip", {"admin": admin["name"], "user_id": user_id, "days": req.days, "expire": expire})
    return ok({"vip_expire_at": expire})


@router.post("/users/{user_id}/status")
async def user_status(user_id: str, req: StatusReq, admin=Depends(admin_required)):
    if not store.set_user_flags(user_id, disabled=req.disabled):
        return fail("用户不存在")
    store.log_event("admin_user_status", {"admin": admin["name"], "user_id": user_id, "disabled": req.disabled})
    return ok({"disabled": req.disabled})


@router.delete("/users/{user_id}")
async def delete_user(user_id: str, admin=Depends(admin_required)):
    if not store.soft_delete_user(user_id):
        return fail("用户不存在")
    store.log_event("admin_user_delete", {"admin": admin["name"], "user_id": user_id})
    return ok({"deleted": True})


@router.get("/orders")
async def orders(
    status: str = "",
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    admin=Depends(admin_required),
):
    rows = store.list_orders(status=status, limit=limit, offset=offset)
    return ok({"items": rows, "limit": limit, "offset": offset})


@router.post("/orders/{out_trade_no}/confirm")
async def confirm_order(out_trade_no: str, admin=Depends(admin_required)):
    row = store.order_status(out_trade_no)
    if not row:
        return fail("订单不存在")
    days = {"prime.pro.month": 30, "prime.pro.year": 365, "prime.pro.lifetime": 3650}.get(
        row["product_id"], 30
    )
    store.mark_order_paid(out_trade_no, days=days)
    store.log_event("admin_order_confirm", {"admin": admin["name"], "out_trade_no": out_trade_no})
    return ok({"status": "paid"})


@router.post("/orders/{out_trade_no}/refund")
async def refund_order(out_trade_no: str, admin=Depends(admin_required)):
    if not store.mark_order_refunded(out_trade_no):
        return fail("订单不存在")
    store.log_event("admin_order_refund", {"admin": admin["name"], "out_trade_no": out_trade_no})
    return ok({"status": "refunded"})


@router.get("/redeem-codes")
async def redeem_codes(admin=Depends(admin_required)):
    return ok({"items": store.list_redeem_codes()})


@router.post("/redeem-codes")
async def create_codes(req: RedeemGenerateReq, admin=Depends(admin_required)):
    codes = store.create_redeem_codes(
        days=req.days, count=req.count, max_uses=req.max_uses, expires_days=req.expires_days
    )
    store.log_event("admin_redeem_create", {"admin": admin["name"], "count": len(codes), "days": req.days})
    return ok({"items": codes})


@router.post("/redeem-codes/{code}/disable")
async def disable_code(code: str, admin=Depends(admin_required)):
    if not store.disable_redeem_code(code):
        return fail("兑换码不存在")
    store.log_event("admin_redeem_disable", {"admin": admin["name"], "code": code})
    return ok({"code": code, "active": 0})


@router.get("/settings")
async def get_settings(admin=Depends(admin_required)):
    return ok(store.all_settings())


@router.put("/settings")
async def put_settings(req: SettingsReq, admin=Depends(admin_required)):
    allowed = {
        "public_base_url",
        "maintenance",
        "global_enabled",
        "show_redeem_entry",
        "free_ai_count",
        "pro_ai_count",
        "support_email",
        "support_douyin",
        "support_xiaohongshu",
        "persona_name",
        "persona_role",
        "ai_prompt",
        "watermark_styles",
        "app_version",
        "download_url",
        "announcement",
        "filter_catalog",
    }
    for key, value in req.values.items():
        if key in allowed:
            store.set_setting(key, value)
    store.log_event("admin_settings", {"admin": admin["name"], "keys": list(req.values.keys())})
    return ok(store.all_settings())


@router.get("/persona")
async def get_persona(admin=Depends(admin_required)):
    return ok(
        {
            "name": store.get_setting("persona_name", "流小萤"),
            "role": store.get_setting("persona_role", "构图导演"),
            "prompt": store.get_setting("ai_prompt", ""),
        }
    )


@router.put("/persona")
async def put_persona(req: PersonaReq, admin=Depends(admin_required)):
    if req.name.strip():
        store.set_setting("persona_name", req.name.strip()[:20])
    if req.role.strip():
        store.set_setting("persona_role", req.role.strip()[:20])
    if req.prompt.strip():
        store.set_setting("ai_prompt", req.prompt.strip()[:2000])
    store.log_event("admin_persona", {"admin": admin["name"]})
    return ok(
        {
            "name": store.get_setting("persona_name", "流小萤"),
            "role": store.get_setting("persona_role", "构图导演"),
            "prompt": store.get_setting("ai_prompt", ""),
        }
    )


class FiltersReq(BaseModel):
    items: list[dict[str, Any]] = []


@router.put("/filters")
async def put_filters(req: FiltersReq, admin=Depends(admin_required)):
    import json

    store.set_setting("filter_catalog", json.dumps(req.items, ensure_ascii=False))
    store.log_event("admin_filters", {"admin": admin["name"], "count": len(req.items)})
    return ok({"items": req.items})


@router.get("/usage")
async def usage(admin=Depends(admin_required)):
    today = datetime.now(timezone.utc).date()
    out = []
    for i in range(13, -1, -1):
        day = (today - timedelta(days=i)).isoformat()
        data = store.overview_for_day(day) if hasattr(store, "overview_for_day") else {}
        out.append({"date": day, **data})
    return ok({"items": out})


@router.get("/events")
async def events(
    kind: str = "",
    limit: int = Query(default=100, ge=1, le=500),
    admin=Depends(admin_required),
):
    return ok({"items": store.recent_events(kind=kind, limit=limit)})


@router.get("/filters")
async def filters(admin=Depends(admin_required)):
    catalog = store.get_setting("filter_catalog", "")
    if catalog:
        try:
            import json

            return ok({"items": json.loads(catalog), "custom": True})
        except Exception:
            pass
    items = [
        {"id": "none", "name": "原片", "category": "原片", "pro": False},
        {"id": "clear", "name": "清透", "category": "原片", "pro": False},
        {"id": "warm", "name": "暖调", "category": "原片", "pro": False},
        {"id": "cool", "name": "冷调", "category": "原片", "pro": False},
        {"id": "mono", "name": "黑白", "category": "黑白", "pro": False},
        {"id": "doka_s50", "name": "Doka S50", "category": "Doka", "pro": True},
        {"id": "doka_s100", "name": "Doka S100", "category": "Doka", "pro": True},
        {"id": "doka_s160", "name": "Doka S160", "category": "Doka", "pro": True},
        {"id": "doka_s200", "name": "Doka S200", "category": "Doka", "pro": True},
        {"id": "doka_s400", "name": "Doka S400", "category": "Doka", "pro": True},
        {"id": "f160c", "name": "F160C", "category": "F 系列", "pro": True},
        {"id": "f400h", "name": "F400H", "category": "F 系列", "pro": True},
        {"id": "fc200", "name": "FC200", "category": "F 系列", "pro": True},
        {"id": "fcc", "name": "FCC", "category": "F 系列", "pro": True},
        {"id": "classic_chrome", "name": "Classic Chrome", "category": "F 系列", "pro": True},
        {"id": "classic_neg", "name": "Classic Neg", "category": "F 系列", "pro": True},
        {"id": "pro_neg", "name": "Pro Neg", "category": "F 系列", "pro": True},
        {"id": "provia", "name": "Provia", "category": "F 系列", "pro": True},
        {"id": "velvia", "name": "Velvia", "category": "F 系列", "pro": True},
        {"id": "astia", "name": "Astia", "category": "F 系列", "pro": True},
        {"id": "kodak_gold", "name": "Gold 200", "category": "Kodak", "pro": True},
        {"id": "portra160", "name": "Portra 160", "category": "Kodak", "pro": True},
        {"id": "portra400", "name": "Portra 400", "category": "Kodak", "pro": True},
        {"id": "ektar", "name": "Ektar 100", "category": "Kodak", "pro": True},
        {"id": "agfa_ap100", "name": "APX 100", "category": "Agfa", "pro": True},
        {"id": "agfa_vista", "name": "Vista 800", "category": "Agfa", "pro": True},
        {"id": "bw_high", "name": "黑白 400", "category": "黑白", "pro": True},
    ]
    return ok({"items": items, "custom": False})
