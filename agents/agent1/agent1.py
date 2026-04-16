from openai import OpenAI
from rag import search
import json
import re
import os
from datetime import datetime

OLLAMA_BASE_URL = "http://124.197.18.16:11434"
OLLAMA_MODEL = "puyangwang/medgemma-27b-it:q6"

client = OpenAI(base_url=OLLAMA_BASE_URL, api_key="ollama")

SYSTEM_PROMPT = open("prompt.txt", encoding="utf-8").read()

# ── State ──────────────────────────────────────────
conversation_history = []
symptoms_accumulated = []

TASKS = [
    ("t21", "thời điểm và cách khởi phát triệu chứng"),
    ("t22", "vị trí, tính chất, mức độ triệu chứng"),
    ("t23", "diễn biến theo thời gian"),
    ("t24", "triệu chứng kèm theo"),
    ("t25", "đã khám hoặc dùng thuốc gì chưa"),
    ("t26", "tình trạng ăn ngủ, cân nặng gần đây"),
    ("t31", "bệnh mãn tính hoặc bệnh cũ"),
    ("t32", "tiêm chủng gần đây"),
    ("t33", "phẫu thuật hoặc chấn thương"),
    ("t34", "truyền máu"),
    ("t35", "dị ứng thuốc hoặc thực phẩm"),
]

task_scores = {tid: 0.0 for tid, _ in TASKS}

MEDICAL_KEYWORDS = [
    "thuốc", "uống thuốc", "paracetamol", "ibuprofen", "kháng sinh",
    "tiêm", "xét nghiệm", "siêu âm", "chụp x-quang", "nhập viện",
    "phẫu thuật", "bác sĩ kê", "đơn thuốc", "liều", "mg",
    "viên", "chai", "kem bôi", "nhỏ mắt", "truyền dịch"
]

EMERGENCY_KEYWORDS = [
    # Tim mạch
    "đau ngực", "tức ngực", "khó thở", "thở không được", "ngất", "ngất xỉu",
    "tim đập nhanh", "tim đập mạnh", "hồi hộp dữ dội",
    # Thần kinh
    "liệt", "tê liệt", "mất ý thức", "co giật", "đột quỵ",
    "méo miệng", "nói không được", "nói khó", "mắt mờ đột ngột",
    "đau đầu dữ dội", "đau đầu đột ngột",
    # Chấn thương / Chảy máu
    "chảy máu không cầm", "nôn ra máu", "đi ngoài ra máu", "tiểu ra máu",
    "tai nạn", "ngã từ cao", "chấn thương đầu",
    # Dị ứng nặng
    "sưng họng", "sưng lưỡi", "không nuốt được", "phát ban toàn thân",
    # Sốt cao / Nhiễm trùng nặng
    "sốt cao", "sốt 39", "sốt 40", "ớn lạnh run", "mê sảng", "lú lẫn",
    # Bụng cấp
    "đau bụng dữ dội", "đau bụng không chịu được", "bụng cứng",
    # Tự hại
    "muốn chết", "tự tử", "tự làm đau"
]

EMERGENCY_MESSAGE = (
    "⚠️ Tôi nhận thấy bạn đang mô tả triệu chứng có thể nghiêm trọng.\n"
    "Vui lòng gọi ngay cấp cứu 115 hoặc đến phòng cấp cứu gần nhất.\n"
    "Không nên chờ đợi."
)


# ── Helpers ────────────────────────────────────────
def get_next_task():
    for tid, desc in TASKS:
        if task_scores[tid] < 0.85:
            return tid, desc
    return None, None


def all_done():
    return all(s >= 0.85 for s in task_scores.values())


def build_task_status() -> str:
    lines = []
    for tid, desc in TASKS:
        score = task_scores[tid]
        mark = "✓" if score >= 0.85 else ("~" if score >= 0.4 else "○")
        lines.append(f"  {mark} {tid} ({desc}): {score:.1f}")
    return "\n".join(lines)


def detect_emergency(text: str) -> bool:
    text_lower = text.lower()
    return any(kw in text_lower for kw in EMERGENCY_KEYWORDS)


def validate_advice(advice: str) -> str:
    if not advice:
        return ""
    advice_lower = advice.lower()
    for kw in MEDICAL_KEYWORDS:
        if kw in advice_lower:
            return ""
    return advice


