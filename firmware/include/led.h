#pragma once
#include "ui.h"

// On-board RGB LED as a quiet usage alarm:
// off < 75%, steady dim amber 75..90%, slow red "breathing" >= 90%.
// A long press mutes the current alarm; it re-arms by itself when usage gets
// worse (amber -> red) or drops back below 75%.
void led_init();
void led_update(const UiData &d, uint32_t now_epoch); // call every ~20 ms

enum MuteResult { MUTE_NOTHING, MUTE_ON, MUTE_OFF };
MuteResult led_toggle_mute(); // long press
bool led_muted();
