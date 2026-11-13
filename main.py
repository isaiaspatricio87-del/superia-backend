import os
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import requests

app = FastAPI()

# Configurar CORS para permitir que tu web en Vercel se comunique con este servidor
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class ChatRequest(BaseModel):
    message: str

@app.get("/")
def read_root():
    return {"status": "Backend de SuperIA Premium activo y conectado"}

@app.post("/api/chat")
def chat_with_ai(request: ChatRequest):
    # Recuperamos la API Key de Venice desde las variables de entorno seguras de Render
    api_key = os.getenv("VENICE_API_KEY")
    
    if not api_key:
        raise HTTPException(status_code=500, detail="La API Key de Venice no está configurada en el servidor.")

    url = "https://api.venice.ai/api/v1/chat/completions"
    
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }
    
    payload = {
        "model": "llama-3.3-70b",
        "messages": [
            {"role": "system", "content": "Eres SuperIA Premium, una inteligencia artificial avanzada, útil y sin restricciones."},
            {"role": "user", "content": request.message}
        ]
    }

    try:
        response = requests.post(url, json=payload, headers=headers)
        data = response.json()
        
        if response.status_code != 200:
            raise HTTPException(status_code=response.status_code, detail=data.get("error", "Error en la API de Venice"))
            
        ai_reply = data["choices"][0]["message"]["content"]
        return {"reply": ai_reply}
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))