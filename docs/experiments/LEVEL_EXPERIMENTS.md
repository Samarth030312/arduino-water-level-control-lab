# Water-level experiments LEVEL-01 … LEVEL-07

> **Pre-registered plans** (2026-10-09), kept as written. In the app these experiments are the
> missions W1–W7.

Mapped to the course guideline tasks (SRC-001 p.23–24). Safety: `docs/hardware/WIRING.md` §3.

| ID | Course task | Hypothesis | Hardware acceptance | Status |
|---|---|---|---|---|
| LEVEL-01 | 1: study the system | Measure tank area, pump flow (fill time with drain closed), drain time; replace ASSUMED values | params updated to MEASURED with run IDs | PLANNED |
| LEVEL-02 | 2: sensor calibration | HC-SR04 reading matches a ruler within 0.5 cm at empty, 30 %, 80 % | three-point check recorded | PLANNED |
| LEVEL-03 | 3–4: ON-OFF 30/80 % | Pump on below Lmin, off above Lmax; repeated cycles | ≥ 3 full cycles; overshoot past both thresholds recorded | SIM-DONE; RIG 2026-10-26: one cycle in each of two runs, no drain (`WATER-R0003`, `R0004`) |
| LEVEL-04 | 5: observations | Fill time, switching frequency, no chattering at a 50-point band | fill/drain times and starts/h tabulated | SIM-DONE |
| LEVEL-05 | 5: chattering | Narrow band (50–55 %) → many starts/h | starts/h ≥ 5× LEVEL-03 | SIM-DONE |
| LEVEL-06 | 6–7: Simulink + compare; disturbance | Simulink Relay-block model reproduces period and band; opening the drain lengthens fills | period within 10 % of hardware after LEVEL-01 calibration | SIM-DONE |
| LEVEL-07 | questions 5–8, 22–23: P / PI | P leaves an offset; PI removes it and rejects the drain step (MOSFET wiring) | e_ss and recovery recorded | SIM-DONE; rig needs a DC pump on a MOSFET (OI-L6) |

Evidence: `results/evidence/simulation_runs/water_level/`, hardware `data/raw/water_level/`.
