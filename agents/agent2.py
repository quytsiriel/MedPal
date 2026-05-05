from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional
import httpx
import os
import json
import difflib
import re
import math
import heapq

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
    place_id: Optional[str] = None

class NavigateRequest(BaseModel):
    session_id: str
    hospital_name: str

class NavigateResponse(BaseModel):
    steps: List[str]
    map_image_url: Optional[str] = None

class UpdateDeptRequest(BaseModel):
    session_id: str
    department: str
    from_department: Optional[str] = None  # For cross-dept routing

class UpdateDeptResponse(BaseModel):
    status: str
    next_steps: List[str]

# --- Config ---

GOOGLE_MAPS_API_KEY = os.getenv("GOOGLE_MAPS_API_KEY", "AIzaSyAnzgVLFFHAIF-mS8sHWI_kAKNJo4btE98")

MOCK_DATA_PATH = os.path.join(os.path.dirname(__file__), "..", "mock_data", "hospital_e.json")
try:
    with open(MOCK_DATA_PATH, "r", encoding="utf-8") as f:
        HOSPITAL_E_DATA = json.load(f)
        MOCK_BUILDINGS = HOSPITAL_E_DATA["buildings"]
        MOCK_MAPPING   = HOSPITAL_E_DATA["mapping"]
        HOSPITAL_E_NAME = HOSPITAL_E_DATA.get("name", "Bệnh viện E")
        HOSPITAL_E_ADDR = HOSPITAL_E_DATA.get("address", "89 Trần Cung, Nghĩa Tân, Cầu Giấy, Hà Nội")
except Exception as e:
    print(f"Error loading mock data: {e}")
    MOCK_BUILDINGS = {}
    MOCK_MAPPING   = []
    HOSPITAL_E_NAME = "Bệnh viện E"
    HOSPITAL_E_ADDR = "89 Trần Cung, Nghĩa Tân, Cầu Giấy, Hà Nội"

# ============================================================
#  INDOOR A* NAVIGATION ENGINE
#  Coordinate system: metres from hospital main gate
#  +Y = north (deeper into hospital), +X = east
# ============================================================

_NODES: dict = {
    # ── Outdoor ──────────────────────────────────────────────
    "hosp_gate":     {"x":   0, "y":   0, "type": "entrance",         "label": "Cổng chính Bệnh viện E"},
    "main_hall":     {"x":   0, "y":  20, "type": "corridor",          "label": "Sảnh chính"},
    "outdoor_junc":  {"x":   0, "y":  45, "type": "corridor",          "label": "Sân trung tâm"},
    "right_fork":    {"x":  15, "y":  55, "type": "corridor",          "label": "Hành lang phía đông"},
    "left_fork":     {"x": -35, "y":  25, "type": "corridor",          "label": "Hành lang phía tây"},
    # ── Building entrances ────────────────────────────────────
    "toa_e_gate":    {"x":   0, "y":  65, "type": "building_entrance", "label": "Cổng vào Tòa E", "building": "Tòa E"},
    "toa_b_gate":    {"x":  12, "y":  73, "type": "building_entrance", "label": "Cổng vào Tòa B", "building": "Tòa B"},
    "toa_c_gate":    {"x":  22, "y":  83, "type": "building_entrance", "label": "Cổng vào Tòa C", "building": "Tòa C"},
    "toa_g_gate":    {"x":  18, "y":  96, "type": "building_entrance", "label": "Cổng vào Tòa G", "building": "Tòa G"},
    "toa_f_gate":    {"x": -55, "y":  28, "type": "building_entrance", "label": "Cổng vào Tòa F", "building": "Tòa F"},
    "toa_a_gate":    {"x": -55, "y":   8, "type": "building_entrance", "label": "Cổng vào Tòa A", "building": "Tòa A"},
}

_EDGES: list = [
    ("hosp_gate",   "main_hall"),
    ("main_hall",   "outdoor_junc"),
    ("outdoor_junc","toa_e_gate"),
    ("outdoor_junc","right_fork"),
    ("right_fork",  "toa_b_gate"),
    ("toa_b_gate",  "toa_c_gate"),
    ("toa_c_gate",  "toa_g_gate"),
    ("main_hall",   "left_fork"),
    ("left_fork",   "toa_f_gate"),
    ("left_fork",   "toa_a_gate"),
]

_BUILDING_GATE_MAP: dict = {
    "Tòa E": "toa_e_gate",
    "Tòa B": "toa_b_gate",
    "Tòa C": "toa_c_gate",
    "Tòa G": "toa_g_gate",
    "Tòa F": "toa_f_gate",
    "Tòa A": "toa_a_gate",
}


