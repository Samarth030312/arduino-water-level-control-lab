# Serial protocol v1: MATLAB ⇄ Arduino (water level)

**STATUS: IMPLEMENTED, run on the rig on 2026-10-26** (`results/evidence/logs/hw_session_water_*.log`
hold every line of those sessions). MATLAB side: `levellab.protocol.*`, `levellab.io.SerialLink`.
Firmware: `firmware/level_controller`. The same firmware, compiled for the PC, runs against an
emulated tank in `firmware/tests` and end to end with the app (`matlab/tests/e2e`).

## 1. Physical

USB CDC serial, **115200 baud, 8N1**, lines terminated by `\n` (a preceding `\r` is ignored).
Opening the port resets the Uno: the host waits for `$HELLO`.

## 2. Framing

```
$<TYPE>,<version>,<field1>,…,<fieldN>*<CS>\n
```

- `version` is `1`. A frame with another version is refused (`ERR` code 2).
- `CS` = two hex digits, XOR of every byte strictly between `$` and `*` (the NMEA 0183 rule). A
  host frame with a wrong checksum is refused (`ERR` code 1).
- Fields never contain `,` `*` `$` or control characters.
- Numbers: decimal, `.` as the separator. Missing value: `nan`.
- A line starting with `#` is **human-readable debug text**. The host logs it and never parses it
  as data. The firmware prints nothing else.
- Anything else is invalid; the host counts it and keeps going.

## 3. Host → device

| Frame | Meaning |
|---|---|
| `$PING,1` | Keep-alive; no answer. The host sends it every 0.25 s while a run is on. |
| `$CFG,1,<mode>,<Lmin>,<Lmax>,<setpoint>,<Kp>,<Ki>` | mode `ONOFF`, `P` or `PI`; levels in %; Kp in PWM counts per %, Ki per % s. The on-off build refuses P and PI (code 8). |
| `$SET,1,<setpoint>` | Setpoint in % (P, PI), held at least 5 % under the overflow limit |
| `$CAL,1,<sensor_to_floor_cm>,<full_cm>[,<air_C>]` | Geometry: sensor face to the tank floor, the depth called 100 %, the air temperature (speed of sound). Kept in EEPROM. |
| `$ZERO,1` | Tank empty: the measured distance becomes the sensor-to-floor height |
| `$GRD,1,<t_dry_s>,<rise_cm>,<t_maxon_s>,<L_over_%>` | The guards (defaults 20 s, 1.0 cm, 180 s, 92 %) |
| `$RUN,1` | Start: t and seq to 0, the controller and telemetry on. Refused while a fault is latched (code 6) or before calibration (code 12). |
| `$STOP,1` | Pump off, run ended, latched faults cleared |

The device answers every command except PING with `$ACK,1,<TYPE>` or
`$ERR,1,<TYPE>,<code>,<text>`. Codes 3 (stop first), 4 (wrong number of fields), 5 (unknown
mode), 7 (unknown command), 9 (values out of range).

## 4. Device → host

| Frame | Meaning |
|---|---|
| `$HELLO,1,water_level_lab,<git_rev>,relay_active_low=<0/1>,pump_pwm=<0/1>,calibrated=<0/1>,free_ram=<bytes>` | Once after reset: the build and its state |
| `$LTEL,1,<seq>,<t_ms>,<mode>,<setpoint>,<level_cm>,<level_pct>,<err>,<u>,<pump>,<flags>` | One per control step (0.1 s), running or idle |
| `$ERR,1,RUN,<code>,<text>` | The firmware stopped the pump by itself (below) |

`u` is the pump command, 0–255 (on-off: 0 or 255); `pump` 1 when the pump is on. `flags`:
bit 0 RUNNING, 1 SENSOR_FAIL, 2 OVERFLOW_GUARD, 3 DRYRUN_GUARD, 4 WATCHDOG_STOP, 5 BUTTON_STOP,
6 RUNTIME_GUARD, 7 OVERFLOW_LATCHED. The field list and flag names live in
`matlab/functions/+levellab/+protocol/schema.m` (the single source for MATLAB).

## 5. What the firmware does by itself

| Code | Cause | Latched until STOP |
|---|---|---|
| 10 | no frame from the host for 3 s during a host-started run | yes |
| 11 | pump on, level rose less than `rise_cm` in `t_dry_s` (dry suction, empty reservoir, blocked pipe) | yes |
| 13 | on-off: pump on for `t_maxon_s` without reaching Lmax | yes |
| 14 | overflow limit reached while the pump was on | yes |
| 15 | 5 s of readings the water could not produce (the sensor's view) | yes |
| — | 5 lost echoes in a row: level `nan`, flag SENSOR_FAIL | yes |
| — | above `L_over`, within 4 cm of the sensor, or the float switch: pump off while it lasts, flag OVERFLOW_GUARD | no |

After any reset D4 is LOW (pump off), and the AVR watchdog resets a program stuck for 2 s.
The physical stop is the wall switch: a software stop is a convenience, not a safety function.

## 6. Example (from the rig, 2026-10-26)

```
host:   $CAL,1,34.2,22,20*66
device: # cal sensor_to_floor_cm=34.2 full_height_cm=22.0 air_C=20.0
device: $ACK,1,CAL*36
host:   $CFG,1,ONOFF,42.5,67.5,50,20,0.5*3A
device: $ACK,1,CFG*3A
host:   $SET,1,50*76
device: $ACK,1,SET*3A
host:   $RUN,1*54
device: $ACK,1,RUN*31
device: $LTEL,1,0,26,ONOFF,nan,14.5,66.0,-16.01,0,0,1*23
```

Checksums computed with the XOR rule (identical to `levellab.protocol.encode`).
