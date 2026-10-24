// Arduino water level control lab: tank, DC pump, HC-SR04, relay
// Arduino Uno + HC-SR04 ultrasonic sensor + 12 V DC pump via relay module (on-off)
// or logic-level MOSFET (PWM, for P / PI).
//
// Course tasks (SRC-001 p.23): ON-OFF control, pump ON below Lmin, OFF above Lmax;
// record fill time and switching frequency. Telemetry: protocol v1 ($LTEL).
//
// PINS (docs/hardware/WIRING.md)
//   D8   HC-SR04 TRIG          D7   HC-SR04 ECHO
//   D4   relay module IN (pump on/off)         RELAY_ACTIVE_LOW = 1 for the common
//                                              blue opto-isolated modules: CHECK yours
//   D5   MOSFET gate via 220 ohm (PWM 980 Hz)  only for P / PI wiring
//   D3   optional Lmax float switch to GND (closed = water at the top): hard overflow stop
//   D12  START / STOP pushbutton to GND
//
// Geometry: the sensor face is SENSOR_TO_FLOOR_CM above the tank floor and 100 % is
// FULL_HEIGHT_CM. Change with  $CAL,1,<sensor_to_floor_cm>,<full_height_cm>[,<air_C>]
// Speed of sound v = 331.3 + 0.606 T m/s (air temperature T, default 20 C -> 343.4 m/s);
// level = sensor_to_floor - v * echo_time / 2 (WATER handout S3-1).
//
// GUARDS: pump off above 92 %; latched off after 60 s at >= 200/255 without a 2 %
// rise while the level is more than 5 % below its target (Lmax for ON-OFF, the setpoint for
// P/PI) - dry run / empty reservoir / blocked pipe. The target condition keeps a PI that holds
// the level with the pump near full speed (big outflow) from tripping. Off after 5 failed
// pings; off if MATLAB goes silent for 3 s while it is in control.
//
// STATUS: runs on the PC against an emulated tank + HC-SR04 (firmware/tests); NOT yet run on hardware.

#define FW_NAME "water_level_lab"
#ifndef FW_REV
#define FW_REV "dev"
#endif
#ifndef RELAY_ACTIVE_LOW
#define RELAY_ACTIVE_LOW 1
#endif

const uint8_t PIN_TRIG = 8, PIN_ECHO = 7, PIN_RELAY = 4, PIN_PWM = 5, PIN_FLOAT = 3, PIN_BTN = 12;
const uint16_t TS_MS = 100;
const float L_OVER = 92.0f, DRY_RISE = 2.0f;
const uint32_t DRY_MS = 60000;
const uint8_t F_RUNNING = 1, F_SENSOR = 2, F_OVERFLOW = 4, F_DRY = 8, F_WATCHDOG = 16, F_BUTTON = 32;

enum Mode : uint8_t { ONOFF, PCTRL, PICTRL };
const char *MODE_NAMES[] = {"ONOFF", "P", "PI"};
struct Config { Mode mode = ONOFF; float Lmin = 30, Lmax = 80, setpoint = 50, Kp = 20, Ki = 0.5f; } cfg;
float sensorToFloor = 30.0f, fullHeight = 25.0f, airC = 20.0f;

bool running = false, hostControlled = false, pumpOn = false;
uint8_t flags = 0, badPings = 0; uint32_t seq = 0, tStart = 0, lastTs = 0, lastHost = 0, fullSince = 0;
float level = NAN, levelCm = NAN, levelAtFull = 0, integ = 0; int u = 0;

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
  u = constrain(duty, 0, 255); pumpOn = u > 0;
  digitalWrite(PIN_RELAY, (pumpOn ^ RELAY_ACTIVE_LOW) ? HIGH : LOW);
  analogWrite(PIN_PWM, u);
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

