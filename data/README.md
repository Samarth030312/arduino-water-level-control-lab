# Data

Everything in `raw/` is measured on the real rig; nothing is simulated and nothing is ever edited
(the app writes each file once and marks it read-only).

**No runs yet.** The first rig session will fill this folder.

```
RUN_REGISTER.csv                           one line per run: the index
raw/water_level/WATER-Rnnnn_<date-time>_<mission>.csv   the samples, read-only
metadata/water_level/<run>.json          settings sent, firmware, OS, link statistics, events, result
metadata/water_level/<run>.png           the app's window when the run ended
```

A run id reads `WATER-R0001_20261101-101500_W2`: apparatus, run number (never reused),
local start time, mission. The register's columns: `run_id, apparatus, run_no, created, rig,
mission, experiment, run_in_series, controller, settings, result, rows, firmware, port, os,
legacy_id, raw_file, meta_file`.

```matlab
setup
R = levellab.data.register();          % every run
```

In the app, RUNS lists them; **OVERLAY RUN** draws one over the simulation of its own settings.
