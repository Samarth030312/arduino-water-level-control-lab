#!/usr/bin/env bash
# Firmware tests on the PC (g++ only, no Arduino toolchain): the real sketch runs against an
# emulated plant; its output is the protocol transcript the MATLAB tests parse. The build is
# also the real-time emulator (--pty) the end-to-end test talks to.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "== water-level firmware against an emulated tank, pump and HC-SR04"
g++ -std=c++17 -O1 -w -include algorithm -I"$root/firmware/tests/host_stubs" -o "$root/firmware/tests/levelsim" "$root/firmware/tests/firmware_host_test.cpp"
"$root/firmware/tests/levelsim" "$root/firmware/tests/fixtures/level_transcript.txt"
echo "== the same firmware built for a DC pump on a MOSFET (PUMP_PWM=1)"
g++ -std=c++17 -O1 -w -include algorithm -DPUMP_PWM=1 -I"$root/firmware/tests/host_stubs" -o "$tmp/levelsim_pwm" "$root/firmware/tests/firmware_host_test.cpp"
"$tmp/levelsim_pwm"
