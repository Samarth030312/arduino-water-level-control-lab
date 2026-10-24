# First principles: tank, outlet, pump, sensor, controller

Code: `levellab.level.physics` (parameters from what is on the bench), `levellab.level.simulate`
(the loop), `levellab.level.cycleAnalysis` (fill and drain times, flows, from a run),
`levellab.level.calibrate` (the sensor against a ruler). Every default is ASSUMED until measured.

## 1. The tank and the outlet

Mass balance, with the outflow from Torricelli's law through an outlet of bore d, discharge
coefficient Cd (about 0.6 for a sharp hole, 0.8 for a short tube) and a valve opening:

```
A dh/dt = q_in − q_out,      q_out = k √h,      k = Cd · a · √(2g),   a = valve · π d² / 4
steady level for an inflow q:   h = (q / k)²
```

| Default | Value | Derived | Value |
|---|---|---|---|
| tank 15 × 15 cm, 25 cm high (= 100 %) | A = 0.0225 m², 5.6 L | k | 1.24 · 10⁻⁴ m^2.5/s |
| outlet 7.7 mm, Cd 0.6, valve 100 % | | outflow when full | 3.7 L/min |
| pump 4 L/min at zero head, 3 m shut-off head | | level at full pump | about 95 % |

The square root makes the tank nonlinear. Linearised at a level h₀:

```
H(s) / Q(s) = K / (τ s + 1),     K = 2 √h₀ / k,     τ = 2 A √h₀ / k
```

At half full (12.5 cm): τ ≈ 130 s. At 30 % τ is smaller, at 80 % larger: the same controller
behaves differently at different levels.

## 2. The pump

Flow falls linearly with the head it lifts against (from Q_max at zero head to nothing at the
shut-off head), it does not turn below a PWM dead zone (20 % in the defaults), and it reaches
its speed with a lag of about 0.5 s; the relay and the pipe add about 1 s of delay.

## 3. The sensor

The HC-SR04 times an ultrasonic echo: level = sensor height − v · t / 2, with the speed of sound
v = 331.3 + 0.606 T m/s. Assume 20 °C on a 35 °C day and every reading is off by up to a few
millimetres (more, the farther the water). The app sends the air temperature with each run.

## 4. Control laws, and what to expect

| Law | Prediction from the model (defaults) |
|---|---|
| on-off, pump on below Lmin, off above Lmax | a limit cycle between the thresholds, slightly beyond them (the delay); 30–80 %: about 4 minutes per cycle, 12 pump starts an hour |
| on-off with a narrow band | more starts per hour; below a few % the relay chatters on sensor noise |
| P, u = Kp e | an offset: the outflow needs a pump command, P gives one only with an error (16.6 % for the default gain) |
| PI, clamping anti-windup | no offset; recovers when the outlet valve opens |
| PI with a plain integrator, pump saturated | the integral grows during the long fill, then the level overshoots |

## 5. Identifying your rig

Calibrate the sensor at five levels or more against a ruler (`docs/experiments/calibration_template.csv`,
`levellab.level.calibrate`). Then W1: a fixed pump command from empty; where the level settles
gives k, the slope at the start gives the pump's flow. Type the tank, outlet and pump into the
physics panel until the SIM column matches the RIG column.
