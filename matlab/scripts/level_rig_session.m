function R = level_rig_session(port, varargin)
%LEVEL_RIG_SESSION  One recorded rig session in the app: geometry, sensor check, on-off run.
%
%   R = level_rig_session('/dev/ttyACM0', 'h_sensor', 0.396, 'tank_H', 0.20)
%   options: h_sensor (m, sensor face to the tank floor), tank_H (m, the depth called 100 %),
%   tank_L, tank_W (m, inside), d_out (mm), Lmin, Lmax (%), Tend (s, on-off run), idle (s of
%   telemetry with the pump off, for the sensor's noise), T_air (C), Bands (N x 2 [Lmin Lmax]: one
%   on-off run per row, in order; default the single Lmin / Lmax).
%
%   Opens water_level_lab, connects, enters the geometry, records `idle` seconds with the pump off
%   (the sensor's noise on a still surface), then runs the on-off mission (W2) for Tend seconds
%   exactly as RUN ON RIG does: the run is saved and registered by the app. The firmware's guards
%   stay active throughout. Progress: results/evidence/logs/level_session_<time>.log.
%   The pump is mains-powered: someone stands at the wall switch.
    o = struct('h_sensor', NaN, 'tank_H', NaN, 'tank_L', NaN, 'tank_W', NaN, 'd_out', NaN, ...
               'Lmin', 30, 'Lmax', 80, 'Tend', 300, 'idle', 20, 'T_air', NaN, 'Bands', []);
    for k = 1:2:numel(varargin), o.(varargin{k}) = varargin{k + 1}; end
    logDir = fullfile(levellab.repoRoot(), 'results', 'evidence', 'logs');
    if ~isfolder(logDir), mkdir(logDir); end
    stamp = char(datetime('now', 'Format', 'yyyyMMdd-HHmmss'));
    logFile = fullfile(logDir, ['level_session_' stamp '.log']);
    app = water_level_lab(); drawnow;
    for f = {'h_sensor', 'tank_H', 'tank_L', 'tank_W', 'd_out', 'T_air'}
        if ~isnan(o.(f{1})), app.set(f{1}, o.(f{1})); end
    end
    assert(app.connect(port), 'levellab:session:connect', 'could not connect on %s', port);
    v = app.values();
    say(sprintf('connected on %s; geometry: sensor %.3f m above the floor, 100 %% = %.3f m, %.3f x %.3f m, drain %.1f mm, air %.0f C', ...
        port, v.h_sensor, v.tank_H, v.tank_L, v.tank_W, v.d_out, v.T_air));
    % the pump off: the reading on a still surface
    L0 = height(app.link().table()); pause(o.idle);
    T = app.link().table(); T = T(L0 + 1:end, :);
    ok = isfinite(T.level_cm);
    R.idle = struct('n', nnz(ok), 'level_cm_mean', mean(T.level_cm(ok)), 'level_cm_std', std(T.level_cm(ok)), ...
        'level_cm_range', [min(T.level_cm(ok)), max(T.level_cm(ok))]);
    say(sprintf('idle %.0f s (pump off): %d readings, level %.2f cm mean, %.2f cm std, %.2f..%.2f cm (firmware geometry until the run sends ours)', ...
        o.idle, R.idle.n, R.idle.level_cm_mean, R.idle.level_cm_std, R.idle.level_cm_range));
    % the on-off runs, one per band
    tags = arrayfun(@(b) strtok(b.Text), app.ui.mb, 'UniformOutput', false);
    bands = o.Bands; if isempty(bands), bands = [o.Lmin o.Lmax]; end
    R.runs = struct('band', {}, 'runId', {}, 'result', {}, 'fault', {});
    for k = 1:size(bands, 1)
        app.selectMission(find(strcmp(tags, 'W2'), 1)); app.setPreset(1); drawnow;
        app.set('Lmin', bands(k, 1)); app.set('Lmax', bands(k, 2)); app.set('Tend', o.Tend); drawnow;
        n0 = height(levellab.data.register());
        say(sprintf('RUN %d/%d on-off %g-%g %% for %g s', k, size(bands, 1), bands(k, 1), bands(k, 2), o.Tend));
        app.runRig(); pause(2);
        if ~app.state().on
            say(['not started: ' app.ui.say.Text]);
            if ~isempty(app.state().fault), app.clearFault(); pause(2); end
            continue
        end
        t1 = tic;
        while app.state().on && toc(t1) < o.Tend + 60, pause(1); end
        if app.state().on, app.stop(); pause(2); end
        Rg = levellab.data.register(); id = ''; res = '';
        if height(Rg) > n0, id = Rg.run_id{end}; res = Rg.result{end}; end
        f = app.state().fault;
        say(sprintf('DONE %.0f s  %s [%s]%s', toc(t1), id, res, ternary(isempty(f), '', ['  FAULT ' f])));
        R.runs(end + 1) = struct('band', bands(k, :), 'runId', id, 'result', res, 'fault', f);
        if ~isempty(f), app.clearFault(); pause(2); end
        pause(5);
    end
    say('session finished');

    function say(s)
        line = sprintf('%s  %s', char(datetime('now', 'Format', 'HH:mm:ss')), s);
        fprintf('%s\n', line);
        fid = fopen(logFile, 'a'); fprintf(fid, '%s\n', line); fclose(fid);
    end
end

function v = ternary(c, a, b), if c, v = a; else, v = b; end, end
