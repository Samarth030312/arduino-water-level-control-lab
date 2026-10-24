# Data management

Applies to every run of this repository (WATER-Rnnnn).

> **Raw data is evidence. It is never edited, never overwritten, never deleted, including when
> the run failed.** A failed run is a result.

## Classes of data

| Class | Produced by | Lives in |
|---|---|---|
| **RIG** | the real board and hardware | `data/raw/water_level/`, `data/metadata/water_level/` |
| **EMULATOR** | the firmware compiled for the PC against an emulated plant | a temporary folder (tests, CI); never `data/` |
| **SIMULATION** | MATLAB or Simulink | `results/` |

## Names

A rig run is `WATER-Rnnnn_<yyyymmdd-HHMMSS>_<mission>`, for example
`WATER-R0012_20261101-101500_W2`: the apparatus, a run number never reused, the local start
time, the mission. `data/RUN_REGISTER.csv` holds one line per run; the number comes from it.

## What is kept for a run

| File | Content |
|---|---|
| `data/raw/water_level/<run>.csv` | every telemetry frame of the run (columns: [data](../data/README.md)), written once, read-only |
| `data/metadata/water_level/<run>.json` | the settings sent, the firmware revision, MATLAB version, OS, port, link statistics, the firmware's events, the result |
| `data/metadata/water_level/<run>.png` | the app's window when the run ended |
| `results/evidence/logs/hw_session_<time>.log` | every line between the app and the board in that session, both directions |

Every run is saved: finished, stopped by the firmware (`STOPPED: <reason>`) or by the operator
(`ABORTED`). **SYNC DATA** in the app commits `data/` and `results/` and pushes them.
