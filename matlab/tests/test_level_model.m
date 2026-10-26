function tests = test_level_model
%TEST_LEVEL_MODEL  Water-level simulation against equilibrium results and the guards.
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    run(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'setup_path.m'));
end

function testPEquilibriumMatchesTheory(tc)
    % Steady state: Q_max (Kp e / 255 - dead) / (1 - dead) = k_out sqrt(h)
    c = levellab.level.defaultConfig(); c.mode = 'P'; c.Kp = 10; c.P.noise_us = 0;
    S = levellab.level.simulate(c); P = c.P;
    f = @(e) P.Q_max * max(0, (c.Kp * e / 255 - P.pwm_dead) / (1 - P.pwm_dead)) ...
             - P.k_out * sqrt((c.setpoint - e) / 100 * P.H);
    e = fzero(f, [0.1 c.setpoint - 1]);
    tc.verifyEqual(S.metrics.ss_error, e, 'AbsTol', 0.7);      % sensor resolution is 1.2 %
end

function testPIRemovesError(tc)
    S = levellab.level.simulate(levellab.level.presetConfig('PI control Kp = 20 Ki = 0.5, 50 %'));
    tc.verifyLessThan(abs(S.metrics.ss_error), 0.7);
    S = levellab.level.simulate(levellab.level.presetConfig('PI, drain opened 1.2x'));
    tc.verifyLessThan(abs(S.metrics.error_after_drain), 0.7);
end

function testOnOffStaysNearBand(tc)
    c = levellab.level.presetConfig('On-off 30-80 % (course)'); S = levellab.level.simulate(c);
    tc.verifyEqual(S.metrics.verdict, 'CYCLING');
    % after the switch the pipe still delivers for the delay: overshoot ~ Q delay / A (in % of H)
    over = 100 * c.P.Q_max * (c.P.delay + c.P.Ts) / c.P.A / c.P.H;
    tc.verifyGreaterThan(S.metrics.band_low, 30 - over - 3); tc.verifyLessThan(S.metrics.band_high, 80 + over + 2);
end

function testNarrowBandSwitchesMore(tc)
    a = levellab.level.simulate(levellab.level.presetConfig('On-off 30-80 % (course)'));
    b = levellab.level.simulate(levellab.level.presetConfig('On-off 50-55 % (narrow band, chatter)'));
    tc.verifyGreaterThan(b.metrics.starts_per_hour, 5 * a.metrics.starts_per_hour);
end

function testDryRunGuard(tc)
    c = levellab.level.defaultConfig(); c.P.Q_max = 0;             % empty reservoir
    S = levellab.level.simulate(c);
    tc.verifyEqual(S.metrics.verdict, 'DRY-RUN GUARD');
    tc.verifyEqual(S.u(end), 0);
end

function testOverflowGuard(tc)
    c = levellab.level.defaultConfig(); c.Lmax = 99; c.Lmin = 95; c.P.k_out = 0; c.Tend = 600;   % nothing drains
    S = levellab.level.simulate(c);
    over = 100 * c.P.Q_max * (c.P.delay + c.P.Ts) / c.P.A / c.P.H;      % still arriving after the cut
    tc.verifyLessThan(max(S.level), c.P.L_over + over + 1);
end

function testEveryPresetRuns(tc)
    p = levellab.level.presets();
    for k = 1:numel(p)
        S = levellab.level.simulate(levellab.level.presetConfig(p(k).name));
        tc.verifyTrue(all(isfinite(S.level)), p(k).name);
        tc.verifyFalse(contains(S.metrics.verdict, 'GUARD'), p(k).name);
    end
end
