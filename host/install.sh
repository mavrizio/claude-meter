#!/bin/bash
# Installs claude-meter on macOS:
#  - Python venv with pyserial
#  - statusLine entry in ~/.claude/settings.json (backup made first)
#  - LaunchAgent that keeps meterd.py running in the background
set -euo pipefail

HOST_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV="$HOST_DIR/.venv"
PY="$VENV/bin/python"
SETTINGS="$HOME/.claude/settings.json"
LABEL="com.claude-meter.meterd"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
STATE_DIR="$HOME/.claude-meter"

mkdir -p "$STATE_DIR"

if [ ! -x "$PY" ]; then
  echo "• creating venv"
  python3 -m venv "$VENV"
fi
"$PY" -m pip install -q --disable-pip-version-check pyserial

echo "• configuring Claude Code status line"
mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak-claude-meter-$(date +%Y%m%d-%H%M%S)"
"$PY" - "$SETTINGS" "$PY" "$HOST_DIR/statusline.py" <<'EOF'
import json, sys
path, py, script = sys.argv[1:]
with open(path) as f:
    s = json.load(f)
old = s.get("statusLine")
if old and "claude-meter" not in json.dumps(old):
    print("  ! an existing statusLine was replaced (see the .bak file):", json.dumps(old))
s["statusLine"] = {"type": "command", "command": f'"{py}" "{script}"', "padding": 0}
with open(path, "w") as f:
    json.dump(s, f, indent=2)
    f.write("\n")
EOF

echo "• installing LaunchAgent"
mkdir -p "$(dirname "$PLIST")"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$PY</string>
    <string>-u</string>
    <string>$HOST_DIR/meterd.py</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$STATE_DIR/meterd.log</string>
  <key>StandardErrorPath</key><string>$STATE_DIR/meterd.log</string>
</dict>
</plist>
EOF
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "✓ installed. Log: $STATE_DIR/meterd.log"
echo "  Open a new Claude Code session (or send a message) to push the first data."
