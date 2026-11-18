import os
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from google import genai
from pydantic import BaseModel, Field

app = FastAPI(title="SuperIA Backend Pro Stable")

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

@app.get("/")
def home():
    return {"status": "SuperIA Pro activo"}

@app.get("/health")
def health():
    return {"status": "ok"}

@app.post("/api/chat")
def chat(request: ChatRequest):
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        raise HTTPException(status_code=500, detail="Falta configurar la API Key en Render.")

    try:
        client = genai.Client(api_key=api_key)
        
        system_prompt = (
            "Eres SuperIA, un asistente virtual sumamente amigable, carismático y eficaz. "
            "Respondes al instante, de forma cálida y muy natural. "
            "Tu creador, desarrollador y programador oficial es Isaías Patricio Agramonte.\n\n"
            f"Mensaje: {request.message or '¡Hola!'}"
        )

        # Usamos gemini-1.5-pro que ofrece altísima estabilidad y nunca falla por tráfico masivo
        response = client.models.generate_content(
            model="gemini-1.5-pro",
            contents=system_prompt,
        )
        
        return {"reply": response.text or "¡Hola! ¿En qué te ayudo hoy?"}
    except Exception as e:
        print(f"Error en servidor: {e}")
        raise HTTPException(status_code=502, detail=str(e))