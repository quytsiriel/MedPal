from sentence_transformers import SentenceTransformer
import faiss, json, pickle, os
import numpy as np
from huggingface_hub import login
import os

login(token=os.getenv("HF_TOKEN"))

BASE = os.path.dirname(__file__)

model = SentenceTransformer("all-MiniLM-L6-v2")

chunks = json.load(open(os.path.join(BASE, "data/chunks.json"), encoding="utf-8"))

embeddings = model.encode(chunks)

index = faiss.IndexFlatL2(embeddings.shape[1])
index.add(np.array(embeddings))

faiss.write_index(index, os.path.join(BASE, "data/faiss.index"))

with open(os.path.join(BASE, "data/chunks.pkl"), "wb") as f:
    pickle.dump(chunks, f)