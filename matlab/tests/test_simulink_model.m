function tests = test_simulink_model
%TEST_SIMULINK_MODEL  Simulink models agree with the MATLAB simulators.
%   Switching systems: compared on metrics (a relay can flip one sample apart),
%   noise off, ideal-average SSR. Skipped without Simulink.
    tests = functiontests(localfunctions);
end

function setupOnce(tc)
    run(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'setup_path.m'));
    tc.assumeTrue(~isempty(ver('simulink')) && license('test', 'Simulink'), 'Simulink not installed');
    tc.TestData.dir = tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
    build_level_simulink(tc.TestData.dir);
end

function testLevelModes(tc)
    for mode = {'ONOFF', 'P', 'PI'}
        c = levellab.level.defaultConfig(); c.mode = mode{1}; c.P.noise_us = 0;
        M = levellab.level.simulate(c);
        R = run_level_simulink(c, tc.TestData.dir);
        if strcmp(mode{1}, 'ONOFF')
            on = R.q > 0.5 * c.P.Q_max; tOn = R.t([false; diff(on) > 0]);
            tOn = tOn(tOn > 5);                               % drop the start-up edge (flow rising from 0)
            perR = mean(diff(tOn)); perM = M.metrics.cycle_period;
            fprintf('  level ONOFF  period MATLAB %.1f s, Simulink %.1f s\n', perM, perR);
            tc.verifyLessThan(abs(perR - perM) / perM, 0.03);
        else
            tail = R.t >= 0.75 * c.Tend;                      % same window as levellab.level.metrics (no drain step)
            essR = c.setpoint - mean(R.level(tail));
            fprintf('  level %-5s  e_ss MATLAB %.2f %%, Simulink %.2f %%\n', mode{1}, M.metrics.ss_error, essR);
            tc.verifyLessThan(abs(essR - M.metrics.ss_error), 0.5, mode{1});
        end
    end
end
