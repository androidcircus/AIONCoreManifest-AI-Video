#!/usr/bin/env bash
# =============================================================================
# Manifest AI - AION CORE FOUND
# Packaging script: static frontend + FastAPI backend
# =============================================================================
set -Eeuo pipefail

API_BASE="http://localhost:8000"
AGENT_URL=""
OUT_DIR="$(pwd)/build"
MAKE_ZIP=1

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --api-base)  API_BASE="${2:?--api-base needs a value}"; shift 2 ;;
    --agent-url) AGENT_URL="${2:?--agent-url needs a value}"; shift 2 ;;
    --out-dir)   OUT_DIR="${2:?--out-dir needs a value}"; shift 2 ;;
    --no-zip)    MAKE_ZIP=0; shift ;;
    -h|--help)   usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done

[[ -n "$AGENT_URL" ]] || AGENT_URL="${API_BASE%/}/agent"

for cmd in sed; do
  command -v "$cmd" >/dev/null || { echo "Missing required command: $cmd" >&2; exit 1; }
done
if [[ $MAKE_ZIP -eq 1 ]] && ! command -v zip >/dev/null; then
  echo "zip not found - continuing with --no-zip behaviour" >&2
  MAKE_ZIP=0
fi

OUT_DIR="$(mkdir -p "$OUT_DIR" && cd "$OUT_DIR" && pwd)"
FRONTEND_DIR="$OUT_DIR/manifest-frontend"
BACKEND_DIR="$OUT_DIR/manifest-backend"

case "$OUT_DIR" in
  "$HOME"|/|/home|/usr|/etc|/var) echo "Refusing to build into $OUT_DIR" >&2; exit 1 ;;
esac

rm -rf "$FRONTEND_DIR" "$BACKEND_DIR" "$FRONTEND_DIR.zip" "$BACKEND_DIR.zip"
mkdir -p "$FRONTEND_DIR/assets" "$BACKEND_DIR/agents"

echo "==> Building into $OUT_DIR"
echo "    API_BASE  = $API_BASE"
echo "    AGENT_URL = $AGENT_URL"

# =============================================================================
#                              FRONTEND (static)
# =============================================================================

cat > "$FRONTEND_DIR/config.js" << 'JS'
window.MANIFEST_CONFIG = {
  API_BASE: "__API_BASE__",
  AGENT_URL: "__AGENT_URL__"
};
JS

cat > "$FRONTEND_DIR/styles.css" << 'CSS'
:root {
  --bg: #0d1117; --surface: #161b22; --border: #30363d;
  --text: #c9d1d9; --muted: #8b949e; --accent: #58a6ff;
  --ok: #238636; --ok-hover: #2ea043; --err: #f85149; --warn: #d29922;
}
* { box-sizing: border-box; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Arial, sans-serif;
  background: var(--bg); color: var(--text); margin: 0; line-height: 1.5;
}
header {
  background: var(--surface); padding: 20px; text-align: center;
  border-bottom: 1px solid var(--border);
}
h1 { margin: 0; color: var(--accent); font-size: 1.5rem; }
.container { max-width: 1200px; margin: auto; padding: 20px; }
.card {
  background: var(--surface); border: 1px solid var(--border);
  border-radius: 8px; padding: 20px; margin-bottom: 20px;
}
.card h2 { margin-top: 0; font-size: 1.15rem; }
label { display: block; font-size: .85rem; color: var(--muted); margin-bottom: 4px; }
button {
  background: var(--ok); color: #fff; border: none; padding: 9px 16px;
  border-radius: 6px; cursor: pointer; font-size: .95rem;
}
button:hover:not(:disabled) { background: var(--ok-hover); }
button:disabled { opacity: .55; cursor: not-allowed; }
button.secondary { background: transparent; border: 1px solid var(--border); color: var(--text); }
input, textarea {
  background: var(--bg); border: 1px solid var(--border); padding: 9px;
  border-radius: 6px; color: var(--text); width: 100%; margin: 0 0 14px;
  font-family: inherit; font-size: .95rem;
}
textarea { min-height: 90px; resize: vertical; }
.row { display: flex; gap: 16px; flex-wrap: wrap; }
.row > * { flex: 1 1 220px; }
.status { font-size: .9rem; min-height: 1.2em; margin: 8px 0 0; }
.status.error { color: var(--err); }
.status.ok { color: var(--accent); }
.status.warn { color: var(--warn); }
.badge {
  display: inline-block; padding: 2px 10px; border-radius: 999px;
  border: 1px solid var(--border); font-size: .8rem; color: var(--muted);
}
.progress { height: 6px; background: var(--bg); border-radius: 999px; overflow: hidden; margin: 10px 0; }
.progress > div { height: 100%; width: 0; background: var(--accent); transition: width .4s; }
.agent-link {
  position: fixed; bottom: 20px; right: 20px; background: var(--ok); color: #fff;
  padding: 12px 20px; border-radius: 999px; text-decoration: none; z-index: 1000;
}
.hidden { display: none !important; }
iframe { border: 1px solid var(--border); border-radius: 8px; width: 100%; height: 600px; }
table { width: 100%; border-collapse: collapse; font-size: .9rem; }
th, td { text-align: left; padding: 8px; border-bottom: 1px solid var(--border); }
th { color: var(--muted); font-weight: 600; }
video { max-width: 100%; border-radius: 8px; }
CSS

cat > "$FRONTEND_DIR/index.html" << 'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>Manifest AI - AION CORE FOUND</title>
  <link rel="stylesheet" href="styles.css"/>
