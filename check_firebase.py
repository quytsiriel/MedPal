from services.firebase import get_db
import os

def check_firebase_status():
    print("--- FIREBASE STATUS CHECK ---")
    
    # Check if credentials file exists
    cred_path = os.path.join(os.getcwd(), "serviceAccountKey.json")
    print(f"Checking for serviceAccountKey.json at: {cred_path}")
    if os.path.exists(cred_path):
        print("RESULT: File found.")
    else:
        print("RESULT: File NOT found in current directory.")

    try:
        db = get_db()
        print("STATUS: Connected to REAL FIREBASE (Firestore)")
        project_id = db.project
        print(f"PROJECT ID: {project_id}")
        # Simple write-read test
        print("Running write-read test...")
        test_ref = db.collection("check_status").document("health")
        test_ref.set({"last_check": firestore.SERVER_TIMESTAMP if hasattr(firestore, "SERVER_TIMESTAMP") else "now"}, merge=True)
        print("Write test: SUCCESS")
        
        val = test_ref.get().to_dict()
        print(f"Read test: SUCCESS (Result: {val})")
        
    except Exception as e:
        print(f"ERROR during Firestore operation: {e}")
    
    print("------------------------------")

if __name__ == "__main__":
    try:
        from google.cloud import firestore
        check_firebase_status()
    except ImportError:
        print("ERROR: google-cloud-firestore not installed.")
