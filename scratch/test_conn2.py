from google.cloud import firestore
from google.oauth2 import service_account

def try_cloud_client():
    cred = service_account.Credentials.from_service_account_file("serviceAccountKey.json")
    db = firestore.Client(project="medpal-dev-493103", credentials=cred, database="medpal-dev-493103")
    docs = db.collection("test").limit(1).get()
    print("SUCCESS with google.cloud.firestore.Client!")

if __name__ == "__main__":
    try_cloud_client()
