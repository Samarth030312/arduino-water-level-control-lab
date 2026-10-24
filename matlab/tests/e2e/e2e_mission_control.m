function ok = e2e_mission_control(appName, simBinary, speedup)
%E2E_MISSION_CONTROL  the app <-> its real firmware <-> an emulated plant.
%
%   ok = e2e_mission_control('water_level_lab', '<repo>/firmware/tests/levelsim', 5)
%
%   The firmware is compiled for the PC (the apparatus's firmware_host_test.cpp, --pty mode)
%   and runs in real time on a pseudo-terminal; the emulated plant runs `speedup` times faster.
%   The app is driven through its own functions: connect, a LAB run with a live setpoint that
%   ends by itself and is saved and registered, then an ABORT that is kept and marked.
%   Data and logs go to a temporary folder. Linux and macOS (needs a display).
    if nargin < 3, speedup = 10; end
    tmp = tempname; mkdir(tmp);
    setenv('LEVELLAB_DATA_ROOT', tmp); setenv('LEVELLAB_LOG_DIR', tmp);
    cleanEnv = onCleanup(@() cellfun(@(v) setenv(v, ''), {'LEVELLAB_DATA_ROOT', 'LEVELLAB_LOG_DIR'}));
    ptyFile = fullfile(tmp, 'pty.txt');
    system(sprintf('"%s" --pty %g > "%s" 2>&1 & echo $! > "%s/sim.pid"', simBinary, speedup, ptyFile, tmp));
    cleanSim = onCleanup(@() system(sprintf('kill $(cat "%s/sim.pid") 2>/dev/null', tmp)));
    t0 = tic; pty = '';
    while isempty(pty) && toc(t0) < 5
        pause(0.2); tok = regexp(fileread(ptyFile), 'PTY (\S+)', 'tokens', 'once');
        if ~isempty(tok), pty = tok{1}; end
    end
    assert(~isempty(pty), 'emulator did not start');
    fprintf('%s: emulated board on %s\n', appName, pty);
    app = feval(appName); cl = onCleanup(@() delete(app.fig));
    code = levellab.data.apparatus().code;
    ok = true;

    lab = numel(app.ui.mb);                                  % LAB is the last mission
    app.selectMission(lab); app.setPreset(1);
    tend = 14; app.set('Tend', tend);
    ok = check(app.connect(pty), 'connect: the firmware said HELLO') & ok;
    ok = check(strcmp(app.ui.stateChip.Text, 'READY'), 'state READY') & ok;
    v0 = app.values();
    app.runRig(); pause(4);
    ok = check(app.state().on && strcmp(app.ui.stateChip.Text, 'RUNNING') && strcmp(app.ui.rec.Visible, 'on'), 'running, REC on') & ok;
    T = app.link().table();
    ok = check(height(T) >= 5, sprintf('telemetry arrives (%d frames)', height(T))) & ok;
    app.liveSet(v0.setpoint + 5); pause(1);
    log = dir(fullfile(tmp, 'hw_session_*.log')); L = fileread(fullfile(tmp, log(end).name));
    ok = check(contains(L, sprintf('> $SET,1,%g', v0.setpoint + 5)), 'live setpoint sent') & ok;
    D = app.metricsTable();
    ok = check(strcmp(app.ui.table.ColumnName{3}, 'RIG LIVE') && ~isempty(D), 'the table scores the live run') & ok;
    t1 = tic; while app.state().on && toc(t1) < tend + 8, pause(0.25); end
    ok = check(~app.state().on, sprintf('the run ended by itself at its run length (%.0f s)', tend)) & ok;
    Rg = levellab.data.register();
    ok = check(height(Rg) == 1 && startsWith(Rg.run_id{1}, [code '-R0001_']) && endsWith(Rg.run_id{1}, '_LAB') && ...
        strcmp(Rg.result{1}, 'FINISHED'), sprintf('saved and registered: %s %s', Rg.run_id{1}, Rg.result{1})) & ok;
    ok = check(isfile(fullfile(tmp, 'data', 'raw', levellab.data.apparatus(code).folder, [Rg.run_id{1} '.csv'])), 'raw CSV written') & ok;
    app.overlay(Rg.run_id{1});
    D = app.metricsTable();
    ok = check(any(~strcmp(D(:, 3), '—')), 'OVERLAY RUN fills the RIG column') & ok;

    app.runRig(); pause(3); app.abort(); pause(0.5);
    Rg = levellab.data.register();
    ok = check(~app.state().on && height(Rg) == 2 && startsWith(Rg.result{2}, 'ABORTED'), ['ABORT ends the run; kept as ' Rg.result{end}]) & ok;
    L = fileread(fullfile(tmp, log(end).name));
    ok = check(contains(L(max(1, end - 3000):end), '> $STOP,1'), 'ABORT sent STOP') & ok;
    fprintf('\nE2E %s %s (data and logs in %s)\n', appName, ternary(ok, 'PASSED', 'FAILED'), tmp);
end

function ok = check(c, msg)
    ok = logical(c);
    if ok, fprintf('  ok    %s\n', msg); else, fprintf('  FAIL  %s\n', msg); end
end
function s = ternary(c, a, b), if c, s = a; else, s = b; end, end