</head>
<body>
  <header><h1>Manifest AI - AION CORE FOUND</h1></header>

  <div class="container">
    <!-- Account -->
    <section id="auth-card" class="card">
      <h2>Account</h2>
      <div id="auth-forms">
        <div class="row">
          <form id="register-form" autocomplete="on">
            <h3>Register</h3>
            <label for="reg-email">Email</label>
            <input type="email" id="reg-email" autocomplete="email" required>
            <label for="reg-password">Password (min 10 characters)</label>
            <input type="password" id="reg-password" autocomplete="new-password" minlength="10" required>
            <button type="submit">Register</button>
          </form>
          <form id="login-form" autocomplete="on">
            <h3>Login</h3>
            <label for="login-email">Email</label>
            <input type="email" id="login-email" autocomplete="email" required>
            <label for="login-password">Password</label>
            <input type="password" id="login-password" autocomplete="current-password" required>
            <button type="submit">Login</button>
          </form>
        </div>
        <p id="auth-status" class="status" role="status" aria-live="polite"></p>
      </div>
      <div id="user-info" class="hidden">
        <p>Signed in as <strong id="user-email"></strong>
           <span class="badge" id="user-credits">- credits</span></p>
        <button class="secondary" id="logout-btn" type="button">Log out</button>
      </div>
    </section>

    <!-- Video generation -->
    <section class="card">
      <h2>Generate Video</h2>
      <label for="idea">Describe your story</label>
      <textarea id="idea" maxlength="2000" placeholder="A lone lighthouse keeper watches a storm roll in..."></textarea>
      <div class="row">
        <div>
          <label for="duration">Length (minutes)</label>
          <input type="number" id="duration" value="2" min="1" max="10">
        </div>
        <div>
          <label for="style">Style</label>
          <input type="text" id="style" value="cinematic">
        </div>
      </div>
      <p class="status" id="cost-hint"></p>
      <button id="generate-btn" type="button">Generate Video</button>
      <div class="progress hidden" id="job-progress"><div></div></div>
      <p id="video-status" class="status" role="status" aria-live="polite"></p>
      <div id="video-result"></div>
    </section>

    <!-- Agent Command Center -->
    <section class="card">
      <h2>Agent Command Center</h2>
      <p><button class="secondary" type="button" id="toggle-agent">Open Agent Dashboard</button></p>
      <iframe id="agent-iframe" class="hidden" title="Agent Command Center" loading="lazy"></iframe>
    </section>

    <!-- Admin -->
    <section class="card hidden" id="admin-card">
      <h2>Admin</h2>
      <p id="admin-summary" class="status"></p>
      <table>
        <thead><tr><th>Email</th><th>Credits</th><th>Jobs</th><th>Joined</th></tr></thead>
        <tbody id="admin-users"></tbody>
      </table>
    </section>
  </div>

  <a href="#" class="agent-link" id="agent-fab">Agent Command Center</a>

  <script src="config.js"></script>
  <script src="app.js"></script>
</body>
</html>
HTML

cat > "$FRONTEND_DIR/app.js" << 'JS'
"use strict";
(function () {
  const CFG = window.MANIFEST_CONFIG || {};
  const API_BASE = String(CFG.API_BASE || "").replace(/\/+$/, "");
  const AGENT_URL = CFG.AGENT_URL || "";

  const $ = (id) => document.getElementById(id);
  const setStatus = (el, msg, kind) => {
    el.textContent = msg || "";
    el.className = "status" + (kind ? " " + kind : "");
  };

  const TOKEN_KEY = "manifest_token";
  let token = localStorage.getItem(TOKEN_KEY);

  function tokenPayload(t) {
    try {
      const part = t.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
      return JSON.parse(atob(part));
    } catch (_) { return null; }
  }
  function tokenValid(t) {
    const p = t && tokenPayload(t);
    return !!(p && p.exp && p.exp * 1000 > Date.now());
  }
  function clearToken() {
    token = null;
    localStorage.removeItem(TOKEN_KEY);
  }

  async function api(path, { method = "GET", body, form, auth = true } = {}) {
    const headers = {};
    if (auth) {
      if (!tokenValid(token)) { clearToken(); showLoggedOut(); throw new Error("Session expired - please log in again."); }
      headers.Authorization = "Bearer " + token;
    }
    let payload;
    if (form) { payload = form; }
    else if (body !== undefined) { headers["Content-Type"] = "application/json"; payload = JSON.stringify(body); }

    let res;
    try {
      res = await fetch(API_BASE + path, { method, headers, body: payload });
    } catch (_) {
      throw new Error("Cannot reach the API. Check your connection or API_BASE.");
    }
    if (res.status === 401) { clearToken(); showLoggedOut(); throw new Error("Session expired - please log in again."); }
    const text = await res.text();
    const data = text ? JSON.parse(text) : {};
    if (!res.ok) throw new Error(data.detail || data.message || ("Request failed (" + res.status + ")"));
    return data;
  }

  function showLoggedIn(profile) {
    $("user-email").textContent = profile.email;
    $("user-credits").textContent = profile.credits_balance + " credits";
    $("auth-forms").classList.add("hidden");
    $("user-info").classList.remove("hidden");
    $("admin-card").classList.toggle("hidden", !profile.is_admin);
    if (profile.is_admin) loadAdmin();
  }
  function showLoggedOut() {
    $("auth-forms").classList.remove("hidden");
    $("user-info").classList.add("hidden");
    $("admin-card").classList.add("hidden");
  }

  async function refreshProfile() {
    const me = await api("/api/me");
    showLoggedIn(me);
    return me;
  }

  $("register-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    const btn = e.target.querySelector("button");
    btn.disabled = true;
    try {
      await api("/api/auth/register", {
        method: "POST", auth: false,
        body: { email: $("reg-email").value, password: $("reg-password").value }
      });
      setStatus($("auth-status"), "Registered. You can log in now.", "ok");
    } catch (err) {
      setStatus($("auth-status"), err.message, "error");
    } finally { btn.disabled = false; }
  });

  $("login-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    const btn = e.target.querySelector("button");
    btn.disabled = true;
    try {
      const fd = new FormData();
      fd.append("username", $("login-email").value);
      fd.append("password", $("login-password").value);
      const data = await api("/api/auth/login", { method: "POST", auth: false, form: fd });
      token = data.access_token;
      localStorage.setItem(TOKEN_KEY, token);
      setStatus($("auth-status"), "", "");
      await refreshProfile();
    } catch (err) {
      setStatus($("auth-status"), err.message, "error");
    } finally { btn.disabled = false; }
  });

  $("logout-btn").addEventListener("click", () => { clearToken(); showLoggedOut(); });

  function updateCost() {
    const mins = Math.max(1, parseInt($("duration").value, 10) || 1);
    const style = ($("style").value || "").trim().toLowerCase();
    const mult = style === "cinematic" ? 1.5 : style === "anime" ? 1.25 : 1;
    setStatus($("cost-hint"), "Estimated cost: " + Math.ceil(mins * 10 * mult) + " credits");
  }
  $("duration").addEventListener("input", updateCost);
  $("style").addEventListener("input", updateCost);
  updateCost();

  let pollTimer = null;
  const POLL_MS = 3000;
  const POLL_TIMEOUT_MS = 30 * 60 * 1000;

  function stopPolling() {
    if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
  }

  $("generate-btn").addEventListener("click", async () => {
    const idea = $("idea").value.trim();
    if (!idea) { setStatus($("video-status"), "Describe your story first.", "warn"); return; }
    const btn = $("generate-btn");
    btn.disabled = true;
    stopPolling();
    $("video-result").innerHTML = "";
    try {
      const job = await api("/api/video/generate", {
        method: "POST",
        body: {
          idea,
          estimated_minutes: parseInt($("duration").value, 10) || 1,
          style: $("style").value || "cinematic"
        }
      });
      setStatus($("video-status"), "Job queued (" + job.job_id + ")", "ok");
      $("job-progress").classList.remove("hidden");
      await refreshProfile();
      pollJob(job.job_id);
    } catch (err) {
      setStatus($("video-status"), err.message, "error");
      btn.disabled = false;
    }
  });

  function pollJob(jobId) {
    const started = Date.now();
    const tick = async () => {
      if (Date.now() - started > POLL_TIMEOUT_MS) {
        stopPolling();
        setStatus($("video-status"), "Stopped watching this job after 30 minutes. Reload to check again.", "warn");
        $("generate-btn").disabled = false;
        return;
      }
      try {
        const s = await api("/api/video/status/" + encodeURIComponent(jobId));
        $("job-progress").querySelector("div").style.width = (s.progress || 0) + "%";
        if (s.status === "completed") {
          stopPolling();
          setStatus($("video-status"), "Video ready.", "ok");
          const url = API_BASE + "/api/video/download/" + encodeURIComponent(jobId);
          const v = document.createElement("video");
          v.controls = true; v.src = url;
          const a = document.createElement("a");
          a.href = url; a.textContent = "Download"; a.download = "";
          $("video-result").append(v, document.createElement("br"), a);
          $("generate-btn").disabled = false;
          refreshProfile().catch(() => {});
        } else if (s.status === "failed") {
          stopPolling();
          setStatus($("video-status"), "Generation failed: " + (s.error || "unknown error") + ". Credits refunded.", "error");
          $("generate-btn").disabled = false;
          refreshProfile().catch(() => {});
        } else {
          setStatus($("video-status"), "Status: " + s.status + " (" + (s.progress || 0) + "%)", "");
        }
      } catch (err) {
        stopPolling();
        setStatus($("video-status"), err.message, "error");
        $("generate-btn").disabled = false;
      }
    };
    pollTimer = setInterval(tick, POLL_MS);
    tick();
  }

  function toggleAgent(e) {
    if (e) e.preventDefault();
    const frame = $("agent-iframe");
    const opening = frame.classList.contains("hidden");
    if (opening && !frame.src) frame.src = AGENT_URL;
    frame.classList.toggle("hidden");
  }
  $("toggle-agent").addEventListener("click", toggleAgent);
  $("agent-fab").addEventListener("click", toggleAgent);

  async function loadAdmin() {
    try {
      const data = await api("/api/admin/overview");
      setStatus($("admin-summary"),
        data.total_users + " users - " + data.total_jobs + " jobs - " +
        data.jobs_running + " running - " + data.credits_outstanding + " credits outstanding");
      const tbody = $("admin-users");
      tbody.textContent = "";
      data.users.forEach((u) => {
        const tr = document.createElement("tr");
        [u.email, u.credits_balance, u.job_count, (u.created_at || "").slice(0, 10)]
          .forEach((val) => {
            const td = document.createElement("td");
            td.textContent = val;
            tr.appendChild(td);
          });
        tbody.appendChild(tr);
      });
    } catch (err) {
      setStatus($("admin-summary"), err.message, "error");
    }
  }

  if (tokenValid(token)) {
    refreshProfile().catch(() => { clearToken(); showLoggedOut(); });
  } else {
    clearToken();
    showLoggedOut();
  }
})();
JS

