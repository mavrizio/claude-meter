// Minimal LVGL 9 config — everything not set here uses LVGL defaults.
#ifndef LV_CONF_H
#define LV_CONF_H

#define LV_COLOR_DEPTH 16
// Use the ESP32 heap: the antialiased arc masks need more than a fixed 64 KB pool.
#define LV_USE_STDLIB_MALLOC LV_STDLIB_CLIB
#define LV_DEF_REFR_PERIOD 16
#define LV_DPI_DEF 130
#define LV_USE_OS LV_OS_NONE
#define LV_USE_LOG 0

#define LV_FONT_MONTSERRAT_12 1
#define LV_FONT_MONTSERRAT_14 1
#define LV_FONT_MONTSERRAT_16 1
#define LV_FONT_MONTSERRAT_20 1
#define LV_FONT_MONTSERRAT_40 1
#define LV_FONT_DEFAULT &lv_font_montserrat_14

#endif