# ── LLM calls ──────────────────────────────────────
def score_tasks_from_history(history: list):
    if not history:
        return

    conversation_text = "\n".join(
        f"{'Bệnh nhân' if m['role'] == 'user' else 'Trợ lý'}: {m['content']}"
        for m in history
    )
    task_list = "\n".join(f"- {tid}: {desc}" for tid, desc in TASKS)

    scoring_prompt = f"""Đây là đoạn hội thoại giữa trợ lý y tế và bệnh nhân:

{conversation_text}

Đánh giá mức độ đã khai thác được thông tin cho từng mục sau.
Chỉ trả về JSON, không giải thích, không markdown.

Thang điểm:
- 1.0: có thông tin rõ ràng, đầy đủ
- 0.5: có đề cập nhưng chưa rõ hoặc chưa đủ
- 0.0: chưa được hỏi hoặc chưa có thông tin

Danh sách mục cần đánh giá:
{task_list}

Trả về đúng định dạng này:
{{"t21": 0.0, "t22": 0.0, "t23": 0.0, "t24": 0.0, "t25": 0.0, "t26": 0.0, "t31": 0.0, "t32": 0.0, "t33": 0.0, "t34": 0.0, "t35": 0.0}}"""

    try:
        response = client.chat.completions.create(
            model=OLLAMA_MODEL,
            messages=[{"role": "user", "content": scoring_prompt}],
            temperature=0
        )
        raw = response.choices[0].message.content.strip()
        match = re.search(r'\{.*\}', raw, re.DOTALL)
        if match:
            scores = json.loads(match.group())
            for tid in task_scores:
                if tid in scores:
                    task_scores[tid] = float(scores[tid])
    except Exception as e:
        print(f"[WARN] Scoring failed: {e}")


def generate_record() -> str:
    conversation_text = "\n".join(
        f"{'Bệnh nhân' if m['role'] == 'user' else 'Trợ lý'}: {m['content']}"
        for m in conversation_history
    )

    record_prompt = f"""Dựa trên đoạn hội thoại sau giữa trợ lý y tế và bệnh nhân:

{conversation_text}

Hãy tạo hồ sơ tiền khám hoàn chỉnh theo đúng định dạng sau.
Chỉ dùng thông tin bệnh nhân đã nói — không bịa, không suy diễn.
Mục nào chưa có thông tin → ghi [chưa khai thác].

---
HỒ SƠ TIỀN KHÁM
---

KHOA ĐỀ NGHỊ:
  - Khoa chính: [tự xác định dựa trên triệu chứng]
  - Chuyên khoa phụ: [nếu có]

LÝ DO KHÁM (CC):
  [1–2 câu tóm tắt]

LỊCH SỬ BỆNH HIỆN TẠI (HPI):
  - Khởi phát: [...]
  - Đặc điểm triệu chứng: [...]
  - Diễn biến: [...]
  - Triệu chứng kèm theo: [...]
  - Đã xử lý: [...]
  - Tình trạng chung: [...]

TIỀN SỬ (PH):
  - Bệnh cũ: [...]
  - Tiêm chủng: [...]
  - Phẫu thuật / Chấn thương: [...]
  - Truyền máu: [...]
  - Dị ứng: [...]

LỜI KHUYÊN SỨC KHỎE:
  [Chỉ gồm: nghỉ ngơi, uống nước, dinh dưỡng, theo dõi triệu chứng]
  [TUYỆT ĐỐI KHÔNG đề cập thuốc hoặc bất kỳ can thiệp y tế nào]
  [Nếu triệu chứng nghiêm trọng → bỏ mục này, chỉ nhắc gặp bác sĩ sớm]"""

    response = client.chat.completions.create(
        model=OLLAMA_MODEL,
        messages=[{"role": "user", "content": record_prompt}],
        temperature=0
    )
    return response.choices[0].message.content.strip()


def parse_record_to_json(record_text: str) -> dict:
    parse_prompt = f"""Đây là hồ sơ tiền khám dạng text:

{record_text}

Trích xuất thông tin và trả về JSON theo cấu trúc sau.
Chỉ trả về JSON, không giải thích, không markdown.
Nếu một trường không có thông tin → điền "[chưa khai thác]".

QUY TẮC cho "loi_khuyen_suc_khoe":
- Chỉ giữ nội dung về: nghỉ ngơi, uống nước, dinh dưỡng, theo dõi triệu chứng
- TUYỆT ĐỐI KHÔNG đề cập: tên thuốc, liều thuốc, tiêm, xét nghiệm,
  phẫu thuật, hoặc bất kỳ can thiệp y tế nào
- Nếu vi phạm → điền chuỗi rỗng ""

{{
  "khoa_de_nghi": {{
    "khoa_chinh": "",
    "chuyen_khoa_phu": ""
  }},
  "ly_do_kham": "",
  "hpi": {{
    "khoi_phat": "",
    "dac_diem_trieu_chung": "",
    "dien_bien": "",
    "trieu_chung_kem_theo": "",
    "da_xu_ly": "",
    "tinh_trang_chung": ""
  }},
  "ph": {{
    "benh_cu": "",
    "tiem_chung": "",
    "phau_thuat_chan_thuong": "",
    "truyen_mau": "",
    "di_ung": ""
  }},
  "loi_khuyen_suc_khoe": ""
}}"""

    try:
        response = client.chat.completions.create(
            model=OLLAMA_MODEL,
            messages=[{"role": "user", "content": parse_prompt}],
            temperature=0
        )
        raw = response.choices[0].message.content.strip()
        match = re.search(r'\{.*\}', raw, re.DOTALL)
        if match:
            return json.loads(match.group())
    except Exception as e:
        print(f"[WARN] Parse failed: {e}")
    return {}


