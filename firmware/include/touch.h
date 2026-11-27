#pragma once

// Minimal XPT2046 driver: we only need taps and long presses, so no
// coordinates and no calibration.
enum TouchEvent { TOUCH_NONE, TOUCH_TAP, TOUCH_LONG };

void touch_init();
TouchEvent touch_poll(); // call every loop; TAP fires on release, LONG while still held
