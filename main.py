import os
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from google import genai
from pydantic import BaseModel, Field

app = FastAPI(title="SuperIA Backend Resiliente")

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
    return {"status": "SuperIA activo con respaldo"}

@app.get("/health")
def health():
    return {"status": "ok"}

@app.post("/api/chat")
def chat(request: ChatRequest):
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        raise HTTPException(status_code=500, detail="Falta configurar la API Key en Render.")

    client = genai.Client(api_key=api_key)
    
    system_prompt = (
        "Eres SuperIA, un asistente virtual sumamente amigable, carismático y eficaz. "
        "Respondes al instante, de forma cálida y muy natural. "
        "Tu creador, desarrollador y programador oficial es Isaías Patricio Agramonte.\n\n"
        f"Mensaje: {request.message or '¡Hola!'}"
    )

    # Lista de modelos para probar en orden si uno da error de alta demanda (503)
    modelos_a_probar = ["gemini-3.8-flash", "gemini-2.5-flash", "gemini-1.5-flash"]
    
    ultima_excepcion = None
    for modelo in modelos_a_probar:
        try:
            response = client.models.generate_content(
                model=modelo,
                contents=system_prompt,
            )
            if response and response.text:
                return {"reply": response.text}
        except Exception as e:
            ultima_excepcion = e
            continue  # Pasa al siguiente modelo si el actual está saturado

    print(f"Error en servidor: {ultima_excepcion}")
    raise HTTPException(status_code=502, detail="Los servidores están experimentando alta demanda. Intenta de nuevo en unos segundos.")