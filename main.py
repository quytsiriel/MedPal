import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv

# Tự động nạp biến môi trường từ file .env vào os.environ
load_dotenv()

from services.firebase import init_firebase
from agents.agent1_router import router as agent1_router
from agents.agent2 import router as agent2_router
from agents.agent3 import router as agent3_router

# Initialize firebase before app starts
init_firebase()

app = FastAPI(title="MedPal API", version="1.0.0")

# CORS setup
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(agent1_router)
app.include_router(agent2_router)
app.include_router(agent3_router)

@app.get("/health")
def health_check():
    return {"status": "ok"}
