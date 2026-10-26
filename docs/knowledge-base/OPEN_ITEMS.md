# Open items and conflicts

An item closes only with evidence (a measurement, an inspection photo, or a document quote).
Record how it was closed.

| ID | Fact needed | Why it matters | How to resolve | Status |
|---|---|---|---|---|
| OI-L1 | The tank: the lab uses a 15 L oil jar (2026-10-26); inside length, width, height to the rim | every level and flow | measure. The overshoot measured on the rig is 2.8 cm ([2026-10-26](../../results/reports/water_level/2026-10-26/README.md)): keep at least 4 cm between 100 % and the rim | OPEN |
| OI-L2 | The outlet: the jar has no drain yet; bore, sharp hole or short tube (Cd) | the outflow k √h, the cycles | drill and measure; fit from the fall rate. In the first session the jar was emptied by hand | OPEN |
| OI-L3 | The pump: yellow Silver 0.5 HP-class single-phase monoblock, 230 V (2026-10-26); rated current, flow, head from its nameplate | the inflow, the fuse, the SSR's heat | read the nameplate. Rise rate measured: 1.07–1.51 cm/s, 39–55 L/min if the jar is 24 × 24 cm ([2026-10-26](../../results/reports/water_level/2026-10-26/README.md)) | OPEN (nameplate) |
| OI-L4 | The sensor's height above the jar floor | the level scale | `$ZERO` with the jar empty, or measure. CONFLICT: tape 34.2 cm; the empty-jar reading 37.7 cm (2026-10-26). A five-level ruler calibration decides | OPEN |
| OI-L5 | The switch: Fotek SSR-40DA, input 3–32 V DC, active HIGH (2026-10-26) | which build to flash | the label | CLOSED: default build (RELAY_ACTIVE_LOW=0, PUMP_PWM=0) |
| OI-L6 | PWM (MOSFET) wiring for P and PI | P / PI on the rig | build it, or run P / PI in simulation only. Not available on 2026-10-26: P and PI not run | OPEN |
| OI-L7 | First rig session: calibration, W1, W2, then W3–W7 | every prediction in this repository | a session with the rig. 2026-10-26: W2 and W5 as on-off, one complete cycle in each of two runs, no drain ([2026-10-26](../../results/reports/water_level/2026-10-26/README.md)); calibration, W1, three-cycle W2, W3–W7 to do | OPEN (partly done) |
| OI-L8 | Lost echoes: 5 in a row stopped two runs on 2026-10-26; the operator suspected a loose HC-SR04 connection | a run stopped by the sensor guard | solder or screw-terminal the four sensor leads, strain-relieve them; watch the lost-echo count in the next report | OPEN |
| OI-L9 | A ripple of 0.65 cm (1 σ), period about 1.1 s, while the jar was emptied by hand | the noise the on-off band must exceed | repeat with a drain and a still surface; the first sloshing mode of the jar is near 1.7 Hz | OPEN |
