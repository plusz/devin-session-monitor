#!/usr/bin/env python3
import glob
import json
import os
import subprocess
import sys
import time
import traceback

STATUS_DIR = os.path.expanduser("~/.devin-status")
ERR_LOG = os.path.join(STATUS_DIR, "hook-errors.log")

# Per-state expiry (seconds). Files self-heal — a revived session recreates
# its file on the next event — so expiring quiet files is safe.
EXPIRY = {
    "starting": 300,     # started but never produced another event = dead spawn
    "question": 3600,
    "permission": 3600,
    "waiting": 3600,
    "working": 7200,
}
DEFAULT_EXPIRY = 3600


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
        "event": event,
        "project": project if project != "?" else rec.get("project", "?"),
        "pid": os.getppid(),
    })
    rec.setdefault("created", time.time())

    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w") as f:
        json.dump(rec, f)
    os.replace(tmp, path)

    # Session files self-heal: any new hook event recreates the file, so
    # expiring quiet files is safe. Devin only fires SessionEnd for top-level
    # teardown — ended conversations/subagents inside a live process go quiet
    # forever, so time-based expiry is the only reliable liveness signal.
    now = time.time()
    for f in glob.glob(os.path.join(STATUS_DIR, "*.json")):
        if f == path:
            continue
        try:
            if now - os.path.getmtime(f) > 86400:
                os.remove(f)
                continue
            with open(f) as fh:
                rec2 = json.load(fh)
            if not isinstance(rec2, dict):
                os.remove(f)
                continue
            ts2 = float(rec2.get("ts") or os.path.getmtime(f))
            if now - ts2 > EXPIRY.get(rec2.get("state"), DEFAULT_EXPIRY):
                os.remove(f)
                continue
            pid = rec2.get("pid")
            if not pid:
                continue
            try:
                os.kill(int(pid), 0)
            except ProcessLookupError:
                os.remove(f)
            except PermissionError:
                pass
            else:
                out = subprocess.run(
                    ["ps", "-p", str(pid), "-o", "comm="],
                    capture_output=True, text=True, timeout=2,
                ).stdout
                if "devin" not in out.lower():
                    os.remove(f)
        except (OSError, ValueError, subprocess.SubprocessError):
            pass
    for f in glob.glob(os.path.join(STATUS_DIR, "*.tmp")):
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
