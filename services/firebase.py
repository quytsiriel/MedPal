import firebase_admin
from firebase_admin import credentials, firestore
import os

# Singleton DB instance
_db = None


def init_firebase():
    """
    Initialize Firebase Admin SDK with service account.
    """
    if firebase_admin._apps:
        return

    cred_path = os.getenv("FIREBASE_CREDENTIALS_PATH", "serviceAccountKey.json")

    if not os.path.exists(cred_path):
        raise Exception(
            f"Firebase credentials not found at: {cred_path}\n"
            f"Hãy tải serviceAccountKey.json từ Firebase Console và đặt vào root project."
        )

    try:
        cred = credentials.Certificate(cred_path)
        firebase_admin.initialize_app(cred)
        print("✅ Firebase initialized successfully")
    except Exception as e:
        raise Exception(f"❌ Firebase initialization failed: {e}")


def get_db():
    """
    Get Firestore client (singleton).
    """
    global _db

    if _db:
        return _db

    if not firebase_admin._apps:
        init_firebase()

    try:
        _db = firestore.client(database_id="medpal-dev-493103")
        print("Firestore client connected")
        return _db
    except Exception as e:
        raise Exception(f"Cannot connect to Firestore: {e}")


# Optional: test connection quickly
def test_connection():
    db = get_db()
    test_ref = db.collection("test").document("ping")

    test_ref.set({"status": "ok"})
    print("Firestore write test OK")