touch "$FRONTEND_DIR/assets/.gitkeep"

esc() { printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'; }
sed -i.bak \
  -e "s/__API_BASE__/$(esc "$API_BASE")/g" \
  -e "s/__AGENT_URL__/$(esc "$AGENT_URL")/g" \
  "$FRONTEND_DIR/config.js"
rm -f "$FRONTEND_DIR/config.js.bak"

grep -q "__API_BASE__\|__AGENT_URL__" "$FRONTEND_DIR/config.js" && {
  echo "Placeholder substitution failed" >&2; exit 1; }

# =============================================================================
#                              BACKEND (FastAPI)
# =============================================================================

cat > "$BACKEND_DIR/requirements.txt" << 'EOF'
fastapi==0.115.6
uvicorn[standard]==0.34.0
python-dotenv==1.0.1
pydantic[email]==2.10.4
bcrypt==4.2.1
PyJWT==2.10.1
python-multipart==0.0.20
SQLAlchemy==2.0.36
psycopg[binary]==3.2.3
httpx==0.28.1
EOF

cat > "$BACKEND_DIR/.env.example" << 'EOF'
SECRET_KEY=
ACCESS_TOKEN_EXPIRE_MINUTES=60
ALLOWED_ORIGINS=http://localhost:5173
DATABASE_URL=sqlite:///./manifest.db
ADMIN_EMAILS=
STORAGE_DIR=./storage
SIGNUP_BONUS_CREDITS=100
VIDEO_PROVIDER=stub
REPLICATE_API_TOKEN=
REPLICATE_MODEL_VERSION=
PAYPAL_ENV=sandbox
PAYPAL_CLIENT_ID=
PAYPAL_CLIENT_SECRET=
PAYPAL_WEBHOOK_ID=
CREDITS_PER_USD=100
EOF

cat > "$BACKEND_DIR/.gitignore" << 'EOF'
__pycache__/
*.py[cod]
.env
*.db
storage/
.venv/
EOF

cat > "$BACKEND_DIR/config.py" << 'PY'
"""Central config. Fails closed on missing secrets instead of shipping a default."""
import os
from functools import lru_cache
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

BASE_DIR = Path(__file__).resolve().parent


def _require(name: str) -> str:
    val = os.getenv(name, "").strip()
    if not val:
        raise RuntimeError(
            f"{name} is not set. Copy .env.example to .env and fill it in. "
            "The application refuses to start with a default secret."
        )
    return val


def _csv(name: str) -> list[str]:
    return [p.strip() for p in os.getenv(name, "").split(",") if p.strip()]


class Settings:
    def __init__(self) -> None:
        self.secret_key = _require("SECRET_KEY")
        if len(self.secret_key) < 32:
            raise RuntimeError("SECRET_KEY must be at least 32 characters.")
        self.algorithm = "HS256"
        self.access_token_expire_minutes = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "60"))
        self.allowed_origins = _csv("ALLOWED_ORIGINS") or ["http://localhost:5173"]
        self.database_url = os.getenv("DATABASE_URL", "sqlite:///./manifest.db")
        self.admin_emails = {e.lower() for e in _csv("ADMIN_EMAILS")}
        self.storage_dir = Path(os.getenv("STORAGE_DIR", BASE_DIR / "storage")).resolve()
        self.signup_bonus_credits = int(os.getenv("SIGNUP_BONUS_CREDITS", "100"))
        self.video_provider = os.getenv("VIDEO_PROVIDER", "stub").lower()
        self.replicate_token = os.getenv("REPLICATE_API_TOKEN", "")
        self.replicate_model_version = os.getenv("REPLICATE_MODEL_VERSION", "")
        self.paypal_env = os.getenv("PAYPAL_ENV", "sandbox").lower()
        self.paypal_client_id = os.getenv("PAYPAL_CLIENT_ID", "")
        self.paypal_client_secret = os.getenv("PAYPAL_CLIENT_SECRET", "")
        self.paypal_webhook_id = os.getenv("PAYPAL_WEBHOOK_ID", "")
        self.credits_per_usd = int(os.getenv("CREDITS_PER_USD", "100"))
        self.storage_dir.mkdir(parents=True, exist_ok=True)

    @property
    def paypal_api_base(self) -> str:
        return (
            "https://api-m.paypal.com"
            if self.paypal_env == "live"
            else "https://api-m.sandbox.paypal.com"
        )

    @property
    def billing_enabled(self) -> bool:
        return bool(self.paypal_client_id and self.paypal_client_secret)


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
PY

