// claude-meter firmware: receives NDJSON usage updates over USB serial
// from the Mac daemon (host/meterd.py) and renders them with LVGL.
#include <Arduino.h>
#include <ArduinoJson.h>
#include <TFT_eSPI.h>
#include <lvgl.h>

#include "ui.h"

#define FW_VERSION "0.1.0"
static const uint16_t SCR_W = 320, SCR_H = 240;
static const uint32_t LINK_TIMEOUT_MS = 8000;

// CYD on-board RGB LED (active low)
static const int LED_R = 4, LED_G = 16, LED_B = 17;

static TFT_eSPI tft;
static uint16_t buf1[SCR_W * 24], buf2[SCR_W * 24];

static UiData data;
static uint32_t last_rx_ms = 0;
static uint32_t epoch_base = 0, epoch_base_ms = 0;
static int32_t tz_off = 0;

static uint32_t now_epoch() {
  if (!epoch_base) return 0;
  return epoch_base + (millis() - epoch_base_ms) / 1000;
}

static void flush_cb(lv_display_t *d, const lv_area_t *a, uint8_t *px) {
  uint32_t w = lv_area_get_width(a), h = lv_area_get_height(a);
  tft.startWrite();
  tft.setAddrWindow(a->x1, a->y1, w, h);
  tft.pushColors((uint16_t *)px, w * h, true);
  tft.endWrite();
  lv_display_flush_ready(d);
}

static uint32_t tick_cb() { return millis(); }

static void read_window(JsonDocument &doc, const char *key, UiWindow &w) {
  JsonArrayConst a = doc[key].as<JsonArrayConst>();
  if (a.isNull() || a.size() < 2) {
    w.present = false;
    return;
  }
  w.present = true;
  w.pct = a[0].as<float>();
  w.resets_at = a[1].as<uint32_t>();
}

static void handle_line(const char *line) {
  JsonDocument doc;
  if (deserializeJson(doc, line)) return;
  const char *t = doc["t"] | "";
  if (strcmp(t, "u") != 0) return;

  last_rx_ms = millis();
  uint32_t now = doc["now"] | 0u;
  if (now) {
    epoch_base = now;
    epoch_base_ms = millis();
  }
  tz_off = doc["tz"] | 0;

  read_window(doc, "fh", data.fh);
  read_window(doc, "sd", data.sd);
  data.ctx = doc["ctx"].isNull() ? -1 : doc["ctx"].as<int>();
  data.cost = doc["cost"].isNull() ? -1.f : doc["cost"].as<float>();
  data.la = doc["la"] | -1;
  data.lr = doc["lr"] | -1;
  data.age = doc["age"] | -1;
  strlcpy(data.model, doc["m"] | "", sizeof data.model);
  data.have_data = doc["ok"] | false;
  data.connected = true;
  ui_update(data);
}

static void poll_serial() {
  static char line[768];
  static size_t len = 0;
  static bool overflow = false;
  while (Serial.available()) {
    char c = (char)Serial.read();
    if (c == '\n') {
      line[len] = 0;
      if (!overflow && len) handle_line(line);
      len = 0;
      overflow = false;
    } else if (c != '\r') {
      if (len < sizeof(line) - 1) line[len++] = c;
      else overflow = true;
    }
  }
}

void setup() {
  Serial.setRxBufferSize(2048);
  Serial.begin(115200);

  for (int p : {LED_R, LED_G, LED_B}) {
    pinMode(p, OUTPUT);
    digitalWrite(p, HIGH); // off
  }

  tft.begin();
  tft.setRotation(1); // landscape, USB on the right
  tft.fillScreen(TFT_BLACK);

  lv_init();
  lv_tick_set_cb(tick_cb);
  lv_display_t *disp = lv_display_create(SCR_W, SCR_H);
  lv_display_set_flush_cb(disp, flush_cb);
  lv_display_set_buffers(disp, buf1, buf2, sizeof(buf1), LV_DISPLAY_RENDER_MODE_PARTIAL);

  ui_init();
  Serial.println("{\"t\":\"hello\",\"fw\":\"" FW_VERSION "\"}");
}

void loop() {
  poll_serial();

  static uint32_t last_tick = 0, last_hello = 0;
  uint32_t ms = millis();
  if (ms - last_tick >= 500) {
    last_tick = ms;
    bool conn = last_rx_ms && (ms - last_rx_ms < LINK_TIMEOUT_MS);
    if (conn != data.connected) {
      data.connected = conn;
      ui_update(data);
    }
    ui_tick(now_epoch(), tz_off, data);
  }
#ifdef CM_DEBUG_HEAP
  static uint32_t last_dbg = 0;
  if (ms - last_dbg >= 1000) {
    last_dbg = ms;
    Serial.printf("{\"t\":\"dbg\",\"free\":%u,\"min\":%u,\"big\":%u}\n", ESP.getFreeHeap(), ESP.getMinFreeHeap(),
                  heap_caps_get_largest_free_block(MALLOC_CAP_8BIT));
  }
#endif
  if (!data.connected && ms - last_hello >= 5000) {
    last_hello = ms;
    Serial.println("{\"t\":\"hello\",\"fw\":\"" FW_VERSION "\"}");
  }

  lv_timer_handler();
  delay(2);
}
