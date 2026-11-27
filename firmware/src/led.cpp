// On-board RGB LED alarm (CYD: active low on R=4, G=16, B=17).
#include "led.h"
#include <Arduino.h>
#include <math.h>

static const int PIN[3] = {4, 16, 17};
static const int CH[3] = {1, 2, 3}; // LEDC channels (0 reserved for the backlight)

// Thresholds and colors (8-bit duty, 255 = full brightness). The LED is very
// bright and green dominates, so amber is mostly red with a pinch of green.
static const float AMBER_PCT = 75.f, RED_PCT = 90.f;
static const uint8_t AMBER_R = 40, AMBER_G = 9;
static const uint8_t RED_MIN = 3, RED_MAX = 70;
static const uint32_t BREATH_MS = 2400;

static void set_rgb(uint8_t r, uint8_t g, uint8_t b) {
  const uint8_t v[3] = {r, g, b};
  // active low: duty 255 = always high = off (the core maps max duty to 100%)
  for (int i = 0; i < 3; i++) ledcWrite(CH[i], 255 - v[i]);
}

void led_init() {
  for (int i = 0; i < 3; i++) {
    pinMode(PIN[i], OUTPUT);
    digitalWrite(PIN[i], HIGH); // off until PWM takes over
    ledcSetup(CH[i], 5000, 8);
  }
  set_rgb(0, 0, 0); // set "off" duty before attaching, so the LED never flashes at boot
  for (int i = 0; i < 3; i++) ledcAttachPin(PIN[i], CH[i]);
}

static float window_pct(const UiWindow &w, uint32_t now) {
  if (!w.present) return 0;
  if (now && w.resets_at && w.resets_at <= now) return 0; // already rolled over
  return w.pct;
}

// 0 = no alarm, 1 = amber, 2 = red
static int g_level = 0, g_muted_level = 0;

void led_update(const UiData &d, uint32_t now) {
  float worst = 0;
  if (d.connected && d.have_data) worst = fmaxf(window_pct(d.fh, now), window_pct(d.sd, now));
  g_level = worst >= RED_PCT ? 2 : worst >= AMBER_PCT ? 1 : 0;

  // re-arm when the alarm clears or gets worse
  if (g_muted_level && (g_level == 0 || g_level > g_muted_level)) g_muted_level = 0;

  if (g_level == 0 || g_muted_level) {
    set_rgb(0, 0, 0);
  } else if (g_level == 2) {
    float ph = (float)(millis() % BREATH_MS) / BREATH_MS;
    float k = 0.5f - 0.5f * cosf(2.f * (float)M_PI * ph); // 0..1..0
    set_rgb((uint8_t)(RED_MIN + k * k * (RED_MAX - RED_MIN)), 0, 0);
  } else {
    set_rgb(AMBER_R, AMBER_G, 0);
  }
}

MuteResult led_toggle_mute() {
  if (g_muted_level) {
    g_muted_level = 0;
    return MUTE_OFF;
  }
  if (g_level == 0) return MUTE_NOTHING;
  g_muted_level = g_level;
  return MUTE_ON;
}

bool led_muted() { return g_muted_level != 0; }
