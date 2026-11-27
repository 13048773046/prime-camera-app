from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import sqlite3
import time
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

DB_PATH = Path(os.environ.get("PRIME_DB_PATH", Path(__file__).resolve().parents[1] / "prime.db"))
SECRET = os.environ.get("PRIME_AUTH_SECRET", "prime-local-dev-secret")
DEV_AUTH = os.environ.get("PRIME_DEV_AUTH", "1") == "1"


def _conn() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db() -> None:
    with _conn() as conn:
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS users (
              id TEXT PRIMARY KEY,
              phone TEXT UNIQUE,
              username TEXT,
              wechat_openid TEXT,
              wechat_nickname TEXT,
              vip_expire_at TEXT,
              deleted_at TEXT,
              created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS codes (
              phone TEXT NOT NULL,
              scene TEXT NOT NULL,
              code TEXT NOT NULL,
              expires_at REAL NOT NULL,
              PRIMARY KEY(phone, scene)
            );
            CREATE TABLE IF NOT EXISTS orders (
              out_trade_no TEXT PRIMARY KEY,
              user_id TEXT NOT NULL,
              product_id TEXT NOT NULL,
              amount REAL NOT NULL,
              status TEXT NOT NULL,
              created_at TEXT NOT NULL,
              paid_at TEXT
            );
            CREATE TABLE IF NOT EXISTS events (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              kind TEXT NOT NULL,
              payload TEXT NOT NULL,
              created_at TEXT NOT NULL
            );
            """
        )


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _unb64(data: str) -> bytes:
    return base64.urlsafe_b64decode(data + "=" * (-len(data) % 4))


def make_token(user_id: str) -> str:
    payload = _b64(json.dumps({"uid": user_id, "ts": int(time.time())}, separators=(",", ":")).encode())
    sig = _b64(hmac.new(SECRET.encode(), payload.encode(), hashlib.sha256).digest())
    return f"{payload}.{sig}"


def parse_token(token: str) -> dict | None:
    try:
        payload, sig = token.split(".", 1)
        expected = _b64(hmac.new(SECRET.encode(), payload.encode(), hashlib.sha256).digest())
        if not hmac.compare_digest(sig, expected):
            return None
        return json.loads(_unb64(payload))
    except Exception:
        return None


def get_user(user_id: str) -> sqlite3.Row | None:
    with _conn() as conn:
        return conn.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()


def user_by_token(token: str | None) -> sqlite3.Row | None:
    if not token:
        return None
    payload = parse_token(token.replace("Bearer ", "").strip())
    if not payload:
        return None
    row = get_user(str(payload.get("uid") or ""))
    if row is None or row["deleted_at"]:
        return None
    return row


def create_or_login(phone: str, username: str = "") -> sqlite3.Row:
    with _conn() as conn:
        row = conn.execute("SELECT * FROM users WHERE phone=?", (phone,)).fetchone()
        if row is None:
            uid = uuid.uuid4().hex[:16]
            conn.execute(
                "INSERT INTO users(id,phone,username,created_at) VALUES(?,?,?,?)",
                (uid, phone, username or f"PRIME {phone[-4:]}", now_iso()),
            )
            row = conn.execute("SELECT * FROM users WHERE id=?", (uid,)).fetchone()
        elif row["deleted_at"]:
            conn.execute("UPDATE users SET deleted_at=NULL, username=? WHERE id=?", (username or row["username"], row["id"]))
            row = conn.execute("SELECT * FROM users WHERE id=?", (row["id"],)).fetchone()
        return row


def set_vip(user_id: str, days: int) -> str:
    base = datetime.now(timezone.utc)
    row = get_user(user_id)
    if row and row["vip_expire_at"]:
        try:
            current = datetime.fromisoformat(row["vip_expire_at"])
            if current > base:
                base = current
        except Exception:
            pass
    expire = (base + timedelta(days=days)).isoformat()
    with _conn() as conn:
        conn.execute("UPDATE users SET vip_expire_at=? WHERE id=?", (expire, user_id))
    return expire


def is_vip(user: sqlite3.Row | None) -> bool:
    if not user or not user["vip_expire_at"]:
        return False
    try:
        return datetime.fromisoformat(user["vip_expire_at"]) > datetime.now(timezone.utc)
    except Exception:
        return False


def save_code(phone: str, scene: str, code: str, ttl: int = 300) -> None:
    with _conn() as conn:
        conn.execute(
            "INSERT OR REPLACE INTO codes(phone,scene,code,expires_at) VALUES(?,?,?,?)",
            (phone, scene, code, time.time() + ttl),
        )


def check_code(phone: str, scene: str, code: str) -> bool:
    with _conn() as conn:
        row = conn.execute("SELECT * FROM codes WHERE phone=? AND scene=?", (phone, scene)).fetchone()
    if not row or row["expires_at"] < time.time():
        return False
    return hmac.compare_digest(str(row["code"]), str(code))


def create_order(user_id: str, product_id: str, amount: float) -> dict:
    no = "P" + datetime.now().strftime("%Y%m%d%H%M%S") + uuid.uuid4().hex[:6]
    with _conn() as conn:
        conn.execute(
            "INSERT INTO orders(out_trade_no,user_id,product_id,amount,status,created_at) VALUES(?,?,?,?,?,?)",
            (no, user_id, product_id, amount, "pending", now_iso()),
        )
    return {
        "app_id": "prime-local",
        "partner_id": "prime-local",
        "prepay_id": "mock_" + no,
        "package_value": "Sign=WXPay",
        "nonce_str": uuid.uuid4().hex[:16],
        "time_stamp": str(int(time.time())),
        "sign": "demo",
        "out_trade_no": no,
    }


def order_status(out_trade_no: str) -> dict | None:
    with _conn() as conn:
        row = conn.execute("SELECT * FROM orders WHERE out_trade_no=?", (out_trade_no,)).fetchone()
    if not row:
        return None
    return dict(row)


def mark_order_paid(out_trade_no: str, days: int = 30) -> bool:
    with _conn() as conn:
        row = conn.execute("SELECT * FROM orders WHERE out_trade_no=?", (out_trade_no,)).fetchone()
        if not row:
            return False
        if row["status"] == "paid":
            return True
        conn.execute("UPDATE orders SET status='paid', paid_at=? WHERE out_trade_no=?", (now_iso(), out_trade_no))
    set_vip(row["user_id"], days)
    return True


def redeem(user_id: str, code: str) -> tuple[bool, str]:
    valid = {"PRIME2026": 30, "PRIME-LIFETIME": 3650, "PRIME-30": 30}
    days = valid.get(code.strip().upper())
    if not days:
        return False, "兑换码无效或已过期"
    set_vip(user_id, days)
    with _conn() as conn:
        conn.execute("INSERT INTO events(kind,payload,created_at) VALUES('redeem',?,?)", (code, now_iso()))
    return True, "兑换成功"


def log_event(kind: str, payload: dict) -> None:
    with _conn() as conn:
        conn.execute(
            "INSERT INTO events(kind,payload,created_at) VALUES(?,?,?)",
            (kind, json.dumps(payload, ensure_ascii=False), now_iso()),
        )


init_db()
