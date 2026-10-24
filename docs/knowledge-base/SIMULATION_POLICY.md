# Simulation policy

## 1. A simulation is a prediction, not a measurement

- Simulated runs are labelled SIMULATION (`data_class` in their metadata) and live under
  `results/`, never in `data/raw/`.
- Agreement with the textbook is not validation. Only a rig run, overlaid on the simulation of
  its own settings (RUNS → OVERLAY RUN), validates the model.

## 2. Parameters carry their status

All plant parameters come from `levellab.level.physics` and carry a status (VERIFIED_FROM_MANUAL,
MEASURED, TESTED, ESTIMATED, ASSUMED, UNVERIFIED; see [INDEX](INDEX.md)) and a source. A
MEASURED value names the session it came from. When a measurement replaces an estimate, change
the number **and** the status.

## 3. Simulate the controller that will run

The simulation reproduces the firmware's loop, not an idealised continuous one: its sample
time, its quantised measurement, its output limits and the firmware's control laws (on-off, P, PI with clamping) and its guards. If the firmware changes any of
these, the simulation changes with it, in the same commit.

## 4. Two implementations must agree

`levellab.level.simulate` and `water_level_plant.slx` are two implementations of the same model; test_simulink_model checks they agree. If they disagree,
one of them is wrong: fix it, do not loosen the tolerance.

## 5. What the simulation does not represent

waves and sloshing, the pump's real curve, air in the pipe, the echo's angle. A report repeats these next to any simulated result it uses.
