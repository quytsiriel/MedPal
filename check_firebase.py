from services.firebase import get_db, FakeFirestore
from google.cloud import firestore

def check_firebase_status():
    print("--- KIỂM TRA TRẠNG THÁI FIREBASE ---")
    db = get_db()
    
    if isinstance(db, FakeFirestore):
        print("STATUS: ⚠️ Đang chạy trên FAKE FIREBASE (In-memory Mock)")
        print("LÝ DO: Không tìm thấy file serviceAccountKey.json hoặc lỗi cấu hình xác thực.")
    else:
        print("STATUS: ✅ Đang chạy trên REAL FIREBASE (Google Cloud Firestore)")
        try:
            # Lấy thông tin dự án nếu là real client
            project_id = db.project
            print(f"PROJECT ID: {project_id}")
        except:
            pass
    
    print("------------------------------------")

if __name__ == "__main__":
    check_firebase_status()
