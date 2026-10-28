#!/usr/bin/env python3
import glob
import json
import os
import sys
import time

STATUS_DIR = os.path.expanduser("~/.devin-status")
os.makedirs(STATUS_DIR, exist_ok=True)

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

event = data.get("hook_event_name", "")
sid = data.get("session_id") or "unknown"
tool = data.get("tool_name", "")
project = os.path.basename(os.environ.get("DEVIN_PROJECT_DIR", "") or "") or "?"

path = os.path.join(STATUS_DIR, f"{sid}.json")

if event == "SessionEnd":
    try:
        os.remove(path)
    except OSError:
        pass
    sys.exit(0)

state = {
    "SessionStart": "starting",
    "UserPromptSubmit": "working",
    "PermissionRequest": "permission",
    "Stop": "waiting",
    "PostCompaction": "working",
    "PreToolUse": "question" if tool == "ask_user_question" else "working",
    "PostToolUse": "working",
}.get(event)

if state is None:
    sys.exit(0)

rec = {}
if os.path.exists(path):
    try:
        with open(path) as f:
            rec = json.load(f)
    except Exception:
        rec = {}

rec.update({
    "session_id": sid,
    "state": state,
    "ts": time.time(),
    "tool": tool,
    "project": project if project != "?" else rec.get("project", "?"),
})
rec.setdefault("created", time.time())

tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(rec, f)
os.replace(tmp, path)

now = time.time()
for f in glob.glob(os.path.join(STATUS_DIR, "*.json")):
    try:
        if now - os.path.getmtime(f) > 86400:
            os.remove(f)
    except OSError:
        pass