cat > "$BACKEND_DIR/database.py" << 'PY'
"""SQLAlchemy session plumbing."""
from collections.abc import Iterator

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from config import settings

connect_args = {"check_same_thread": False} if settings.database_url.startswith("sqlite") else {}

engine = create_engine(
    settings.database_url,
    connect_args=connect_args,
    pool_pre_ping=True,
    future=True,
)

SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False, future=True)


class Base(DeclarativeBase):
    pass


def get_db() -> Iterator[Session]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
PY

cat > "$BACKEND_DIR/models.py" << 'PY'
"""ORM models."""
import uuid
from datetime import datetime, timezone

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from database import Base


def _uuid() -> str:
    return str(uuid.uuid4())


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    email: Mapped[str] = mapped_column(String(320), unique=True, index=True, nullable=False)
    hashed_password: Mapped[str] = mapped_column(String(255), nullable=False)
    credits_balance: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    jobs: Mapped[list["VideoJob"]] = relationship(back_populates="user")


class VideoJob(Base):
    __tablename__ = "video_jobs"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True, nullable=False)
    idea: Mapped[str] = mapped_column(Text, nullable=False)
    duration_minutes: Mapped[int] = mapped_column(Integer, default=2)
    style: Mapped[str] = mapped_column(String(64), default="cinematic")
    status: Mapped[str] = mapped_column(String(24), default="queued", index=True)
    progress: Mapped[int] = mapped_column(Integer, default=0)
    credit_cost: Mapped[int] = mapped_column(Integer, default=0)
    error: Mapped[str | None] = mapped_column(Text, nullable=True)
    final_video_path: Mapped[str | None] = mapped_column(String(1024), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)

    user: Mapped[User] = relationship(back_populates="jobs")


class CreditTransaction(Base):
    __tablename__ = "credit_transactions"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True, nullable=False)
    job_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    amount: Mapped[int] = mapped_column(Integer, nullable=False)
    balance_after: Mapped[int] = mapped_column(Integer, nullable=False)
    transaction_type: Mapped[str] = mapped_column(String(32), nullable=False)
    reference: Mapped[str | None] = mapped_column(String(255), nullable=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
PY

cat > "$BACKEND_DIR/utils.py" << 'PY'
"""Pricing and credit ledger helpers."""
import math

from sqlalchemy import select, update
from sqlalchemy.orm import Session

from models import CreditTransaction, User

BASE_CREDITS_PER_MINUTE = 10
STYLE_MULTIPLIERS = {"cinematic": 1.5, "anime": 1.25, "documentary": 1.0, "sketch": 1.0}


def calculate_credit_cost(minutes: int, style: str = "cinematic") -> int:
    minutes = max(1, min(int(minutes or 1), 10))
    mult = STYLE_MULTIPLIERS.get((style or "").lower(), 1.0)
    return math.ceil(minutes * BASE_CREDITS_PER_MINUTE * mult)


def _record(db: Session, user_id: str, amount: int, balance_after: int,
            kind: str, job_id: str | None = None, reference: str | None = None) -> None:
    db.add(CreditTransaction(
        user_id=user_id, job_id=job_id, amount=amount,
        balance_after=balance_after, transaction_type=kind, reference=reference,
    ))


def debit_credits(db: Session, user_id: str, cost: int, job_id: str | None = None) -> int | None:
    result = db.execute(
        update(User)
        .where(User.id == user_id, User.credits_balance >= cost)
        .values(credits_balance=User.credits_balance - cost)
    )
    if result.rowcount == 0:
        db.rollback()
        return None
    balance = db.execute(select(User.credits_balance).where(User.id == user_id)).scalar_one()
    _record(db, user_id, -cost, balance, "usage", job_id=job_id)
    db.commit()
    return balance


def credit_credits(db: Session, user_id: str, amount: int, kind: str,
                   job_id: str | None = None, reference: str | None = None) -> int:
    db.execute(
        update(User)
        .where(User.id == user_id)
        .values(credits_balance=User.credits_balance + amount)
    )
    balance = db.execute(select(User.credits_balance).where(User.id == user_id)).scalar_one()
    _record(db, user_id, amount, balance, kind, job_id=job_id, reference=reference)
    db.commit()
    return balance
PY

cat > "$BACKEND_DIR/auth.py" << 'PY'
"""Password hashing, token issuing, and the get_current_user dependency."""
from datetime import datetime, timedelta, timezone

import bcrypt
import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session

from config import settings
from database import get_db
from models import User

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login")

_UNAUTHORIZED = HTTPException(
    status_code=status.HTTP_401_UNAUTHORIZED,
    detail="Could not validate credentials",
    headers={"WWW-Authenticate": "Bearer"},
)


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode()[:72], bcrypt.gensalt()).decode()


def verify_password(password: str, hashed: str) -> bool:
    try:
        return bcrypt.checkpw(password.encode()[:72], hashed.encode())
    except ValueError:
        return False


def create_access_token(user_id: str) -> str:
    now = datetime.now(timezone.utc)
    return jwt.encode(
        {
            "sub": user_id,
            "iat": now,
            "exp": now + timedelta(minutes=settings.access_token_expire_minutes),
        },
        settings.secret_key,
        algorithm=settings.algorithm,
    )


def decode_token(token: str) -> str:
    try:
        payload = jwt.decode(token, settings.secret_key, algorithms=[settings.algorithm])
    except jwt.PyJWTError:
        raise _UNAUTHORIZED
    user_id = payload.get("sub")
    if not user_id:
        raise _UNAUTHORIZED
    return user_id


def user_from_token(token: str, db: Session) -> User:
    user = db.get(User, decode_token(token))
    if user is None:
        raise _UNAUTHORIZED
    return user


def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)) -> User:
    return user_from_token(token, db)


def is_admin(user: User) -> bool:
    return user.email.lower() in settings.admin_emails


def get_current_admin(user: User = Depends(get_current_user)) -> User:
    if not is_admin(user):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Admin access required")
    return user
PY

cat > "$BACKEND_DIR/video.py" << 'PY'
"""Video generation worker."""
import logging
import shutil
import subprocess
from pathlib import Path

