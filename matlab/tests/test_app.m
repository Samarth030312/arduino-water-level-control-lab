function tests = test_app
%TEST_APP  water_level_lab without hardware: every preset simulates
%   and fills its table, the rig is refused politely. The rig path: tests/e2e/e2e_mission_control.m.
    tests = functiontests(localfunctions);
end

function setupOnce(tc)
    try, f = uifigure('Visible', 'off'); delete(f); catch err, tc.assumeFail(['no display: ' err.message]); end
end

function testWater(tc), everyPreset(tc, @water_level_lab); end

function everyPreset(tc, appFun)
    app = appFun(); c = onCleanup(@() delete(app.fig));
    for k = 1:numel(app.ui.mb)
        app.selectMission(k);
        for p = 1:numel(app.ui.preset.Items)
            app.setPreset(p);
            S = app.sim(); D = app.metricsTable();
            tc.verifyTrue(any(isfinite(S.y)), sprintf('mission %d preset %d simulates', k, p));
            tc.verifyTrue(any(~strcmp(D(:, 2), '—')), sprintf('mission %d preset %d has numbers', k, p));
        end
    end
    app.runRig();
    tc.verifyFalse(app.state().on); tc.verifyTrue(contains(app.ui.say.Text, 'Not connected'));
end
