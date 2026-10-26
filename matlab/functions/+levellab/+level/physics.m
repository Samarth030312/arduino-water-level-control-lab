function [P, D] = physics(spec)
%PHYSICS  Tank, outlet, pump and sensor parameters from the dimensions you measure.
%
%   [P, D] = levellab.level.physics()          % defaults: all ASSUMED until measured
%   [P, D] = levellab.level.physics(spec)      % any subset of D.spec's fields
%
%   Inputs (spec), defaults for a 15 L jar filled by a 0.5 HP-class mains pump, all ESTIMATED
%   until measured: tank_L, tank_W 0.24 m, tank_H 0.26 m (water depth = 100 %), h_sensor 0.32 m
%   (HC-SR04 face above the floor), d_out 8 mm (outlet bore), Cd 0.6 (sharp orifice ~0.6,
%   short tube ~0.8), valve 100 % (opening, scales the outlet area), Q_max 25 L/min (pump at
%   zero head), H_max 25 m (pump shut-off head; Inf = no curve), h_lift 0.3 m (from the
%   reservoir surface to the tank floor), pwm_dead 20 % (DC pump on PWM only), tau_pump 0.3 s,
%   delay 1.5 s (switching to water arriving), T_air 20 C (speed of sound for the HC-SR04).
%   Physics:
%     A dh/dt = q_in - q_out,     q_out = k sqrt(h),   k = Cd a sqrt(2 g),  a = valve pi d^2 / 4
%     (Torricelli; the square root makes the tank nonlinear)
%     steady level for an inflow q:  h = (q / k)^2
%     linearised at h0:  H(s)/Q(s) = K / (tau s + 1),  K = 2 sqrt(h0) / k,  tau = 2 A sqrt(h0) / k
%   P is levellab.level.params() with these values in place, for levellab.level.simulate.
    def = struct('tank_L', 0.24, 'tank_W', 0.24, 'tank_H', 0.26, 'h_sensor', 0.32, 'd_out', 8, 'Cd', 0.6, ...
        'valve', 100, 'Q_max', 25, 'H_max', 25, 'h_lift', 0.3, 'pwm_dead', 20, 'tau_pump', 0.3, 'delay', 1.5, 'T_air', 20);
    if nargin < 1, spec = struct(); end
    for f = fieldnames(def)', if ~isfield(spec, f{1}) || isempty(spec.(f{1})), spec.(f{1}) = def.(f{1}); end, end
    g = 9.81;
    A = spec.tank_L * spec.tank_W;
    a = spec.valve / 100 * pi * (spec.d_out / 1000)^2 / 4;
    k = spec.Cd * a * sqrt(2 * g);
    Q = spec.Q_max / 60000;
    P = levellab.level.params();
    P.A = A; P.H = spec.tank_H; P.h_sensor = spec.h_sensor; P.Q_max = Q; P.k_out = k;
    P.pwm_dead = spec.pwm_dead / 100; P.tau_pump = spec.tau_pump; P.delay = spec.delay;
    P.H_max = spec.H_max; P.h_lift = spec.h_lift; P.T_air = spec.T_air; P.H_rim = spec.tank_H + 0.03;
    for n = {'A', 'H', 'h_sensor', 'Q_max', 'k_out', 'pwm_dead', 'tau_pump', 'delay'}
        P.meta.(n{1}).status = 'ASSUMED'; P.meta.(n{1}).note = 'from the values in levellab.level.physics';
    end
    % steady level at full pump (with the pump curve): solve q(h) = k sqrt(h)
    qh = @(h) Q * max(0, 1 - (spec.h_lift + h) / spec.H_max);
    hs = 0; for it = 1:60, hs = (qh(hs) / max(k, eps))^2; end
    h0 = 0.5 * spec.tank_H;
    D = struct('spec', spec, 'A', A, 'a', a, 'k', k, 'h_full_pump', hs, 'pct_full_pump', 100 * hs / spec.tank_H, ...
        'K', 2 * sqrt(h0) / max(k, eps), 'tau', 2 * A * sqrt(h0) / max(k, eps), 'h0', h0, ...
        't_fill_empty', spec.tank_H * A / max(Q, eps), 'V_L', 1000 * A * spec.tank_H, ...
        'q_out_full_Lmin', 60000 * k * sqrt(spec.tank_H));
    D.tf = sprintf('H(s)/Q(s) = %.0f / (%.0f s + 1)  at h0 = %.0f cm  [m per m^3/s]', D.K, D.tau, 100 * h0);
end
