"""Check Latest Firebase Sessions"""
import sys, os
from datetime import datetime

# Adjust Python path to load MedPal modules
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from services.firebase import get_db

def _safe_str(val):
    if val is None:
        return "None"
    s = str(val).replace('\n', ' ')
    s = s.encode('ascii', 'ignore').decode('ascii')
    return s[:100] + "..." if len(s) > 100 else s

def main():
    try:
        db = get_db()
        docs = list(db.collection('sessions').get())
        print(f"Total sessions found: {len(docs)}\n")
        
        session_list = []
        for doc in docs:
            data = doc.to_dict()
            ts_raw = data.get('updated_at') or data.get('created_at')
            ts = str(ts_raw) if ts_raw else ""
            session_list.append((ts, doc.id, data))
        
        session_list.sort(key=lambda x: x[0], reverse=True)
        
        print("=== 5 MOST RECENT SESSIONS ===")
        for ts, sid, data in session_list[:5]:
            print(f"\n[Session ID]: {sid}")
            print(f"  Thoi gian: {ts}")
            print(f"  Trang thai (status): {data.get('status')}")
            if 'tasks_completed' in data:
                print(f"  Tasks completed: {len(data['tasks_completed'])}")
            if 'messages' in data:
                print(f"  Message count: {len(data['messages'])}")
                if data['messages']:
                    last_msg = data['messages'][-1]
                    print(f"  Last msg: [{last_msg.get('role')}] {_safe_str(last_msg.get('content'))}")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()
