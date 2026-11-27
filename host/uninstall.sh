#!/bin/bash
# Removes the LaunchAgent and the claude-meter statusLine entry.
set -euo pipefail
LABEL="com.claude-meter.meterd"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SETTINGS="$HOME/.claude/settings.json"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$PLIST"

if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak-claude-meter-$(date +%Y%m%d-%H%M%S)"
  python3 - "$SETTINGS" <<'EOF'
import json, sys
p = sys.argv[1]
s = json.load(open(p))
if "claude-meter" in json.dumps(s.get("statusLine", "")):
    del s["statusLine"]
    json.dump(s, open(p, "w"), indent=2)
    open(p, "a").write("\n")
    print("statusLine removed")
EOF
fi
echo "✓ uninstalled (state in ~/.claude-meter left in place)"
