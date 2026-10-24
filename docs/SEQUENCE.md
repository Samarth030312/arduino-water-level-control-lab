# The sequence: everything, in order

## Without hardware

**1. Set up.** In MATLAB:

```matlab
gitclone("https://github.com/Samarth030312/arduino-water-level-control-lab.git", Depth=1);
cd arduino-water-level-control-lab
setup open
```

**2. The tank (W1).** A fixed pump command from empty: where does the level stop? Change the
outlet bore, the valve and the pump flow in the physics panel and predict, before you play, where
it will stop now. Read: [first principles](FIRST_PRINCIPLES.md).

**3. On-off (W2).** The cycle: fill and drain times, starts per hour; halve the band.

**4. P and PI (W3, W4).** The offset of P against the REF column; PI without it.

**5. Disturbance, limits, windup (W5–W7).** The outlet valve opens; a setpoint near the rim; a
saturated pump, with and without anti-windup. Switch the firmware's guards off (simulation only)
to see what they prevent.

**6. Simulink.** **OPEN IN SIMULINK** on any mission. Read: [Simulink](SIMULINK.md).

## With the rig

**7. Build and wire** ([replicate](REPLICATE.md)), [checklist](safety/EXPERIMENT_CHECKLIST.md).

**8. Flash, connect, calibrate** (SENSOR CHECK against a ruler).

**9. W1 on the rig**, then fit your tank: physics panel until SIM matches RIG.

**10. W2 → W7 on the rig.** Every run lands in `data/raw/water_level/` and
`data/RUN_REGISTER.csv`; RUNS → OVERLAY RUN draws it over the simulation of its own settings.