def _node_dist(a: dict, b: dict) -> float:
    return math.sqrt((a["x"] - b["x"]) ** 2 + (a["y"] - b["y"]) ** 2)


def _astar(start_id: str, goal_id: str) -> list:
    """A* on the outdoor hospital node graph. Returns list of node IDs."""
    adj: dict = {k: [] for k in _NODES}
    for a, b in _EDGES:
        d = _node_dist(_NODES[a], _NODES[b])
        adj[a].append((d, b))
        adj[b].append((d, a))

    h = lambda nid: _node_dist(_NODES[nid], _NODES[goal_id])
    heap = [(h(start_id), 0.0, start_id, [start_id])]
    visited: set = set()

    while heap:
        _, g, curr, path = heapq.heappop(heap)
        if curr == goal_id:
            return path
        if curr in visited:
            continue
        visited.add(curr)
        for cost, nb in adj[curr]:
            if nb not in visited:
                ng = g + cost
                heapq.heappush(heap, (ng + h(nb), ng, nb, path + [nb]))

    return [start_id, goal_id]


def _cross_z(ax, ay, bx, by, cx, cy) -> float:
    """Z-component of cross-product AB × BC."""
    return (bx - ax) * (cy - by) - (by - ay) * (cx - bx)


def _turn_label(ax, ay, bx, by, cx, cy) -> str:
    """'trái', 'phải', or '' (straight)."""
    cross = _cross_z(ax, ay, bx, by, cx, cy)
    # dot product to check if nearly straight
    v1x, v1y = bx - ax, by - ay
    v2x, v2y = cx - bx, cy - by
    dot = v1x * v2x + v1y * v2y
    m1 = math.sqrt(v1x ** 2 + v1y ** 2) or 1
    m2 = math.sqrt(v2x ** 2 + v2y ** 2) or 1
    cos_a = max(-1.0, min(1.0, dot / (m1 * m2)))
    angle = math.degrees(math.acos(cos_a))
    if angle < 20:
        return ""
    return "trái" if cross > 0 else "phải"


def _outdoor_steps(node_path: list) -> list:
    """Convert A* node path → human-readable outdoor steps."""
    steps = []
    for i in range(len(node_path) - 1):
        curr_id = node_path[i]
        next_id = node_path[i + 1]
        curr = _NODES[curr_id]
        nxt  = _NODES[next_id]
        dist_m = max(1, int(_node_dist(curr, nxt)))

        turn = ""
        if i > 0:
            prev = _NODES[node_path[i - 1]]
            turn = _turn_label(prev["x"], prev["y"],
                               curr["x"], curr["y"],
                               nxt["x"],  nxt["y"])

        ntype = nxt["type"]
        if ntype == "building_entrance":
            lbl = nxt["label"]
            if turn:
                steps.append(f"Rẽ {turn} sau {dist_m}m, đến {lbl}")
            else:
                steps.append(f"Đi thẳng {dist_m}m đến {lbl}")
        elif ntype in ("corridor", "entrance"):
            if turn:
                steps.append(f"Rẽ {turn} sau {dist_m}m")
            elif dist_m >= 8:
                steps.append(f"Đi thẳng {dist_m}m")
    return steps


def _vertical_steps(building: str, from_floor: int, to_floor: int) -> list:
    """Generate elevator/stairs instruction for floor change."""
    if from_floor == to_floor:
        return []
    delta = to_floor - from_floor
    direction = "lên" if delta > 0 else "xuống"
    use_elevator = abs(delta) >= 2
    transport = "thang máy" if use_elevator else "thang bộ"
    return [f"{direction.capitalize()} {transport} đến Tầng {to_floor}"]


def _corridor_to_dept(dept_name: str, dept_index: int, floor: int) -> list:
    """Generate corridor steps from floor lobby to the department."""
    # Deterministic directions derived from dept_index so they're consistent
    dist1 = 10 + (dept_index % 4) * 5   # 10, 15, 20, 25 m
    dist2 = 5  + (dept_index % 3) * 5   # 5, 10, 15 m
    turn  = "trái" if dept_index % 2 == 0 else "phải"
    steps = [
        f"Từ khu thang, đi thẳng {dist1}m dọc hành lang Tầng {floor}",
        f"Rẽ {turn} sau {dist2}m vào {dept_name}",
    ]
    return steps


# ── Dept lookup helpers ───────────────────────────────────────

