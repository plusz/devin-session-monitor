#!/usr/bin/env bash
# Installs devin-session-monitor: hook script, lifecycle hooks, CLI dashboard, menu bar app.
set -euo pipefail

DEVIN_CONFIG="$HOME/.config/devin"
STATUS_DIR="$HOME/.devin-status"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$DEVIN_CONFIG" "$STATUS_DIR"

cp "$SRC/hooks/devin-status-hook.py" "$DEVIN_CONFIG/devin-status-hook.py"
cp "$SRC/bin/devin-status" "$DEVIN_CONFIG/devin-status.sh"
chmod +x "$DEVIN_CONFIG/devin-status-hook.py" "$DEVIN_CONFIG/devin-status.sh"

HOOK_CMD="python3 $DEVIN_CONFIG/devin-status-hook.py"
DEVIN_CONFIG="$DEVIN_CONFIG" HOOK_CMD="$HOOK_CMD" python3 - <<'PY'
import json, os, shutil, time

cfg_path = os.path.join(os.environ["DEVIN_CONFIG"], "config.json")
hook_cmd = os.environ["HOOK_CMD"]

try:
    cfg = json.load(open(cfg_path))
except (FileNotFoundError, json.JSONDecodeError):
    cfg = {"version": 1}

if os.path.exists(cfg_path):
    shutil.copy(cfg_path, f"{cfg_path}.bak-{time.strftime('%Y%m%d-%H%M%S')}")

entry = [{"matcher": "", "hooks": [{"type": "command", "command": hook_cmd}]}]
events = ["SessionStart", "SessionEnd", "UserPromptSubmit", "PermissionRequest",
          "Stop", "PostCompaction", "PreToolUse", "PostToolUse"]

hooks = cfg.setdefault("hooks", {})
for e in events:
    hooks[e] = entry

json.dump(cfg, open(cfg_path, "w"), indent=2)
print(f"hooks written to {cfg_path} (previous config backed up)")
PY

# Build menu bar app (requires Xcode Command Line Tools / swiftc)
if command -v swiftc >/dev/null 2>&1; then
  APP="$HOME/Applications/DevinStatus.app"
  mkdir -p "$APP/Contents/MacOS"
  swiftc -O -o "$APP/Contents/MacOS/DevinStatus" "$SRC/menubar-app/main.swift"
  cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>DevinStatus</string>
    <key>CFBundleIdentifier</key><string>local.devinstatus</string>
    <key>CFBundleName</key><string>DevinStatus</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>LSUIElement</key><true/>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict>
</plist>
EOF
  echo "built $APP"
else
  echo "swiftc not found — skipping menu bar app (CLI dashboard still works)"
fi

ln -sf "$DEVIN_CONFIG/devin-status.sh" /opt/homebrew/bin/devin-status 2>/dev/null || true

echo
echo "Done. Notes:"
echo "  - Hooks are loaded at session start — already-running sessions won't report."
echo "  - Run 'devin-status' for the CLI dashboard, or open ~/Applications/DevinStatus.app."
