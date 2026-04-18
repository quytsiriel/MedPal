from services.firebase import get_db

print("1. Đang kết nối...")
db = get_db()
print(f"2. DB type: {type(db)}")

print("3. Đang ghi...")
db.collection("test").document("ping").set({"status": "ok"})
print("4. Ghi xong")

print("5. Đang đọc...")
doc = db.collection("test").document("ping").get()
print(f"6. Kết quả: {doc.to_dict()}")
