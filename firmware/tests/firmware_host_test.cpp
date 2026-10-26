// Runs the real water-level firmware (level_controller.ino) on the PC against an emulated tank,
// DC pump and HC-SR04, drives it like MATLAB would, and checks control and every guard.
//
//   scripts/validation/build_firmware.sh        (builds and runs this)
//
// The emulated tank is a test double, not a measured model of any rig: a 15 L jar (24 x 24 cm,
// 100 % = 26 cm of water, sensor 32 cm above the floor), a mains pump at 25 L/min behind an
// active-HIGH SSR (PUMP_PWM = 0), or a DC pump on a MOSFET (PUMP_PWM = 1, 4 L/min), a gravity
// outlet, and the true speed of sound for the emulated air temperature.

#include "Arduino.h"
#include <algorithm>
#include <string>
#include <chrono>
#include <thread>
#include <fcntl.h>
#include <unistd.h>
#include <termios.h>

#ifndef RELAY_ACTIVE_LOW
#define RELAY_ACTIVE_LOW 0          // the firmware's defaults, needed here before the sketch is included
#endif
#ifndef PUMP_PWM
#define PUMP_PWM 0
#endif

double g_now_ms = 0;
static bool g_realtime = false;                 // --pty mode: real wall-clock time
static double wallMs() {
  using namespace std::chrono;
  static auto t0 = steady_clock::now();
  return duration<double, std::milli>(steady_clock::now() - t0).count();
}
uint32_t millis() { if (g_realtime) g_now_ms = wallMs(); return (uint32_t)g_now_ms; }
uint32_t micros() { millis(); return (uint32_t)(g_now_ms * 1000.0); }
void delay(unsigned long ms);
void delayMicroseconds(unsigned int) {}
static int g_pin[20], g_pwm[20];
void pinMode(uint8_t p, uint8_t m) { if (m == INPUT_PULLUP) g_pin[p] = HIGH; }
void digitalWrite(uint8_t p, uint8_t v) { g_pin[p] = v; }
int digitalRead(uint8_t p) { return g_pin[p]; }
void analogWrite(uint8_t p, int v) { g_pwm[p] = v; }
char *dtostrf(double v, signed char w, unsigned char p, char *b) { sprintf(b, "%*.*f", w, p, v); return b; }
HostSerial Serial;

// ------------------------------------------------------------------ emulated tank + pump + sensor
struct Tank {
#if PUMP_PWM
  double A = 0.15 * 0.15, H = 0.25, hSensor = 0.30, Qmax = 4.0 / 60000;
#else
  double A = 0.24 * 0.24, H = 0.26, hSensor = 0.32, Qmax = 25.0 / 60000;   // 15 L jar, mains pump
#endif
  double h = 0.02;                                     // water depth, m
  double kOut = 0.25 * Qmax / std::sqrt(0.24);         // gravity outlet: a quarter of the pump at 24 cm
  double airC = 20;                                    // true air temperature
  bool reservoirEmpty = false, sensorDead = false;
  int pumpStarts = 0; bool lastOn = false;
  bool pumpOn() const {
#if PUMP_PWM
    return g_pwm[5] > 0;
#else
    return g_pin[4] == (RELAY_ACTIVE_LOW ? LOW : HIGH);
#endif
  }
  void step(double dt) {
#if PUMP_PWM
    double q = reservoirEmpty ? 0 : Qmax * std::max(0.0, (g_pwm[5] / 255.0 - 0.2) / 0.8);
#else
    double q = (pumpOn() && !reservoirEmpty) ? Qmax : 0;
#endif
    if (pumpOn() && !lastOn) pumpStarts++; lastOn = pumpOn();
    h = std::min(std::max(h + dt / A * (q - kOut * std::sqrt(std::max(h, 0.0))), 0.0), hSensor - 0.01);
  }
  unsigned long echoUs() const {
    if (sensorDead) return 0;
    double v = 331.3 + 0.606 * airC;                   // m/s
    return (unsigned long)std::lround(2 * (hSensor - h) / v * 1e6);
  }
} tank;
static double lastStep = 0;
static void advance(double ms) { g_now_ms += ms; tank.step(ms / 1000.0); }
void delay(unsigned long ms) {
  if (g_realtime) { std::this_thread::sleep_for(std::chrono::milliseconds(ms)); g_now_ms = wallMs(); return; }
  advance(ms);
}
unsigned long pulseIn(uint8_t, uint8_t, unsigned long) { return tank.echoUs(); }