static float medianOf3() {
  float a = pingCm(); delay(10); float b = pingCm(); delay(10); float c = pingCm();
  if (isnan(a) || isnan(b) || isnan(c)) {
    if (!isnan(a) && !isnan(b)) return (a + b) / 2;
    return isnan(a) ? (isnan(b) ? c : b) : a;
  }
  return max(min(a, b), min(max(a, b), c));
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
    cfg.mode = (Mode)m; cfg.Lmin = atof(tok[3]); cfg.Lmax = atof(tok[4]); cfg.setpoint = atof(tok[5]);
    cfg.Kp = atof(tok[6]); cfg.Ki = atof(tok[7]);
    if (cfg.Lmax > L_OVER - 2) cfg.Lmax = L_OVER - 2;
    if (cfg.setpoint > L_OVER - 5) cfg.setpoint = L_OVER - 5;
    ack(t); return;
  }
  if (!strcmp(t, "CAL")) {
    if (nt != 4 && nt != 5) { err(t, 4, "fields"); return; }
    sensorToFloor = atof(tok[2]); fullHeight = atof(tok[3]);
    if (nt == 5) airC = constrain(atof(tok[4]), -10.0f, 50.0f);
    ack(t); return;
  }
  if (!strcmp(t, "SET")) { if (nt == 3) { cfg.setpoint = min(atof(tok[2]), L_OVER - 5); ack(t); } else err(t, 4, "fields"); return; }
  if (!strcmp(t, "RUN")) {
    if (flags & (F_DRY | F_SENSOR)) { err(t, 6, "fault latched: STOP first"); return; }
    running = true; hostControlled = true; seq = 0; tStart = millis(); integ = 0; fullSince = 0; ack(t); return;
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
static void controlStep(uint32_t now) {
  float d = medianOf3();
  if (isnan(d)) { if (++badPings >= 5) { level = NAN; if (running) { stopAll(); flags |= F_SENSOR; } } }
  else { badPings = 0; levelCm = sensorToFloor - d; level = 100.0f * levelCm / fullHeight; }
  if (!running || isnan(level)) { pump(0); return; }

  int duty = 0; float e = cfg.setpoint - level;
  switch (cfg.mode) {
    case ONOFF:
      if (level < cfg.Lmin) duty = 255; else if (level > cfg.Lmax) duty = 0; else duty = pumpOn ? 255 : 0;
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
  // guards
  if (level > L_OVER || digitalRead(PIN_FLOAT) == LOW) { duty = 0; flags |= F_OVERFLOW; } else flags &= ~F_OVERFLOW;
  float target = (cfg.mode == ONOFF) ? cfg.Lmax : cfg.setpoint;
  if (duty >= 200 && level < target - 5.0f) {
    if (!fullSince) { fullSince = now; levelAtFull = level; }
    if (now - fullSince > DRY_MS && level - levelAtFull < DRY_RISE) { stopAll(); flags |= F_DRY; err("RUN", 11, "no level rise at full pump: dry run?"); return; }
  } else fullSince = 0;
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
  char b[48]; snprintf(b, sizeof(b), "HELLO,1,%s,%s,relay_active_low=%d", FW_NAME, FW_REV, RELAY_ACTIVE_LOW); sendFrame(b);
}

void loop() {
  pollHost();
  uint32_t now = millis();
  static bool lastBtn = HIGH; static uint32_t tBtn = 0;
  bool b = digitalRead(PIN_BTN);
  if (b != lastBtn && now - tBtn > 50) {
    tBtn = now; lastBtn = b;
    if (b == LOW) {
      if (running) { stopAll(); flags |= F_BUTTON; }
      else if (!(flags & (F_DRY | F_SENSOR))) { running = true; hostControlled = false; tStart = now; seq = 0; integ = 0; flags = 0; }
      else flags = 0;
    }
  }
  if (running && hostControlled && now - lastHost > 3000) { stopAll(); flags |= F_WATCHDOG; err("RUN", 10, "host silent >3 s - pump off"); }
  if (now - lastTs >= TS_MS) { lastTs = now; controlStep(now); sendTelemetry(now); }
}
