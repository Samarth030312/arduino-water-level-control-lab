# Water-level mission control: `water_level_lab`

```matlab
setup open               % from the repository folder
```

![water_level_lab](../../results/figures/app_mission_control.png)

## The screen

**Centre:** the tank in 3-D: the water column follows the
level, the inflow and outflow streams thicken with the flow, the HC-SR04's ping reaches the
surface, the outlet valve's handle turns with its opening, and Lmin (green), Lmax (red) and the
setpoint (white) are marked on the tank. **Right:** the level the sensor reports (dotted: the
true level) and the pump command. The live numbers include the net flow into the tank.

## The physics panel

| You give | The model uses |
|---|---|
| tank length, width, height | A dh/dt = q_in − q_out, 100 % = the tank height |
| outlet bore, Cd, valve opening | q_out = k √h, k = Cd · a · √(2g) (Torricelli: the reason the tank is nonlinear) |
| pump flow at zero head, shut-off head, lift, dead zone, delay | q_in from the pump command, falling with the head |
| sensor height, air temperature | the HC-SR04's distance → level (speed of sound with temperature) |

Derived and shown live: the level a full pump can hold, the linearised gain and time constant
at half height, the time to fill and the volume. **Outflow** can be a gravity outlet or a
constant drain (inspect your rig); the **firmware guards** (overflow above 92 %, dry run) can be
switched off in simulation to see what they prevent.

## Missions

| | Question |
|---|---|
| W1 · Filling | Where does the level stop for a fixed pump command, and why there? |
| W2 · On-off | How long are the fill and drain times, how often does the pump start, and what if the band is halved? |
| W3 · P control | Why does P leave an offset? |
| W4 · PI control | How does PI remove it? |
| W5 · Valve disturbance | The outlet opens to 130 % at 600 s: who holds the level? |
| W6 · Limits | A setpoint near the rim, an overflow, a pump too small. |
| W7 · Windup | The pump saturates on the way to 85 %: clamping against a plain integrator. |
| LAB · Free | Anything; on the rig the setpoint changes live (P / PI). |

**OPEN IN SIMULINK** builds `water_level_plant.slx` (Relay block for on-off, PI, open loop,
valve step) with the current settings. On the rig: ON-OFF through the relay, P and PI with the
PWM (MOSFET) wiring; the app sends the tank geometry and air temperature ($CAL) before each run.

## On the rig

Wiring: [WATER_LEVEL_WIRING.md](../hardware/WIRING.md). Measure the tank and the sensor
height first and type them into the physics panel: they set both the model and the firmware's
level scale.
