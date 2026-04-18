from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional
import httpx
import os

# Production Domain from Git Repo: https://api.medpal-backend.xyz
BASE_URL = os.getenv("BASE_URL", "https://api.medpal-backend.xyz")

router = APIRouter(prefix="/agent2", tags=["Agent 2 - Navigation & Routing"])

# --- Models ---

class HospitalRequest(BaseModel):
    lat: float
    lng: float
    radius: Optional[int] = 5000

class HospitalResponse(BaseModel):
    name: str
    address: str
    open_status: str
    lat: float
    lng: float
    photo_url: Optional[str] = None

class NavigateRequest(BaseModel):
    session_id: str
    hospital_name: str

class NavigateResponse(BaseModel):
    steps: List[str]
    map_image_url: Optional[str] = None

class UpdateDeptRequest(BaseModel):
    session_id: str
    department: str

class UpdateDeptResponse(BaseModel):
    status: str
    next_steps: List[str]

import json

# --- Helpers & Mocks ---

GOOGLE_MAPS_API_KEY = os.getenv("GOOGLE_MAPS_API_KEY", "AIzaSyAnzgVLFFHAIF-mS8sHWI_kAKNJo4btE98")

# Load Hospital E Mock Data
MOCK_DATA_PATH = os.path.join(os.path.dirname(__file__), "..", "mock_data", "hospital_e.json")
try:
    with open(MOCK_DATA_PATH, "r", encoding="utf-8") as f:
        HOSPITAL_E_DATA = json.load(f)
        MOCK_BUILDINGS = HOSPITAL_E_DATA["buildings"]
        MOCK_MAPPING = HOSPITAL_E_DATA["mapping"]
        HOSPITAL_E_NAME = HOSPITAL_E_DATA.get("name", "Bệnh viện E")
        HOSPITAL_E_ADDR = HOSPITAL_E_DATA.get("address", "89 Trần Cung, Nghĩa Tân, Cầu Giấy, Hà Nội")
except Exception as e:
    print(f"Error loading mock data: {e}")
    MOCK_BUILDINGS = {}
    MOCK_MAPPING = []
    HOSPITAL_E_NAME = "Bệnh viện E"
    HOSPITAL_E_ADDR = "89 Trần Cung, Nghĩa Tân, Cầu Giấy, Hà Nội"

# --- Endpoints ---

@router.post("/hospitals", response_model=List[HospitalResponse])
async def get_hospitals(req: HospitalRequest):
    """
    Fetches REAL hospitals near the user's GPS coordinates using Google Places API.
    """
    url = (
        f"https://maps.googleapis.com/maps/api/place/nearbysearch/json"
        f"?location={req.lat},{req.lng}"
        f"&radius={req.radius}"
        f"&type=hospital"
        f"&language=vi"
        f"&key={GOOGLE_MAPS_API_KEY}"
    )

    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(url, timeout=10.0)
            data = response.json()

        if data.get("status") != "OK":
            # If Google fails, we might return an empty list or a specific error
            if data.get("status") == "ZERO_RESULTS":
                return []
            raise HTTPException(status_code=500, detail=f"Google API Error: {data.get('status')}")

        results = data.get("results", [])[:5]  # Take top 5
        hospitals = []
        
        # --- MOCK BỆNH VIỆN E MVP ---
        hospitals.append(HospitalResponse(
            name=HOSPITAL_E_NAME,
            address=HOSPITAL_E_ADDR,
            open_status="Mở cửa 24/7",
            lat=MOCK_BUILDINGS["Tòa E"]["lat"],
            lng=MOCK_BUILDINGS["Tòa E"]["lng"],
            photo_url=None
        ))

        for p in results:
            geo = p.get("geometry", {}).get("location", {})
            
            # Fetch Photo URL if available
            photo_url = None
            photos = p.get("photos", [])
            if photos:
                ref = photos[0].get("photo_reference")
                # Photo Proxy to avoid CORS blocks on Browser
                photo_url = f"{BASE_URL}/agent2/photo?ref={ref}"

            hospitals.append(HospitalResponse(
                name=p.get("name", "Bệnh viện"),
                address=p.get("vicinity", "Không rõ địa chỉ"),
                open_status="Đang mở cửa" if p.get("opening_hours", {}).get("open_now") else "Mở cửa 24/7",
                lat=geo.get("lat"),
                lng=geo.get("lng"),
                photo_url=photo_url
            ))
        
        return hospitals

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/navigate", response_model=NavigateResponse)
async def navigate(req: NavigateRequest):
    if not req.session_id or not req.hospital_name:
        raise HTTPException(status_code=400, detail="Missing session_id or hospital_name")
    
    # In a real app, this might use a graph-based routing algorithm or a map service
    return {
        "steps": [
            f"Đi thẳng 50m đến tiền sảnh {req.hospital_name}",
            "Rẽ trái ở quầy lễ tân A",
            "Lên thang máy số 3 tới phòng 204"
        ],
        "map_image_url": f"{BASE_URL}/static/maps/default.png"
    }

