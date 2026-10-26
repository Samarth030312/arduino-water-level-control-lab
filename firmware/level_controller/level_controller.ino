// Arduino water level control lab: tank, pump, HC-SR04 ultrasonic level sensor
//
// Two pump wirings, chosen at build time:
//   PUMP_PWM = 0 (default)  ON-OFF actuator on D4: a solid-state relay (e.g. Fotek SSR-40DA)
//                           switching a mains AC pump, or a relay module. ON-OFF only: an
//                           induction motor behind a zero-cross SSR cannot be speed-controlled.
//   PUMP_PWM = 1            a DC pump on a logic-level MOSFET on D5 (PWM 980 Hz): P and PI too.
// RELAY_ACTIVE_LOW = 0 (default): D4 HIGH switches the pump on (an SSR's input, "high-level
// trigger" relay modules). Set 1 for the common active-LOW opto relay modules.
//
// Control (ON-OFF): pump ON below Lmin, OFF above Lmax (levels in % of the calibrated height).
// Telemetry: protocol v1 ($LTEL). Commands: CFG, SET, RUN, STOP, CAL, ZERO, GRD, PING.
//
// PINS (docs/hardware/WIRING.md)
//   D8   HC-SR04 TRIG          D7   HC-SR04 ECHO
//   D4   pump on/off: SSR input + (SSR input - to GND), or relay module IN
//   D5   MOSFET gate via 220 ohm (PWM)  only with PUMP_PWM = 1
//   D3   optional float switch to GND (closed = water at the top): hard overflow stop
//   D12  START / STOP pushbutton to GND
//
// Geometry: the sensor face is sensorToFloor cm above the tank floor; 100 % is fullHeight cm
// of water. level = sensorToFloor - d, with d = v t / 2 and v = 331.3 + 0.606 T m/s (air T).
// $ZERO,1 with the tank empty measures sensorToFloor; $CAL,1,<sensor_to_floor>,<full_height>
// [,<air_C>] sets it explicitly. Both are kept in EEPROM. RUN is refused until calibrated.
//
// GUARDS (pump forced off)
//   overflow     level > L_over (92 %), or the water closer than 4 cm to the sensor (its dead
//                zone), or the float switch closed; reached while the pump runs -> latched
// SENSOR: one ping per 100 ms step (>= 60 ms between pings: no ghost echoes), median of the
// last 5, pings farther from it than the water can move rejected (5 s of that while pumping:
// sensor fault); the pump turns ON only after 3 readings in a row below Lmin, OFF at once.
//   no filling   the pump has run t_dry s (20) and the level rose less than rise_cm (1.0): dry
//                suction, empty reservoir, blocked or broken pipe -> latched
//   run time     ON-OFF: the pump has run t_maxon s (180) without reaching Lmax -> latched
//   sensor       5 failed pings in a row -> latched
//   host         MATLAB silent for 3 s while it is in control
//   hang         the AVR watchdog resets a stuck program (2 s); after any reset D4 is LOW: off
// MOTOR (ON-OFF wiring): at least 3 s on and 15 s off between switchings (anti
// short-cycling: an induction motor and its relay take the starting current every start); the
// overflow and fault guards override it.
// $GRD,1,<t_dry_s>,<rise_cm>,<t_maxon_s>,<L_over_%> changes the guards.
//
// STATUS: runs on the PC against an emulated tank + HC-SR04 (firmware/tests).

#define FW_NAME "water_level_lab"
#ifndef FW_REV
#define FW_REV "dev"
#endif
#ifndef RELAY_ACTIVE_LOW
#define RELAY_ACTIVE_LOW 0
#endif
#ifndef PUMP_PWM
#define PUMP_PWM 0
#endif
#ifdef __AVR__
#include <avr/wdt.h>
#include <EEPROM.h>
#endif

