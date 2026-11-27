#pragma once

// Minimal XPT2046 driver: we only need "was the screen tapped?", so no
// coordinates and no calibration.
void touch_init();
bool touch_tapped(); // poll often (~every loop); true once per new press