def _find_dept(name: str) -> Optional[dict]:
    """Fuzzy-match department name in MOCK_MAPPING."""
    low = name.lower()
    for item in MOCK_MAPPING:
        if low in item["khoa"].lower() or item["khoa"].lower() in low:
            return item
    dept_names = [i["khoa"] for i in MOCK_MAPPING]
    matches = difflib.get_close_matches(name, dept_names, n=1, cutoff=0.4)
    if matches:
        for item in MOCK_MAPPING:
            if item["khoa"] == matches[0]:
                return item
    stop = {'khoa', 'phòng', 'bệnh', 'viện', 'tôi', 'bác', 'sĩ', 'với',
            'cần', 'đến', 'sang', 'bảo', 'là', 'vào', 'ở', 'tại', 'của'}
    tokens_in = {t for t in re.findall(r'\w+', low) if t not in stop}
    best, best_score = None, 0
    for item in MOCK_MAPPING:
        tokens_dept = {t for t in re.findall(r'\w+', item["khoa"].lower()) if t not in stop}
        score = len(tokens_in & tokens_dept)
        if score > best_score:
            best_score = score
            best = item
    if best and best_score >= 2:
        return best
    return None


# ── Main hierarchical pathfinder ─────────────────────────────

def build_indoor_path(from_dept_name: Optional[str], to_dept_name: str) -> list:
    """
    Hierarchical A* pathfinding:
      1. Building  – outdoor walk from start → dest building entrance
      2. Floor     – elevator / stairs to the right floor
      3. Department – corridor to the department

    from_dept_name=None  →  start from hospital main gate.
    """
    # ── Resolve destination ──────────────────────────────────
    to_item = _find_dept(to_dept_name)
    if not to_item:
        return [f"Không tìm thấy thông tin về {to_dept_name}. Vui lòng hỏi lễ tân."]
    to_building  = to_item["toa"]
    to_floor     = to_item["tang"]
    to_dept_canonical = to_item["khoa"]
    to_idx = MOCK_MAPPING.index(to_item)

    # ── Resolve source ───────────────────────────────────────
    from_building: Optional[str] = None
    from_floor = 1
    if from_dept_name:
        from_item = _find_dept(from_dept_name)
        if from_item:
            from_building = from_item["toa"]
            from_floor    = from_item["tang"]

    # ── PHASE 1: Outdoor navigation (building → building) ────
    steps = []

    if from_building is None:
        # Start from hospital gate
        start_node = "hosp_gate"
    else:
        # Already inside a building — exit it first
        start_node = _BUILDING_GATE_MAP.get(from_building, "outdoor_junc")
        if from_building != to_building:
            steps.append(f"Ra khỏi {from_building}, hướng đến sân bệnh viện")

    goal_node = _BUILDING_GATE_MAP.get(to_building, "outdoor_junc")

    if start_node != goal_node:
        path = _astar(start_node, goal_node)
        outdoor = _outdoor_steps(path)
        steps.extend(outdoor)
    else:
        # Same building — skip outdoor steps
        if from_building:
            steps.append(f"Ở lại {to_building}, di chuyển đến khu thang")

    # ── PHASE 2: Vertical movement (floor) ───────────────────
    # If from_dept is in same building, we start from from_floor; else floor 1
    start_floor = from_floor if (from_building == to_building) else 1

    # "Enter building" step only when coming from outside
    if from_building != to_building or from_building is None:
        steps.append(f"Vào {to_building}, đi thẳng 15m đến khu thang")

    vert = _vertical_steps(to_building, start_floor, to_floor)
    steps.extend(vert)

    # ── PHASE 3: Corridor to department ─────────────────────
    corridor = _corridor_to_dept(to_dept_canonical, to_idx, to_floor)
    steps.extend(corridor)

    return steps


# ============================================================
#  ENDPOINTS
# ============================================================

@router.post("/hospitals", response_model=List[HospitalResponse])
async def get_hospitals(req: HospitalRequest):
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
            if data.get("status") == "ZERO_RESULTS":
                return []
            raise HTTPException(status_code=500, detail=f"Google API Error: {data.get('status')}")

        results = data.get("results", [])[:5]
        hospitals = []

        hospitals.append(HospitalResponse(
            name=HOSPITAL_E_NAME,
            address=HOSPITAL_E_ADDR,
            open_status="Mở cửa 24/7",
            lat=MOCK_BUILDINGS["Tòa E"]["lat"],
            lng=MOCK_BUILDINGS["Tòa E"]["lng"],
            photo_url=None,
            place_id="ChIJTz29XkOrNTERQ1d-5z72mB0"
        ))

        for p in results:
            geo = p.get("geometry", {}).get("location", {})
            photo_url = None
            photos = p.get("photos", [])
            if photos:
                ref = photos[0].get("photo_reference")
                photo_url = f"{BASE_URL}/agent2/photo?ref={ref}"
            hospitals.append(HospitalResponse(
                name=p.get("name", "Bệnh viện"),
                address=p.get("vicinity", "Không rõ địa chỉ"),
                open_status="Đang mở cửa" if p.get("opening_hours", {}).get("open_now") else "Mở cửa 24/7",
                lat=geo.get("lat"),
                lng=geo.get("lng"),
                photo_url=photo_url,
                place_id=p.get("place_id")
            ))

        return hospitals

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/navigate", response_model=NavigateResponse)
async def navigate(req: NavigateRequest):
    if not req.session_id or not req.hospital_name:
        raise HTTPException(status_code=400, detail="Missing session_id or hospital_name")
    return {
        "steps": [
            f"Đi thẳng 50m đến tiền sảnh {req.hospital_name}",
            "Rẽ trái ở quầy lễ tân",
            "Lên thang máy số 3 tới tầng 2"
        ],
        "map_image_url": f"{BASE_URL}/static/maps/default.png"
    }


