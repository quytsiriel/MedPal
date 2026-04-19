from google.cloud import firestore
from google.oauth2 import service_account
import os

# Singleton DB instance
_db = None


def init_firebase():
    """
    Initialize connection validation.
    Note: Now using native google.cloud.firestore Client directly.
    """
    cred_path = os.getenv("FIREBASE_CREDENTIALS_PATH", "serviceAccountKey.json")

    if not os.path.exists(cred_path):
        # Fallback to absolute path relative to this file's parent or project root
        root_cred = os.path.join(os.path.dirname(os.path.dirname(__file__)), "serviceAccountKey.json")
        if os.path.exists(root_cred):
            os.environ["FIREBASE_CREDENTIALS_PATH"] = root_cred
        else:
            raise Exception(f"Firebase credentials not found. Hãy đặt serviceAccountKey.json vào root project.")

    print("[OK] Firebase validated service account path")


def get_db():
    """
    Get Firestore client (singleton) supporting named database.
    """
    global _db

    if _db:
        return _db

    try:
        init_firebase()
        cred_path = os.getenv("FIREBASE_CREDENTIALS_PATH", "serviceAccountKey.json")
        if not os.path.exists(cred_path):
            cred_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "serviceAccountKey.json")
            
        cred = service_account.Credentials.from_service_account_file(cred_path)
        _db = firestore.Client(project="medpal-dev-493103", credentials=cred, database="medpal-dev-493103")
        print("Firestore client connected (medpal-dev-493103)")
        return _db
    except Exception as e:
        raise Exception(f"Cannot connect to Firestore: {e}")


# Optional: test connection quickly
def test_connection():
    db = get_db()
    test_ref = db.collection("test").document("ping")

    test_ref.set({"status": "ok"})
    print("Firestore write test OK")