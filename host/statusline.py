#!/usr/bin/env python3
"""Claude Code statusLine command for claude-meter.

Claude Code pipes a JSON payload on stdin each time the status line refreshes.
We save the interesting bits to ~/.claude-meter/state.json (read by meterd.py)
and print a compact status line for the terminal. No third-party deps.
"""
import json
import os
import sys
import tempfile
import time

STATE_DIR = os.path.expanduser("~/.claude-meter")
STATE_FILE = os.path.join(STATE_DIR, "state.json")


def load_prev():
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except Exception:
        return {}


def window(rl, key):
    w = (rl or {}).get(key) or {}
    p, r = w.get("used_percentage"), w.get("resets_at")
    if p is None or r is None:
        return None
    return {"pct": float(p), "resets_at": int(r)}


def save(state):
    os.makedirs(STATE_DIR, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=STATE_DIR, prefix=".state-")
    with os.fdopen(fd, "w") as f:
        json.dump(state, f)
    os.replace(tmp, STATE_FILE)


def fmt_rem(sec):
    if sec <= 0:
        return "ora"
    if sec >= 86400:
        return f"{sec // 86400}g{sec % 86400 // 3600}h"
    if sec >= 3600:
        return f"{sec // 3600}h{sec % 3600 // 60:02d}m"
    return f"{sec // 60}m"


def color(pct):
    return "\033[32m" if pct < 50 else "\033[33m" if pct < 80 else "\033[31m"


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        data = {}

    now = time.time()
    prev = load_prev()
    rl = data.get("rate_limits")
    cost = data.get("cost") or {}
    ctx = data.get("context_window") or {}

    state = {
        "updated_at": now,
        "session_id": data.get("session_id"),
        "model": (data.get("model") or {}).get("display_name"),
        "context_pct": ctx.get("used_percentage"),
        "cost_usd": cost.get("total_cost_usd"),
        "lines_added": cost.get("total_lines_added"),
        "lines_removed": cost.get("total_lines_removed"),
    }
    # Rate limits are account-wide; a fresh session doesn't report them until its
    # first API response, so keep the previous value while it's still valid.
    for key in ("five_hour", "seven_day"):
        w = window(rl, key)
        if w is None:
            old = prev.get(key)
            if old and old.get("resets_at", 0) > now:
                w = old
        state[key] = w

    try:
        save(state)
    except Exception:
        pass

    parts = []
    if state["model"]:
        parts.append(f"\033[2m{state['model']}\033[0m")
    for key, label in (("five_hour", "5h"), ("seven_day", "7d")):
        w = state[key]
        if w:
            rem = fmt_rem(int(w["resets_at"] - now))
            parts.append(f"{label} {color(w['pct'])}{w['pct']:.0f}%\033[0m \033[2m{rem}\033[0m")
    if state["context_pct"] is not None:
        parts.append(f"ctx {state['context_pct']:.0f}%")
    print("  ".join(parts))


if __name__ == "__main__":
    main()