const uint8_t PIN_TRIG = 8, PIN_ECHO = 7, PIN_RELAY = 4, PIN_PWM = 5, PIN_FLOAT = 3, PIN_BTN = 12;
const uint16_t TS_MS = 100;
const float D_MIN_CM = 4.0f;                              // HC-SR04 dead zone ~2 cm + margin
const uint32_t MIN_ON_MS = 3000, MIN_OFF_MS = 15000;      // motor anti short-cycling (ON-OFF wiring): <= ~200 starts/h
const uint8_t F_RUNNING = 1, F_SENSOR = 2, F_OVERFLOW = 4, F_DRY = 8, F_WATCHDOG = 16, F_BUTTON = 32, F_TIMEOUT = 64, F_OVERFLOW_LATCH = 128;
struct Guards { float tDry = 20, riseCm = 1.0f, tMaxOn = 180, Lover = 92; } grd;

enum Mode : uint8_t { ONOFF, PCTRL, PICTRL };
const char *MODE_NAMES[] = {"ONOFF", "P", "PI"};
struct Config { Mode mode = ONOFF; float Lmin = 30, Lmax = 80, setpoint = 50, Kp = 20, Ki = 0.5f; } cfg;
float sensorToFloor = 30.0f, fullHeight = 25.0f, airC = 20.0f;
bool calibrated = false;
struct CalStore { uint16_t magic; float s2f, full, air; };
const uint16_t CAL_MAGIC = 0x57A1;
static void saveCal() {
#ifdef __AVR__
  CalStore c = {CAL_MAGIC, sensorToFloor, fullHeight, airC}; EEPROM.put(0, c);
#endif
  calibrated = true;
}
static void loadCal() {
#ifdef __AVR__
  CalStore c; EEPROM.get(0, c);
  if (c.magic == CAL_MAGIC && c.s2f > 5 && c.s2f < 400 && c.full > 1 && c.full < c.s2f) {
    sensorToFloor = c.s2f; fullHeight = c.full; airC = c.air; calibrated = true;
  }
#endif
}

bool running = false, hostControlled = false, pumpOn = false;
uint8_t flags = 0, badPings = 0; uint32_t seq = 0, tStart = 0, lastTs = 0, lastHost = 0, fullSince = 0;
uint32_t pumpSince = 0, dryWin = 0; uint8_t lowCount = 0;                        // when the pump last switched; dry-run window start
float level = NAN, levelCm = NAN, dist = NAN, levelAtFull = 0, levelAtWin = 0, integ = 0; int u = 0;

static char hexDigit(uint8_t v) { return v < 10 ? '0' + v : 'A' + v - 10; }
static int8_t hexVal(char c) { if (c >= '0' && c <= '9') return c - '0'; if (c >= 'A' && c <= 'F') return c - 'A' + 10; if (c >= 'a' && c <= 'f') return c - 'a' + 10; return -1; }
static uint8_t xorSum(const char *s) { uint8_t x = 0; while (*s) x ^= (uint8_t)*s++; return x; }
static void sendFrame(const char *body) {
  uint8_t cs = xorSum(body);
  Serial.write('$'); Serial.print(body); Serial.write('*');
  Serial.write(hexDigit(cs >> 4)); Serial.write(hexDigit(cs & 15)); Serial.write('\n');
}
static void ack(const char *t) { char b[24]; snprintf(b, sizeof(b), "ACK,1,%s", t); sendFrame(b); }
static void err(const char *t, int code, const char *txt) { char b[64]; snprintf(b, sizeof(b), "ERR,1,%s,%d,%s", t, code, txt); sendFrame(b); }

static void pump(int duty) {
  u = constrain(duty, 0, 255);
  bool on = u > 0;
  if (on != pumpOn) pumpSince = millis();
  pumpOn = on;
#if PUMP_PWM
  analogWrite(PIN_PWM, u);
  digitalWrite(PIN_RELAY, RELAY_ACTIVE_LOW ? HIGH : LOW);   // relay output unused: held off
#else
  digitalWrite(PIN_RELAY, (pumpOn ^ RELAY_ACTIVE_LOW) ? HIGH : LOW);
#endif
}
static void stopAll() { running = false; pump(0); integ = 0; }

