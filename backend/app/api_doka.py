from __future__ import annotations

import random
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends, Header, HTTPException, Request
from pydantic import BaseModel

from . import store

router = APIRouter(tags=["doka-parity"])
app_router = APIRouter(tags=["doka-app"])


def ok(data: Any = None, message: str = "ok") -> dict:
    return {"code": 0, "message": message, "data": data}


def fail(message: str, code: int = 1) -> dict:
    return {"code": code, "message": message, "data": None}


def _token(authorization: str | None) -> str | None:
    if not authorization:
        return None
    return authorization.replace("Bearer ", "").strip()


def current_user(authorization: str | None = Header(default=None)):
    user = store.user_by_token(_token(authorization))
    if not user:
        raise HTTPException(status_code=401, detail="登录已失效")
    return user


def optional_user(authorization: str | None = Header(default=None)):
    return store.user_by_token(_token(authorization))


def profile(user) -> dict:
    vip = store.is_vip(user)
    return {
        "user_id": user["id"],
        "username": user["username"] or "",
        "phone_num": user["phone"] or "",
        "is_login": True,
        "login_status": "valid",
        "login_type": "phone" if user["phone"] else "wechat",
        "has_phone_bound": bool(user["phone"]),
        "wechat_bound": bool(user["wechat_openid"]),
        "wechat_nickname": user["wechat_nickname"] or "",
        "is_vip": vip,
        "vip_type": "pro" if vip else "",
        "vip_expire_at": user["vip_expire_at"] or "",
        "remaining_free_count": int(store.get_setting("free_ai_count", "5")) if not vip else int(store.get_setting("pro_ai_count", "9999")),
        "remaining_compose_count": int(store.get_setting("free_ai_count", "5")) if not vip else int(store.get_setting("pro_ai_count", "9999")),
        "remaining_filter_count": int(store.get_setting("free_ai_count", "5")) if not vip else int(store.get_setting("pro_ai_count", "9999")),
    }


class SendCodeReq(BaseModel):
    phone_num: str = ""
    scene: str = "login"


class LoginReq(BaseModel):
    phone_num: str = ""
    msg_code: str = ""
    username: str = ""


class WechatLoginReq(BaseModel):
    code: str = ""
    state: str = ""


class BindPhoneReq(BaseModel):
    phone_num: str = ""
    msg_code: str = ""


class CreateOrderReq(BaseModel):
    product_id: str = ""


class RedeemReq(BaseModel):
    redeem_code: str = ""


class SecurityReq(BaseModel):
    installer_risk: bool = False
    proxy_risk: bool = False
    detail: dict = {}


PRODUCTS = [
    {
        "product_id": "prime.pro.month",
        "product_type": "subscription",
        "title": "连续包月",
        "duration_days": 30,
        "actual_price": 18.0,
        "original_price": 28.0,
        "daily_price": "0.60",
        "currency_symbol": "¥",
        "google_base_plan_id": "",
        "google_offer_id": "",
        "google_offer_token": "",
        "google_product_type": "subs",
    },
    {
        "product_id": "prime.pro.year",
        "product_type": "subscription",
        "title": "连续包年",
        "duration_days": 365,
        "actual_price": 128.0,
        "original_price": 336.0,
        "daily_price": "0.35",
        "currency_symbol": "¥",
        "google_base_plan_id": "",
        "google_offer_id": "",
        "google_offer_token": "",
        "google_product_type": "subs",
    },
    {
        "product_id": "prime.pro.lifetime",
        "product_type": "lifetime",
        "title": "终身 Pro",
        "duration_days": 3650,
        "actual_price": 298.0,
        "original_price": 598.0,
        "daily_price": "—",
        "currency_symbol": "¥",
        "google_base_plan_id": "",
        "google_offer_id": "",
        "google_offer_token": "",
        "google_product_type": "inapp",
    },
]


@router.post("/auth/get_code")
async def get_code(req: SendCodeReq):
    phone = req.phone_num.strip()
    if len(phone) < 6:
        return fail("请输入正确的手机号")
    code = f"{random.randint(0, 999999):06d}"
    store.save_code(phone, req.scene or "login", code, 300)
    data = {"expires_in": 300}
    if store.DEV_AUTH:
        data["dev_code"] = code  # 仅本地开发返回；生产由短信通道发送
    return ok(data)