@router.post("/update-dept", response_model=UpdateDeptResponse)
async def update_dept(req: UpdateDeptRequest):
    # Match department in Mock DB
    for item in MOCK_MAPPING:
        if req.department.lower() in item["khoa"].lower() or item["khoa"].lower() in req.department.lower():
            toa_name = item["toa"]
            tang = item["tang"]
            room = item.get("phong")
            
            steps = [
                f"Di chuyển đến {toa_name}",
                f"Sử dụng thang máy hoặc thang bộ lên Tầng {tang}",
                f"Tìm biển báo hướng dẫn đến {item['khoa']}{f' (Phòng {room})' if room else ''} tại Tầng {tang}"
            ]
            
            return {
                "status": "updated",
                "next_steps": steps
            }

    return {
        "status": "updated",
        "next_steps": [
            f"Đi dọc hành lang đến {req.department}",
            "Rẽ phải tại biển báo chỉ dẫn",
            "Phòng khám ở cuối dãy"
        ]
    }

@router.get("/building-coords")
async def get_building_coords(department: str):
    for item in MOCK_MAPPING:
        if department.lower() in item["khoa"].lower() or item["khoa"].lower() in department.lower():
            toa_name = item["toa"]
            if toa_name in MOCK_BUILDINGS:
                return {
                    "department": item["khoa"],
                    "building_name": toa_name,
                    "lat": MOCK_BUILDINGS[toa_name]["lat"],
                    "lng": MOCK_BUILDINGS[toa_name]["lng"]
                }
    
    # Defaults to Tòa E if not found
    return {
        "department": department,
        "building_name": "Tòa E",
        "lat": MOCK_BUILDINGS["Tòa E"]["lat"],
        "lng": MOCK_BUILDINGS["Tòa E"]["lng"]
    }

@router.get("/geocoding")
async def reverse_geocode(lat: float, lng: float):
    """Converts coordinates to a Vietnamese address via Google Geocoding API."""
    url = (
        "https://maps.googleapis.com/maps/api/geocode/json"
        f"?latlng={lat},{lng}"
        "&language=vi"
        f"&key={GOOGLE_MAPS_API_KEY}"
    )
    async with httpx.AsyncClient() as client:
        try:
            res = await client.get(url, timeout=10.0)
            data = res.json()
            if data['status'] == 'OK' and data['results']:
                return {"address": data['results'][0]['formatted_address']}
            return {"address": "Không xác định được vị trí"}
        except:
            return {"address": "Không xác định được vị trí"}

@router.get("/photo")
async def proxy_photo(ref: str):
    """Proxies photo requests to Google to avoid CORS blocks on Web."""
    url = (
        "https://maps.googleapis.com/maps/api/place/photo"
        "?maxwidth=400"
        f"&photo_reference={ref}"
        f"&key={GOOGLE_MAPS_API_KEY}"
    )
    from fastapi.responses import RedirectResponse
    return RedirectResponse(url)
