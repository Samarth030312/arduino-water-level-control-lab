# Pre-power checklist: water level rig (mains pump, SSR, HC-SR04)

Complete every line before the first power-up of each session; photograph the wiring.

## Unplugged

- [ ] Pump nameplate read: ____ HP, ____ V, ____ A, ____ L/h (OI-L3).
- [ ] Pump body to plug earth pin: ____ Ω (under 1 Ω).
- [ ] Socket box: live through the SSR (terminal L traced), fuse fitted, lid closed, SSR on its heatsink.
- [ ] RCD present on the wall socket; TEST button trips it.
- [ ] SSR input: 3 (+) to D4, 4 (−) to GND. HC-SR04: VCC 5V, GND, TRIG D8, ECHO D7.
- [ ] Sensor face 2–4 cm above the rim, square, centred, clear of the inlet jet.
- [ ] Delivery pipe ends **above** the highest water level; drain open into the 500 L tank.
- [ ] Pump casing primed; suction under water in the 500 L tank.
- [ ] Electronics and laptop above and away from the water; cables with drip loops.

## Low voltage only (pump unplugged)

- [ ] FLASH FIRMWARE (pump wiring: mains AC pump · SSR); `$HELLO` shows `pump_pwm=0`.
- [ ] Geometry entered (jar inside size, sensor height, 100 % depth, drain bore).
- [ ] Level matches a ruler at three depths within ~0.5 cm.
- [ ] RUN below Lmin: SSR LED on; STOP: off.

## First pump run

- [ ] An operator at the wall switch.
- [ ] On-off 30–80 %: pump starts below 30 %, stops above 80 %; peak under 90 %.
- [ ] STOP stops the pump; closing MATLAB stops it within 3 s.
- [ ] After a few cycles: SSR heatsink warm, not hot (power off before touching).

## Stop at once on

Water over 90 %, a leak near the box, a pump that hums without pumping, a hot SSR or smell, a
tripped RCD or fuse. Unplug, record the time and run ID, find the cause.
