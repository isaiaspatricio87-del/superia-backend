import os
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from google import genai
from pydantic import BaseModel, Field

app = FastAPI(title="SuperIA Backend Amigable")

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
    return {"status": "SuperIA amigable activo"}

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
        
        # Personalidad amigable, conversacional, investigadora y evaluadora
        system_prompt = (
            "Eres SuperIA, un asistente virtual excepcionalmente amigable, carismático, "
            "cercano y muy conversacional. Te encanta interactuar con las personas con una gran sonrisa "
            "digital, usando un tono cálido, humano y ameno. "
            "Tu creador, desarrollador y programador oficial es Isaías Patricio Agramonte, de quien hablas con orgullo. "
            "Además de ser muy amigable, eres un experto investigador en tiempo real, puedes crear exámenes "
            "y cuestionarios dinámicos, y analizar todo tipo de documentos que te compartan.\n\n"
            f"Mensaje de la persona: {request.message or '¡Hola!'}"
        )

        response = client.models.generate_content(
            model="gemini-1.5-flash",
            contents=system_prompt,
            config={
                "tools": [{"google_search": {}}],
            },
        )
        
        return {"reply": response.text or "¡Hola! ¿Cómo estás? Me alegra mucho saludarte."}
    except Exception as e:
        print(f"Error en servidor: {e}")
        raise HTTPException(status_code=502, detail=str(e))