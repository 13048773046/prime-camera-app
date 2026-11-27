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
ADMIN_USER = os.environ.get("PRIME_ADMIN_USER", "玉玲")
ADMIN_PASSWORD = os.environ.get("PRIME_ADMIN_PASSWORD", "prime-admin-2026")
PUBLIC_BASE_URL = os.environ.get("PRIME_PUBLIC_BASE", "https://uosar.yosar.cloud").rstrip("/")


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
            CREATE TABLE IF NOT EXISTS redeem_codes (
              code TEXT PRIMARY KEY,
              days INTEGER NOT NULL,
              max_uses INTEGER NOT NULL DEFAULT 1,
              used_count INTEGER NOT NULL DEFAULT 0,
              active INTEGER NOT NULL DEFAULT 1,
              expires_at TEXT,
              created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );
            """
        )
        # 轻量迁移：老库没有的列补上，重复执行不报错。
        for table, column, ddl in [
            ("users", "disabled_at", "ALTER TABLE users ADD COLUMN disabled_at TEXT"),
        ]:
            cols = {row[1] for row in conn.execute(f"PRAGMA table_info({table})").fetchall()}
            if column not in cols:
                conn.execute(ddl)
        defaults = {
            "public_base_url": PUBLIC_BASE_URL,
            "maintenance": "0",
            "global_enabled": "1",
            "show_redeem_entry": "1",
            "free_ai_count": "5",
            "pro_ai_count": "9999",
            "support_email": "support@uosar.yosar.cloud",
            "support_douyin": "PRIME",
            "support_xiaohongshu": "PRIME",
            "persona_name": "流小萤",
            "persona_role": "构图导演",
            "ai_prompt": "你是流小萤，PRIME 的构图导演。先看主体和场景，再给一句能立即执行的动作口令，不要泛泛而谈。",
            "watermark_styles": "minimal,white,film,magazine",
            "app_version": "0.4.5",
            "download_url": "",
            "announcement": "",
            "filter_catalog": "",
        }
        stamp = now_iso()
        for key, value in defaults.items():
            conn.execute(
                "INSERT OR IGNORE INTO settings(key,value,updated_at) VALUES(?,?,?)",
                (key, value, stamp),
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
    if row is None or row["deleted_at"] or row["disabled_at"]:
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


def log_event(kind: str, payload: dict) -> None:
    with _conn() as conn:
        conn.execute(
            "INSERT INTO events(kind,payload,created_at) VALUES(?,?,?)",
            (kind, json.dumps(payload, ensure_ascii=False), now_iso()),
        )


def make_admin_token(name: str = "") -> str:
    payload = _b64(json.dumps({"role": "admin", "name": name or ADMIN_USER, "ts": int(time.time())}, separators=(",", ":")).encode())
    sig = _b64(hmac.new(SECRET.encode(), payload.encode(), hashlib.sha256).digest())
    return f"{payload}.{sig}"


def parse_admin_token(token: str) -> dict | None:
    try:
        payload, sig = token.split(".", 1)
        expected = _b64(hmac.new(SECRET.encode(), payload.encode(), hashlib.sha256).digest())
        if not hmac.compare_digest(sig, expected):
            return None
        data = json.loads(_unb64(payload))
        if data.get("role") != "admin":
            return None
        # 管理 token 最长 7 天，避免浏览器 localStorage 里的旧 token 永久有效。
        if time.time() - float(data.get("ts") or 0) > 7 * 86400:
            return None
        return data
    except Exception:
        return None


def admin_by_token(token: str | None) -> dict | None:
    if not token:
        return None
    return parse_admin_token(token.replace("Bearer ", "").strip())


def get_setting(key: str, default: str | None = None) -> str | None:
    with _conn() as conn:
        row = conn.execute("SELECT value FROM settings WHERE key=?", (key,)).fetchone()
    return row["value"] if row else default


def set_setting(key: str, value: str) -> None:
    with _conn() as conn:
        conn.execute(
            "INSERT OR REPLACE INTO settings(key,value,updated_at) VALUES(?,?,?)",
            (key, str(value), now_iso()),
        )


def all_settings() -> dict[str, str]:
    with _conn() as conn:
        rows = conn.execute("SELECT key,value FROM settings").fetchall()
    return {row["key"]: row["value"] for row in rows}


def list_users(q: str = "", limit: int = 50, offset: int = 0) -> list[dict]:
    limit = max(1, min(limit, 200))
    with _conn() as conn:
        if q:
            rows = conn.execute(
                "SELECT id,phone,username,vip_expire_at,created_at,deleted_at,disabled_at FROM users "
                "WHERE phone LIKE ? OR username LIKE ? ORDER BY created_at DESC LIMIT ? OFFSET ?",
                (f"%{q}%", f"%{q}%", limit, offset),
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT id,phone,username,vip_expire_at,created_at,deleted_at,disabled_at FROM users "
                "ORDER BY created_at DESC LIMIT ? OFFSET ?",
                (limit, offset),
            ).fetchall()
    return [dict(row) for row in rows]


def count_users(q: str = "") -> int:
    with _conn() as conn:
        if q:
            row = conn.execute(
                "SELECT COUNT(*) AS n FROM users WHERE phone LIKE ? OR username LIKE ?",
                (f"%{q}%", f"%{q}%"),
            ).fetchone()
        else:
            row = conn.execute("SELECT COUNT(*) AS n FROM users").fetchone()
    return int(row["n"])


def set_user_flags(user_id: str, disabled: bool | None = None, restore_vip_days: int = 0) -> bool:
    with _conn() as conn:
        row = conn.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()
        if not row:
            return False
        if disabled is not None:
            conn.execute("UPDATE users SET disabled_at=? WHERE id=?", (now_iso() if disabled else None, user_id))
    if restore_vip_days:
        set_vip(user_id, restore_vip_days)
    return True


def soft_delete_user(user_id: str) -> bool:
    with _conn() as conn:
        row = conn.execute("SELECT id FROM users WHERE id=?", (user_id,)).fetchone()
        if not row:
            return False
        conn.execute("UPDATE users SET deleted_at=? WHERE id=?", (now_iso(), user_id))
    return True


def list_orders(status: str = "", limit: int = 50, offset: int = 0) -> list[dict]:
    limit = max(1, min(limit, 200))
    with _conn() as conn:
        if status:
            rows = conn.execute(
                "SELECT o.*, u.phone, u.username FROM orders o LEFT JOIN users u ON u.id=o.user_id "
                "WHERE o.status=? ORDER BY o.created_at DESC LIMIT ? OFFSET ?",
                (status, limit, offset),
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT o.*, u.phone, u.username FROM orders o LEFT JOIN users u ON u.id=o.user_id "
                "ORDER BY o.created_at DESC LIMIT ? OFFSET ?",
                (limit, offset),
            ).fetchall()
    return [dict(row) for row in rows]


def mark_order_refunded(out_trade_no: str) -> bool:
    with _conn() as conn:
        row = conn.execute("SELECT * FROM orders WHERE out_trade_no=?", (out_trade_no,)).fetchone()
        if not row:
            return False
        conn.execute("UPDATE orders SET status='refunded' WHERE out_trade_no=?", (out_trade_no,))
    return True


def create_redeem_codes(days: int, count: int = 10, max_uses: int = 1, expires_days: int = 365) -> list[dict]:
    import secrets
    import string

    days = max(1, min(days, 3650))
    count = max(1, min(count, 200))
    max_uses = max(1, min(max_uses, 1000))
    alphabet = string.ascii_uppercase + string.digits
    created: list[dict] = []
    expires = (datetime.now(timezone.utc) + timedelta(days=max(1, expires_days))).isoformat()
    with _conn() as conn:
        for _ in range(count):
            code = "PRIME-" + "".join(secrets.choice(alphabet) for _ in range(8))
            conn.execute(
                "INSERT INTO redeem_codes(code,days,max_uses,used_count,active,expires_at,created_at) VALUES(?,?,?,0,1,?,?)",
                (code, days, max_uses, expires, now_iso()),
            )
            created.append({"code": code, "days": days, "max_uses": max_uses, "expires_at": expires})
    return created


def list_redeem_codes(limit: int = 100) -> list[dict]:
    with _conn() as conn:
        rows = conn.execute(
            "SELECT code,days,max_uses,used_count,active,expires_at,created_at FROM redeem_codes "
            "ORDER BY created_at DESC LIMIT ?",
            (max(1, min(limit, 500)),),
        ).fetchall()
    return [dict(row) for row in rows]


def disable_redeem_code(code: str) -> bool:
    with _conn() as conn:
        row = conn.execute("SELECT code FROM redeem_codes WHERE code=?", (code.upper(),)).fetchone()
        if not row:
            return False
        conn.execute("UPDATE redeem_codes SET active=0 WHERE code=?", (code.upper(),))
    return True


def overview() -> dict:
    today = datetime.now(timezone.utc).date().isoformat()
    now = now_iso()
    with _conn() as conn:
        users = conn.execute("SELECT COUNT(*) AS n FROM users WHERE deleted_at IS NULL").fetchone()["n"]
        new_users = conn.execute("SELECT COUNT(*) AS n FROM users WHERE created_at LIKE ?", (today + "%",)).fetchone()["n"]
        pro_users = conn.execute("SELECT COUNT(*) AS n FROM users WHERE vip_expire_at > ?", (now,)).fetchone()["n"]
        orders_today = conn.execute("SELECT COUNT(*) AS n FROM orders WHERE created_at LIKE ?", (today + "%",)).fetchone()["n"]
        paid = conn.execute(
            "SELECT COUNT(*) AS n, COALESCE(SUM(amount),0) AS amount FROM orders WHERE status='paid' AND paid_at LIKE ?",
            (today + "%",),
        ).fetchone()
        scans = conn.execute("SELECT COUNT(*) AS n FROM events WHERE kind='scan' AND created_at LIKE ?", (today + "%",)).fetchone()["n"]
        redeems = conn.execute("SELECT COUNT(*) AS n FROM events WHERE kind='redeem' AND created_at LIKE ?", (today + "%",)).fetchone()["n"]
    return {
        "users": int(users),
        "new_users_today": int(new_users),
        "pro_users": int(pro_users),
        "orders_today": int(orders_today),
        "paid_orders_today": int(paid["n"]),
        "revenue_today": float(paid["amount"]),
        "scan_today": int(scans),
        "redeem_today": int(redeems),
    }


def overview_for_day(day: str) -> dict:
    with _conn() as conn:
        new_users = conn.execute("SELECT COUNT(*) AS n FROM users WHERE created_at LIKE ?", (day + "%",)).fetchone()["n"]
        orders = conn.execute("SELECT COUNT(*) AS n FROM orders WHERE created_at LIKE ?", (day + "%",)).fetchone()["n"]
        paid = conn.execute(
            "SELECT COUNT(*) AS n, COALESCE(SUM(amount),0) AS amount FROM orders WHERE status='paid' AND paid_at LIKE ?",
            (day + "%",),
        ).fetchone()
        scans = conn.execute("SELECT COUNT(*) AS n FROM events WHERE kind='scan' AND created_at LIKE ?", (day + "%",)).fetchone()["n"]
    return {
        "new_users": int(new_users),
        "orders": int(orders),
        "paid_orders": int(paid["n"]),
        "revenue": float(paid["amount"]),
        "scans": int(scans),
    }


def recent_events(kind: str = "", limit: int = 100) -> list[dict]:
    with _conn() as conn:
        if kind:
            rows = conn.execute(
                "SELECT id,kind,payload,created_at FROM events WHERE kind=? ORDER BY id DESC LIMIT ?",
                (kind, max(1, min(limit, 500))),
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT id,kind,payload,created_at FROM events ORDER BY id DESC LIMIT ?",
                (max(1, min(limit, 500)),),
            ).fetchall()
    out = []
    for row in rows:
        item = dict(row)
        try:
            item["payload"] = json.loads(item["payload"])
        except Exception:
            pass
        out.append(item)
    return out


def redeem(user_id: str, code: str) -> tuple[bool, str]:
    raw = code.strip().upper()
    with _conn() as conn:
        row = conn.execute("SELECT * FROM redeem_codes WHERE code=?", (raw,)).fetchone()
    if row:
        if not row["active"]:
            return False, "兑换码已停用"
        if row["expires_at"]:
            try:
                if datetime.fromisoformat(row["expires_at"]) <= datetime.now(timezone.utc):
                    return False, "兑换码已过期"
            except Exception:
                pass
        if row["used_count"] >= row["max_uses"]:
            return False, "兑换码已被使用完"
        with _conn() as conn:
            conn.execute("UPDATE redeem_codes SET used_count=used_count+1 WHERE code=?", (raw,))
        set_vip(user_id, int(row["days"]))
        log_event("redeem", {"code": raw, "days": int(row["days"]), "user_id": user_id})
        return True, "兑换成功"
    valid = {"PRIME2026": 30, "PRIME-LIFETIME": 3650, "PRIME-30": 30}
    days = valid.get(raw)
    if not days:
        return False, "兑换码无效或已过期"
    set_vip(user_id, days)
    log_event("redeem", {"code": raw, "days": days, "user_id": user_id})
    return True, "兑换成功"


init_db()
