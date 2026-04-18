"""
FPT Cloud Whisper Speech-to-Text Service (Synchronous)
Sử dụng model FPT.AI-whisper-medium đã được fine-tune cho Tiếng Việt.
"""
import os
import tempfile
import base64
import httpx

# ── Config ─────────────────────────────────────────
WHISPER_API_URL = "https://mkp-api.fptcloud.com/v1/audio/transcriptions"
WHISPER_API_KEY = os.environ.get(
    "FPT_WHISPER_API_KEY",
    "sk-w1k463lYF3vS9keWrT7vEYGq6i-IN1Q7vtBFAgLNJUs="
)
WHISPER_MODEL = os.environ.get("FPT_WHISPER_MODEL", "FPT.AI-whisper-medium")


def transcribe_audio_base64(audio_base64: str, language: str = "vi") -> str:
    """
    Nhận audio dạng base64, gửi đến FPT Whisper API, trả về text transcript.

    Args:
        audio_base64: Chuỗi base64 của file audio (wav/mp3/m4a/webm)
        language: Ngôn ngữ nhận dạng (mặc định: vi - Tiếng Việt)

    Returns:
        Chuỗi text đã được nhận dạng từ giọng nói

    Raises:
        Exception: Khi API trả về lỗi hoặc không thể giải mã audio
    """
    # Decode base64 thành bytes
    try:
        audio_bytes = base64.b64decode(audio_base64)
    except Exception as e:
        raise Exception(f"Không thể decode audio base64: {e}")

    # Xác định extension dựa trên magic bytes của file
    ext = _detect_audio_format(audio_bytes)
    print(f"[STT] Detected audio format: {ext}, size: {len(audio_bytes)} bytes")

    # Ghi ra file tạm để gửi qua multipart/form-data
    with tempfile.NamedTemporaryFile(suffix=f".{ext}", delete=False) as tmp:
        tmp.write(audio_bytes)
        tmp_path = tmp.name

    try:
        with open(tmp_path, "rb") as audio_file:
            response = httpx.post(
                WHISPER_API_URL,
                headers={
                    "Authorization": f"Bearer {WHISPER_API_KEY}",
                },
                data={
                    "model": WHISPER_MODEL,
                    "response_format": "json",
                    "language": language,
                },
                files={
                    "file": (f"audio.{ext}", audio_file, f"audio/{ext}"),
                },
                timeout=60.0,
            )

        if response.status_code != 200:
            raise Exception(
                f"Whisper API error {response.status_code}: {response.text}"
            )

        result = response.json()
        transcript = result.get("text", "").strip()

        if not transcript:
            raise Exception("Whisper API trả về transcript rỗng.")

        print(f"[STT] Transcript: {transcript}")
        return transcript

    finally:
        # Dọn file tạm
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


def _detect_audio_format(audio_bytes: bytes) -> str:
    """Phát hiện định dạng audio dựa trên magic bytes."""
    if audio_bytes[:4] == b"RIFF":
        return "wav"
    if audio_bytes[:3] == b"ID3" or audio_bytes[:2] == b"\xff\xfb":
        return "mp3"
    if audio_bytes[:4] == b"fLaC":
        return "flac"
    if audio_bytes[:4] == b"\x1aE\xdf\xa3":
        return "webm"
    if len(audio_bytes) > 8 and audio_bytes[4:8] == b"ftyp":
        return "m4a"
    # Fallback: dùng wav
    return "wav"