#include "../level_controller/level_controller.ino"

static void send(const std::string &body) {
  uint8_t x = 0; for (char c : body) x ^= (uint8_t)c;
  char t[4]; snprintf(t, sizeof t, "%02X", x);
  for (char c : "$" + body + "*" + t + "\n") Serial.in.push_back(c);
}
static void runFor(double s, bool ping = true) {
  double end = g_now_ms + s * 1000, nextPing = g_now_ms;
  while (g_now_ms < end) {
    if (ping && g_now_ms >= nextPing) { send("PING,1"); nextPing += 1000; }
    loop(); advance(1);
  }
}
static int fails = 0;
#define CHECK(cond, msg) do { if (cond) printf("  ok    %s\n", msg); else { printf("  FAIL  %s\n", msg); fails++; } } while (0)
static double lvlPct() { return 100 * tank.h / tank.H; }
static double lastField(int idx) {
  size_t p = Serial.out.rfind("$LTEL,1,"); if (p == std::string::npos) return NAN;
  std::string l = Serial.out.substr(p + 8, Serial.out.find('*', p) - p - 8);
  for (int i = 0; i < idx; i++) l = l.substr(l.find(',') + 1);
  return atof(l.c_str());
}
static void reset(double hPct) { send("STOP,1"); runFor(0.3, false); tank.h = hPct / 100 * tank.H; tank.pumpStarts = 0; }

// --pty [speedup]: run the firmware in real time on a pseudo-terminal so MATLAB can connect to it
// (end-to-end test of water_level_lab <-> real firmware code <-> emulated tank). The firmware keeps
// real time (its 3 s watchdog is real); the tank runs `speedup` times faster.
static int runPty(double speedup) {
  g_realtime = true;
  int m = posix_openpt(O_RDWR | O_NOCTTY);
  if (m < 0 || grantpt(m) || unlockpt(m)) { perror("pty"); return 2; }
  fcntl(m, F_SETFL, O_NONBLOCK);
  int sl = open(ptsname(m), O_RDWR | O_NOCTTY);
  struct termios tio; tcgetattr(sl, &tio); cfmakeraw(&tio); tcsetattr(sl, TCSANOW, &tio);
  printf("PTY %s\n", ptsname(m)); fflush(stdout);
  // relay wiring (as the lab rig): the pump follows the relay pin; P / PI switch it with u > 0
  setup();
  double lastHello = wallMs(), last = wallMs(); bool heard = false;
  for (;;) {
    char b[256]; ssize_t n = read(m, b, sizeof b);
    for (ssize_t i = 0; i < n; i++) Serial.in.push_back(b[i]);
    if (n > 0) heard = true;
    if (!heard && wallMs() - lastHello > 1000) { setup(); lastHello = wallMs(); }
    loop();
    double now = wallMs(); tank.step(speedup * (now - last) / 1000.0); last = now;
    if (!Serial.out.empty()) { ssize_t w = write(m, Serial.out.data(), Serial.out.size()); if (w > 0) Serial.out.erase(0, w); }
    std::this_thread::sleep_for(std::chrono::microseconds(500));
  }
}

static void calibrate() {               // the geometry of the emulated tank, as the operator would
  char b[64]; snprintf(b, sizeof b, "CAL,1,%.1f,%.1f,20", tank.hSensor * 100, tank.H * 100); send(b); runFor(0.2, false);
}

