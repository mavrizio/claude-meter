#!/usr/bin/env python3
"""claude-meter daemon: streams ~/.claude-meter/state.json to the ESP32 over USB serial.

Keeps the serial port open (opening it resets the ESP32), finds the board
automatically, reconnects when it is unplugged.

    meterd.py            # normal mode
    meterd.py --demo     # fake data, to test the display
    meterd.py --port /dev/cu.wchusbserial11240
"""
import argparse
import glob
import json
import math
import os
import sys
import time

import serial

STATE_FILE = os.path.expanduser("~/.claude-meter/state.json")
PORT_GLOBS = ["/dev/cu.wchusbserial*", "/dev/cu.usbserial*", "/dev/cu.SLAB_USBtoUART*"]
SEND_EVERY = 2.0


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


def find_port():
    for g in PORT_GLOBS:
        ports = sorted(glob.glob(g))
        if ports:
            return ports[0]
    return None


def read_state():
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except Exception:
        return None


def build_msg(state, now):
    msg = {"t": "u", "now": int(now), "tz": time.localtime().tm_gmtoff, "ok": state is not None}
    if not state:
        return msg
    for key, short in (("five_hour", "fh"), ("seven_day", "sd")):
        w = state.get(key)
        if w and w.get("resets_at", 0) > now:
            msg[short] = [round(float(w["pct"]), 1), int(w["resets_at"])]
    if state.get("context_pct") is not None:
        msg["ctx"] = int(round(state["context_pct"]))
    if state.get("cost_usd") is not None:
        msg["cost"] = round(float(state["cost_usd"]), 2)
    if state.get("lines_added") is not None:
        msg["la"] = int(state["lines_added"])
        msg["lr"] = int(state.get("lines_removed") or 0)
    if state.get("model"):
        msg["m"] = str(state["model"])[:20]
    msg["age"] = max(0, int(now - state.get("updated_at", now)))
    return msg


def demo_state(t0, now):
    t = now - t0
    fh = 5 + 93 * (0.5 - 0.5 * math.cos(t / 12))  # sweeps 5% -> 98% -> 5%
    return {
        "updated_at": now - (0 if int(t / 10) % 2 else 60),
        "model": "Opus 5.5",
        "five_hour": {"pct": fh, "resets_at": int(t0 + 2 * 3600 + 14 * 60)},
        "seven_day": {"pct": 41.2, "resets_at": int(t0 + 3 * 86400 + 4 * 3600)},
        "context_pct": min(99, 8 + t * 0.8),
        "cost_usd": 0.42 + t * 0.013,
        "lines_added": 156 + int(t),
        "lines_removed": 23 + int(t / 3),
    }


def run(port_arg, demo):
    t0 = time.time()
    while True:
        port = port_arg or find_port()
        if not port:
            log("board not found, retrying...")
            time.sleep(3)
            continue
        try:
            ser = serial.Serial()
            ser.port, ser.baudrate, ser.timeout = port, 115200, 0.2
            ser.dtr = False  # avoid holding the board in reset / bootloader
            ser.rts = False
            ser.open()
            log("connected", port)
            last_sent, last_msg = 0.0, None
            buf = b""
            while True:
                buf += ser.read(256)
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    line = line.strip()
                    if line.startswith(b"{"):
                        log("board:", line.decode(errors="replace"))
                        last_sent = 0  # board (re)booted: send immediately
                now = time.time()
                state = demo_state(t0, now) if demo else read_state()
                msg = build_msg(state, now)
                cmp = {k: v for k, v in msg.items() if k not in ("now", "age")}
                if cmp != last_msg or now - last_sent >= SEND_EVERY:
                    ser.write((json.dumps(msg, separators=(",", ":")) + "\n").encode())
                    last_sent, last_msg = now, cmp
        except (serial.SerialException, OSError) as e:
            log("serial error:", e)
            try:
                ser.close()
            except Exception:
                pass
            time.sleep(2)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", help="serial port (default: auto-detect)")
    ap.add_argument("--demo", action="store_true", help="send fake data")
    a = ap.parse_args()
    try:
        run(a.port, a.demo)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    sys.exit(main())
