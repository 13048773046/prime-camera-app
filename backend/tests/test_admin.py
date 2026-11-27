from pathlib import Path

from fastapi.testclient import TestClient

from app import store

store.DB_PATH = Path("/tmp/prime_admin_api_test.db")
if store.DB_PATH.exists():
    store.DB_PATH.unlink()
store.init_db()

from app.main import app  # noqa: E402

client = TestClient(app)


def _admin_token() -> str:
    response = client.post(
        "/admin/api/login",
        json={"username": "玉玲", "password": "prime-admin-2026"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["code"] == 0
    return body["data"]["token"]


def _user() -> dict:
    code = client.post(
        "/ai_camera/auth/get_code",
        json={"phone_num": "13900004444", "scene": "login"},
    ).json()["data"]["dev_code"]
    data = client.post(
        "/ai_camera/auth/login",
        json={"phone_num": "13900004444", "msg_code": code},
    ).json()["data"]
    return {"Authorization": f"Bearer {data['token']}"}


def test_admin_login_and_overview():
    token = _admin_token()
    headers = {"Authorization": f"Bearer {token}"}
    overview = client.get("/admin/api/overview", headers=headers).json()
    assert overview["code"] == 0
    assert overview["data"]["users"] >= 0
    assert overview["data"]["public_base_url"] == "https://uosar.yosar.cloud"
    assert client.get("/admin/api/overview").status_code == 401


def test_admin_settings_and_redeem_code():
    headers = {"Authorization": f"Bearer {_admin_token()}"}
    settings = client.get("/admin/api/settings", headers=headers).json()["data"]
    assert settings["public_base_url"] == "https://uosar.yosar.cloud"
    update = client.put(
        "/admin/api/settings",
        headers=headers,
        json={"values": {"announcement": "今晚更新，22:00 后可用"}},
    ).json()
    assert update["code"] == 0

    created = client.post(
        "/admin/api/redeem-codes",
        headers=headers,
        json={"days": 7, "count": 2, "max_uses": 1, "expires_days": 30},
    ).json()["data"]["items"]
    assert len(created) == 2
    code = created[0]["code"]
    user_headers = _user()
    redeem = client.post(
        "/api/v1/redeem_vip_code",
        headers=user_headers,
        json={"redeem_code": code},
    ).json()
    assert redeem["code"] == 0
    assert redeem["data"]["profile"]["is_vip"] is True

    # 同一兑换码不可再被第二个用户使用
    code2 = client.post(
        "/ai_camera/auth/get_code",
        json={"phone_num": "13900005555", "scene": "login"},
    ).json()["data"]["dev_code"]
    token2 = client.post(
        "/ai_camera/auth/login",
        json={"phone_num": "13900005555", "msg_code": code2},
    ).json()["data"]["token"]
    again = client.post(
        "/api/v1/redeem_vip_code",
        headers={"Authorization": f"Bearer {token2}"},
        json={"redeem_code": code},
    ).json()
    assert again["code"] != 0


def test_admin_users_orders_and_events():
    headers = {"Authorization": f"Bearer {_admin_token()}"}
    user_headers = _user()
    users = client.get("/admin/api/users", headers=headers).json()["data"]
    assert users["total"] >= 1
    user_id = users["items"][0]["id"]
    vip = client.post(
        f"/admin/api/users/{user_id}/vip",
        headers=headers,
        json={"days": 30},
    ).json()
    assert vip["code"] == 0
    disable = client.post(
        f"/admin/api/users/{user_id}/status",
        headers=headers,
        json={"disabled": True},
    ).json()
    assert disable["code"] == 0
    assert client.get("/admin/api/users", headers=headers).json()["data"]["items"][0]["status"] == "已禁用"

    order = client.post(
        "/ai_camera/pay/create_order",
        headers=user_headers,
        json={"product_id": "prime.pro.month"},
    ).json()["data"]["out_trade_no"]
    assert client.post(f"/admin/api/orders/{order}/confirm", headers=headers).json()["code"] == 0
    assert client.post(f"/admin/api/orders/{order}/refund", headers=headers).json()["code"] == 0

    events = client.get("/admin/api/events?kind=admin", headers=headers).json()["data"]["items"]
    assert any(e["kind"] == "admin_login" for e in events) or events == []


def test_admin_persona_is_live():
    headers = {"Authorization": f"Bearer {_admin_token()}"}
    update = client.put(
        "/admin/api/persona",
        headers=headers,
        json={"name": "小萤", "role": "构图导演", "prompt": "你是小萤，说话直接。"},
    ).json()
    assert update["code"] == 0
    line = client.post(
        "/v1/persona/line",
        json={"scene": "portrait", "subject_height": 0.6, "target_height": 0.62, "distance": 1.9},
    ).json()
    assert line["name"] == "小萤"
    assert line["role"] == "构图导演"
    assert line["line"]
    client.put(
        "/admin/api/persona",
        headers=headers,
        json={"name": "流小萤", "role": "构图导演", "prompt": "你是流小萤，PRIME 的构图导演。"},
    )
