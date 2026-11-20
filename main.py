import base64
from datetime import datetime
import hashlib
import hmac
import json
import os
import sqlite3
import time
from typing import Literal
import urllib.error
import urllib.request
from zoneinfo import ZoneInfo

from fastapi import FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field


DB_PATH = os.getenv("AUTH_DB_PATH", "superia_users.db")
AUTH_SECRET = os.getenv("AUTH_SECRET_KEY", "superia-secret-key-isaias-2026")
ADMIN_KEY = os.getenv("ADMIN_KEY", "isaias-admin-2026")
TOKEN_TTL_SECONDS = 60 * 60 * 24 * 7  # 7 días

OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"
OPENROUTER_BASE_MODEL = os.getenv("OPENROUTER_BASE_MODEL", "openai/gpt-4o-mini")
OPENROUTER_ONLINE_MODEL = os.getenv(
    "OPENROUTER_ONLINE_MODEL",
    "openai/gpt-4o-mini:online",
)
OPENROUTER_AUDIO_MODEL = os.getenv(
    "OPENROUTER_AUDIO_MODEL",
    "google/gemini-2.5-flash:online",
)


app = FastAPI(title="SuperIA Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)


def _get_db() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def _init_db() -> None:
    with _get_db() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                email TEXT NOT NULL UNIQUE,
                password_hash TEXT NOT NULL,
                created_at INTEGER NOT NULL
            )
            """
        )
        conn.commit()


_init_db()


def _hash_password(password: str) -> str:
    salt = os.urandom(16).hex()
    digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        salt.encode("utf-8"),
        120_000,
    ).hex()
    return f"{salt}${digest}"


def _verify_password(password: str, stored_hash: str) -> bool:
    try:
        salt, expected_digest = stored_hash.split("$", 1)
    except ValueError:
        return False

    actual_digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        salt.encode("utf-8"),
        120_000,
    ).hex()
    return hmac.compare_digest(actual_digest, expected_digest)


def _create_token(user_id: int, name: str, email: str) -> str:
    payload = {
        "uid": user_id,
        "name": name,
        "email": email,
        "exp": int(time.time()) + TOKEN_TTL_SECONDS,
    }
    payload_b64 = base64.urlsafe_b64encode(
        json.dumps(payload, separators=(",", ":")).encode("utf-8")
    ).decode("utf-8")
    signature = hmac.new(
        AUTH_SECRET.encode("utf-8"),
        payload_b64.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    return f"{payload_b64}.{signature}"


def _verify_token(token: str) -> dict:
    try:
        payload_b64, signature = token.split(".", 1)
        expected_sig = hmac.new(
            AUTH_SECRET.encode("utf-8"),
            payload_b64.encode("utf-8"),
            hashlib.sha256,
        ).hexdigest()
        if not hmac.compare_digest(signature, expected_sig):
            raise HTTPException(status_code=401, detail="Sesión inválida.")

        padded = payload_b64 + "=" * (-len(payload_b64) % 4)
        payload = json.loads(
            base64.urlsafe_b64decode(padded.encode("utf-8")).decode("utf-8")
        )
        if int(payload.get("exp", 0)) < int(time.time()):
            raise HTTPException(status_code=401, detail="La sesión expiró.")
        return payload
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=401, detail="Token de sesión mal formado.")


def _require_user(authorization: str | None) -> dict:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=401,
            detail="Debes iniciar sesión para usar SuperIA.",
        )
    token = authorization.removeprefix("Bearer ").strip()
    return _verify_token(token)


def _audio_format_from_mime(mime_type: str | None) -> str:
    if not mime_type:
        return "wav"
    lowered = mime_type.lower()
    if "mp3" in lowered or "mpeg" in lowered:
        return "mp3"
    if "ogg" in lowered:
        return "ogg"
    if "webm" in lowered:
        return "webm"
    if "m4a" in lowered or "mp4" in lowered or "aac" in lowered:
        return "m4a"
    return "wav"


def _is_followup_detail_request(text: str) -> bool:
    lowered = text.strip().lower()
    phrases = (
        "mas detalle",
        "más detalle",
        "mas detalles",
        "más detalles",
        "mas informacion",
        "más información",
        "mas info",
        "más info",
        "explicame eso",
        "explícame eso",
        "amplia eso",
        "amplía eso",
        "continua",
        "continúa",
        "sigue",
        "profundiza",
    )
    return any(p in lowered for p in phrases)


def _needs_live_search(text: str, history: list["HistoryTurn"]) -> bool:
    if _is_followup_detail_request(text):
        return False

    lowered = text.lower()
    keywords = (
        "clima",
        "tiempo",
        "lluvia",
        "lloviendo",
        "nublado",
        "soleado",
        "temperatura",
        "pronostico",
        "pronóstico",
        "partido",
        "partidos",
        "resultado",
        "resultados",
        "juego",
        "juegos",
        "gol",
        "goles",
        "liga",
        "nba",
        "nfl",
        "mlb",
        "ufc",
        "f1",
        "formula 1",
        "fórmula 1",
        "tenis",
        "boxeo",
        "beisbol",
        "béisbol",
        "futbol",
        "fútbol",
        "noticia",
        "noticias",
        "actual",
        "actualidad",
        "en vivo",
        "precio",
        "precios",
        "dolar",
        "dólar",
        "investiga",
        "busca",
    )
    return any(word in lowered for word in keywords)


def _call_openrouter(api_key: str, model: str, messages: list[dict]) -> dict:
    body = {
        "model": model,
        "messages": messages,
    }
    req = urllib.request.Request(
        OPENROUTER_URL,
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "HTTP-Referer": "https://superia-backend-1.onrender.com",
            "X-Title": "SuperIA",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as http_err:
        err_body = http_err.read().decode("utf-8", errors="replace")
        print(
            f"Error HTTP OpenRouter ({http_err.code}): {err_body}",
            flush=True,
        )
        if http_err.code == 401:
            raise HTTPException(
                status_code=401,
                detail="OPENROUTER_API_KEY inválida o revocada en Render.",
            )
        if http_err.code == 402:
            raise HTTPException(
                status_code=402,
                detail="OpenRouter no tiene créditos disponibles para esta consulta.",
            )
        if http_err.code == 429:
            raise HTTPException(
                status_code=429,
                detail="Límite de peticiones alcanzado en OpenRouter. Intenta en unos segundos.",
            )
        raise HTTPException(
            status_code=502,
            detail="OpenRouter devolvió un error. Revisa los logs de Render.",
        )
    except Exception as err:
        print(f"Error de red con OpenRouter: {err}", flush=True)
        raise HTTPException(
            status_code=502,
            detail="No se pudo conectar con OpenRouter. Revisa los logs de Render.",
        )


class RegisterRequest(BaseModel):
    name: str = Field(min_length=2, max_length=80)
    email: str = Field(min_length=5, max_length=150)
    password: str = Field(min_length=6, max_length=128)


class LoginRequest(BaseModel):
    email: str = Field(min_length=5, max_length=150)
    password: str = Field(min_length=1, max_length=128)


class GoogleLoginRequest(BaseModel):
    name: str = Field(default="Usuario Google", max_length=80)
    email: str = Field(min_length=5, max_length=150)


class HistoryTurn(BaseModel):
    role: Literal["user", "model"]
    text: str = Field(max_length=20000)


class ChatRequest(BaseModel):
    message: str = Field(default="", max_length=20000)
    memories: list[str] = Field(default_factory=list)
    history: list[HistoryTurn] = Field(default_factory=list)
    image_base64: str | None = None
    image_mime_type: str | None = None
    audio_base64: str | None = None
    audio_mime_type: str | None = None


@app.get("/")
def home():
    return {"status": "SuperIA activo", "provider": "OpenRouter"}


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/api/auth/register")
def register(request: RegisterRequest):
    name = request.name.strip()
    email = request.email.strip().lower()
    password = request.password

    if "@" not in email or "." not in email.split("@")[-1]:
        raise HTTPException(status_code=400, detail="Ingresa un correo válido.")

    password_hash = _hash_password(password)
    now = int(time.time())

    try:
        with _get_db() as conn:
            cursor = conn.execute(
                """
                INSERT INTO users (name, email, password_hash, created_at)
                VALUES (?, ?, ?, ?)
                """,
                (name, email, password_hash, now),
            )
            conn.commit()
            user_id = cursor.lastrowid
    except sqlite3.IntegrityError:
        raise HTTPException(
            status_code=409,
            detail="Ese correo ya está registrado. Inicia sesión.",
        )

    token = _create_token(user_id=user_id, name=name, email=email)
    return {
        "token": token,
        "user": {"id": user_id, "name": name, "email": email},
    }


@app.post("/api/auth/login")
def login(request: LoginRequest):
    email = request.email.strip().lower()

    with _get_db() as conn:
        row = conn.execute(
            "SELECT id, name, email, password_hash FROM users WHERE email = ?",
            (email,),
        ).fetchone()

    if not row or not _verify_password(request.password, row["password_hash"]):
        raise HTTPException(
            status_code=401,
            detail="Correo o contraseña incorrectos.",
        )

    token = _create_token(
        user_id=row["id"],
        name=row["name"],
        email=row["email"],
    )
    return {
        "token": token,
        "user": {
            "id": row["id"],
            "name": row["name"],
            "email": row["email"],
        },
    }


@app.post("/api/auth/google")
def auth_google(request: GoogleLoginRequest):
    email = request.email.strip().lower()
    name = request.name.strip() or email.split("@")[0]

    if "@" not in email or "." not in email.split("@")[-1]:
        raise HTTPException(status_code=400, detail="Correo de Google inválido.")

    with _get_db() as conn:
        row = conn.execute(
            "SELECT id, name, email FROM users WHERE email = ?",
            (email,),
        ).fetchone()

        if row:
            user_id = row["id"]
            user_name = row["name"]
        else:
            now = int(time.time())
            random_hash = _hash_password(os.urandom(24).hex())
            cursor = conn.execute(
                """
                INSERT INTO users (name, email, password_hash, created_at)
                VALUES (?, ?, ?, ?)
                """,
                (name, email, random_hash, now),
            )
            conn.commit()
            user_id = cursor.lastrowid
            user_name = name

    token = _create_token(user_id=user_id, name=user_name, email=email)
    return {
        "token": token,
        "user": {"id": user_id, "name": user_name, "email": email},
    }


@app.get("/api/auth/me")
def me(authorization: str | None = Header(default=None)):
    payload = _require_user(authorization)
    return {
        "user": {
            "id": payload["uid"],
            "name": payload["name"],
            "email": payload["email"],
        }
    }


@app.get("/api/admin/users")
def list_users(admin_key: str = ""):
    if admin_key != ADMIN_KEY:
        raise HTTPException(
            status_code=403,
            detail="Clave de administrador incorrecta.",
        )

    with _get_db() as conn:
        rows = conn.execute(
            "SELECT id, name, email, created_at FROM users ORDER BY id DESC"
        ).fetchall()

    return {
        "total": len(rows),
        "users": [dict(row) for row in rows],
    }


@app.post("/api/chat")
def chat(
    request: ChatRequest,
    authorization: str | None = Header(default=None),
):
    current_user = _require_user(authorization)
    api_key = os.getenv("OPENROUTER_API_KEY")

    if not api_key:
        raise HTTPException(
            status_code=500,
            detail="Falta configurar OPENROUTER_API_KEY en Render.",
        )

    now_rd = datetime.now(ZoneInfo("America/Santo_Domingo"))
    fecha_hora_actual = now_rd.strftime(
        "%A, %d/%m/%Y a las %I:%M:%S %p (Hora de República Dominicana, AST)"
    )

    system_instruction = (
        "Eres SuperIA, una inteligencia artificial amigable, cercana, "
        "respetuosa y eficaz. Responde con naturalidad, limpieza y calidez, "
        "en el idioma del usuario, sin agregar listas de enlaces o fuentes "
        "al final a menos que el usuario pida explícitamente enlaces o "
        "fuentes. "
        f"El usuario autenticado se llama {current_user['name']}. "
        f"FECHA Y HORA ACTUAL EXACTA: {fecha_hora_actual}. "
        "Si el usuario pregunta qué hora es o qué día es hoy, responde usando "
        "esa fecha y hora exacta. "
        "Tu creador y desarrollador es Isaías Patricio Agramonte. "
        "Si te preguntan quién te creó, quién te desarrolló, quién es "
        "tu creador, quién hizo SuperIA o cualquier pregunta equivalente "
        "sobre el origen de SuperIA, responde claramente que fue creada "
        "por Isaías Patricio Agramonte. No atribuyas la creación de "
        "SuperIA a OpenAI, Google ni a otra persona o empresa. "
        "REGLA DE CONTINUIDAD: Cuando el usuario pida «más detalle», "
        "«más información», «explícame eso» o algo similar, SIEMPRE "
        "continúa y amplía directamente el tema o la última respuesta de la "
        "conversación anterior (por ejemplo, si antes hablaron de la fecha/día "
        "de hoy, da detalles útiles sobre el día, calendario, temporada o lo "
        "que corresponda a ese tema). NUNCA respondas preguntando «¿Sobre qué "
        "tema específico te gustaría que te diera más detalle?» ni digas que "
        "necesitas contexto cuando ya hay un tema en el historial. "
        "Cuando el usuario pregunte por el estado del tiempo meteorológico "
        "(si está nublado, soleado, lloviendo, temperatura, etc.) o sobre "
        "resultados, partidos y noticias recientes de CUALQUIER DEPORTE en el "
        "mundo, responde con la información más fresca y actual disponible. "
        "Usa Markdown estándar para títulos, listas y **negritas**."
    )

    messages: list[dict] = [{"role": "system", "content": system_instruction}]

    for turn in request.history[-14:]:
        if turn.text.strip():
            role = "assistant" if turn.role == "model" else "user"
            messages.append({"role": role, "content": turn.text.strip()})

    user_content: list[dict] = []

    if request.memories:
        memories_text = "\n".join(f"- {memory}" for memory in request.memories)
        user_content.append(
            {
                "type": "text",
                "text": f"Notas que el usuario guardó:\n{memories_text}",
            }
        )

    msg_text = request.message.strip()
    if _is_followup_detail_request(msg_text):
        msg_text = (
            f"{msg_text} (Amplía y da más detalles directamente sobre el "
            "último tema tratado en esta conversación, sin preguntar de qué "
            "tema se trata)."
        )

    if msg_text:
        user_content.append(
            {
                "type": "text",
                "text": msg_text,
            }
        )

    if request.image_base64:
        try:
            base64.b64decode(request.image_base64, validate=True)
        except Exception:
            raise HTTPException(
                status_code=400,
                detail="La imagen recibida no es válida.",
            )
        mime = request.image_mime_type or "image/jpeg"
        user_content.append(
            {
                "type": "image_url",
                "image_url": {
                    "url": f"data:{mime};base64,{request.image_base64}",
                },
            }
        )

    selected_model = (
        OPENROUTER_ONLINE_MODEL
        if _needs_live_search(request.message, request.history)
        else OPENROUTER_BASE_MODEL
    )

    if request.audio_base64:
        try:
            base64.b64decode(request.audio_base64, validate=True)
        except Exception:
            raise HTTPException(
                status_code=400,
                detail="El audio recibido no es válido.",
            )
        audio_fmt = _audio_format_from_mime(request.audio_mime_type)
        user_content.append(
            {
                "type": "input_audio",
                "input_audio": {
                    "data": request.audio_base64,
                    "format": audio_fmt,
                },
            }
        )
        selected_model = OPENROUTER_AUDIO_MODEL

    if not user_content:
        user_content.append({"type": "text", "text": "¡Hola!"})

    if len(user_content) == 1 and user_content[0]["type"] == "text":
        messages.append({"role": "user", "content": user_content[0]["text"]})
    else:
        messages.append({"role": "user", "content": user_content})

    data = _call_openrouter(
        api_key=api_key,
        model=selected_model,
        messages=messages,
    )

    choices = data.get("choices") or []
    message_obj = choices[0].get("message", {}) if choices else {}
    reply = message_obj.get("content") or ""

    if isinstance(reply, list):
        reply = "\n".join(
            part.get("text", "")
            for part in reply
            if isinstance(part, dict) and part.get("text")
        )

    if not reply or not reply.strip():
        reply = "No pude generar una respuesta. Inténtalo de nuevo."

    return {"reply": reply}