import base64
import os

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from google import genai
from google.genai import types
from pydantic import BaseModel, Field


app = FastAPI(title="SuperIA Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)


class ChatRequest(BaseModel):
    message: str = Field(default="", max_length=20000)
    memories: list[str] = Field(default_factory=list)
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


@app.post("/api/chat")
def chat(request: ChatRequest):
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        raise HTTPException(
            status_code=500,
            detail="Falta configurar GEMINI_API_KEY en Render.",
        )

    parts = []

    if request.memories:
        memories_text = "\n".join(f"- {item}" for item in request.memories)
        parts.append(f"Memorias del usuario:\n{memories_text}")

    if request.message.strip():
        parts.append(request.message.strip())

    if not parts and not request.image_base64 and not request.audio_base64:
        parts.append("¡Hola!")

    if request.image_base64:
        try:
            image_bytes = base64.b64decode(request.image_base64, validate=True)
        except Exception:
            raise HTTPException(
                status_code=400,
                detail="La imagen recibida no es válida.",
            )

        parts.append(
            types.Part.from_bytes(
                data=image_bytes,
                mime_type=request.image_mime_type or "image/jpeg",
            )
        )

    if request.audio_base64:
        try:
            audio_bytes = base64.b64decode(request.audio_base64, validate=True)
        except Exception:
            raise HTTPException(
                status_code=400,
                detail="El audio recibido no es válido.",
            )

        parts.append(
            types.Part.from_bytes(
                data=audio_bytes,
                mime_type=request.audio_mime_type or "audio/wav",
            )
        )

    try:
        client = genai.Client(api_key=api_key)

        response = client.models.generate_content(
            model="gemini-3.5-flash-lite",
            contents=parts,
            config=types.GenerateContentConfig(
                system_instruction=(
                    "Eres SuperIA, un asistente amigable, claro y eficaz. "
                    "Responde en el idioma del usuario."
                ),
            ),
        )

        reply = response.text
        if not reply or not reply.strip():
            reply = "No pude generar una respuesta. Inténtalo de nuevo."

        return {"reply": reply}

    except Exception as error:
        error_text = str(error)
        print(f"Error al consultar Gemini: {error_text}", flush=True)

        if "429" in error_text or "RESOURCE_EXHAUSTED" in error_text.upper():
            raise HTTPException(
                status_code=429,
                detail=(
                    "Gemini agotó la cuota disponible para este proyecto. "
                    "Revisa los límites de uso de Google AI Studio."
                ),
            )

        raise HTTPException(
            status_code=502,
            detail="No se pudo obtener respuesta de Gemini. Revisa los logs de Render.",
        )