import httpx
from sqlalchemy.orm import Session

from config import settings
from database import SessionLocal
from models import VideoJob, utcnow
from utils import credit_credits

log = logging.getLogger("manifest.video")


def _set(db: Session, job: VideoJob, **fields) -> None:
    for key, value in fields.items():
        setattr(job, key, value)
    job.updated_at = utcnow()
    db.commit()


def _output_path(job_id: str) -> Path:
    return settings.storage_dir / f"{job_id}.mp4"


def _render_stub(job: VideoJob, dest: Path) -> None:
    if not shutil.which("ffmpeg"):
        raise RuntimeError("ffmpeg not installed - required by the stub provider")
    seconds = max(2, min(int(job.duration_minutes) * 60, 60))
    caption = (job.idea or "Manifest AI")[:80].replace(":", " ").replace("'", " ")
    subprocess.run(
        [
            "ffmpeg", "-y", "-f", "lavfi",
            "-i", f"color=c=0x0d1117:s=1280x720:d={seconds}",
            "-vf", (
                f"drawtext=text='{caption}':fontcolor=0x58a6ff:fontsize=36:"
                "x=(w-text_w)/2:y=(h-text_h)/2"
            ),
            "-pix_fmt", "yuv420p", str(dest),
        ],
        check=True, capture_output=True, timeout=600,
    )


def _render_replicate(job: VideoJob, dest: Path) -> None:
    if not (settings.replicate_token and settings.replicate_model_version):
        raise RuntimeError("REPLICATE_API_TOKEN and REPLICATE_MODEL_VERSION are required")
    headers = {
        "Authorization": f"Bearer {settings.replicate_token}",
        "Content-Type": "application/json",
        "Prefer": "wait",
    }
    payload = {
        "version": settings.replicate_model_version,
        "input": {"prompt": f"{job.idea}. Style: {job.style}."},
    }
    with httpx.Client(timeout=900) as client:
        res = client.post("https://api.replicate.com/v1/predictions",
                          json=payload, headers=headers)
        res.raise_for_status()
        body = res.json()
        if body.get("status") != "succeeded":
            raise RuntimeError(f"provider returned status={body.get('status')}: {body.get('error')}")
        output = body.get("output")
        url = output[-1] if isinstance(output, list) else output
        if not url:
            raise RuntimeError("provider returned no output URL")
        with client.stream("GET", url) as stream:
            stream.raise_for_status()
            with dest.open("wb") as fh:
                for chunk in stream.iter_bytes():
                    fh.write(chunk)


RENDERERS = {"stub": _render_stub, "replicate": _render_replicate}


def run_job(job_id: str) -> None:
    """Runs in a worker thread via BackgroundTasks. Opens its own session."""
    db = SessionLocal()
    try:
        job = db.get(VideoJob, job_id)
        if job is None or job.status not in ("queued",):
            return
        _set(db, job, status="running", progress=5)
        renderer = RENDERERS.get(settings.video_provider)
        if renderer is None:
            raise RuntimeError(f"unknown VIDEO_PROVIDER: {settings.video_provider}")
        dest = _output_path(job_id)
        _set(db, job, progress=25)
        renderer(job, dest)
        if not dest.exists() or dest.stat().st_size == 0:
            raise RuntimeError("renderer produced no output file")
        _set(db, job, status="completed", progress=100, final_video_path=str(dest), error=None)
        log.info("job %s completed (%s bytes)", job_id, dest.stat().st_size)
    except Exception as exc:  # noqa: BLE001
        log.exception("job %s failed", job_id)
        job = db.get(VideoJob, job_id)
        if job is not None:
            _set(db, job, status="failed", error=str(exc)[:500])
            if job.credit_cost:
                credit_credits(db, job.user_id, job.credit_cost, "refund", job_id=job_id)
    finally:
        db.close()
PY

cat > "$BACKEND_DIR/billing.py" << 'PY'
"""PayPal Orders v2 integration."""
import logging

import httpx
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from auth import get_current_user
from config import settings
from database import get_db
from models import CreditTransaction, User
from utils import credit_credits

log = logging.getLogger("manifest.billing")
router = APIRouter(prefix="/api/billing", tags=["billing"])

PACKAGES = {
    "starter": {"usd": "5.00", "credits": 500},
    "creator": {"usd": "20.00", "credits": 2200},
    "studio": {"usd": "50.00", "credits": 6000},
}


def _require_billing() -> None:
    if not settings.billing_enabled:
        raise HTTPException(503, "Billing is not configured on this deployment")


async def _access_token() -> str:
    async with httpx.AsyncClient(timeout=30) as client:
        res = await client.post(
            f"{settings.paypal_api_base}/v1/oauth2/token",
            auth=(settings.paypal_client_id, settings.paypal_client_secret),
            data={"grant_type": "client_credentials"},
        )
    res.raise_for_status()
    return res.json()["access_token"]


class OrderRequest(BaseModel):
    package: str = Field(pattern="^(starter|creator|studio)$")


@router.get("/packages")
def packages() -> dict:
    return {"enabled": settings.billing_enabled, "packages": PACKAGES}


@router.post("/paypal/order")
async def create_order(req: OrderRequest, user: User = Depends(get_current_user)) -> dict:
    _require_billing()
    pkg = PACKAGES[req.package]
    token = await _access_token()
    async with httpx.AsyncClient(timeout=30) as client:
        res = await client.post(
            f"{settings.paypal_api_base}/v2/checkout/orders",
            headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
            json={
                "intent": "CAPTURE",
                "purchase_units": [{
                    "reference_id": f"{user.id}:{req.package}",
                    "description": f"Manifest AI - {pkg['credits']} credits",
                    "amount": {"currency_code": "USD", "value": pkg["usd"]},
                }],
            },
        )
    if res.status_code >= 300:
        log.error("paypal order failed: %s", res.text)
        raise HTTPException(502, "Could not create PayPal order")
    return {"order_id": res.json()["id"], "credits": pkg["credits"], "usd": pkg["usd"]}


class CaptureRequest(BaseModel):
    order_id: str
    package: str = Field(pattern="^(starter|creator|studio)$")


