# First principles: tank, outlet, pump, sensor, controller

Code: `levellab.level.physics` (parameters from what is on the bench), `levellab.level.simulate`
(the loop, with the firmware's guards), `levellab.level.cycleAnalysis` (fill and drain times,
flows, from a run), `levellab.level.calibrate` (the sensor against a ruler). The defaults describe
the lab rig of 2026-10-26 (a 15 L jar, a 0.5 HP-class mains pump behind an SSR, an 8 mm drain);
every one is ESTIMATED until measured.

## 1. The tank and the outlet

Mass balance, with the outflow from Torricelli's law through an outlet of bore d, discharge
coefficient Cd (about 0.6 for a sharp hole, 0.8 for a short tube) and a valve opening:

```
A dh/dt = q_in − q_out,      q_out = k √h,      k = Cd · a · √(2g),   a = valve · π d² / 4
steady level for an inflow q:   h = (q / k)²
```

| Default (rig, ESTIMATED) | Value | Derived | Value |
|---|---|---|---|
| jar 24 × 24 cm inside, 100 % = 26 cm of water | A = 0.0576 m², 15.0 L | k | 1.34 · 10⁻⁴ m^2.5/s |
| drain 8 mm, Cd 0.6, open | | outflow at 30 % / 80 % / 100 % | 2.2 / 3.7 / 4.1 L/min |
| pump 25 L/min at zero head, 25 m shut-off head | | balance level at full pump | ~10 m: none (the jar overflows) |

The pump delivers six times what the drain can take away: left on, it fills the empty jar to the
rim in under a minute and then overflows it. The level must be controlled, and the guards in section 5 must hold.

The square root makes the tank nonlinear. Linearised at a level h₀ (q_in = q₀ + q, h = h₀ + δh):

```
A dδh/dt = q − (k / 2√h₀) δh      →      H(s) / Q(s) = K / (τ s + 1),
K = 2 √h₀ / k,     τ = 2 A √h₀ / k
```

| Level | h₀ | τ | K |
|---|---|---|---|
| 30 % | 7.8 cm | 241 s | 4.2 · 10³ s/m² |
| 50 % | 13 cm | 311 s | 5.4 · 10³ s/m² |
| 80 % | 20.8 cm | 393 s | 6.8 · 10³ s/m² |

τ grows with √h₀: the deeper the water, the more slowly a change in inflow shows. The same
controller behaves differently at different levels.

**Self-regulating, not integrating.** With a gravity drain the tank finds its own balance for any
inflow it can hold (h = (q/k)²): it is self-regulating, a first-order lag. With a pumped (constant)
outflow it would be a pure integrator, A dh/dt = q_in − q_out, and only integral action could
hold a level against it.

## 2. The pump

A single-phase induction motor driving a self-priming centrifugal pump: it runs at one speed.
Flow falls with the head it lifts (Q_max at zero head to nothing at the shut-off head; here the
head is well under a metre, so the pump gives nearly Q_max); it reaches speed in a fraction of a
second; the water arrives after a delay (priming, pipe filling: 1.5 s assumed).

It can only be **switched**, not throttled: behind a zero-cross SSR, which switches whole mains
half-cycles, an induction motor fed in bursts hums, heats and loses torque. Each start draws 5–7
times the running current: motors are rated for a limited number of starts an hour, so the
firmware keeps every on and off state for a minimum time (3 s on, 15 s off).

## 3. The sensor

The HC-SR04 sends a 40 kHz burst and times its echo: distance d = v · t / 2, level =
sensor height − d, with the speed of sound v = 331.3 + 0.606 T m/s (T in °C). At 20 °C, v =
343.4 m/s; at 35 °C, 352.5 m/s. Code that assumes 20 °C in a 35 °C room computes distances 2.6 %
too short: at 30 cm from the sensor the level reads ~0.8 cm too high. The app sends the air
temperature with each run.