// ------------------------------------------------------------------ sensor
static float pingCm() {
  digitalWrite(PIN_TRIG, LOW); delayMicroseconds(2);
  digitalWrite(PIN_TRIG, HIGH); delayMicroseconds(10); digitalWrite(PIN_TRIG, LOW);
  unsigned long us = pulseIn(PIN_ECHO, HIGH, 25000UL);        // 25 ms ~ 4 m
  float cmPerUs = (331.3f + 0.606f * airC) / 20000.0f;        // m/s -> cm/us, there and back
  return us ? us * cmPerUs : NAN;
}

// One ping per control step (100 ms): the HC-SR04 needs >= 60 ms between pings, or it hears the
// previous ping still echoing around the tank (ghost readings, much too short). The level is the
// median of the last NBUF accepted pings. A ping is accepted only within JUMP_CM + RATE_CM_S x
// (time since the last accepted ping) of that median: the water cannot move faster than the pump
// fills or the drain empties (~1.4 cm/s on the lab jar), so real motion is always tracked and an
// echo from the walls never is, however consistent. After 5 s of rejections: while the pump runs,
// the sensor cannot be trusted -> sensor fault (pump off); while idle, the buffer restarts.
const uint8_t NBUF = 5, MAX_REJECTS = 50;
const float JUMP_CM = 3.0f, RATE_CM_S = 2.0f;
float dBuf[NBUF]; uint8_t nBuf = 0, iBuf = 0, rejects = 0;
bool sensorDistrust = false;
static float bufMedian() {
  float t[NBUF]; for (uint8_t i = 0; i < nBuf; i++) t[i] = dBuf[i];
  for (uint8_t i = 1; i < nBuf; i++) for (uint8_t j = i; j > 0 && t[j - 1] > t[j]; j--) { float x = t[j]; t[j] = t[j - 1]; t[j - 1] = x; }
  return t[nBuf / 2];
}
static void bufReset() { nBuf = 0; iBuf = 0; rejects = 0; }
static float filteredCm() {                  // NAN: no echo; otherwise the median distance
  float d = pingCm();
  if (isnan(d)) return NAN;
  if (nBuf >= 3 && fabs(d - bufMedian()) > JUMP_CM + RATE_CM_S * 0.1f * (rejects + 1)) {
    if (++rejects >= MAX_REJECTS) { sensorDistrust = true; bufReset(); return NAN; }
    return bufMedian();
  }
  rejects = 0;
  dBuf[iBuf] = d; iBuf = (iBuf + 1) % NBUF; if (nBuf < NBUF) nBuf++;
  return bufMedian();
}
static float medianOf3() {                   // for $ZERO: three pings, 70 ms apart
  float a = pingCm(); delay(70); float b = pingCm(); delay(70); float c = pingCm();
  if (isnan(a) || isnan(b) || isnan(c)) {
    if (!isnan(a) && !isnan(b)) return (a + b) / 2;
    return isnan(a) ? (isnan(b) ? c : b) : a;
  }
  return max(min(a, b), min(max(a, b), c));
}

static void reportCal() {
  char a[10], b[10], c[10];
  dtostrf(sensorToFloor, 1, 1, a); dtostrf(fullHeight, 1, 1, b); dtostrf(airC, 1, 1, c);
  Serial.print("# cal sensor_to_floor_cm="); Serial.print(a); Serial.print(" full_height_cm="); Serial.print(b);
  Serial.print(" air_C="); Serial.println(c);
}

