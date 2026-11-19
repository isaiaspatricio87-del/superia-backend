import base64
import hashlib
import hmac
import json
import os
import sqlite3
import time
from typing import Literal

from fastapi import FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from google import genai
from google.genai import types
from pydantic import BaseModel, Field


DB_PATH = os.getenv("AUTH_DB_PATH", "superia_users.db")
AUTH_SECRET = os.getenv("AUTH_SECRET_KEY", "superia-secret-key-isaias-2026")
TOKEN_TTL_SECONDS = 60 * 60 * 24 * 7  # 7 días


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


class RegisterRequest(BaseModel):
    name: str = Field(min_length=2, max_length=80)
    email: str = Field(min_length=5, max_length=150)
    password: str = Field(min_length=6, max_length=128)


class LoginRequest(BaseModel):
    email: str = Field(min_length=5, max_length=150)
    password: str = Field(min_length=1, max_length=128)


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
    return {"status": "SuperIA activo"}


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


@app.post("/api/chat")
def chat(
    request: ChatRequest,
    authorization: str | None = Header(default=None),
):
    current_user = _require_user(authorization)
    api_key = os.getenv("GEMINI_API_KEY")

    if not api_key:
        raise HTTPException(
            status_code=500,
            detail="Falta configurar GEMINI_API_KEY en Render.",
        )

    try:
        client = genai.Client(api_key=api_key)

        system_instruction = (
            "Eres SuperIA, una inteligencia artificial amigable, cercana, "
            "respetuosa y eficaz. Responde con naturalidad y calidez, en el "
            "idioma del usuario. "
            f"El usuario autenticado se llama {current_user['name']}. "
            "Tu creador y desarrollador es Isaías Patricio Agramonte. "
            "Si te preguntan quién te creó, quién te desarrolló, quién es "
            "tu creador, quién hizo SuperIA o cualquier pregunta equivalente "
            "sobre el origen de SuperIA, responde claramente que fue creada "
            "por Isaías Patricio Agramonte. No atribuyas la creación de "
            "SuperIA a Google ni a otra persona o empresa. Google proporciona "
            "el modelo de inteligencia artificial que usa SuperIA. "
            "Mantén el tema de la conversación. Si el usuario dice «dame más "
            "detalle», «explícame eso» o algo parecido, continúa el tema "
            "anterior con un tono conversacional; no le preguntes de nuevo "
            "cuál era el tema. "
            "TIENES ACCESO A INTERNET EN TIEMPO REAL: Cuando el usuario pregunte "
            "por la hora actual, el día de hoy, el estado del tiempo meteorológico "
            "(si está nublado, soleado, lloviendo, temperatura, etc.) o sobre "
            "resultados y noticias recientes de CUALQUIER DEPORTE en el mundo, "
            "DEBES usar Google Search obligatoriamente para investigar la información "
            "más fresca y reciente en la web. No inventes datos ni fuentes; "
            "si no puedes verificar algo, dilo. Usa Markdown estándar para "
            "títulos, listas y **negritas**."
        )

        conversation = [
            types.Content(
                role=turn.role,
                parts=[types.Part.from_text(text=turn.text)],
            )
            for turn in request.history[-12:]
            if turn.text.strip()
        ]

        current_parts: list[types.Part] = []

        if request.memories:
            memories_text = "\n".join(
                f"- {memory}" for memory in request.memories
            )
            current_parts.append(
                types.Part.from_text(
                    text=f"Notas que el usuario guardó:\n{memories_text}"
                )
            )

        if request.message.strip():
            current_parts.append(
                types.Part.from_text(text=request.message.strip())
            )

        if request.image_base64:
            try:
                image_bytes = base64.b64decode(
                    request.image_base64,
                    validate=True,
                )
            except Exception:
                raise HTTPException(
                    status_code=400,
                    detail="La imagen recibida no es válida.",
                )

            current_parts.append(
                types.Part.from_bytes(
                    data=image_bytes,
                    mime_type=request.image_mime_type or "image/jpeg",
                )
            )

        if request.audio_base64:
            try:
                audio_bytes = base64.b64decode(
                    request.audio_base64,
                    validate=True,
                )
            except Exception:
                raise HTTPException(
                    status_code=400,
                    detail="El audio recibido no es válido.",
                )

            current_parts.append(
                types.Part.from_bytes(
                    data=audio_bytes,
                    mime_type=request.audio_mime_type or "audio/wav",
                )
            )

        if not current_parts:
            current_parts.append(types.Part.from_text(text="¡Hola!"))

        conversation.append(
            types.Content(role="user", parts=current_parts)
        )

        response = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=conversation,
            config=types.GenerateContentConfig(
                system_instruction=system_instruction,
                tools=[
                    types.Tool(
                        google_search=types.GoogleSearch()
                    )
                ],
            ),
        )

        reply = response.text

        if not reply or not reply.strip():
            reply = "No pude generar una respuesta. Inténtalo de nuevo."

        source_links = []
        seen_urls = set()

        for candidate in response.candidates or []:
            metadata = getattr(candidate, "grounding_metadata", None)

            for chunk in getattr(metadata, "grounding_chunks", []) or []:
                web = getattr(chunk, "web", None)
                url = getattr(web, "uri", None) if web else None
                title = getattr(web, "title", None) if web else None

                if url and url not in seen_urls:
                    seen_urls.add(url)
                    label = title or url
                    source_links.append(f"- [{label}]({url})")

        if source_links:
            reply += "\n\n**Fuentes:**\n" + "\n".join(source_links)

        return {"reply": reply}

    except HTTPException:
        raise
    except Exception as error:
        error_text = str(error)
        print(f"Error al consultar Gemini: {error_text}", flush=True)

        if "429" in error_text or "RESOURCE_EXHAUSTED" in error_text.upper():
            raise HTTPException(
                status_code=429,
                detail=(
                    "Gemini agotó la cuota disponible para este proyecto. "
                    "Revisa los límites de uso y la facturación en Google AI Studio."
                ),
            )

        raise HTTPException(
            status_code=502,
            detail=(
                "No se pudo obtener respuesta de Gemini. "
                "Revisa los logs de Render."
            ),
        )