Its limits: nothing closer than about 2 cm; a beam about ±15° wide (16 cm across at 30 cm);
resolution of a few millimetres; ripples, foam and the jar's walls give false echoes. Pings closer
than about 60 ms hear the previous ping's echo still ringing in the jar (on the rig, three pings
10 ms apart started the pump with the jar full). The firmware pings once per 0.1 s step and reports
the median of the last five accepted pings; a ping further from that median than 3 cm plus 2 cm/s
of elapsed time is rejected, since the water cannot move that fast (the rig's fastest rise is
1.5 cm/s). Five seconds of rejected pings while the pump is under control is a sensor fault.

## 4. Control: on-off with two thresholds

The course's law: pump ON below Lmin, OFF above Lmax, unchanged in between (a relay with
hysteresis). The level cycles between the thresholds. One cycle, with Q_in the pump's flow and
Q_out the mean drain flow over the band:

```
T_on  = A (Lmax − Lmin) / (Q_in − Q_out),      T_off = A (Lmax − Lmin) / Q_out
```

With the defaults, 30–80 % (13 cm, 7.5 L): T_on = 7.5 L / (24.6 − 3.0 L/min) ≈ 21 s,
T_off = 7.5 L / 2.9 L/min ≈ 155 s, a cycle of ~3 minutes, 20 starts an hour. The simulation of
the same loop (sensor, delay, guards): fill 21.6 s, drain 157 s, cycle 179 s, 22 starts an hour,
the level between 30.5 % and 84.3 %.

**Overshoot.** After the switch-off the pipe still delivers for the delay: ≈ Q_in t_d / A =
417 mL/s × 1.5 s / 576 cm² ≈ 1.1 cm ≈ 4 % of the jar (simulated: Lmax 80 % → peak 84.3 %).
On the rig (2026-10-26) it was 2.8 cm: the level kept rising for 1.8–2.6 s at 1.1–1.5 cm/s
([results](RESULTS.md)).
Undershoot at Lmin is small: the drain is slow.

**Band width.** Halving the band halves both times and doubles the starts per hour. Below the
sensor's noise (a few mm, ~1 %) the relay would chatter; the firmware's minimum on and off times
stop that at ~200 starts an hour, still too many for the motor: keep the band wide on the rig.

| Law | On this rig |
|---|---|
| on-off, Lmin / Lmax | the rig's law (above) |
| on-off with a narrow band | more starts; chattering is held off by the minimum times |
| P, PI | simulation only with this pump (no speed control); with a PWM DC pump: P leaves an offset (the drain needs a pump command, and P gives one only with an error); PI removes it; clamping prevents windup when the pump saturates |

## 5. The interlock (guards)

Truth table of the firmware (`firmware/level_controller`), evaluated every 0.1 s:

| Condition | Pump | Latched |
|---|---|---|
| level > 92 %, or water within 4 cm of the sensor, or the float switch closed | OFF | no |
| pump ON for 20 s and the level rose < 1 cm (dry suction, empty reservoir, blocked or broken pipe) | OFF | yes |
| pump ON for 180 s without reaching Lmax (drain too large, leak, sensor fault) | OFF | yes |
| 5 failed pings in a row | OFF | yes |
| 5 s of pings rejected as jumps the water cannot make, while running | OFF | yes |
| MATLAB silent for 3 s while it controls | OFF | yes (until a new RUN) |
| program stuck for 2 s | the AVR watchdog resets the board: D4 LOW, OFF | — |
| not calibrated | RUN refused | — |
| otherwise | as the controller says, held ≥ 3 s on and ≥ 15 s off | — |

## 6. Identifying the rig

1. Measure the jar (inside length, width, height to the rim), the sensor height above the floor,
   the drain bore; enter them in the app's physics panel.
2. Calibrate the sensor at five levels or more against a ruler (`docs/experiments/calibration_template.csv`,
   `levellab.level.calibrate`): fit a line, report its largest error and the noise when still.
3. From an on-off run, the rise rate with the pump on and the fall rate with it off give
   Q_in − Q_out and Q_out (× A); predict T_on and T_off from section 4 and compare.
4. Type the measured A, Q_max and drain into the physics panel until the SIM column matches the RIG column.