// ------------------------------------------------------------------ protocol
static void handleLine(char *line) {
  if (line[0] != '$') return;
  char *star = strrchr(line, '*');
  if (star) { *star = 0; if (xorSum(line + 1) != (uint8_t)((hexVal(star[1]) << 4) | hexVal(star[2]))) { err("?", 1, "checksum"); return; } }
  char *tok[10]; uint8_t nt = 0;
  for (char *p = strtok(line + 1, ","); p && nt < 10; p = strtok(NULL, ",")) tok[nt++] = p;
  if (nt < 2 || strcmp(tok[1], "1")) { err("?", 2, "version"); return; }
  const char *t = tok[0];
  lastHost = millis();
  if (!strcmp(t, "PING")) return;
  if (!strcmp(t, "CFG")) {
    if (running) { err(t, 3, "stop first"); return; }
    if (nt != 8) { err(t, 4, "fields"); return; }
    uint8_t m = 255; for (uint8_t i = 0; i < 3; i++) if (!strcmp(tok[2], MODE_NAMES[i])) m = i;
    if (m == 255) { err(t, 5, "mode"); return; }
#if !PUMP_PWM
    if (m != ONOFF) { err(t, 8, "on-off pump wiring: P and PI need PUMP_PWM (DC pump on a MOSFET)"); return; }
#endif
    float lo = atof(tok[3]), hi = atof(tok[4]);
    if (!(lo >= 0 && hi > lo)) { err(t, 9, "need 0 <= Lmin < Lmax"); return; }
    cfg.mode = (Mode)m; cfg.Lmin = lo; cfg.Lmax = hi; cfg.setpoint = atof(tok[5]);
    cfg.Kp = atof(tok[6]); cfg.Ki = atof(tok[7]);
    if (cfg.Lmax > grd.Lover - 2) cfg.Lmax = grd.Lover - 2;
    if (cfg.setpoint > grd.Lover - 5) cfg.setpoint = grd.Lover - 5;
    ack(t); return;
  }
  if (!strcmp(t, "CAL")) {
    if (running) { err(t, 3, "stop first"); return; }
    if (nt != 4 && nt != 5) { err(t, 4, "fields"); return; }
    float s2f = atof(tok[2]), full = atof(tok[3]);
    if (!(s2f > 5 && s2f < 400 && full > 1 && full <= s2f - D_MIN_CM)) { err(t, 9, "need 5 < sensor_to_floor < 400, full <= sensor_to_floor - 4"); return; }
    sensorToFloor = s2f; fullHeight = full;
    if (nt == 5) airC = constrain(atof(tok[4]), -10.0f, 50.0f);
    saveCal(); reportCal(); ack(t); return;
  }
  if (!strcmp(t, "ZERO")) {                         // tank empty: the measured distance is sensor -> floor
    if (running) { err(t, 3, "stop first"); return; }
    float d = medianOf3();
    if (isnan(d) || d < 5) { err(t, 9, "no valid echo"); return; }
    sensorToFloor = d;
    if (fullHeight > sensorToFloor - D_MIN_CM) fullHeight = sensorToFloor - D_MIN_CM;
    saveCal(); reportCal(); ack(t); return;
  }
  if (!strcmp(t, "GRD")) {
    if (running) { err(t, 3, "stop first"); return; }
    if (nt != 6) { err(t, 4, "fields"); return; }
    grd.tDry = constrain(atof(tok[2]), 2.0f, 600.0f); grd.riseCm = constrain(atof(tok[3]), 0.1f, 20.0f);
    grd.tMaxOn = constrain(atof(tok[4]), 5.0f, 3600.0f); grd.Lover = constrain(atof(tok[5]), 50.0f, 98.0f);
    ack(t); return;
  }
  if (!strcmp(t, "SET")) { if (nt == 3) { cfg.setpoint = min(atof(tok[2]), grd.Lover - 5); ack(t); } else err(t, 4, "fields"); return; }
  if (!strcmp(t, "RUN")) {
    if (flags & (F_DRY | F_SENSOR | F_TIMEOUT | F_OVERFLOW_LATCH)) { err(t, 6, "fault latched: STOP first"); return; }
    if (!calibrated) { err(t, 12, "not calibrated: $ZERO with the tank empty, or $CAL"); return; }
    running = true; hostControlled = true; seq = 0; tStart = millis(); integ = 0; fullSince = 0; dryWin = 0; lowCount = 0; ack(t); return;
  }
  if (!strcmp(t, "STOP") || !strcmp(t, "ESTOP")) { stopAll(); flags = 0; ack(t); return; }
  err(t, 7, "unknown");
}

