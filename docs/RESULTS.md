# Results

**First rig session: 2026-10-26**, four runs, on-off control (missions W2 and W5)
([session page](../results/reports/water_level/2026-10-26/README.md),
[generated report](../results/reports/water_level/2026-10-26/REPORT.md)). A 15 L jar, a 0.5 HP-class
mains pump through a Fotek SSR-40DA, an HC-SR04, an Arduino Uno. The jar has no drain yet: it was
emptied by hand between fills.

| | Predicted (ESTIMATED rig) | Rig |
|---|---|---|
| on-off switching | ON below Lmin, OFF above Lmax, hold in between | as predicted, two runs |
| rise with the pump ON | 0.72 cm/s (25 L/min into 24 × 24 cm) | 1.07–1.51 cm/s |
| T_on, 42.5–67.5 % / 30–80 % | 6.9 s / 9.1 s (model with the measured flows) | 6.1 s / 10.0 s |
| overshoot past Lmax | 1.1 cm (4 %) | 2.8 cm (11–13 %) |
| guards | overflow, lost echo, jump, minimum times | each one reached acted; no false pump start once the filter was fixed |
| MATLAB vs Simulink, same run | — | T_on within 0.2 s; level RMS 0.4–1.2 cm |
| P, PI | offset with P, none with PI | not run: they need a DC pump on a MOSFET |

What the session changed: the firmware (one ping per 100 ms step and a median-of-5 filter with a
rate gate, after ghost echoes started the pump in R0001; message texts moved to flash after
corrupted telemetry in R0002), and the Simulink relay (it now starts with the pump off, as the
firmware does).

| What | Where |
|---|---|
| the predictions, mission by mission | the app: every mission's SIM and REF columns; [first principles](FIRST_PRINCIPLES.md) |
| the firmware against the emulated rig | `firmware/tests/firmware_host_test.cpp` (run by `scripts/validation/host_tests.sh` and CI) |
| the app, the firmware and the emulated rig end to end | `matlab/tests/e2e/e2e_mission_control.m` (CI, Linux) |
| Simulink against the MATLAB model | `matlab/tests/test_simulink_model.m` |
| a session's report from `data/`, each run replayed in MATLAB and Simulink | `matlab/scripts/level_session_report.m` |
| a scripted rig session (idle noise, then on-off runs) | `matlab/scripts/level_rig_session.m` |

Each session's report goes to `results/reports/water_level/<date>/`; this page lists what the rig
showed against each prediction, as the
[DC servo lab](https://github.com/Samarth030312/rhino-rmcs-2303-dc-servo-control/blob/main/docs/RESULTS.md) does.
