# Troubleshooting

First: `setup probe` in MATLAB (from the repository folder). It checks MATLAB, the toolchain,
the USB driver, the serial permission, a busy port, and asks the board for its firmware; each
problem comes with its fix. Installation per system: [install](../install/README.md).

## Computer and board

| Symptom | Cause | Fix |
|---|---|---|
| no port in the app's list | charge-only cable, hub, missing CH340 driver (Windows, old macOS), Linux permission | data cable, another socket; `setup probe` names the cause; Windows: [CH340 driver](../install/windows/README.md) |
| port appears, then vanishes (Ubuntu) | `brltty` grabs CH340 boards | `sudo apt remove brltty` |
| "port in use" | Arduino IDE Serial Monitor, another MATLAB | close it |
| connected, but no `$HELLO` within 6 s | another sketch on the board | **FLASH FIRMWARE** |
| compile fails with `bad CPU type` (Apple silicon) | the AVR compiler is an Intel binary | Rosetta 2 (`softwareupdate --install-rosetta`); the macOS installer does it |
| compile fails on Windows with odd path errors | non-ASCII user name | the toolchain goes to `C:\arduino-lab-tools` automatically; or set `LEVELLAB_TOOLS` |
| `host silent` fault | MATLAB stopped sending (frozen, closed, laptop asleep) | CLEAR FAULT, RUN again |

## The rig

| Symptom | Cause | Fix |
|---|---|---|
| SENSOR CHECK reads nonsense or jumps | sensor not straight above the water, a ripple, too close (HC-SR04 minimum ~2 cm) | mount it square above a calm spot, at the height you typed in the physics panel |
| the level reads a few % off | speed of sound: air temperature | type the air temperature in the physics panel (the app sends it with each run) |
| the pump never starts | the SSR's input wired wrong way round (3 + to D4, 4 − to GND), the wrong build (a relay module that is active-LOW needs the *relay* pump wiring), the socket box unplugged, the RCD tripped | the SSR's LED shows whether the Uno switches it; the default build drives D4 HIGH for ON |
| `dry run` fault | the level does not rise while the pump runs: empty reservoir, air in the pipe | refill, prime; STOP clears it |
| `overflow` fault | the level passed 92 % | lower the setpoint; check the outlet |
| P or PI does nothing | they need the PWM (MOSFET) wiring, not the relay | [wiring](hardware/WIRING.md) |
| the rig fills faster or slower than the grey line | another tank, outlet or pump | measure and type them in the physics panel; W1 shows where the level settles |

## Data

| Symptom | Fix |
|---|---|
| a run is missing from RUNS | runs are saved when they end, stopped or aborted ones too; see `data/RUN_REGISTER.csv` |
| SYNC DATA fails | no write access to the repository: push to your own fork |
