# Open items and conflicts

An item closes only with evidence (a measurement, an inspection photo, or a document quote).
Record how it was closed.

| ID | Fact needed | Why it matters | How to resolve | Status |
|---|---|---|---|---|
| OI-L1 | The tank: the lab uses a 15 L oil jar (2026-10-26); inside length, width, height to the rim | every level and flow | measure | OPEN |
| OI-L2 | The outlet: the jar has no drain yet; bore, sharp hole or short tube (Cd) | the outflow k √h, the cycles | drill and measure; fit from the fall rate | OPEN |
| OI-L3 | The pump: yellow Silver 0.5 HP-class single-phase monoblock, 230 V (2026-10-26); rated current, flow, head from its nameplate | the inflow, the fuse, the SSR's heat | read the nameplate; measure the rise rate | OPEN |
| OI-L4 | The sensor's height above the jar floor | the level scale | `$ZERO` with the jar empty, or measure | OPEN |
| OI-L5 | The switch: Fotek SSR-40DA, input 3–32 V DC, active HIGH (2026-10-26) | which build to flash | the label | CLOSED: default build (RELAY_ACTIVE_LOW=0, PUMP_PWM=0) |
| OI-L6 | PWM (MOSFET) wiring for P and PI | P / PI on the rig | build it, or run P / PI in simulation only | OPEN |
| OI-L7 | First rig session: calibration, W1, W2, then W3–W7 | every prediction in this repository | a session with the rig | OPEN |
