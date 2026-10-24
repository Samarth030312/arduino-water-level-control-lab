# Course guide: ENR312 Control Systems Laboratory (Ahmedabad University)

This repository is one apparatus of the ENR312 control laboratory. Everything in it is general;
this page maps the course handout onto the parts of the repository that let you **do** each task
and **find** each answer yourself. It does not give the answers: the models, the rig and your
data do.

## Before the lab

Install and open the app ([the sequence](../SEQUENCE.md), the steps without hardware); play each
mission once. Write down what you expect the rig to do before you see it.

## The handout, task by task

| Handout | Mission in the app | What to look at |
|---|---|---|
| Section 1, task 1: filling, emptying, Lmin and Lmax | W1, W2 | where the level settles for a fixed pump command; the thresholds |
| task 2: hardware, two thresholds, calibration | SENSOR CHECK | [wiring](../hardware/WIRING.md); the calibration sheet in `docs/experiments/` |
| tasks 3–5: on-off program, cycles, fill time, switching, chattering | W2 | cycle times and pump starts per hour in the table; halve the band |
| task 6: Simulink tank with the Relay block | OPEN IN SIMULINK | [Simulink](../SIMULINK.md) |
| task 7: hardware against Simulink | W2 on the rig, then OVERLAY RUN | the differences, and why |
| S3-1 level from the echo; the speed of sound | — | `levellab.level.soundSpeed`; the air temperature in the physics panel |
| S3-2 calibration at five levels or more | SENSOR CHECK with a ruler | `levellab.level.calibrate` |
| S3-3, S3-4 inflow and outflow from the cycle; T_on and T_off | W2 | `levellab.level.cycleAnalysis` on a run |
| S3-5 overshoot above Lmax | W2 | the delay of relay, pipe and pump |
| S3-6 a narrower band; chattering; relay life | W2 presets | starts per hour |
| S3-7 Simulink tuned to the measured period | OPEN IN SIMULINK | adjust the outflow until the period matches |
| S3-8 nonlinear outflow, PI on PWM, a step, an extra drain, windup | W4, W5, W7 | the valve step; ANTI-WINDUP on and off |
| S3-9 linearisation, τ at Lmin and Lmax | — | [first principles](../FIRST_PRINCIPLES.md) |
| S3-10 self-regulating or integrating; P alone | W3 | constant or level-dependent outflow |
| S3-11 interlocks | W6 | the firmware's guards (switch them off in simulation to see why) |
| S3-12 why hardware differs from Simulink | W2 rig against model | your list, with evidence from your runs |

## The lab report

The course asks for a summary of the tasks, a description of what you did, your programs, the
answers to the Section 2 and Section 3 questions, screenshots of simulation inputs and outputs,
and a comparison of simulation and hardware with its advantages and limitations. Every rig run
is saved and numbered in `data/RUN_REGISTER.csv`: cite run ids for every hardware number.