@router.post("/auth/login")
async def login(req: LoginReq):
    phone = req.phone_num.strip()
    if not store.check_code(phone, "login", req.msg_code.strip()):
        return fail("验证码错误或已过期")
    user = store.create_or_login(phone, req.username)
    return ok(
        {
            "token": store.make_token(user["id"]),
            "user_id": user["id"],
            "username": user["username"],
            "phone_num": user["phone"],
            "is_first_login": False,
            "account_merged": False,
            "has_phone_bound": True,
            "wechat_bound": bool(user["wechat_openid"]),
            "wechat_nickname": user["wechat_nickname"] or "",
            "login_type": "phone",
            "merge_kind": "",
        }
    )


@router.post("/auth/wechat_login")
async def wechat_login(req: WechatLoginReq):
    # 未配置微信开放平台时，使用本地演示身份；不伪造真实微信资料。
    phone = "wechat-demo"
    user = store.create_or_login(phone, "微信用户")
    return ok(
        {
            "token": store.make_token(user["id"]),
            "user_id": user["id"],
            "username": user["username"],
            "phone_num": user["phone"],
            "is_first_login": False,
            "account_merged": False,
            "has_phone_bound": bool(user["phone"]),
            "wechat_bound": True,
            "wechat_nickname": user["wechat_nickname"] or "微信用户",
            "login_type": "wechat",
            "merge_kind": "",
        }
    )


@router.post("/auth/bind_phone")
async def bind_phone(req: BindPhoneReq, user=Depends(current_user)):
    if not store.check_code(req.phone_num, "bind", req.msg_code):
        return fail("验证码错误或已过期")
    with store._conn() as conn:
        conn.execute("UPDATE users SET phone=? WHERE id=?", (req.phone_num, user["id"]))
    return ok(profile(store.get_user(user["id"])))


@router.post("/auth/bind_wechat")
async def bind_wechat(user=Depends(current_user)):
    with store._conn() as conn:
        conn.execute("UPDATE users SET wechat_openid=?, wechat_nickname=? WHERE id=?", ("local-demo", "微信用户", user["id"]))
    return ok(profile(store.get_user(user["id"])))


@router.post("/auth/unbind_wechat")
async def unbind_wechat(user=Depends(current_user)):
    with store._conn() as conn:
        conn.execute("UPDATE users SET wechat_openid=NULL, wechat_nickname=NULL WHERE id=?", (user["id"],))
    return ok(profile(store.get_user(user["id"])))


@router.post("/auth/replace_wechat")
async def replace_wechat(user=Depends(current_user)):
    return ok(profile(user))


@router.post("/auth/verify_wechat_change")
async def verify_wechat_change(user=Depends(current_user)):
    return ok({"verified": True})


@router.post("/auth/delete_account")
async def delete_account(user=Depends(current_user)):
    with store._conn() as conn:
        conn.execute("UPDATE users SET deleted_at=? WHERE id=?", (store.now_iso(), user["id"]))
    return ok({"deleted": True})


@router.post("/auth/me")
async def me(user=Depends(current_user)):
    return ok(profile(user))


@router.get("/vip/products")
async def vip_products():
    return ok(
        {
            "products": PRODUCTS,
            "benefits": [
                {"title": "AI 构图不限次", "desc": "实时主体识别、距离与机位建议"},
                {"title": "全部胶片滤镜", "desc": "Doka 系列、F 系列、Kodak 与 Agfa 经典色彩"},
                {"title": "导出无水印", "desc": "保留完整分辨率与原片质感"},
                {"title": "多景别方案", "desc": "一次拍摄生成远景、中景、近景三套方案"},
            ],
            "purchase_note": "当前为 PRIME 自托管演示环境，支付通道未接入真实商户。",
            "renewal_tip": "订阅到期前 24 小时自动续费，可随时在系统设置中取消。",
            "privacy_policy": "https://example.com/privacy",
            "user_agreement": "https://example.com/terms",
        }
    )


