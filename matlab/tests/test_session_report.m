function tests = test_session_report
%TEST_SESSION_REPORT  The rig session of 2026-10-26, re-analysed from data/, gives the published numbers.
    tests = functiontests(localfunctions);
end

function setupOnce(tc)
    run(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'setup_path.m'));
    out = tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
    tc.TestData.N = level_session_report('2026-10-26', 'Out', out);
    tc.TestData.out = out;
end

function testRunsAndFiles(tc)
    N = tc.TestData.N;
    tc.verifyEqual(N.runs, 4);
    for f = {'REPORT.md', 'onoff_cycles.png', 'all_runs.png'}
        tc.verifyTrue(isfile(fullfile(tc.TestData.out, f{1})), f{1});
    end
end

function testCycles(tc)
    % R0001 (no outflow) is not analysed; R0003 and R0004 each have one complete cycle
    c = tc.TestData.N.cycles;
    tc.verifyEqual({c.run_id}, {'WATER-R0003_20261026-183239_W2', 'WATER-R0004_20261026-183835_W5'});
    tc.verifyEqual([c.Ton_s], [6.1 10.0], 'AbsTol', 0.05);
    tc.verifyEqual([c.overshoot_cm], [2.8 2.8], 'AbsTol', 0.1);
    tc.verifyEqual([c.rise_cm_s], [1.07 1.51], 'AbsTol', 0.01);
    tc.verifyGreaterThan([c.fall_cm_s], 0);
end