@router.post("/update-dept")
async def update_dept(req: UpdateDeptRequest):
    """
    Hierarchical indoor pathfinding from (from_department | hospital gate) → department.
    Returns step-by-step directions using A* on the hospital node graph.
    """
    steps = build_indoor_path(
        from_dept_name=req.from_department,
        to_dept_name=req.department,
    )

    # Also resolve canonical name for status message
    to_item = _find_dept(req.department)
    canonical = to_item["khoa"] if to_item else req.department
    toa = to_item["toa"] if to_item else "?"
    tang = to_item["tang"] if to_item else "?"

    return {
        "status": "updated",
        "department": canonical,
        "building": toa,
        "floor": tang,
        "next_steps": steps,
        "steps": steps,   # compat alias
    }


@router.get("/building-coords")
async def get_building_coords(department: str):
    # 1. Exact / substring match
    for item in MOCK_MAPPING:
        if department.lower() in item["khoa"].lower() or item["khoa"].lower() in department.lower():
            toa_name = item["toa"]
            if toa_name in MOCK_BUILDINGS:
                return {
                    "department": item["khoa"],
                    "building_name": toa_name,
                    "lat": MOCK_BUILDINGS[toa_name]["lat"],
                    "lng": MOCK_BUILDINGS[toa_name]["lng"],
                    "floor": item["tang"],
                }

    # 2. Fuzzy match
    dept_names = [item["khoa"] for item in MOCK_MAPPING]
    matches = difflib.get_close_matches(department, dept_names, n=1, cutoff=0.4)
    if matches:
        for item in MOCK_MAPPING:
            if item["khoa"] == matches[0]:
                toa_name = item["toa"]
                return {
                    "department": item["khoa"],
                    "building_name": toa_name,
                    "lat": MOCK_BUILDINGS[toa_name]["lat"],
                    "lng": MOCK_BUILDINGS[toa_name]["lng"],
                    "floor": item["tang"],
                }

    # 3. Token-based keyword match
    stop = {'khoa', 'phòng', 'bệnh', 'viện', 'tôi', 'bác', 'sĩ', 'với',
            'cần', 'đến', 'sang', 'bảo', 'là', 'vào', 'ở', 'tại', 'của'}
    tokens_in = {t for t in re.findall(r'\w+', department.lower()) if t not in stop}
    best_item, max_overlap = None, 0
    for item in MOCK_MAPPING:
        dept_tokens = {t for t in re.findall(r'\w+', item["khoa"].lower()) if t not in stop}
        overlap = len(tokens_in & dept_tokens)
        if overlap > max_overlap:
            max_overlap = overlap
            best_item = item
    if best_item and len(tokens_in) > 0:
        ratio = max_overlap / len(tokens_in)
        if ratio >= 0.6 or max_overlap >= 2:
            toa_name = best_item["toa"]
            return {
                "department": best_item["khoa"],
                "building_name": toa_name,
                "lat": MOCK_BUILDINGS[toa_name]["lat"],
                "lng": MOCK_BUILDINGS[toa_name]["lng"],
                "floor": best_item["tang"],
            }

    raise HTTPException(status_code=404, detail="Không tìm thấy khoa bạn cần.")


@router.get("/geocoding")
async def reverse_geocode(lat: float, lng: float):
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
        except Exception:
            pass
    return {"address": "Không xác định được vị trí"}


@router.get("/photo")
async def proxy_photo(ref: str):
    url = (
        "https://maps.googleapis.com/maps/api/place/photo"
        "?maxwidth=400"
        f"&photo_reference={ref}"
        f"&key={GOOGLE_MAPS_API_KEY}"
    )
    from fastapi.responses import RedirectResponse
    return RedirectResponse(url)
