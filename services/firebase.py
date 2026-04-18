import firebase_admin
from firebase_admin import credentials, firestore
import os

class FakeDocument:
    def __init__(self, doc_id, data=None):
        self.doc_id = doc_id
        self._data = data or {}
    @property
    def exists(self): return bool(self._data)
    def to_dict(self): return self._data
    def set(self, data): self._data.update(data)
    def update(self, data): self._data.update(data)
    def get(self): return self

class FakeCollection:
    def __init__(self, name, store):
        self.name = name
        self.store = store
        if name not in self.store: self.store[name] = {}
    def document(self, doc_id):
        if doc_id not in self.store[self.name]:
            self.store[self.name][doc_id] = FakeDocument(doc_id)
        return self.store[self.name][doc_id]

class FakeFirestore:
    def __init__(self): self.store = {}
    def collection(self, name): return FakeCollection(name, self.store)

_fake_db = FakeFirestore()

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
            print(f"Warning: Firebase init issue: {e}")
            
        
def get_db():
    try:
        if not firebase_admin._apps:
            init_firebase()
        return firestore.client(database_id="medpal-dev-493103")
    except Exception as e:
        print("MOCKING FIREBASE: Using in-memory storage (no serviceAccountKey.json found)")
        return _fake_db