# How it works

Four things can run the same experiment: the **simulator** in the app, the **Simulink** model,
the **emulator** (the real firmware compiled for the PC), and the **rig**.

## The loop

```mermaid
flowchart LR
    SP["setpoint %<br/>(or Lmin, Lmax)"] --> E(("−"))
    E --> C["Arduino Uno, every 0.1 s<br/>on-off · P · PI"]
    C -->|"D4: SSR or relay (on-off)<br/>D5: MOSFET PWM (P, PI)"| P["pump<br/>flow falls with head"]
    P -->|"relay + pipe delay"| T["tank<br/>A dh/dt = q_in − k·√h"]
    T --> O["outlet, valve"]
    T -.->|"echo"| S["HC-SR04<br/>level = sensor height − v·t/2"]
    S -.->|"D7, D8"| E
```

What makes this plant interesting for control, all of it in the model:

- **It regulates itself, nonlinearly.** The outflow grows with √h, so every pump command has its
  own resting level, and the tank is faster near the bottom than near the top.
- **The pump can only fill.** Emptying is the outlet's job; the pump also has a dead zone at low
  PWM and gives less flow against a higher head.
- **The sensor measures distance, not level.** It needs the sensor's height above the floor and
  the air temperature (the speed of sound); ripples make it noisy.
- **Things go wrong with water.** The firmware guards against overflow (above 92 %), against a
  dry run (pumping hard for a minute without the level rising) and against a silent PC.

## Four ways to run one experiment

| | What it is | Use it to |
|---|---|---|
| **Simulator** | MATLAB, inside the app: the tank, outlet, valve, pump curve and dead zone, the delay, the sensor, the firmware's guards and controller laws | learn the concepts without hardware; predict a rig run |
| **Simulink** | `water_level_plant.slx`, generated from code: the tank as an integrator, the Relay block for on-off, a Discrete PID for P / PI; **OPEN IN SIMULINK** builds it with the app's settings | see and change the block diagram ([Simulink](SIMULINK.md)) |
| **Emulator** | the sketch compiled with g++ against an emulated tank, pump and HC-SR04, in real time on a pseudo-terminal (or faster) | test the firmware and the app together without a rig; CI does |
| **Rig** | the Uno, the relay or MOSFET, the pump, the tank, the sensor | measure |

## A run, from button to file

```mermaid
sequenceDiagram
    participant App as app (MATLAB)
    participant Uno as Arduino Uno
    App->>Uno: $CAL sensor height, full height, air temperature
    App->>Uno: $CFG mode, Lmin, Lmax, setpoint, Kp, Ki
    App->>Uno: $RUN
    loop every 0.1 s
        Uno->>Uno: ping the HC-SR04, guards, control law, pump
        Uno-->>App: $LTEL: setpoint, level, pump, flags
        App-->>Uno: $PING
    end
    App->>Uno: $STOP (pump off)
    App->>App: data/raw/water_level/WATER-Rnnnn_….csv, metadata, RUN_REGISTER.csv
```

Protocol: [serial protocol](architecture/SERIAL_PROTOCOL.md). Pins: [wiring](hardware/WIRING.md).