@router.get("/vip/status")
async def vip_status(user=Depends(optional_user)):
    if not user:
        return ok(
            {
                "is_vip": False,
                "vip_type": "",
                "vip_expire_at": "",
                "remaining_free_count": 0,
                "remaining_compose_count": 0,
                "remaining_filter_count": 0,
            }
        )
    p = profile(user)
    return ok(
        {
            "is_vip": p["is_vip"],
            "vip_type": p["vip_type"],
            "vip_expire_at": p["vip_expire_at"],
            "remaining_free_count": p["remaining_free_count"],
            "remaining_compose_count": p["remaining_compose_count"],
            "remaining_filter_count": p["remaining_filter_count"],
        }
    )


@router.post("/pay/create_order")
async def create_order(req: CreateOrderReq, user=Depends(current_user)):
    product = next((p for p in PRODUCTS if p["product_id"] == req.product_id), None)
    if not product:
        return fail("套餐不存在")
    order = store.create_order(user["id"], req.product_id, product["actual_price"])
    return ok(order)


@router.get("/pay/order_status")
async def pay_order_status(out_trade_no: str, user=Depends(current_user)):
    row = store.order_status(out_trade_no)
    if not row or row["user_id"] != user["id"]:
        return fail("订单不存在")
    return ok(
        {
            "out_trade_no": row["out_trade_no"],
            "status": row["status"],
            "trade_state": "SUCCESS" if row["status"] == "paid" else "NOTPAY",
            "trade_state_desc": "支付成功" if row["status"] == "paid" else "等待支付",
            "is_vip": store.is_vip(user),
            "vip_type": "pro" if store.is_vip(user) else "",
            "vip_expire_at": user["vip_expire_at"] or "",
        }
    )


@router.post("/pay/google_play/verify")
async def google_play_verify(user=Depends(current_user)):
    return fail("Google Play 未配置，无法校验购买凭证")


@router.post("/pay/mock_confirm")
async def mock_confirm(out_trade_no: str, user=Depends(current_user)):
    """开发联调专用：把订单标记为已支付。生产环境不会暴露给客户端。"""
    if not store.DEV_AUTH:
        return fail("未开启本地联调模式")
    if not store.mark_order_paid(out_trade_no):
        return fail("订单不存在")
    return ok(profile(store.get_user(user["id"])))


@app_router.post("/api/v1/redeem_vip_code")
async def redeem_vip_code(req: RedeemReq, user=Depends(current_user)):
    ok_flag, message = store.redeem(user["id"], req.redeem_code)
    if not ok_flag:
        return fail(message)
    return ok({"message": message, "profile": profile(store.get_user(user["id"]))})


@app_router.post("/app/config_doka")
async def doka_config():
    return ok(
        {
            "globalEnabled": store.get_setting("global_enabled", "1") == "1",
            "securityBlockInstallerRisk": False,
            "securityBlockProxyRisk": False,
            "showAliyunOnFirstAICompose": False,
            "showCompleteCopywriting": True,
            "showRedeemCodeEntry": store.get_setting("show_redeem_entry", "1") == "1",
            "wechatAccountManagementEnabled": True,
            "wechatLoginEnabled": True,
            "wechatPhoneBindEnabled": True,
            "wechatVipBindPhoneRequired": False,
            "maintenance": store.get_setting("maintenance", "0") == "1",
            "announcement": store.get_setting("announcement", ""),
        }
    )


@app_router.post("/app/version_doka_android")
async def doka_version():
    return ok(
        {
            "versionCode": store.get_setting("app_version", "0.4.5").replace(".", "").lstrip("0") or "0",
            "versionName": store.get_setting("app_version", "0.4.5"),
            "updateType": "none" if not store.get_setting("download_url", "") else "force",
            "updateDesc": store.get_setting("announcement", ""),
            "appAddress": store.get_setting("download_url", ""),
            "h5UrlAddress": store.get_setting("public_base_url", store.PUBLIC_BASE_URL) + "/h5/",
        }
    )


@app_router.post("/app/security/report")
async def security_report(req: SecurityReq, request: Request):
    store.log_event(
        "security",
        {"installer_risk": req.installer_risk, "proxy_risk": req.proxy_risk, "detail": req.detail, "ip": request.client.host if request.client else ""},
    )
    return ok({"reported": True})