static void pollHost() {
  static char buf[80]; static uint8_t n = 0;
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\r') continue;
    if (c == '\n') { buf[n] = 0; if (n) handleLine(buf); n = 0; }
    else if (n < sizeof(buf) - 1) buf[n++] = c; else n = 0;
  }
}

// ------------------------------------------------------------------ control
static void fault(uint8_t f, int code, const char *txt) { stopAll(); flags |= f; err("RUN", code, txt); }

static void controlStep(uint32_t now) {
  float d = filteredCm();
  if (sensorDistrust) {                       // 5 s of readings the water could not produce
    sensorDistrust = false;
    if (running) { fault(F_SENSOR, 15, "the level readings jump more than the water can move: check the sensor's view"); return; }
  }
  if (isnan(d)) { if (++badPings >= 5) { level = NAN; dist = NAN; bufReset(); if (running) { stopAll(); flags |= F_SENSOR; } } }
  else { badPings = 0; dist = d; levelCm = sensorToFloor - d; level = 100.0f * levelCm / fullHeight; }
  if (!running || isnan(level)) { pump(0); return; }

  int duty = 0; float e = cfg.setpoint - level;
  switch (cfg.mode) {
    case ONOFF:                              // ON needs 3 readings in a row below Lmin; OFF is immediate
      lowCount = (level < cfg.Lmin) ? min(lowCount + 1, 10) : 0;
      if (lowCount >= 3) duty = 255; else if (level > cfg.Lmax) duty = 0; else duty = pumpOn ? 255 : 0;
      break;
    case PCTRL: duty = constrain((int)lround(cfg.Kp * e), 0, 255); break;
    case PICTRL: {                                   // same clamping anti-windup as the MATLAB model
      float Ts = TS_MS / 1000.0f, iNew = integ + cfg.Ki * Ts * e, uRaw = cfg.Kp * e + iNew;
      float uu = constrain(uRaw, 0.0f, 255.0f);
      if (uu != uRaw && ((uRaw > uu) == (e > 0))) {
        iNew = constrain(iNew, -cfg.Kp * e, 255.0f - cfg.Kp * e);
        if ((e > 0 && iNew < integ) || (e < 0 && iNew > integ)) iNew = integ;
        uu = constrain(cfg.Kp * e + iNew, 0.0f, 255.0f);
      }
      integ = iNew; duty = (int)lround(uu); break;
    }
  }
#if !PUMP_PWM
  // motor: keep each state for its minimum time (the overflow guard below overrides this)
  if (pumpOn && duty == 0 && now - pumpSince < MIN_ON_MS) duty = 255;
  if (!pumpOn && duty > 0 && now - pumpSince < MIN_OFF_MS) duty = 0;
#endif
  // overflow: above the limit, inside the sensor's dead zone, or the float switch
  if (level > grd.Lover || dist < D_MIN_CM || digitalRead(PIN_FLOAT) == LOW) {
    // above the limit with the pump running means the sensing or the control failed: latch
    if (pumpOn) { fault(F_OVERFLOW | F_OVERFLOW_LATCH, 14, "overflow limit reached with the pump on: check the sensor and the settings"); return; }
    duty = 0; flags |= F_OVERFLOW;
  } else flags &= ~F_OVERFLOW;
  // no filling: over each t_dry window with the pump on, the level must rise rise_cm
  bool fullOn = PUMP_PWM ? (duty >= 200 && level < ((cfg.mode == ONOFF) ? cfg.Lmax : cfg.setpoint) - 5.0f) : (duty > 0 && pumpOn);
  if (fullOn) {
    if (!dryWin) { dryWin = now; levelAtWin = levelCm; }
    else if (now - dryWin >= (uint32_t)(grd.tDry * 1000)) {
      if (levelCm - levelAtWin < grd.riseCm) { fault(F_DRY, 11, "pump on but the level is not rising: dry suction, empty reservoir or blocked pipe?"); return; }
      dryWin = now; levelAtWin = levelCm;
    }
  } else dryWin = 0;
  // run time (ON-OFF: every fill must end at Lmax; P and PI run the pump continuously by design)
  if (cfg.mode == ONOFF && pumpOn && duty > 0 && now - pumpSince > (uint32_t)(grd.tMaxOn * 1000)) { fault(F_TIMEOUT, 13, "pump on longer than t_maxon: check the outlet and the level sensor"); return; }
  pump(duty);
}

