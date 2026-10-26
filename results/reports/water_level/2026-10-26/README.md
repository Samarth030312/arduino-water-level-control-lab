# Rig session 2026-10-26

The first runs on the real rig: a 15 L jar filled from a 500 L tank by a 0.5 HP-class single-phase
monoblock pump (yellow, Silver brand, nameplate not yet read), switched on its live wire by a
Fotek SSR-40DA from pin D4 of an Arduino Uno; an HC-SR04 above the jar on D8 (TRIG) and D7 (ECHO).
Four registered runs, `WATER-R0001` to `WATER-R0004` in `data/`, 17:59–18:43 IST.

The tables and figures are in **[REPORT.md](REPORT.md)**, generated from `data/` by
`matlab/scripts/level_session_report.m`; every number below comes from there or from the logs.

| Time | Run | Firmware | What happened |
|---|---|---|---|
| 17:54–17:59 | `R0001` W2 30–80 % | `28601cd` | the pump started 9 times with the jar filling and full: ghost echoes; ended when USB dropped (pump off) |
| 18:13–18:18 | `R0002` W2 30–80 % | `e300af3` | one clean fill, 28.6 → 83.6 % in 10 s; 5 lost echoes at 104 s (sensor fault, pump already off), then corrupted telemetry; stopped by the operator |
| 18:25–18:27 | not registered | `b7da4bf` | 5 lost echoes 56 s in, the pump off throughout; the operator suspected a loose HC-SR04 connection and stopped the session (log only: `hw_session_water_20261026-182451.log`) |
| 18:29–18:32 | `R0003` W2 42.5–67.5 % | `b7da4bf` | two fills, one complete cycle; stopped at 193 s by the jump guard (readings the water could not produce) |
| 18:38–18:43 | `R0004` W5 run as on-off 30–80 % | `b7da4bf` | two fills, one complete cycle, the overflow guard reached once (92.9 %, pump already off); stopped by the operator at 273 s |

Logs (every serial line): `results/evidence/logs/hw_session_water_20261026-*.log`; the scripted
sessions: `level_session_20261026-*.log`; each firmware upload: `flash_20261026-*.log`.

## 1. Hypothesis

From [first principles](../../../../docs/FIRST_PRINCIPLES.md), with the default rig (ESTIMATED):

- On-off between Lmin and Lmax cycles the level: pump ON below Lmin, OFF above Lmax, the level
  rising at (Q_in − Q_out) / A and falling at Q_out / A.
- T_on = A ΔL / (Q_in − Q_out), T_off = A ΔL / Q_out.
- The level overshoots Lmax by about Q_in t_d / A ≈ 1.1 cm (4 %) for t_d = 1.5 s.
- The firmware's guards hold the pump off whatever the controller says, at most ~200 starts an hour.

## 2. Procedure

1. Firmware flashed from the app (build: on-off, SSR active-HIGH); the app's geometry sent with
   each run (`$CAL`): sensor 34.2 cm above the floor (measured by the operator with a tape),
   100 % = 22 cm of water; jar 24 × 24 cm (ESTIMATED).
2. R0003 by `matlab/scripts/level_rig_session.m` (10 s idle, then the run); R0004 by the
   operator from the app (mission W5, whose valve step at 600 s was never reached: it ran as on-off).
3. **The jar has no drain yet.** With the pump off, the operator emptied it by hand; the outflow
   in R0003 and R0004 is therefore that hand-emptying, not an orifice.
4. The mains-side checks of [the wiring guide](../../../../docs/hardware/WIRING.md) (earth, RCD, fuse, heatsink) are the
   operator's and are not recorded here.

## 3. Measurements

| | R0003 (42.5–67.5 %) | R0004 (30–80 %) |
|---|---:|---:|
| rise with the pump ON | 1.07 cm/s | 1.51 cm/s |
| fall with the pump OFF (hand-emptying) | 0.047 cm/s | 0.083 cm/s |
| Q_in, Q_out (× 576 cm², ESTIMATED area) | 38.6, 1.6 L/min | 55.2, 2.9 L/min |
| T_on, rig | 6.1 s | 10.0 s |
| T_off, rig | 89 s | 131 s |
| overshoot past Lmax | 2.8 cm | 2.8 cm |
| time the level kept rising after switch-off (overshoot / rise rate) | 2.6 s | 1.8 s |