@router.post("/paypal/capture")
async def capture_order(req: CaptureRequest, user: User = Depends(get_current_user),
                        db: Session = Depends(get_db)) -> dict:
    _require_billing()
    reference = f"paypal:{req.order_id}"
    already = db.execute(
        select(CreditTransaction.id).where(CreditTransaction.reference == reference)
    ).first()
    if already:
        return {"status": "already_captured", "credits_balance": user.credits_balance}

    token = await _access_token()
    async with httpx.AsyncClient(timeout=30) as client:
        res = await client.post(
            f"{settings.paypal_api_base}/v2/checkout/orders/{req.order_id}/capture",
            headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        )
    body = res.json() if res.content else {}
    if res.status_code >= 300 or body.get("status") != "COMPLETED":
        log.error("paypal capture failed: %s %s", res.status_code, res.text)
        raise HTTPException(402, "Payment was not completed")

    paid = body["purchase_units"][0]["payments"]["captures"][0]["amount"]["value"]
    expected = PACKAGES[req.package]["usd"]
    if paid != expected:
        log.error("amount mismatch: paid=%s expected=%s", paid, expected)
        raise HTTPException(400, "Payment amount mismatch")

    credits = PACKAGES[req.package]["credits"]
    balance = credit_credits(db, user.id, credits, "purchase", reference=reference)
    return {"status": "completed", "credits_added": credits, "credits_balance": balance}
PY

cat > "$BACKEND_DIR/agents/__init__.py" << 'PY'
PY

cat > "$BACKEND_DIR/agents/orchestrator.py" << 'PY'
"""Agent orchestrator."""
import asyncio
import uuid
from datetime import datetime, timezone

from agents.craft_agent import CraftAgent
from agents.spatial_composer import SpatialComposer

AGENTS = ("orchestrator", "craft", "spatial", "synthesizer")


class AgentOrchestrator:
    def __init__(self) -> None:
        self._tasks: dict[str, dict] = {}
        self._handles: set[asyncio.Task] = set()
        self._craft = CraftAgent()
        self._spatial = SpatialComposer()

    async def start_task(self, description: str) -> str:
        task_id = str(uuid.uuid4())
        self._tasks[task_id] = {
            "id": task_id, "description": description, "status": "running",
            "progress": 0, "result": None,
            "started_at": datetime.now(timezone.utc).isoformat(),
        }
        handle = asyncio.create_task(self._run(task_id, description))
        self._handles.add(handle)
        handle.add_done_callback(self._handles.discard)
        return task_id

    async def _run(self, task_id: str, description: str) -> None:
        record = self._tasks[task_id]
        try:
            plan = self._craft.plan(description)
            record["progress"] = 50
            await asyncio.sleep(0)
            record["result"] = {
                "spec": plan,
                "scene_graph": self._spatial.compose_scene(description),
            }
            record["status"] = "completed"
            record["progress"] = 100
        except Exception as exc:  # noqa: BLE001
            record["status"] = "failed"
            record["error"] = str(exc)

    async def get_task_result(self, task_id: str) -> dict | None:
        return self._tasks.get(task_id)

    def get_agent_status(self) -> dict:
        running = sum(1 for t in self._tasks.values() if t["status"] == "running")
        return {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "agents": [{"name": name, "state": "busy" if running else "idle"} for name in AGENTS],
            "tasks_running": running,
            "tasks_total": len(self._tasks),
        }
PY

cat > "$BACKEND_DIR/agents/craft_agent.py" << 'PY'
"""Turns a free-text target into a structured VM/build spec."""
import re


class CraftAgent:
    def plan(self, description: str) -> dict:
        text = (description or "").strip()
        tokens = [t for t in re.split(r"[^a-z0-9]+", text.lower()) if t]
        heavy = any(t in tokens for t in ("gpu", "render", "train", "video", "4k"))
        return {
            "target": text[:500],
            "steps": [
                {"id": 1, "action": "analyse_requirements"},
                {"id": 2, "action": "select_base_image"},
                {"id": 3, "action": "provision_resources"},
                {"id": 4, "action": "verify"},
            ],
            "resources": {
                "vcpu": 8 if heavy else 2,
                "memory_gb": 32 if heavy else 4,
                "gpu": "a10g" if heavy else None,
            },
            "keywords": tokens[:20],
        }
PY

cat > "$BACKEND_DIR/agents/spatial_composer.py" << 'PY'
"""Builds a simple scene graph from a scene description."""
import re

_KNOWN = ("lighthouse", "forest", "city", "ocean", "desert", "room",
          "mountain", "street", "ship", "temple")


class SpatialComposer:
    def compose_scene(self, description: str) -> dict:
        text = (description or "").lower()
        found = [w for w in _KNOWN if w in text] or ["ground_plane"]
        nodes = [
            {
                "id": f"node_{i}",
                "type": name,
                "transform": {"position": [i * 4.0, 0.0, 0.0], "rotation": [0, 0, 0], "scale": 1.0},
            }
            for i, name in enumerate(found)
        ]
        night = bool(re.search(r"night|dark|storm|moon", text))
        return {
            "nodes": nodes,
            "camera": {"position": [0, 1.7, 8], "look_at": [0, 1, 0], "fov": 45},
            "lighting": {"preset": "night" if night else "daylight",
                         "intensity": 0.35 if night else 1.0},
        }
PY

cat > "$BACKEND_DIR/vm_synthesizer.py" << 'PY'
"""VM spec synthesizer."""


class VMSynthesizer:
    def synthesize(self, spec: dict) -> dict:
        resources = spec.get("resources", {})
        gpu = resources.get("gpu")
        return {
            "image": "debian-13-cloud",
            "instance_type": "gpu.a10g" if gpu else "std.2x4",
            "cloud_init": [
                "apt-get update",
                "apt-get install -y python3 python3-pip ffmpeg",
            ],
            "estimated_usd_per_hour": 1.20 if gpu else 0.09,
        }
PY

cat > "$BACKEND_DIR/agents/periodic_table.json" << 'JSON'
{
  "version": 1,
  "groups": [
    {
      "id": "perception",
      "label": "Perception",
      "elements": [
        {"symbol": "Vi", "name": "Vision", "capability": "image and frame understanding"},
        {"symbol": "Au", "name": "Audio", "capability": "speech and sound understanding"},
        {"symbol": "Tx", "name": "Text", "capability": "language understanding"}
      ]
    },
    {
      "id": "reasoning",
      "label": "Reasoning",
      "elements": [
        {"symbol": "Pl", "name": "Planner", "capability": "task decomposition"},
        {"symbol": "Cr", "name": "Critic", "capability": "self-evaluation"},
        {"symbol": "Me", "name": "Memory", "capability": "long-horizon recall"}
      ]
    },
    {
      "id": "synthesis",
      "label": "Synthesis",
      "elements": [
        {"symbol": "Sp", "name": "Spatial", "capability": "scene graph composition"},
        {"symbol": "Mo", "name": "Motion", "capability": "temporal coherence"},
        {"symbol": "Rn", "name": "Render", "capability": "frame synthesis"}
      ]
    },
    {
      "id": "execution",
      "label": "Execution",
      "elements": [
        {"symbol": "Vm", "name": "VM Builder", "capability": "environment provisioning"},
        {"symbol": "Or", "name": "Orchestrator", "capability": "agent scheduling"}
      ]
    }
  ]
}
JSON

