import firebase_admin
from firebase_admin import credentials, firestore
import os

def test_firebase_connection():
    cred_path = "serviceAccountKey.json"
    if not os.path.exists(cred_path):
        print("Error: serviceAccountKey.json not found")
        return

    if not firebase_admin._apps:
        cred = credentials.Certificate(cred_path)
        firebase_admin.initialize_app(cred)

    print("--- Testing Connection ---")
    
    # Test 1: medpal-dev-493103
    try:
        db = firestore.client(database_id="medpal-dev-493103")
        # Try a real operation
        docs = db.collection("sessions").limit(1).get()
        print(f"SUCCESS with database_id='medpal-dev-493103'. Found {len(docs)} docs.")
    except Exception as e:
        print(f"FAILED with database_id='medpal-dev-493103': {e}")

    # Test 2: (default)
    try:
        db = firestore.client(database_id="(default)")
        docs = db.collection("sessions").limit(1).get()
        print(f"SUCCESS with database_id='(default)'. Found {len(docs)} docs.")
    except Exception as e:
        print(f"FAILED with database_id='(default)': {e}")

if __name__ == "__main__":
    test_firebase_connection()