R0002's fill gives a third rise rate: 28.6 → 83.6 % (6.3 → 18.4 cm) in 10.2 s, ≈ 1.2 cm/s.

**The sensor** ([REPORT.md](REPORT.md), section 2). With the pump off and the surface still, the
firmware's level held to 0.1 cm (idle checks: 14.50 and 10.60 cm, no change in 10 s; a held
value can also mean rejected pings, so this bounds the noise only together with the jump counts below). While the
jar was being emptied by hand, the level carried a ripple of 0.64–0.65 cm (1 σ) about its trend
with a period of about 1.1 s, in both runs. The first sloshing mode of a 24 cm square jar with 10
cm of water is near 1.7 Hz (0.6 s), so the ripple is more likely the hand-emptying than a free
slosh; its cause is not established. In R0001 (before the one-ping-per-step filter) 690 frames
jumped by more than 1.5 cm with the pump off; in R0003 and R0004, 16 and 38.

## 4. Validation

| Prediction | Rig | Verdict |
|---|---|---|
| on-off switches at the thresholds, holds in between | ON once the level read below Lmin, OFF at the first reading above Lmax, in both runs | **confirmed** |
| T_on = A ΔL / (Q_in − Q_out) | 5.1 s vs 6.1 s (R0003); 7.3 s vs 10.0 s (R0004): the formula leaves out the 3 readings before ON, the pipe delay and the run-down | **confirmed in form**; the model with delay gives 6.9 s and 9.1 s |
| T_off = A ΔL / Q_out | 117 s vs 89 s; 133 s vs 131 s: the hand-emptying was not steady | not testable without a drain |
| overshoot ≈ 1.1 cm (4 %) | 2.8 cm (11–13 %) in both runs; the model with the measured flows: 1.6 and 2.6 cm | **larger than predicted**: the water kept rising 1.8–2.6 s after switch-off, against 1.5 s assumed |
| pump flow 25 L/min (ESTIMATED) | 1.07–1.51 cm/s; 39–55 L/min if the jar is 24 × 24 cm | **not confirmed**: either the pump gives more or the jar is narrower; measure the jar |
| guards | overflow guard tripped at 92.9 % (R0004), jump guard stopped R0003, lost-echo guard stopped R0002, minimum off time held; no false pump start after the filter (R0003, R0004) | **confirmed** |
| MATLAB model = Simulink model | T_on 6.9 / 7.1 s and 9.1 / 9.3 s; RMS difference of the level 1.2 and 0.4 cm | **agree** |

P and PI (missions W3, W4, W7) were not run: they need a pump whose speed can be set (a DC pump on
a MOSFET, build `PUMP_PWM=1`). The lab's mains pump on a zero-cross SSR can only be switched,
and the firmware refuses P and PI on that wiring.

## 5. Conclusion

On-off control of the jar works on the rig as designed, and every guard that was reached acted.
The hysteresis band shows clearly: the pump runs in short bursts (6–10 s) and is off for 1.5–2
minutes; with the pump about twenty times stronger than the hand-emptying, almost all of the cycle
is the drain. The overshoot is two to three times the first estimate, so the 100 % mark must keep more
margin below the rim than the 3 cm first advised, or Lmax must be lower.

Limitations: no drain (no Torricelli outflow, so the self-regulating plant and the cycle times
of first principles are untested), one complete cycle per run, the jar's area and rim height
not measured, the sensor height read 37.7 cm empty against 34.2 cm by tape (to be resolved by a
ruler calibration, `docs/experiments/calibration_template.csv`).

Next session ([open items](../../../../docs/knowledge-base/OPEN_ITEMS.md)): fit a drain to the jar,
measure the jar and the rim, calibrate the sensor at five levels, run W1 (fill from empty),
W2 at 30–80 % for at least three cycles, W5 by opening the drain tap mid-run; P and PI once a
DC pump and a MOSFET are fitted.

## Reproduce this report

From a clone, in MATLAB (Simulink optional: without it the dashed Simulink traces are left out):

```matlab
setup
level_session_report('2026-10-26', 'Note', ['The jar has no drain yet: during R0003 and R0004 the operator ' ...
    'emptied it by hand while the pump was off, so the outflow is neither constant nor Torricelli''s; the model ' ...
    'takes it as the constant mean rate measured in each run. After R0002 the operator suspected a loose HC-SR04 ' ...
    'connection and re-seated it.'])
```