cat > "$BACKEND_DIR/main.py" << 'PY'
"""Manifest AI API."""
import json
import logging
from functools import lru_cache
from pathlib import Path

from fastapi import (BackgroundTasks, Depends, FastAPI, HTTPException, Query,
                     WebSocket, WebSocketDisconnect, status)
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import func, select
from sqlalchemy.orm import Session

import video
from agents.orchestrator import AgentOrchestrator
from agents.spatial_composer import SpatialComposer
from auth import (create_access_token, get_current_admin, get_current_user,
                  hash_password, is_admin, user_from_token, verify_password)
from billing import router as billing_router
from config import BASE_DIR, settings
from database import Base, SessionLocal, engine, get_db
from models import CreditTransaction, User, VideoJob
from utils import calculate_credit_cost, credit_credits, debit_credits
from vm_synthesizer import VMSynthesizer

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("manifest")

Base.metadata.create_all(bind=engine)

app = FastAPI(title="Manifest AI", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST"],
    allow_headers=["Authorization", "Content-Type"],
)
app.include_router(billing_router)

orchestrator = AgentOrchestrator()
spatial_composer = SpatialComposer()
vm_synth = VMSynthesizer()


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "ok"}


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=10, max_length=128)


@app.post("/api/auth/register", status_code=status.HTTP_201_CREATED)
def register(req: RegisterRequest, db: Session = Depends(get_db)) -> dict:
    existing = db.execute(select(User.id).where(User.email == req.email.lower())).first()
    if existing:
        log.info("register attempt for existing address")
        return {"message": "Registration received. Try logging in."}
    user = User(
        email=req.email.lower(),
        hashed_password=hash_password(req.password),
        credits_balance=0,
    )
    db.add(user)
    db.commit()
    if settings.signup_bonus_credits:
        credit_credits(db, user.id, settings.signup_bonus_credits, "bonus", reference="signup")
    return {"message": "Registration received. Try logging in."}


@app.post("/api/auth/login")
def login(
    form: "OAuth2PasswordRequestForm" = Depends(),
    db: Session = Depends(get_db),
) -> dict:
    user = db.execute(select(User).where(User.email == form.username.lower())).scalar_one_or_none()
    if user is None or not verify_password(form.password, user.hashed_password):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid email or password")
    return {"access_token": create_access_token(user.id), "token_type": "bearer"}


@app.get("/api/me")
def me(user: User = Depends(get_current_user)) -> dict:
    return {
        "id": user.id,
        "email": user.email,
        "credits_balance": user.credits_balance,
        "is_admin": is_admin(user),
    }


@app.get("/api/credits/transactions")
def transactions(user: User = Depends(get_current_user), db: Session = Depends(get_db)) -> dict:
    rows = db.execute(
        select(CreditTransaction)
        .where(CreditTransaction.user_id == user.id)
        .order_by(CreditTransaction.created_at.desc())
        .limit(100)
    ).scalars().all()
    return {"balance": user.credits_balance, "transactions": [
        {"amount": r.amount, "type": r.transaction_type,
         "balance_after": r.balance_after, "created_at": r.created_at.isoformat()}
        for r in rows
    ]}


class GenerationRequest(BaseModel):
    idea: str = Field(min_length=3, max_length=2000)
    estimated_minutes: int = Field(default=2, ge=1, le=10)
    style: str = Field(default="cinematic", max_length=64)


