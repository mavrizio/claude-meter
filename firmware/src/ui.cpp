// claude-meter UI (LVGL 9, 320x240 landscape)
#include "ui.h"
#include <lvgl.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

// ---------- palette ----------
#define C_BG      lv_color_hex(0x0D0D0F)
#define C_SURFACE lv_color_hex(0x17171B)
#define C_TRACK   lv_color_hex(0x232328)
#define C_TEXT    lv_color_hex(0xF2F2F3)
#define C_MUTED   lv_color_hex(0x8B8B94)
#define C_DIM     lv_color_hex(0x4A4A52)
#define C_ACCENT  lv_color_hex(0xD97757)
#define C_GREEN   lv_color_hex(0x4FD18B)
#define C_AMBER   lv_color_hex(0xF2B347)
#define C_RED     lv_color_hex(0xF2545B)

static const int GSIZE = 144; // gauge diameter
static const int GW = 12;     // gauge stroke
static const int ARC_START = 135, ARC_SWEEP = 270;

struct Gauge {
  lv_obj_t *glow2, *glow1, *arc, *pace, *num, *pct, *title, *reset;
  int32_t shown = 0;  // currently displayed value 0..1000
  int32_t target = 0; // value we are animating toward
  bool present = false;
  uint32_t window_s = 0;
  int cx = 0, cy = 0;
};

static Gauge g_fh, g_sd;
static lv_obj_t *lbl_model, *lbl_clock, *dot;
static lv_obj_t *stats, *lbl_msg, *bar_ctx, *lbl_ctx, *lbl_cost, *lbl_add, *lbl_rem;
static bool intro_done = false;

// Smooth green -> amber -> red as usage grows.
static lv_color_t level_color(int32_t v) {
  if (v <= 500) return C_GREEN;
  if (v <= 750) return lv_color_mix(C_AMBER, C_GREEN, (uint8_t)((v - 500) * 255 / 250));
  if (v <= 920) return lv_color_mix(C_RED, C_AMBER, (uint8_t)((v - 750) * 255 / 170));
  return C_RED;
}

static lv_obj_t *mk_label(lv_obj_t *parent, const lv_font_t *font, lv_color_t col, const char *txt) {
  lv_obj_t *l = lv_label_create(parent);
  lv_obj_set_style_text_font(l, font, 0);
  lv_obj_set_style_text_color(l, col, 0);
  lv_label_set_text(l, txt);
  return l;
}

