import base64
import binascii
import os
from typing import Optional

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from google import genai
from pydantic import BaseModel, Field


app = FastAPI(title="SuperIA Backend")

# Permite que Flutter Web se comunique con el backend.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)


class ChatRequest(BaseModel):
    message: str = Field(default="", max_length=10000)
    memories: list[str] = Field(default_factory=list, max_length=30)

    audio_base64: Optional[str] = Field(default=None, max_length=7000000)
    audio_mime_type: Optional[str] = Field(default="audio/wav", max_length=100)

    image_base64: Optional[str] = Field(default=None, max_length=12000000)
    image_mime_type: Optional[str] = Field(default="image/jpeg", max_length=100)


@app.get("/")
def home():
    return {"status": "SuperIA backend activo"}


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

    message = request.message.strip()

    if not message and not request.audio_base64 and not request.image_base64:
        raise HTTPException(
            status_code=400,
            detail="Envía un mensaje, una imagen o una nota de voz.",
        )

    memories_text = "\n".join(
        f"- {memory}" for memory in request.memories[:30]
    )

    if not memories_text:
        memories_text = "- No hay memorias guardadas."

    prompt = (
        "Eres SuperIA, un asistente útil y amable creado por Isaías Patricio Agramonte. "
        "Hablas español informal y respondes con claridad. Si el usuario envía una nota de voz, "
        "entiende lo que dice y responde a su petición. Si envía una imagen, analízala para responder. "
        "Cuando la pregunta necesite información reciente o en tiempo real, usa Google Search "
        "y menciona las fuentes en la respuesta.\n\n"
        f"Memorias del usuario:\n{memories_text}\n\n"
        f"Mensaje del usuario:\n{message or 'El usuario envió un archivo multimedia.'}"
    )

    content = [prompt]

    try:
        if request.audio_base64:
            audio_bytes = base64.b64decode(
                request.audio_base64,
                validate=True,
            )

            content.append(
                {
                    "inline_data": {
                        "data": base64.b64encode(audio_bytes).decode("utf-8"),
                        "mime_type": request.audio_mime_type or "audio/wav",
                    }
                }
            )

        if request.image_base64:
            image_bytes = base64.b64decode(
                request.image_base64,
                validate=True,
            )

            content.append(
                {
                    "inline_data": {
                        "data": base64.b64encode(image_bytes).decode("utf-8"),
                        "mime_type": request.image_mime_type or "image/jpeg",
                    }
                }
            )

        client = genai.Client(api_key=api_key)

        result = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=content,
            config={
                "tools": [{"google_search": {}}],
            },
        )

        answer = result.text or "No recibí una respuesta de Gemini."
        return {"reply": answer}

    except (binascii.Error, ValueError) as error:
        raise HTTPException(
            status_code=400,
            detail="El audio o la imagen enviados no tienen un formato válido.",
        ) from error

    except Exception as error:
        print(f"Error al consultar Gemini: {error}")
        raise HTTPException(
            status_code=502,
            detail="No se pudo obtener respuesta de Gemini. Revisa los logs de Render.",
        ) from error