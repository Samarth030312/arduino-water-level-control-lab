function tests = test_level_course
%TEST_LEVEL_COURSE  Water handout helpers: speed of sound, calibration, cycle analysis, tank types.
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    run(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'setup_path.m'));
end

function testSoundSpeed(tc)
    tc.verifyEqual(levellab.level.soundSpeed(20), 343.42, 'AbsTol', 1e-9);
    [~, e] = levellab.level.soundSpeed(35, 20, 30, 7.5);           % 22.5 cm to the water
    tc.verifyEqual(e, 22.5 * (1 - 343.42 / 352.51), 'AbsTol', 1e-9);
    [~, e0] = levellab.level.soundSpeed(20, 20, 30, 10); tc.verifyEqual(e0, 0);
end

function testCalibrateRecoversLine(tc)
    ruler = (2:4:22)'; reading = 1.03 * ruler - 0.4;
    cal = levellab.level.calibrate(ruler, reading, [12 12.1 11.9]);
    tc.verifyEqual([cal.a cal.b], [1.03 -0.4], 'AbsTol', 1e-12);
    tc.verifyLessThan(cal.maxErr, 1e-9);
    tc.verifyEqual(cal.correct(1.03 * 7 - 0.4), 7, 'AbsTol', 1e-12);
end

function testCycleAnalysisOnKnownSawtooth(tc)
    % constant flows: rise 0.1 cm/s for 50 s, fall 0.2 cm/s for 25 s, between 5 and 10 cm
    t = (0:0.1:600)'; lev = zeros(size(t)); pump = false(size(t)); h = 5; on = true;
    for k = 1:numel(t)
        lev(k) = h; pump(k) = on;
        h = h + 0.1 * (on * 0.1 - ~on * 0.2);
        if on && h >= 10, on = false; elseif ~on && h <= 5, on = true; end
    end
    r = levellab.level.cycleAnalysis(t, lev, pump, 0.01, 10);      % A = 100 cm^2
    tc.verifyEqual(r.rise_cm_s, 0.1, 'RelTol', 0.02);
    tc.verifyEqual(r.fall_cm_s, 0.2, 'RelTol', 0.02);
    tc.verifyEqual(r.Qout_mL_s, 20, 'RelTol', 0.02);
    tc.verifyEqual(r.Qin_mL_s, 30, 'RelTol', 0.02);
    tc.verifyEqual([r.Ton_s r.Toff_s], [50 25], 'AbsTol', 0.3);
end

function testConstantOutflowIsIntegrating(tc)
    % pump fixed at full: gravity tank settles, constant-outflow tank keeps rising to the top
    c = levellab.level.defaultConfig(); c.mode = 'P'; c.Kp = 1000; c.setpoint = 99; c.h0 = 10; c.Tend = 1500;
    c.guards = false;                                             % tank physics only
    c.P = levellab.level.physics(struct('tank_L', 0.15, 'tank_W', 0.15, 'tank_H', 0.25, 'h_sensor', 0.30, 'd_out', 7.7, 'Q_max', 4, 'H_max', 3, 'h_lift', 0.05, 'delay', 1)); c.P.noise_us = 0;      % a pump that cannot overflow the gravity tank
    g = levellab.level.simulate(c);
    c.outflow = 'constant'; c.Qout = 1; k = levellab.level.simulate(c);
    tc.verifyLessThan(abs(g.level(end) - g.level(end - 500)), 0.5);          % settled
    tc.verifyGreaterThan(k.level(end), g.level(end));                        % integrator goes higher
end

function testNoFalseDryRunWhenBalancedAtFullPump(tc)
    c = levellab.level.defaultConfig(); c.mode = 'PI'; c.h0 = 30; c.setpoint = 60;
    c.drainFactor = 1.15; c.tDrain = 500; c.Tend = 1000;
    S = levellab.level.simulate(c);
    tc.verifyEmpty(S.guard);
    tc.verifyLessThan(abs(S.metrics.error_after_drain), 1);
    c.pumpFailAt = 700; S = levellab.level.simulate(c);
    tc.verifyEqual(S.guard, 'DRY-RUN');                                      % a real dry run still trips
end
