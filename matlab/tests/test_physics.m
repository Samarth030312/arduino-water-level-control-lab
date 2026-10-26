function tests = test_physics
%TEST_PHYSICS  Datasheet / dimension physics of the three rigs, the thermal fit, the run register.
    tests = functiontests(localfunctions);
end

function testTankTorricelli(tc)
    % a small pump and tank, where the open-loop level can balance inside the tank (with the
    % rig's 25 L/min pump and 8 mm drain it cannot: the jar must overflow - see testRigPumpOverflowsOpenLoop)
    small = struct('tank_L', 0.15, 'tank_W', 0.15, 'tank_H', 0.25, 'h_sensor', 0.30, 'd_out', 7.7, 'Q_max', 4, 'H_max', 3, 'h_lift', 0.05, 'delay', 1);
    [P, D] = levellab.level.physics(small);
    tc.verifyEqual(D.k, 0.6 * pi * 0.0077^2 / 4 * sqrt(2 * 9.81), 'RelTol', 1e-12);
    c = levellab.level.defaultConfig(); c.P = P; c.mode = 'OL'; c.olPct = 100; c.h0 = 0; c.Tend = 1500;
    c.guards = false;                         % the 92 % overflow guard would stop it short of 95 %
    S = levellab.level.simulate(c);
    tc.verifyEqual(S.level(end), D.pct_full_pump, 'AbsTol', 1.5, 'open loop settles where q_in = k sqrt(h)');
    small.valve = 55; [P2, ~] = levellab.level.physics(small);
    c.P = P2; c.guards = false; c.h0 = 50; S = levellab.level.simulate(c);
    tc.verifyGreaterThan(S.spill(end), 1, 'outlet half closed, no guard: the tank overflows');
    c.guards = true; c.mode = 'PI'; c.setpoint = 50; S = levellab.level.simulate(c);
    tc.verifyEqual(S.spill(end), 0);
end

function testRigPumpOverflowsOpenLoop(tc)
    % the rig's defaults: balance would need (q / k)^2 metres of water, far above the jar
    [~, D] = levellab.level.physics();
    tc.verifyGreaterThan(D.pct_full_pump, 1000);
end

function testRegisterIdsAndLegacy(tc)
    old = getenv('LEVELLAB_DATA_ROOT'); c = onCleanup(@() setenv('LEVELLAB_DATA_ROOT', old));
    tmp = tempname; mkdir(tmp); setenv('LEVELLAB_DATA_ROOT', tmp);
    T = table((0:4)', (100:100:500)', repmat({'S'}, 5, 1), repmat({'PI'}, 5, 1), 30 * ones(5, 1), (1:5)', ...
        'VariableNames', {'seq', 't_ms', 'loop', 'ctrl', 'setpoint', 'meas'});
    r1 = levellab.data.saveRun('WATER', T, struct('ctrl', 'PI', 'Kp', 1), {}, struct('mission', 'W2', 'legacy_id', 'OLD-1'));
    r2 = levellab.data.saveRun('WATER', T, struct('ctrl', 'P'), {}, struct('mission', 'W4', 'result', 'STOPPED: test'));
    tc.verifyMatches(r1.runId, '^WATER-R0001_\d{8}-\d{6}_W2$');
    tc.verifyMatches(r2.runId, '^WATER-R0002_\d{8}-\d{6}_W4$');
    R = levellab.data.register();
    tc.verifyEqual(height(R), 2); tc.verifyEqual(R.result{2}, 'STOPPED: test');
    tc.verifyEqual(levellab.data.resolve('OLD-1'), r1.runId);
end