@app.post("/api/video/generate", status_code=status.HTTP_202_ACCEPTED)
def generate_video(
    req: GenerationRequest,
    background: BackgroundTasks,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    cost = calculate_credit_cost(req.estimated_minutes, req.style)
    job = VideoJob(
        user_id=user.id, idea=req.idea, duration_minutes=req.estimated_minutes,
        style=req.style, status="queued", progress=0, credit_cost=cost,
    )
    db.add(job)
    db.commit()

    if debit_credits(db, user.id, cost, job_id=job.id) is None:
        job.status = "failed"
        job.error = "Insufficient credits"
        db.commit()
        raise HTTPException(status.HTTP_402_PAYMENT_REQUIRED,
                            f"Insufficient credits: this job costs {cost}")

    background.add_task(video.run_job, job.id)
    return {
        "job_id": job.id, "status": "queued", "credit_cost": cost,
        "estimated_completion_seconds": req.estimated_minutes * 60,
    }


def _own_job(job_id: str, user: User, db: Session) -> VideoJob:
    job = db.execute(
        select(VideoJob).where(VideoJob.id == job_id, VideoJob.user_id == user.id)
    ).scalar_one_or_none()
    if job is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Job not found")
    return job


@app.get("/api/video/status/{job_id}")
def video_status(job_id: str, user: User = Depends(get_current_user),
                 db: Session = Depends(get_db)) -> dict:
    job = _own_job(job_id, user, db)
    return {
        "job_id": job.id, "status": job.status, "progress": job.progress or 0,
        "error": job.error,
        "download_url": f"/api/video/download/{job.id}" if job.status == "completed" else None,
    }


@app.get("/api/video/download/{job_id}")
def video_download(job_id: str, user: User = Depends(get_current_user),
                   db: Session = Depends(get_db)) -> FileResponse:
    job = _own_job(job_id, user, db)
    if job.status != "completed" or not job.final_video_path:
        raise HTTPException(status.HTTP_409_CONFLICT, "Video is not ready")
    path = Path(job.final_video_path).resolve()
    if settings.storage_dir not in path.parents or not path.is_file():
        raise HTTPException(status.HTTP_410_GONE, "Video file is no longer available")
    return FileResponse(path, media_type="video/mp4", filename=f"manifest-{job.id}.mp4")


@app.get("/api/video/jobs")
def list_jobs(user: User = Depends(get_current_user), db: Session = Depends(get_db)) -> dict:
    rows = db.execute(
        select(VideoJob).where(VideoJob.user_id == user.id)
        .order_by(VideoJob.created_at.desc()).limit(50)
    ).scalars().all()
    return {"jobs": [
        {"job_id": j.id, "status": j.status, "progress": j.progress,
         "idea": j.idea[:120], "created_at": j.created_at.isoformat()} for j in rows
    ]}


class VMBuildRequest(BaseModel):
    target_description: str = Field(min_length=3, max_length=2000)


@app.post("/api/build_vm")
async def build_vm(req: VMBuildRequest, user: User = Depends(get_current_user)) -> dict:
    task_id = await orchestrator.start_task(req.target_description)
    return {"task_id": task_id, "status": "started"}


@app.get("/api/vm_spec/{task_id}")
async def vm_spec(task_id: str, user: User = Depends(get_current_user)) -> dict:
    task = await orchestrator.get_task_result(task_id)
    if task is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Task not found")
    if task["status"] != "completed":
        return {"status": task["status"], "progress": task.get("progress", 0)}
    return {"status": "completed", "spec": task["result"]["spec"],
            "vm": vm_synth.synthesize(task["result"]["spec"])}


@lru_cache
def _periodic_table() -> dict:
    path = BASE_DIR / "agents" / "periodic_table.json"
    if not path.is_file():
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Periodic table unavailable")
    return json.loads(path.read_text())


@app.get("/api/periodic_table")
def periodic_table() -> dict:
    return _periodic_table()


class WorldBuilderRequest(BaseModel):
    scene_description: str = Field(min_length=3, max_length=2000)


@app.post("/api/world/build")
def build_world(req: WorldBuilderRequest, user: User = Depends(get_current_user)) -> dict:
    return {"scene_graph": spatial_composer.compose_scene(req.scene_description)}


@app.websocket("/ws")
async def agent_ws(websocket: WebSocket, token: str = Query(...)) -> None:
    db = SessionLocal()
    try:
        user_from_token(token, db)
    except HTTPException:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return
    finally:
        db.close()

    await websocket.accept()
    try:
        while True:
            await websocket.send_json(orchestrator.get_agent_status())
            await __import__("asyncio").sleep(2)
    except WebSocketDisconnect:
        return


@app.get("/api/admin/overview")
def admin_overview(admin: User = Depends(get_current_admin), db: Session = Depends(get_db)) -> dict:
    total_users = db.execute(select(func.count(User.id))).scalar_one()
    total_jobs = db.execute(select(func.count(VideoJob.id))).scalar_one()
    running = db.execute(
        select(func.count(VideoJob.id)).where(VideoJob.status.in_(("queued", "running")))
    ).scalar_one()
    outstanding = db.execute(select(func.coalesce(func.sum(User.credits_balance), 0))).scalar_one()
    job_counts = dict(db.execute(
        select(VideoJob.user_id, func.count(VideoJob.id)).group_by(VideoJob.user_id)
    ).all())
    users = db.execute(select(User).order_by(User.created_at.desc()).limit(100)).scalars().all()
    return {
        "total_users": total_users, "total_jobs": total_jobs,
        "jobs_running": running, "credits_outstanding": outstanding,
        "users": [
            {"id": u.id, "email": u.email, "credits_balance": u.credits_balance,
             "job_count": job_counts.get(u.id, 0), "created_at": u.created_at.isoformat()}
            for u in users
        ],
    }


@app.get("/api/admin/jobs")
def admin_jobs(admin: User = Depends(get_current_admin), db: Session = Depends(get_db)) -> dict:
    rows = db.execute(select(VideoJob).order_by(VideoJob.created_at.desc()).limit(200)).scalars().all()
    return {"jobs": [
        {"job_id": j.id, "user_id": j.user_id, "status": j.status, "progress": j.progress,
         "error": j.error, "credit_cost": j.credit_cost,
         "created_at": j.created_at.isoformat()} for j in rows
    ]}


if __name__ == "__main__":
    import os
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", "8000")))
PY

# Fix login handler to use OAuth2PasswordRequestForm
python3 - "$BACKEND_DIR/main.py" << 'PYFIX'
import sys, re
path = sys.argv[1]
src = open(path).read()
src = src.replace(
    "from fastapi.security import OAuth2PasswordBearer" , "")
src = src.replace(
    "from pydantic import BaseModel, EmailStr, Field",
    "from fastapi.security import OAuth2PasswordRequestForm\nfrom pydantic import BaseModel, EmailStr, Field",
)
old = '''class LoginRequest(BaseModel):
    username: EmailStr
    password: str


@app.post("/api/auth/login")
def login(
    username: str = Query(default=None, include_in_schema=False),
    db: Session = Depends(get_db),
    form: "OAuth2Form" = Depends(),  # noqa: F821 - bound below
) -> dict:'''
new = '''@app.post("/api/auth/login")
def login(
    form: OAuth2PasswordRequestForm = Depends(),
    db: Session = Depends(get_db),
) -> dict:'''
assert old in src, "login block not found"
src = src.replace(old, new)
open(path, "w").write(src)
print("   main.py login handler wired to OAuth2PasswordRequestForm")
PYFIX

cat > "$BACKEND_DIR/render.yaml" << 'YAML'
services:
  - type: web
    name: manifest-api
    runtime: python
    plan: starter
    buildCommand: pip install -r requirements.txt
    startCommand: uvicorn main:app --host 0.0.0.0 --port $PORT --workers 1
    healthCheckPath: /healthz
    envVars:
      - key: SECRET_KEY
        generateValue: true
      - key: ALLOWED_ORIGINS
        sync: false
      - key: ADMIN_EMAILS
        sync: false
      - key: VIDEO_PROVIDER
        value: stub
      - key: DATABASE_URL
        fromDatabase:
          name: manifest-db
          property: connectionString

databases:
  - name: manifest-db
    plan: basic-256mb
YAML

cat > "$BACKEND_DIR/Dockerfile" << 'DOCKER'
FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
ENV PORT=8000
EXPOSE 8000
HEALTHCHECK CMD python -c "import urllib.request,os;urllib.request.urlopen(f'http://127.0.0.1:{os.getenv(\"PORT\",\"8000\")}/healthz')"
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT}"]
DOCKER

cat > "$BACKEND_DIR/README.md" << 'MD'
# Manifest AI - Backend

FastAPI. Every module `main.py` imports is present in this package.

## Run locally

    python3 -m venv .venv && source .venv/bin/activate
    pip install -r requirements.txt
    cp .env.example .env
    python -c "import secrets;print('SECRET_KEY='+secrets.token_urlsafe(48))" >> .env
    uvicorn main:app --reload --port 8000

Docs at http://localhost:8000/docs, health at /healthz.
MD

if [[ $MAKE_ZIP -eq 1 ]]; then
  ( cd "$OUT_DIR" && zip -qr "manifest-frontend.zip" "manifest-frontend" )
  ( cd "$OUT_DIR" && zip -qr "manifest-backend.zip" "manifest-backend" \
      -x '*.pyc' '*__pycache__/*' '*/.env' '*/storage/*' )
  echo "==> manifest-frontend.zip"
  echo "==> manifest-backend.zip"
fi

if command -v python3 >/dev/null; then
  python3 -m compileall -q "$BACKEND_DIR" >/dev/null \
    && echo "==> Python syntax check passed" \
    || { echo "Python syntax check FAILED" >&2; exit 1; }
fi

cat << EOF

Build complete: $OUT_DIR

Next steps
  1. Backend:  cd "$BACKEND_DIR" && see README.md
               cp .env.example .env and set SECRET_KEY + ALLOWED_ORIGINS + ADMIN_EMAILS
  2. Frontend: static host (Netlify / Cloudflare Pages / S3).
               config.js already points at $API_BASE - no manual editing.
  3. Add your frontend origin to ALLOWED_ORIGINS on the backend.
EOF