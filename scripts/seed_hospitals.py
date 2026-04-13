import firebase_admin
from firebase_admin import credentials, firestore
import os
from dotenv import load_dotenv

load_dotenv()

cred = credentials.Certificate("secrets/medpal-dev-dda57-firebase-adminsdk-fbsvc-39d9c09b3a.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

hospital_data = {
    "hospital_id": "bv_mock_01",
    "name": "Bệnh viện Đa Khoa Mẫu",
    "address": "123 Phố Mẫu, Hoàn Kiếm, Hà Nội",
    "entrance_coords": {"lat": 21.028, "lng": 105.834},
    "departments": [
        {"id": "tq",           "name": "Phòng Khám Tổng Quát", "floor": 1, "building": "A", "room": "105"},
        {"id": "ho_hap",       "name": "Khoa Hô Hấp",          "floor": 2, "building": "A", "room": "201"},
        {"id": "tieu_hoa",     "name": "Khoa Tiêu Hóa",        "floor": 2, "building": "A", "room": "205"},
        {"id": "da_lieu",      "name": "Khoa Da Liễu",         "floor": 2, "building": "B", "room": "210"},
        {"id": "co_xuong_khop","name": "Khoa Cơ Xương Khớp",  "floor": 3, "building": "B", "room": "301"},
        {"id": "tim_mach",     "name": "Khoa Tim Mạch",        "floor": 3, "building": "C", "room": "305"},
    ],
    "waypoints": [
        {
            "from": "entrance", "to": "tq",
            "steps": [
                "Từ cổng chính đi thẳng 40m",
                "Rẽ phải tại biển Nhà A",
                "Phòng 105 bên tay trái"
            ]
        },
        {
            "from": "entrance", "to": "ho_hap",
            "steps": [
                "Từ cổng chính đi thẳng 40m",
                "Rẽ phải vào Nhà A",
                "Lên cầu thang tầng 2",
                "Phòng 201 bên tay phải"
            ]
        },
        {
            "from": "entrance", "to": "tieu_hoa",
            "steps": [
                "Từ cổng chính đi thẳng 40m",
                "Rẽ phải vào Nhà A",
                "Lên cầu thang tầng 2",
                "Phòng 205 cuối hành lang"
            ]
        },
        {
            "from": "entrance", "to": "da_lieu",
            "steps": [
                "Từ cổng chính đi thẳng 60m",
                "Rẽ trái vào Nhà B",
                "Lên thang máy tầng 2",
                "Phòng 210 bên tay phải"
            ]
        },
        {
            "from": "entrance", "to": "co_xuong_khop",
            "steps": [
                "Từ cổng chính đi thẳng 60m",
                "Rẽ trái vào Nhà B",
                "Lên thang máy tầng 3",
                "Phòng 301 bên tay trái"
            ]
        },
        {
            "from": "entrance", "to": "tim_mach",
            "steps": [
                "Từ cổng chính đi thẳng 80m",
                "Rẽ trái vào Nhà C",
                "Lên thang máy tầng 3",
                "Phòng 305 bên tay phải"
            ]
        },
    ]
}

# Upsert vào Firestore
db.collection("hospitals").document("bv_mock_01").set(hospital_data)
print("✅ Hospital mock data inserted successfully!")

# Verify
doc = db.collection("hospitals").document("bv_mock_01").get()
data = doc.to_dict()
print(f"✅ Verified: {data['name']} - {len(data['departments'])} khoa, {len(data['waypoints'])} waypoints")