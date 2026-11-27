#pragma once
#include "ui.h"

// On-board RGB LED as a quiet usage alarm:
// off < 75%, steady dim amber 75..90%, slow red "breathing" >= 90%.
void led_init();
void led_update(const UiData &d, uint32_t now_epoch); // call every ~20 ms
