import warnings
warnings.filterwarnings("ignore")
from langchain_text_splitters import RecursiveCharacterTextSplitter
import os, json

BASE = os.path.dirname(__file__)

text = open(os.path.join(BASE, "data/output/output.txt"), encoding="utf-8").read()

splitter = RecursiveCharacterTextSplitter(
    chunk_size=500,
    chunk_overlap=50
)

chunks = splitter.split_text(text)

json.dump(chunks, open(os.path.join(BASE, "data/chunks.json"), "w", encoding="utf-8"), ensure_ascii=False)