static lv_obj_t *mk_box(lv_obj_t *parent) {
  lv_obj_t *o = lv_obj_create(parent);
  lv_obj_remove_style_all(o);
  lv_obj_remove_flag(o, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_remove_flag(o, LV_OBJ_FLAG_CLICKABLE);
  return o;
}

static lv_obj_t *mk_arc(lv_obj_t *parent, int x, int y, int size, int w, lv_opa_t ind_opa, bool track) {
  lv_obj_t *a = lv_arc_create(parent);
  lv_obj_remove_style_all(a);
  lv_obj_set_pos(a, x, y);
  lv_obj_set_size(a, size, size);
  lv_obj_remove_flag(a, LV_OBJ_FLAG_CLICKABLE);
  lv_obj_remove_flag(a, LV_OBJ_FLAG_SCROLLABLE);
  lv_arc_set_bg_angles(a, ARC_START, ARC_START + ARC_SWEEP);
  lv_arc_set_range(a, 0, 1000);
  lv_arc_set_value(a, 0);
  lv_obj_set_style_arc_width(a, w, LV_PART_MAIN);
  lv_obj_set_style_arc_width(a, w, LV_PART_INDICATOR);
  lv_obj_set_style_arc_rounded(a, true, LV_PART_MAIN);
  lv_obj_set_style_arc_rounded(a, true, LV_PART_INDICATOR);
  lv_obj_set_style_arc_color(a, C_TRACK, LV_PART_MAIN);
  lv_obj_set_style_arc_opa(a, track ? LV_OPA_COVER : LV_OPA_TRANSP, LV_PART_MAIN);
  lv_obj_set_style_arc_color(a, C_GREEN, LV_PART_INDICATOR);
  lv_obj_set_style_arc_opa(a, ind_opa, LV_PART_INDICATOR);
  return a;
}

// ---------- gauge ----------
static void gauge_apply(Gauge *g, int32_t v) {
  g->shown = v;
  lv_color_t c = level_color(v);
  lv_obj_t *arcs[3] = {g->glow2, g->glow1, g->arc};
  for (lv_obj_t *a : arcs) {
    lv_arc_set_value(a, v);
    lv_obj_set_style_arc_color(a, c, LV_PART_INDICATOR);
  }
  if (g->present || !intro_done) {
    char b[8];
    snprintf(b, sizeof b, "%d", (int)((v + 5) / 10));
    lv_label_set_text(g->num, b);
    lv_obj_remove_flag(g->pct, LV_OBJ_FLAG_HIDDEN);
  } else {
    lv_label_set_text(g->num, "--");
    lv_obj_add_flag(g->pct, LV_OBJ_FLAG_HIDDEN);
  }
}

static void anim_cb(void *var, int32_t v) { gauge_apply((Gauge *)var, v); }

static void gauge_animate(Gauge *g, int32_t to, uint32_t ms) {
  lv_anim_delete(g, anim_cb);
  lv_anim_t a;
  lv_anim_init(&a);
  lv_anim_set_var(&a, g);
  lv_anim_set_exec_cb(&a, anim_cb);
  lv_anim_set_values(&a, g->shown, to);
  lv_anim_set_duration(&a, ms);
  lv_anim_set_path_cb(&a, lv_anim_path_ease_in_out);
  lv_anim_start(&a);
}

static void gauge_set_target(Gauge *g, bool present, float pct) {
  int32_t t = present ? (int32_t)lroundf(fminf(fmaxf(pct, 0.f), 100.f) * 10.f) : 0;
  bool changed = (t != g->target) || (present != g->present);
  g->present = present;
  g->target = t;
  if (intro_done && changed) gauge_animate(g, t, 900);
  if (intro_done && !present) gauge_apply(g, g->shown); // refresh "--"
}

static void gauge_build(Gauge &g, lv_obj_t *scr, int x, int y, const char *title, uint32_t window_s) {
  g.window_s = window_s;
  g.cx = x + GSIZE / 2;
  g.cy = y + GSIZE / 2;
  // two soft halo layers under the main stroke => glow
  g.glow2 = mk_arc(scr, x - 7, y - 7, GSIZE + 14, GW + 14, 22, false);
  g.glow1 = mk_arc(scr, x - 3, y - 3, GSIZE + 6, GW + 6, 55, false);
  g.arc = mk_arc(scr, x, y, GSIZE, GW, LV_OPA_COVER, true);

  lv_obj_t *row = mk_box(g.arc);
  lv_obj_set_size(row, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
  lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
  lv_obj_set_flex_align(row, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_END, LV_FLEX_ALIGN_END);
  lv_obj_set_style_pad_column(row, 2, 0);
  lv_obj_align(row, LV_ALIGN_CENTER, 4, -6);
  g.num = mk_label(row, &lv_font_montserrat_40, C_TEXT, "0");
  g.pct = mk_label(row, &lv_font_montserrat_16, C_MUTED, "%");
  lv_obj_set_style_pad_bottom(g.pct, 7, 0);

  g.title = mk_label(g.arc, &lv_font_montserrat_12, C_MUTED, title);
  lv_obj_set_style_text_letter_space(g.title, 1, 0);
  lv_obj_align(g.title, LV_ALIGN_CENTER, 0, 24);

  g.reset = mk_label(g.arc, &lv_font_montserrat_14, C_MUTED, "");
  lv_obj_align(g.reset, LV_ALIGN_BOTTOM_MID, 0, 0);

  // "pace" marker: where you'd be if you spread usage evenly over the window
  g.pace = mk_box(scr);
  lv_obj_set_size(g.pace, 10, 10);
  lv_obj_set_style_radius(g.pace, LV_RADIUS_CIRCLE, 0);
  lv_obj_set_style_bg_color(g.pace, C_TEXT, 0);
  lv_obj_set_style_bg_opa(g.pace, LV_OPA_COVER, 0);
  lv_obj_set_style_border_color(g.pace, C_BG, 0);
  lv_obj_set_style_border_width(g.pace, 2, 0);
  lv_obj_add_flag(g.pace, LV_OBJ_FLAG_HIDDEN);
}

static void fmt_remaining(char *b, size_t n, int32_t s) {
  if (s <= 0) snprintf(b, n, LV_SYMBOL_REFRESH " ora");
  else if (s >= 86400) snprintf(b, n, LV_SYMBOL_REFRESH " %dg %dh", (int)(s / 86400), (int)(s % 86400 / 3600));
  else if (s >= 3600) snprintf(b, n, LV_SYMBOL_REFRESH " %dh %02dm", (int)(s / 3600), (int)(s % 3600 / 60));
  else if (s >= 60) snprintf(b, n, LV_SYMBOL_REFRESH " %dm", (int)(s / 60));
  else snprintf(b, n, LV_SYMBOL_REFRESH " <1m");
}

static void gauge_tick(Gauge &g, const UiWindow &w, uint32_t now) {
  if (!g.present || !now || !w.resets_at) {
    lv_obj_add_flag(g.pace, LV_OBJ_FLAG_HIDDEN);
    lv_label_set_text(g.reset, "");
    return;
  }
  int32_t rem = (int32_t)w.resets_at - (int32_t)now;
  char b[24];
  fmt_remaining(b, sizeof b, rem);
  lv_label_set_text(g.reset, b);

  if (rem <= 0 && g.target != 0) gauge_set_target(&g, true, 0); // window rolled over

  float frac = 1.f - (float)rem / (float)g.window_s;
  frac = fminf(fmaxf(frac, 0.f), 1.f);
  float ang = (ARC_START + ARC_SWEEP * frac) * (float)M_PI / 180.f;
  float r = GSIZE / 2.f - GW / 2.f;
  int px = g.cx + (int)lroundf(r * cosf(ang));
  int py = g.cy + (int)lroundf(r * sinf(ang));
  lv_obj_set_pos(g.pace, px - 5, py - 5);
  lv_obj_remove_flag(g.pace, LV_OBJ_FLAG_HIDDEN);
}

// ---------- intro sweep ----------
static void intro_back_done(lv_anim_t *a) {
  intro_done = true;
  Gauge *gs[2] = {&g_fh, &g_sd};
  for (Gauge *g : gs) gauge_animate(g, g->target, 900);
}

static void intro_up_done(lv_anim_t *a) {
  Gauge *g = (Gauge *)a->var;
  lv_anim_t b;
  lv_anim_init(&b);
  lv_anim_set_var(&b, g);
  lv_anim_set_exec_cb(&b, anim_cb);
  lv_anim_set_values(&b, 1000, 0);
  lv_anim_set_duration(&b, 700);
  lv_anim_set_path_cb(&b, lv_anim_path_ease_in_out);
  if (g == &g_sd) lv_anim_set_completed_cb(&b, intro_back_done);
  lv_anim_start(&b);
}

static void intro_start() {
  Gauge *gs[2] = {&g_fh, &g_sd};
  for (int i = 0; i < 2; i++) {
    lv_anim_t a;
    lv_anim_init(&a);
    lv_anim_set_var(&a, gs[i]);
    lv_anim_set_exec_cb(&a, anim_cb);
    lv_anim_set_values(&a, 0, 1000);
    lv_anim_set_duration(&a, 800);
    lv_anim_set_delay(&a, 200 + i * 150);
    lv_anim_set_path_cb(&a, lv_anim_path_ease_in_out);
    lv_anim_set_completed_cb(&a, intro_up_done);
    lv_anim_start(&a);
  }
}

// ---------- public ----------
void ui_init() {
  lv_obj_t *scr = lv_screen_active();
  lv_obj_set_style_bg_color(scr, C_BG, 0);
  lv_obj_set_style_bg_opa(scr, LV_OPA_COVER, 0);
  lv_obj_remove_flag(scr, LV_OBJ_FLAG_SCROLLABLE);

  // header
  lv_obj_t *logo = mk_box(scr);
  lv_obj_set_size(logo, 10, 10);
  lv_obj_set_pos(logo, 12, 9);
  lv_obj_set_style_radius(logo, 3, 0);
  lv_obj_set_style_bg_color(logo, C_ACCENT, 0);
  lv_obj_set_style_bg_opa(logo, LV_OPA_COVER, 0);
  lv_obj_t *title = mk_label(scr, &lv_font_montserrat_14, C_TEXT, "claude meter");
  lv_obj_set_pos(title, 28, 5);

  lv_obj_t *hr = mk_box(scr);
  lv_obj_set_size(hr, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
  lv_obj_set_flex_flow(hr, LV_FLEX_FLOW_ROW);
  lv_obj_set_flex_align(hr, LV_FLEX_ALIGN_END, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
  lv_obj_set_style_pad_column(hr, 8, 0);
  lv_obj_align(hr, LV_ALIGN_TOP_RIGHT, -12, 5);
  lbl_model = mk_label(hr, &lv_font_montserrat_14, C_MUTED, "");
  lbl_clock = mk_label(hr, &lv_font_montserrat_14, C_TEXT, "--:--");
  dot = mk_box(hr);
  lv_obj_set_size(dot, 8, 8);
  lv_obj_set_style_radius(dot, LV_RADIUS_CIRCLE, 0);
  lv_obj_set_style_bg_color(dot, C_DIM, 0);
  lv_obj_set_style_bg_opa(dot, LV_OPA_COVER, 0);

  // gauges
  gauge_build(g_fh, scr, 10, 34, "SESSIONE 5H", 5 * 3600);
  gauge_build(g_sd, scr, 166, 34, "SETTIMANA", 7 * 86400);

  // bottom card
  lv_obj_t *card = mk_box(scr);
  lv_obj_set_pos(card, 8, 186);
  lv_obj_set_size(card, 304, 46);
  lv_obj_set_style_radius(card, 12, 0);
  lv_obj_set_style_bg_color(card, C_SURFACE, 0);
  lv_obj_set_style_bg_opa(card, LV_OPA_COVER, 0);

  lbl_msg = mk_label(card, &lv_font_montserrat_14, C_MUTED, "");
  lv_obj_center(lbl_msg);

  stats = mk_box(card);
  lv_obj_set_size(stats, 304, 46);

  lv_obj_t *t1 = mk_label(stats, &lv_font_montserrat_12, C_MUTED, "CONTESTO");
  lv_obj_set_pos(t1, 14, 6);
  bar_ctx = lv_bar_create(stats);
  lv_obj_remove_style_all(bar_ctx);
  lv_obj_set_size(bar_ctx, 80, 6);
  lv_obj_set_pos(bar_ctx, 14, 30);
  lv_bar_set_range(bar_ctx, 0, 100);
  lv_obj_set_style_radius(bar_ctx, 3, LV_PART_MAIN);
  lv_obj_set_style_bg_color(bar_ctx, C_TRACK, LV_PART_MAIN);
  lv_obj_set_style_bg_opa(bar_ctx, LV_OPA_COVER, LV_PART_MAIN);
  lv_obj_set_style_radius(bar_ctx, 3, LV_PART_INDICATOR);
  lv_obj_set_style_bg_color(bar_ctx, C_GREEN, LV_PART_INDICATOR);
  lv_obj_set_style_bg_opa(bar_ctx, LV_OPA_COVER, LV_PART_INDICATOR);
  lbl_ctx = mk_label(stats, &lv_font_montserrat_14, C_TEXT, "--");
  lv_obj_set_pos(lbl_ctx, 102, 24);

  lv_obj_t *t2 = mk_label(stats, &lv_font_montserrat_12, C_MUTED, "COSTO");
  lv_obj_set_pos(t2, 146, 6);
  lbl_cost = mk_label(stats, &lv_font_montserrat_16, C_TEXT, "--");
  lv_obj_set_pos(lbl_cost, 146, 22);

  lv_obj_t *t3 = mk_label(stats, &lv_font_montserrat_12, C_MUTED, "RIGHE");
  lv_obj_set_pos(t3, 218, 6);
  lv_obj_t *lines = mk_box(stats);
  lv_obj_set_size(lines, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
  lv_obj_set_flex_flow(lines, LV_FLEX_FLOW_ROW);
  lv_obj_set_style_pad_column(lines, 6, 0);
  lv_obj_set_pos(lines, 218, 23);
  lbl_add = mk_label(lines, &lv_font_montserrat_14, C_GREEN, "");
  lbl_rem = mk_label(lines, &lv_font_montserrat_14, C_RED, "");

  UiData empty;
  ui_update(empty);
  intro_start();
}

void ui_update(const UiData &d) {
  gauge_set_target(&g_fh, d.fh.present, d.fh.pct);
  gauge_set_target(&g_sd, d.sd.present, d.sd.pct);

  lv_label_set_text(lbl_model, d.model);

  if (!d.connected || !d.have_data) {
    lv_obj_add_flag(stats, LV_OBJ_FLAG_HIDDEN);
    lv_obj_remove_flag(lbl_msg, LV_OBJ_FLAG_HIDDEN);
    lv_label_set_text(lbl_msg, !d.connected ? LV_SYMBOL_USB "  In attesa del Mac..."
                                            : "Avvia Claude Code per vedere i limiti");
    return;
  }
  lv_obj_add_flag(lbl_msg, LV_OBJ_FLAG_HIDDEN);
  lv_obj_remove_flag(stats, LV_OBJ_FLAG_HIDDEN);

  char b[24];
  if (d.ctx >= 0) {
    lv_bar_set_value(bar_ctx, d.ctx, LV_ANIM_ON);
    lv_obj_set_style_bg_color(bar_ctx, level_color(d.ctx * 10), LV_PART_INDICATOR);
    snprintf(b, sizeof b, "%d%%", d.ctx);
    lv_label_set_text(lbl_ctx, b);
  } else {
    lv_bar_set_value(bar_ctx, 0, LV_ANIM_OFF);
    lv_label_set_text(lbl_ctx, "--");
  }

  if (d.cost >= 0) {
    snprintf(b, sizeof b, d.cost < 100 ? "$%.2f" : "$%.0f", d.cost);
    lv_label_set_text(lbl_cost, b);
  } else {
    lv_label_set_text(lbl_cost, "--");
  }

  if (d.la >= 0) {
    snprintf(b, sizeof b, "+%d", d.la);
    lv_label_set_text(lbl_add, b);
    snprintf(b, sizeof b, "-%d", d.lr < 0 ? 0 : d.lr);
    lv_label_set_text(lbl_rem, b);
  } else {
    lv_label_set_text(lbl_add, "--");
    lv_label_set_text(lbl_rem, "");
  }
}

void ui_tick(uint32_t now, int32_t tz, const UiData &d) {
  if (now) {
    uint32_t local = now + tz;
    char b[8];
    snprintf(b, sizeof b, "%02u:%02u", (unsigned)(local / 3600 % 24), (unsigned)(local / 60 % 60));
    lv_label_set_text(lbl_clock, b);
  }
  // dot: grey = no Mac, green = connected, orange = Claude working right now
  lv_color_t c = !d.connected ? C_DIM : (d.age >= 0 && d.age < 20 ? C_ACCENT : C_GREEN);
  lv_obj_set_style_bg_color(dot, c, 0);

  gauge_tick(g_fh, d.fh, d.connected ? now : 0);
  gauge_tick(g_sd, d.sd, d.connected ? now : 0);
}
