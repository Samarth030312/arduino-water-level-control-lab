# Water level control — wiring and electrical guidelines

Hardware (course guideline, SRC-001 p.23): Arduino Uno, small tank, DC pump, relay module,
level sensing (ultrasonic chosen: HC-SR04). Firmware: `firmware/level_controller/`.
Status: pin plan DECIDED; **not yet wired**. Pump and tank models are not specified by the
course — record what the lab provides (OI-L1).

## 1. Pin plan

| Arduino Uno | Connects to | Notes |
|---|---|---|
| **D8** | HC-SR04 TRIG | |
| **D7** | HC-SR04 ECHO | 5 V module: direct |
| 5 V / GND | HC-SR04 VCC / GND | |
| **D4** | relay module **IN** | on-off pump control (course). Firmware default: active-LOW module |
| 5 V / GND | relay module VCC / GND | |
| **D5** | MOSFET gate via 220 Ω, 10 kΩ gate→GND | only for P / PI (PWM 980 Hz) |
| **D3** | float switch → GND (optional) | closes at the top: hardware overflow stop |
| **D12** | START/STOP push-button → GND | standalone use |

Pick **one** pump path:

- **A. Relay (course, on-off only):** pump + to supply + through the relay's COM→NO contact.
- **B. MOSFET (needed for P / PI):** logic-level N-MOSFET (e.g. IRLZ44N), pump between +12 V and
  drain, source to GND, **flyback diode (1N5819 or 1N4007) across the pump, cathode to +12 V**.

In wiring A, the P / PI modes degrade to on/off (any u > 0 closes the relay).

## 2. Diagram

```
              +-------------+               HC-SR04 (face down, 30 cm above tank floor)
   USB -------| Arduino Uno |  D8 ---------> TRIG
              |             |  D7 <--------- ECHO
              |             |  5V/GND ------ VCC/GND
              |             |
              |          D4 |------> relay IN        A: 12 V + ---- COM  NO ---- pump + 
              |       5V/GND|------> relay VCC/GND                               pump - ---- 12 V -
              |             |
              |          D5 |--220R--> MOSFET G      B: 12 V + ---- pump + ---+--- diode cathode
              |             |         (10k G->S)        pump - ---- MOSFET D -+--- diode anode
              |             |                           MOSFET S ---- 12 V - ---- Uno GND
              |          D3 |---[float switch]---GND
              |         D12 |---[START/STOP]----GND
              +-------------+
```

Wiring B needs the 12 V supply's 0 V joined to the Uno GND. Wiring A does not (the relay
isolates), but joining them does no harm.

## 3. Power and water rules

- Pump supply: as rated on the pump (typically 6–12 V DC, < 1 A). Fuse it at ~2× the pump's
  rated current.
- **Electronics above and away from the tank**, on a tray that cannot be splashed. Drip loops on
  the cables. Never handle wiring with wet hands.
- Do not run the pump dry: the firmware stops it if it is commanded near full for 60 s
  without a 2 % rise, and forces it off above 92 %. Keep the reservoir full anyway.
- Mount the HC-SR04 at least 2 cm above the highest water level (its minimum range) and away from
  the tank wall; foam or ripples give false echoes.

## 4. Calibration

Measure the sensor face to tank floor distance and the height you call 100 %, then send
`$CAL,1,<sensor_to_floor_cm>,<full_height_cm>[,<air_C>]` (defaults 30 cm, 25 cm and 20 °C air; the speed of sound is corrected for the air temperature).
Check: empty tank reads ~0 %, a ruler-measured level matches the reading within 0.5 cm.

## 5. Bring-up order

1. Upload: `scripts/setup/upload level /dev/ttyACM0`. Serial Monitor 115200: `$HELLO` then `$LTEL`.
2. Pump disconnected: `$CFG,1,ONOFF,30,80,50,20,0.5` and `$RUN,1`; the relay clicks on when the
   reading is below 30 %. Check whether your relay module is active-LOW (default) or active-HIGH
   (rebuild with `-DRELAY_ACTIVE_LOW=0`).
3. Connect the pump; run W2 (on-off) from `setup water`.