static void sendTelemetry(uint32_t now) {
  char sp[10], lc[10], lp[10], er[10];
  if (isnan(levelCm)) strcpy(lc, "nan"); else dtostrf(levelCm, 1, 1, lc);
  if (isnan(level)) { strcpy(lp, "nan"); strcpy(er, "nan"); } else { dtostrf(level, 1, 1, lp); dtostrf(cfg.setpoint - level, 1, 2, er); }
  dtostrf(cfg.mode == ONOFF ? NAN : cfg.setpoint, 1, 1, sp); if (cfg.mode == ONOFF) strcpy(sp, "nan");
  char body[110];
  snprintf(body, sizeof(body), "LTEL,1,%lu,%lu,%s,%s,%s,%s,%s,%d,%d,%X",
           (unsigned long)seq++, (unsigned long)(now - tStart), MODE_NAMES[cfg.mode], sp, lc, lp, er, u,
           pumpOn ? 1 : 0, flags | (running ? F_RUNNING : 0));
  sendFrame(body);
}

void setup() {
  pinMode(PIN_RELAY, OUTPUT); pinMode(PIN_PWM, OUTPUT); pump(0);
  pinMode(PIN_TRIG, OUTPUT); pinMode(PIN_ECHO, INPUT);
  pinMode(PIN_FLOAT, INPUT_PULLUP); pinMode(PIN_BTN, INPUT_PULLUP);
  Serial.begin(115200);
  loadCal();
  char b[112]; snprintf(b, sizeof(b), "HELLO,1,%s,%s,relay_active_low=%d,pump_pwm=%d,calibrated=%d", FW_NAME, FW_REV, RELAY_ACTIVE_LOW, PUMP_PWM, calibrated ? 1 : 0); sendFrame(b);
  if (calibrated) reportCal();
#ifdef __AVR__
  wdt_enable(WDTO_2S);
#endif
}

void loop() {
#ifdef __AVR__
  wdt_reset();
#endif
  pollHost();
  uint32_t now = millis();
  static bool lastBtn = HIGH; static uint32_t tBtn = 0;
  bool b = digitalRead(PIN_BTN);
  if (b != lastBtn && now - tBtn > 50) {
    tBtn = now; lastBtn = b;
    if (b == LOW) {
      if (running) { stopAll(); flags |= F_BUTTON; }
      else if (!(flags & (F_DRY | F_SENSOR | F_TIMEOUT | F_OVERFLOW_LATCH)) && calibrated) { running = true; hostControlled = false; tStart = now; seq = 0; integ = 0; flags = 0; dryWin = 0; }
      else flags = 0;
    }
  }
  if (running && hostControlled && now - lastHost > 3000) { stopAll(); flags |= F_WATCHDOG; err("RUN", 10, "host silent >3 s - pump off"); }
  if (now - lastTs >= TS_MS) { lastTs = now; controlStep(now); sendTelemetry(now); }
}