def save_record(record: dict, record_text: str, emergency: bool = False):
    os.makedirs("data/output", exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    prefix = "emergency" if emergency else "record"
    filepath = f"data/output/{prefix}_{timestamp}.json"

    if "loi_khuyen_suc_khoe" in record:
        record["loi_khuyen_suc_khoe"] = validate_advice(
            record["loi_khuyen_suc_khoe"]
        )

    output = {
        "timestamp": datetime.now().isoformat(),
        "emergency": emergency,
        "task_scores": {tid: task_scores[tid] for tid, _ in TASKS},
        "conversation": conversation_history,
        "record_text": record_text,
        "record": record
    }

    with open(filepath, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    label = "[⚠️] Emergency log" if emergency else "[✓] Hồ sơ"
    print(f"\n{label} đã lưu: {filepath}")
    return filepath


def save_emergency_record(trigger_text: str):
    os.makedirs("data/output", exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filepath = f"data/output/emergency_{timestamp}.json"

    output = {
        "timestamp": datetime.now().isoformat(),
        "emergency": True,
        "trigger_text": trigger_text,
        "task_scores": {tid: task_scores[tid] for tid, _ in TASKS},
        "conversation": conversation_history,
        "record": None
    }

    with open(filepath, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    print(f"\n[⚠️] Emergency log đã lưu: {filepath}")
    return filepath


# ── Main loop ──────────────────────────────────────
print("=== MEDICAL AGENT (OLLAMA + RAG) ===\n")

is_first_turn = True

while True:
    user_input = input("User: ").strip()
    if user_input.lower() == "exit":
        break
    if not user_input:
        continue

    # ── EMERGENCY CHECK — ưu tiên tuyệt đối ──────
    if detect_emergency(user_input):
        conversation_history.append({"role": "user", "content": user_input})
        conversation_history.append({"role": "assistant", "content": EMERGENCY_MESSAGE})
        print(f"\nAI: {EMERGENCY_MESSAGE}\n")
        save_emergency_record(trigger_text=user_input)
        print("\n[✓] Kết thúc phiên — emergency.")
        break

    # ── Luồng bình thường ─────────────────────────
    symptoms_accumulated.append(user_input)
    rag_query = " ".join(symptoms_accumulated[-5:])
    context = "\n".join(search(rag_query))

    conversation_history.append({"role": "user", "content": user_input})

    if not is_first_turn:
        score_tasks_from_history(conversation_history)
        print(f"[DEBUG] { {tid: f'{task_scores[tid]:.1f}' for tid, _ in TASKS} }\n")

    # ── Kiểm tra all_done TRƯỚC khi hỏi tiếp ─────
    if not is_first_turn and all_done():
        print("\n[...] Đã đủ thông tin. Đang tạo hồ sơ...\n")

        record_text = generate_record()
        print(f"AI: {record_text}\n")

        print("[...] Đang chuyển đổi sang JSON...")
        record_json = parse_record_to_json(record_text)
        save_record(record_json, record_text, emergency=False)

        print("\n[✓] Kết thúc phiên.")
        break

    # ── Tiếp tục hỏi ──────────────────────────────
    current_task_id, current_task_desc = get_next_task()

    if is_first_turn:
        instruction = (
            "Đây là lượt đầu tiên. "
            "Chào bệnh nhân thật ngắn gọn (một câu), "
            "sau đó hỏi ngay về thời điểm và cách khởi phát của triệu chứng họ vừa mô tả. "
            "Không hỏi bệnh nhân muốn khám khoa nào — việc đó do bạn tự quyết định."
        )
        is_first_turn = False
    else:
        task_status = build_task_status()
        instruction = (
            f"TRẠNG THÁI CÁC NHIỆM VỤ:\n"
            f"  ✓ = đã đủ thông tin | ~ = chưa rõ | ○ = chưa hỏi\n"
            f"{task_status}\n\n"
            f"NHIỆM VỤ TIẾP THEO: hỏi về '{current_task_desc}'.\n"
            f"Chỉ hỏi đúng một câu tự nhiên, ngắn gọn.\n"
            f"KHÔNG hỏi lại bất kỳ mục nào đã đánh dấu ✓."
        )

    messages_to_send = [
        {
            "role": "system",
            "content": (
                f"{SYSTEM_PROMPT}\n\n"
                f"---\n"
                f"DỮ LIỆU THAM KHẢO NỘI BỘ "
                f"(hồ sơ bệnh nhân KHÁC — không đọc cho bệnh nhân, "
                f"chỉ dùng để hiểu ngữ cảnh lâm sàng, "
                f"KHÔNG dùng làm thông tin của bệnh nhân hiện tại):\n"
                f"{context}\n"
                f"---"
            )
        }
    ]

    for msg in conversation_history[:-1]:
        messages_to_send.append({"role": msg["role"], "content": msg["content"]})

    messages_to_send.append({
        "role": "user",
        "content": f"{user_input}\n\n[HƯỚNG DẪN]\n{instruction}"
    })

    response = client.chat.completions.create(
        model=OLLAMA_MODEL,
        messages=messages_to_send
    )

    ai_reply = response.choices[0].message.content.strip()
    conversation_history.append({"role": "assistant", "content": ai_reply})

    print(f"\nAI: {ai_reply}\n")