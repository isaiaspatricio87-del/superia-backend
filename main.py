import base64
import os
from typing import Literal

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


@app.post("/api/chat")
def chat(request: ChatRequest):
    api_key = os.getenv("GEMINI_API_KEY")

    if not api_key:
        raise HTTPException(
            status_code=500,
            detail="Falta configurar GEMINI_API_KEY en Render.",
        )

    try:
        client = genai.Client(api_key=api_key)

        # Instrucción del sistema ampliada para hora, día, clima y deportes en tiempo real
        system_instruction = (
            "Eres SuperIA, una inteligencia artificial amigable, cercana, "
            "respetuosa y eficaz. Responde con naturalidad y calidez, en el "
            "idioma del usuario. "
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
            "siempre contrasta y presenta información real y actualizada. "
            "Usa Markdown estándar para títulos, listas y **negritas**."
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
            model="gemini-3.8-flash",
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