int main(int argc, char **argv) {
  if (argc > 1 && std::string(argv[1]) == "--pty") { calibrated = true; sensorToFloor = tank.hSensor * 100; fullHeight = tank.H * 100;
    return runPty(argc > 2 ? atof(argv[2]) : 1.0); }
#if PUMP_PWM
  printf("water-level firmware host test, PUMP_PWM = 1 (emulated 15x15 cm tank, DC pump on a MOSFET)\n");
#else
  printf("water-level firmware host test, PUMP_PWM = 0 (emulated 15 L jar, mains pump behind an SSR)\n");
#endif
  setup(); runFor(1, false);
  char hello[96]; snprintf(hello, sizeof hello, "$HELLO,1,water_level_lab,dev,relay_active_low=0,pump_pwm=%d,calibrated=0*", PUMP_PWM);
  CHECK(Serial.out.find(hello) != std::string::npos, "HELLO reports the wiring and that it is not calibrated");
  CHECK(!tank.pumpOn(), "pump OFF after power-up");
  send("CFG,1,ONOFF,30,80,50,20,0.5"); send("RUN,1"); runFor(0.3, false);
  CHECK(Serial.out.find("ERR,1,RUN,12,not calibrated") != std::string::npos && !running, "RUN refused until calibrated");

  // $ZERO with the tank empty measures sensor -> floor
  tank.h = 0; send("ZERO,1"); runFor(0.3, false);
  CHECK(fabs(sensorToFloor - tank.hSensor * 100) < 0.3 && calibrated, "$ZERO (empty tank) measures the sensor height");
  calibrate();
  runFor(1, false);
  CHECK(fabs(lastField(5) - 0) < 1.5, "empty tank reads about 0 %");
  tank.h = 0.5 * tank.H; runFor(1, false);
  CHECK(fabs(lastField(5) - 50) < 1.5, "half full reads about 50 %");

  // ON-OFF 30-80 %: several cycles, pump on below Lmin, off above Lmax, never chatters
  reset(10); send("CFG,1,ONOFF,30,80,50,20,0.5"); send("RUN,1");
  double lo = 100, hi = 0; runFor(120);
  for (int i = 0; i < 900; i++) { runFor(1); lo = std::min(lo, lvlPct()); hi = std::max(hi, lvlPct()); }
  printf("        ON-OFF 30-80: level %.1f..%.1f %%, %d pump starts in 900 s\n", lo, hi, tank.pumpStarts);
  CHECK(lo > 25 && lo < 31 && hi > 79 && hi < 88, "ON-OFF cycles between Lmin and Lmax");
  CHECK(tank.pumpStarts >= 3 && tank.pumpStarts < 60, "several clean cycles, no chattering");

#if !PUMP_PWM
  // P and PI are refused on the on-off wiring
  send("STOP,1"); send("CFG,1,PI,30,80,50,20,0.5"); runFor(0.2, false);
  CHECK(Serial.out.find("ERR,1,CFG,8,on-off pump wiring") != std::string::npos, "P / PI refused on the on-off (SSR) wiring");
  // anti short-cycling: a 2 % band would switch fast; the minimum on / off times space the starts
  reset(50); send("CFG,1,ONOFF,49,51,50,20,0.5"); send("RUN,1"); runFor(120);
  printf("        ON-OFF 49-51: %d pump starts in 120 s (minimum on 3 s, off 15 s)\n", tank.pumpStarts);
  CHECK(tank.pumpStarts >= 3 && tank.pumpStarts <= 120 / 18 + 1, "narrow band: it cycles, and the minimum on / off times space the starts");
#else
  // P control on the PWM output
  reset(40); send("CFG,1,P,30,80,50,20,0.5"); send("RUN,1"); runFor(1);
  CHECK(fabs(lastField(7) - std::min(255.0, std::round(20 * lastField(6)))) < 1.5, "P: u = Kp e, clamped 0..255");
  // PI holding the level with the pump near full speed (large outflow): NOT a dry run
  reset(60); tank.kOut = tank.Qmax * 0.63 / std::sqrt(0.15);
  send("CFG,1,PI,30,80,60,20,0.5"); send("RUN,1"); runFor(500);
  tank.kOut *= 0.9 / 0.63; runFor(300);
  printf("        PI at 60 %% with a large outflow: level %.1f %%, u = %.0f\n", lvlPct(), lastField(7));
  CHECK(lastField(7) >= 200 && running && !(flags & F_DRY), "PI holding the level at full pump: no false dry-run trip");
  tank.reservoirEmpty = true; runFor(300);
  CHECK(!running && (flags & F_DRY), "PI: supply lost -> dry-run stop");
  tank.reservoirEmpty = false; tank.kOut = 0.25 * tank.Qmax / std::sqrt(0.24);
#endif

  // overflow guard: above 92 % the pump is forced off; the float switch does the same
  reset(95); send("CFG,1,ONOFF,30,80,50,20,0.5"); send("RUN,1"); runFor(1);
  CHECK(!tank.pumpOn() && (flags & F_OVERFLOW), "overflow guard (> 92 %): pump off");
  reset(20); runFor(16, false); send("RUN,1"); runFor(1); CHECK(tank.pumpOn(), "below Lmin: pump on");
  g_pin[PIN_FLOAT] = LOW; runFor(1);
  CHECK(!tank.pumpOn() && (flags & F_OVERFLOW), "float switch closed: pump off at once (overrides the minimum on time)");
  g_pin[PIN_FLOAT] = HIGH;
  // the sensor's dead zone: water within 4 cm of the sensor is an overflow whatever the calibration says
  reset(20); send("CAL,1,32,40,20"); send("RUN,1"); runFor(1); tank.h = tank.hSensor - 0.03; runFor(1);
  CHECK(!tank.pumpOn() && (flags & F_OVERFLOW), "water within 4 cm of the sensor: pump off");
  calibrate();

  // dry run: pump on, reservoir empty -> no rise over t_dry -> latched stop + error
  reset(20); runFor(16, false); tank.reservoirEmpty = true; send("CFG,1,ONOFF,30,80,50,20,0.5"); send("RUN,1"); runFor(65);
  CHECK(!running && (flags & F_DRY) && !tank.pumpOn(), "dry run: latched off when the level does not rise");
  CHECK(Serial.out.find("the level is not rising") != std::string::npos, "dry run reported to the host");
  send("RUN,1"); runFor(0.2);
  CHECK(Serial.out.find("fault latched") != std::string::npos, "RUN refused until STOP clears the fault");
  tank.reservoirEmpty = false;

  // run time: an outlet as large as the pump -> it never reaches Lmax -> stopped after t_maxon
  reset(20); runFor(16, false); { double k = tank.kOut; tank.kOut = tank.Qmax / std::sqrt(0.06);
  send("GRD,1,600,0.2,60,92"); send("CFG,1,ONOFF,30,80,50,20,0.5"); send("RUN,1"); runFor(70);
  CHECK(!running && (flags & F_TIMEOUT) && !tank.pumpOn(), "pump on longer than t_maxon: latched off");
  tank.kOut = k; send("STOP,1"); send("GRD,1,20,1,180,92"); runFor(0.2, false); }

  // sensor lost: 5 failed pings -> pump off
  reset(20); runFor(16, false); send("RUN,1"); runFor(1); tank.sensorDead = true; runFor(2);
  CHECK(!running && (flags & F_SENSOR) && !tank.pumpOn(), "sensor lost: pump off");
  tank.sensorDead = false;

  // host watchdog
  reset(20); runFor(16, false); send("RUN,1"); runFor(1); runFor(4, false);
  CHECK(!running && !tank.pumpOn() && Serial.out.find("host silent") != std::string::npos, "host watchdog: pump off after 3 s");

  // speed of sound: at 35 C the 20 C constant reads the level too high; $CAL with air 35 C fixes it
  reset(50); tank.airC = 35; runFor(1, false);
  double errUncal = lastField(5) - lvlPct();
  { char b[64]; snprintf(b, sizeof b, "CAL,1,%.1f,%.1f,35", tank.hSensor * 100, tank.H * 100); send(b); } runFor(1, false);
  double errCal = lastField(5) - lvlPct();
  printf("        level error at 35 C air: %.2f %% uncorrected, %.2f %% with $CAL air 35 C\n", errUncal, errCal);
  CHECK(errUncal > 0.8 && fabs(errCal) < 0.4, "air-temperature correction removes the speed-of-sound error");
  tank.airC = 20; calibrate();

  send("CFG,1,BOGUS,30,80,50,20,0.5"); runFor(0.1, false);
  CHECK(Serial.out.find("ERR,1,CFG,5,mode") != std::string::npos, "unknown mode refused");
  send("CFG,1,ONOFF,80,30,50,20,0.5"); runFor(0.1, false);
  CHECK(Serial.out.find("ERR,1,CFG,9") != std::string::npos, "Lmin above Lmax refused");

  if (argc > 1) {
    FILE *f = fopen(argv[1], "w"); size_t p = 0; long n = 0;
    while (p < Serial.out.size()) {
      size_t q = Serial.out.find('\n', p); if (q == std::string::npos) q = Serial.out.size();
      std::string l = Serial.out.substr(p, q - p);
      if (l.rfind("$LTEL", 0) != 0 || n++ % 20 == 0) fprintf(f, "%s\n", l.c_str());
      p = q + 1;
    }
    fclose(f); printf("  transcript -> %s\n", argv[1]);
  }
  printf(fails ? "water-level firmware host test: %d FAILED\n" : "water-level firmware host test: all passed\n", fails);
  return fails != 0;
}
