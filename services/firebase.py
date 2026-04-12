import firebase_admin
from firebase_admin import credentials, firestore
import os

# Initialize Firebase Admin
def init_firebase():
    if not firebase_admin._apps:
        try:
            # Check for a service account key file in the root directory
            cred_path = os.getenv("FIREBASE_CREDENTIALS_PATH", "serviceAccountKey.json")
            if os.path.exists(cred_path):
                cred = credentials.Certificate(cred_path)
                firebase_admin.initialize_app(cred)
            else:
                # Fallback to application default credentials
                firebase_admin.initialize_app()
        except Exception as e:
            print(f"Warning: Firebase initialization issue: {e}")

def get_db():
    try:
        if not firebase_admin._apps:
            init_firebase()
        return firestore.client()
    except Exception as e:
        raise Exception(f"Failed to connect to Firestore: {e}. Ensure you have provided a serviceAccountKey.json or set GOOGLE_APPLICATION_CREDENTIALS.")
