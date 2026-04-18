import firebase_admin
from firebase_admin import credentials, firestore
import os
from dotenv import load_dotenv

load_dotenv()

# Init Firebase Admin
cred = credentials.Certificate("secrets/medpal-dev-dda57-firebase-adminsdk-fbsvc-39d9c09b3a.json")
firebase_admin.initialize_app(cred)

db = firestore.client()

# Test 1: Write
db.collection("sessions").document("test_connection").set({
    "status": "connected",
    "agent": "test",
    "timestamp": firestore.SERVER_TIMESTAMP
})
print("✅ Write OK")

# Test 2: Read
doc = db.collection("sessions").document("test_connection").get()
print(f"✅ Read OK: {doc.to_dict()}")

# Test 3: Check hospitals collection
hospitals = db.collection("hospitals").stream()
print(f"✅ Hospitals collection accessible")
