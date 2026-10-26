# Electrical safety: water and mains

The lab rig switches a **230 V mains pump** next to **open water**. The rules below are not
optional; the wiring is in [WIRING.md](../hardware/WIRING.md).

- **Earth the pump's metal body** (through its own 3-pin plug into an earthed socket) and check
  continuity with a meter before the first use.
- **30 mA RCD (RCCB)** on the socket feeding the pump; press TEST before each session.
- **Fuse** the live line (6.3 A slow-blow or a 6 A C-curve MCB for a 0.5 HP pump).
- **Never switch mains from an Arduino pin.** The Uno drives only the SSR's low-voltage input
  (3–32 V DC); the SSR switches the live line inside a closed box.
- **The SSR is not an isolator.** It leaks ~3 mA when off: unplug before touching the mains side.
- **SSR on a heatsink**; a varistor (275 V AC) across its load terminals is recommended for a motor.
- **Separate the circuits**: mains in the box, low voltage outside it; Uno and laptop above and
  away from the water; drip loops on every cable; no water containers above electrical parts.
- **Dry hands, dry floor**; mop spills at once; never handle wiring while the pump is plugged in.
- **The real emergency stop is the wall switch** (or the RCD's test button): an operator stands at
  it for the first runs. STOP in the app, the push button and the firmware's guards come second.
- **Never run the pump dry**: prime its casing before the first start; the firmware stops it when
  the level does not rise.
- With a **DC pump** instead (12 V, `PUMP_PWM=1`): fuse the supply at about twice the pump's
  current, flyback diode across the pump, supply 0 V joined to the Uno's GND.
