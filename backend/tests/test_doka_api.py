from pathlib import Path

from fastapi.testclient import TestClient

from app import store
from app.main import app

store.DB_PATH = Path("/tmp/prime_doka_api_test.db")
if store.DB_PATH.exists():
    store.DB_PATH.unlink()
store.init_db()
client = TestClient(app)


def _login(phone: str = "13900001111") -> dict:
    code = client.post(
        "/ai_camera/auth/get_code",
        json={"phone_num": phone, "scene": "login"},
    ).json()["data"]["dev_code"]
    response = client.post(
        "/ai_camera/auth/login",
        json={"phone_num": phone, "msg_code": code},
    )
    assert response.status_code == 200
    assert response.json()["code"] == 0
    return response.json()["data"]


def test_auth_and_me():
    data = _login()
    token = data["token"]
    me = client.post(
        "/ai_camera/auth/me",
        headers={"Authorization": f"Bearer {token}"},
    ).json()
    assert me["code"] == 0
    assert me["data"]["phone_num"] == "13900001111"
    assert me["data"]["is_login"] is True


def test_vip_products_order_and_status():
    data = _login("13900002222")
    headers = {"Authorization": f"Bearer {data['token']}"}
    products = client.get("/ai_camera/vip/products").json()["data"]["products"]
    assert any(p["product_id"] == "prime.pro.month" for p in products)

    order = client.post(
        "/ai_camera/pay/create_order",
        headers=headers,
        json={"product_id": "prime.pro.month"},
    ).json()
    assert order["code"] == 0
    out_trade_no = order["data"]["out_trade_no"]

    status = client.get(
        f"/ai_camera/pay/order_status?out_trade_no={out_trade_no}",
        headers=headers,
    ).json()
    assert status["data"]["status"] == "pending"

    confirm = client.post(
        f"/ai_camera/pay/mock_confirm?out_trade_no={out_trade_no}",
        headers=headers,
    ).json()
    assert confirm["code"] == 0
    assert confirm["data"]["is_vip"] is True


def test_redeem_and_config():
    data = _login("13900003333")
    headers = {"Authorization": f"Bearer {data['token']}"}
    redeem = client.post(
        "/api/v1/redeem_vip_code",
        headers=headers,
        json={"redeem_code": "PRIME2026"},
    ).json()
    assert redeem["code"] == 0
    assert redeem["data"]["profile"]["is_vip"] is True

    assert client.post("/app/config_doka").json()["data"]["globalEnabled"] is True
    assert client.post("/app/version_doka_android").json()["code"] == 0
