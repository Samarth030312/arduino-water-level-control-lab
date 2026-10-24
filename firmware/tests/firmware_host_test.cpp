// Runs the real water-level firmware (level_controller.ino) on the PC against an emulated tank,
// DC pump and HC-SR04, drives it like MATLAB would, and checks control and every guard.
//
//   scripts/validation/build_firmware.sh        (builds and runs this)
//
// The emulated tank is a test double (15 x 15 cm, 4 L/min pump, gravity outlet, true speed of
// sound from the emulated air temperature), not a model of the real rig.

#include "Arduino.h"
#include <algorithm>
#include <string>
#include <chrono>
#include <thread>
#include <fcntl.h>
#include <unistd.h>
#include <termios.h>

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
  double A = 0.15 * 0.15, H = 0.25, hSensor = 0.30;   // m^2, m (100 %), sensor face above floor
  double h = 0.02;                                     // water depth, m
  double Qmax = 4.0 / 60000;                           // m^3/s
  double kOut = Qmax / std::sqrt(0.24);                // gravity outlet: full pump settles at 24 cm
  double airC = 20;                                    // true air temperature
  bool reservoirEmpty = false, sensorDead = false;
  bool pwmWiring = false;                              // P / PI: pump on a MOSFET (D5), 20 % dead zone
  int pumpStarts = 0; bool lastOn = false;
  bool pumpOn() const {                                // relay module, active LOW (firmware default)
    return g_pin[4] == LOW;
  }
  void step(double dt) {
    double q = (pumpOn() && !reservoirEmpty) ? Qmax : 0;
    if (pwmWiring) q = reservoirEmpty ? 0 : Qmax * std::max(0.0, (g_pwm[5] / 255.0 - 0.2) / 0.8);
    if (pumpOn() && !lastOn) pumpStarts++; lastOn = pumpOn();
    h = std::min(std::max(h + dt / A * (q - kOut * std::sqrt(std::max(h, 0.0))), 0.0), H + 0.05);
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

int main(int argc, char **argv) {
  if (argc > 1 && std::string(argv[1]) == "--pty") return runPty(argc > 2 ? atof(argv[2]) : 1.0);
  printf("water-level firmware host test (emulated 15x15 cm tank, 4 L/min pump, HC-SR04)\n");
  setup(); runFor(1, false);
  CHECK(Serial.out.find("$HELLO,1,water_level_lab,dev,relay_active_low=1*") != std::string::npos, "HELLO reports the relay polarity");
  CHECK(!tank.pumpOn(), "pump OFF after power-up");
  CHECK(fabs(lastField(5) - lvlPct()) < 1.5, "level reading matches the tank (20 C, default geometry)");

  // ON-OFF 30-80 %: several cycles, pump on below Lmin, off above Lmax, never chatters
  reset(10); send("CFG,1,ONOFF,30,80,50,20,0.5"); send("RUN,1");
  double lo = 100, hi = 0; runFor(60);
  for (int i = 0; i < 1500; i++) { runFor(1); lo = std::min(lo, lvlPct()); hi = std::max(hi, lvlPct()); }
  printf("        ON-OFF 30-80: level %.1f..%.1f %%, %d pump starts in 1500 s\n", lo, hi, tank.pumpStarts);
  CHECK(lo > 25 && lo < 31 && hi > 79 && hi < 86, "ON-OFF cycles between Lmin and Lmax");
  CHECK(tank.pumpStarts >= 3 && tank.pumpStarts < 40, "several clean cycles, no chattering");

  // P control on the PWM output (pump model uses the relay pin: P/PI need the MOSFET wiring;
  // here the relay follows u > 0, so only check the computed duty)
  reset(40); send("CFG,1,P,30,80,50,20,0.5"); send("RUN,1"); runFor(1);
  CHECK(fabs(lastField(7) - std::min(255.0, std::round(20 * lastField(6)))) < 1.5, "P: u = Kp e, clamped 0..255");

  // overflow guard: level above 92 % forces the pump off; float switch does the same
  reset(95); send("CFG,1,ONOFF,30,80,50,20,0.5"); send("RUN,1"); runFor(1);
  CHECK(!tank.pumpOn() && (flags & F_OVERFLOW), "overflow guard (> 92 %): pump off");
  reset(20); send("RUN,1"); runFor(1); CHECK(tank.pumpOn(), "below Lmin: pump on");
  g_pin[PIN_FLOAT] = LOW; runFor(1);
  CHECK(!tank.pumpOn() && (flags & F_OVERFLOW), "float switch closed: pump off");
  g_pin[PIN_FLOAT] = HIGH;

  // dry run: pump on, reservoir empty -> no rise for 60 s -> latched stop + error
  reset(20); tank.reservoirEmpty = true; send("CFG,1,ONOFF,30,80,50,20,0.5"); send("RUN,1"); runFor(65);
  CHECK(!running && (flags & F_DRY) && !tank.pumpOn(), "dry run: latched off after 60 s without a rise");
  CHECK(Serial.out.find("no level rise at full pump") != std::string::npos, "dry run reported to the host");
  send("RUN,1"); runFor(0.2);
  CHECK(Serial.out.find("fault latched") != std::string::npos, "RUN refused until STOP clears the fault");
  tank.reservoirEmpty = false;

  // balanced at the setpoint with the PWM pump near full speed (large outflow): NOT a dry run.
  // The earlier rule (>= 200/255 for 60 s, < 2 % rise) tripped here.
  reset(60); tank.pwmWiring = true; tank.kOut = tank.Qmax * 0.63 / std::sqrt(0.15);  // holding 60 % needs u ~ 180
  send("CFG,1,PI,30,80,60,20,0.5"); send("RUN,1"); runFor(500);
  tank.kOut *= 0.9 / 0.63;                                 // outlet opened: now holding 60 % needs u ~ 235
  runFor(300);
  printf("        PI at 60 %% with a large outflow: level %.1f %%, u = %.0f\n", lvlPct(), lastField(7));
  CHECK(lastField(7) >= 200, "the PWM pump really is above 200/255 while holding the level");
  CHECK(running && !(flags & F_DRY), "PI holding the level at full pump: no false dry-run trip");
  // ... but a real dry run in PI is still caught: water supply stops, level falls
  tank.reservoirEmpty = true; runFor(300);
  CHECK(!running && (flags & F_DRY), "PI: supply lost -> dry-run stop");
  tank.reservoirEmpty = false; tank.pwmWiring = false; tank.kOut = tank.Qmax / std::sqrt(0.24);

  // sensor lost: 5 failed pings -> pump off
  reset(20); send("RUN,1"); runFor(1); tank.sensorDead = true; runFor(2);
  CHECK(!running && (flags & F_SENSOR) && !tank.pumpOn(), "sensor lost: pump off");
  tank.sensorDead = false;

  // host watchdog
  reset(20); send("RUN,1"); runFor(1); runFor(4, false);
  CHECK(!running && !tank.pumpOn() && Serial.out.find("host silent") != std::string::npos, "host watchdog: pump off after 3 s");

  // speed of sound: at 35 C the 20 C constant reads the level too high; $CAL with air 35 C fixes it
  reset(50); tank.airC = 35; runFor(1, false);
  double errUncal = lastField(5) - lvlPct();
  send("CAL,1,30,25,35"); runFor(1, false);
  double errCal = lastField(5) - lvlPct();
  printf("        level error at 35 C air: %.2f %% uncorrected, %.2f %% with $CAL air 35 C\n", errUncal, errCal);
  CHECK(errUncal > 0.8 && fabs(errCal) < 0.3, "air-temperature correction removes the speed-of-sound error");
  tank.airC = 20; send("CAL,1,30,25,20"); runFor(0.2, false);

  send("CFG,1,BOGUS,30,80,50,20,0.5"); runFor(0.1, false);
  CHECK(Serial.out.find("ERR,1,CFG,5,mode") != std::string::npos, "unknown mode refused");

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
