import faiss, pickle, numpy as np, os
from sentence_transformers import SentenceTransformer

BASE = os.path.dirname(__file__)

model = SentenceTransformer("all-MiniLM-L6-v2")

index = faiss.read_index(os.path.join(BASE, "data/faiss.index"))

chunks = pickle.load(open(os.path.join(BASE, "data/chunks.pkl"), "rb"))

def search(query, k=3):
    q_emb = model.encode([query])
    D, I = index.search(np.array(q_emb), k)
    return [chunks[i] for i in I[0]]