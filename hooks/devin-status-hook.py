#!/usr/bin/env python3
import glob
import json
import os
import sys
import time
import traceback

STATUS_DIR = os.path.expanduser("~/.devin-status")
ERR_LOG = os.path.join(STATUS_DIR, "hook-errors.log")


def log_err(msg):
    try:
        with open(ERR_LOG, "a") as f:
            f.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}\n")
    except OSError:
        pass


def main():
    os.makedirs(STATUS_DIR, exist_ok=True)

    try:
        data = json.load(sys.stdin)
    except Exception:
        return

    if not isinstance(data, dict):
        log_err(f"non-dict payload: {data!r:.200}")
        return

    event = data.get("hook_event_name", "")
    sid = data.get("session_id") or "unknown"
    tool = data.get("tool_name", "")
    project = os.path.basename(os.environ.get("DEVIN_PROJECT_DIR", "") or "") or "?"

    safe_sid = "".join(c for c in str(sid) if c.isalnum() or c in "-_.") or "unknown"
    path = os.path.join(STATUS_DIR, f"{safe_sid}.json")

    if event == "SessionEnd":
        try:
            os.remove(path)
        except OSError:
            pass
        return

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
        return

    rec = {}
    if os.path.exists(path):
        try:
            with open(path) as f:
                rec = json.load(f)
        except Exception:
            rec = {}
    if not isinstance(rec, dict):
        rec = {}

    rec.update({
        "session_id": sid,
        "state": state,
        "ts": time.time(),
        "tool": tool,
        "project": project if project != "?" else rec.get("project", "?"),
    })
    rec.setdefault("created", time.time())

    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w") as f:
        json.dump(rec, f)
    os.replace(tmp, path)

    now = time.time()
    for f in glob.glob(os.path.join(STATUS_DIR, "*.json")) + glob.glob(os.path.join(STATUS_DIR, "*.tmp")):
        try:
            if now - os.path.getmtime(f) > 86400:
                os.remove(f)
        except OSError:
            pass


try:
    main()
except Exception:
    log_err(traceback.format_exc(limit=3))
sys.exit(0)
