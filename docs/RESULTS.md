# Results

**No rig session yet.** Everything this repository can say today is a prediction from the
physics of the default rig (ASSUMED values) and a test of the firmware against an emulated rig.

| What | Where |
|---|---|
| the predictions, mission by mission | the app: every mission's SIM and REF columns; [first principles](FIRST_PRINCIPLES.md) |
| the firmware against the emulated rig | `firmware/tests/firmware_host_test.cpp` (run by `scripts/validation/host_tests.sh` and CI) |
| the app, the firmware and the emulated rig end to end | `matlab/tests/e2e/e2e_mission_control.m` (CI, Linux) |
| Simulink against the MATLAB model | `matlab/tests/test_simulink_model.m` |

When the first session is recorded, its report goes to `results/reports/<date>/` and this page
lists what the rig showed against each prediction, as the
[DC servo lab](https://github.com/Samarth030312/rhino-rmcs-2303-dc-servo-control/blob/main/docs/RESULTS.md) does.
