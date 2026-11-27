#pragma once
#include <stdint.h>

struct UiWindow {
  bool present = false;
  float pct = 0;          // 0..100
  uint32_t resets_at = 0; // unix epoch seconds
};

struct UiData {
  bool connected = false; // Mac daemon is talking to us
  bool have_data = false; // Claude Code has written at least one status update
  UiWindow fh;            // 5-hour session window
  UiWindow sd;            // 7-day weekly window
  int ctx = -1;           // context window used %, -1 = unknown
  float cost = -1;        // session cost USD, <0 = unknown
  int la = -1, lr = -1;   // lines added / removed
  int age = -1;           // seconds since last Claude Code update
  char model[24] = "";
};

void ui_init();
void ui_update(const UiData &d);                          // new data arrived
void ui_tick(uint32_t now_epoch, int32_t tz, const UiData &d); // ~2x per second
