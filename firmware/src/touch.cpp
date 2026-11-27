// XPT2046 resistive touch on the CYD's second SPI bus (VSPI):
// CLK 25, MOSI 32, MISO 39, CS 33 (IRQ 36 unused: we poll the pressure).
#include "touch.h"
#include <Arduino.h>
#include <SPI.h>

static const int T_CLK = 25, T_MOSI = 32, T_MISO = 39, T_CS = 33;
static const int Z_PRESS = 400, Z_RELEASE = 200; // hysteresis on pressure
static const uint32_t POLL_MS = 20, LOCKOUT_MS = 350;

static SPIClass tspi(VSPI);
static const SPISettings TS_SPI(2000000, MSBFIRST, SPI_MODE0);

// One 12-bit conversion: send the command, the result arrives in the next 16 bits.
static int read12(uint8_t cmd) {
  tspi.transfer(cmd);
  return tspi.transfer16(0) >> 3;
}

static int pressure() {
  tspi.beginTransaction(TS_SPI);
  digitalWrite(T_CS, LOW);
  int z1 = read12(0xB1);
  int z2 = read12(0xC1);
  read12(0xD0); // power down between conversions, keep PENIRQ enabled
  digitalWrite(T_CS, HIGH);
  tspi.endTransaction();
  return z1 + 4095 - z2;
}

void touch_init() {
  pinMode(T_CS, OUTPUT);
  digitalWrite(T_CS, HIGH);
  tspi.begin(T_CLK, T_MISO, T_MOSI, T_CS);
}

bool touch_tapped() {
  static uint32_t last_poll = 0, last_tap = 0;
  static bool down = false;
  static uint8_t hi = 0, lo = 0;

  uint32_t ms = millis();
  if (ms - last_poll < POLL_MS || ms < 500) return false; // let the chip settle after boot
  last_poll = ms;

  int z = pressure();
  // Require 2 strong samples to press and 3 weak ones to release: rejects noise.
  hi = z > Z_PRESS ? (hi < 255 ? hi + 1 : hi) : 0;
  lo = z < Z_RELEASE ? (lo < 255 ? lo + 1 : lo) : 0;

  if (!down && hi >= 2) {
    down = true;
    if (ms - last_tap >= LOCKOUT_MS) {
      last_tap = ms;
      return true;
    }
  } else if (down && lo >= 3) {
    down = false;
  }
  return false;
}
