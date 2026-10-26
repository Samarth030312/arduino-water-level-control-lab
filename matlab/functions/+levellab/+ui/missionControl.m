function app = missionControl(D)
%MISSIONCONTROL  The mission-control window shared by the temperature and water-level apps.
%
%   app = levellab.ui.missionControl(D)        D from the app (see below)
%
%   The mission-control layout: top bar with ABORT; missions, presets, controls and the
%   physics panel on the left; the apparatus in 3-D with four live numbers in the centre; the
%   controlled variable and the actuator on the right; rig controls, a SIM / RIG / REF table
%   and the recorded runs at the bottom. What differs per apparatus comes from D:
%
%   D.code, D.title, D.tel, D.sketch     'WATER', 'WATER LEVEL LAB', 'LTEL', 'level'
%   D.missions(k)    tag, short, brief, presets(j).label / .set (struct of control values)
%   D.controls(k)    key, label, section, type 'num'|'drop'|'text', lims, fmt, items, data, default,
%                    show (optional @(v) logical: visible for these values), tip (optional)
%   D.sections       section titles in order
%   D.physics        @(v) [P, text]: parameters for the simulation and the derived-physics text
%   D.simulate       @(v, P) S: t, y (true), ys (what the controller reads), r, u (actuator %),
%                    and anything the scene or the metrics need
%   D.numbers        {label, colour key, @(S, k) value text} x 4 for the live readouts
%   D.yLabel, D.uLabel, D.extraTrace (optional: @(S) [t, y] drawn dotted on the y plot)
%   D.metrics        @(t, r, y, u, v) struct;  D.rows {key, name, fmt};  D.ref @(v, P) struct
%   D.scene          @(ax) handles;  D.pose  @(h, st) st: y, u, sp, t, extra
%   D.rigModes       modes the firmware runs;  D.cfg @(v) {CFG fields};  D.preRun @(link, v)
%   D.fromTel        @(T) table with t_s, setpoint, meas, u_pct (plus the raw columns)
%   D.flags          telemetry flag names that mean the firmware stopped the actuator
%
%   Returns handles and functions for scripts and tests (selectMission, setPreset, set, sim,
%   metricsTable, overlay, connect, runRig, stop, abort, state, link, runs).

    K = levellab.ui.palette();
    A = levellab.data.apparatus(D.code);
    link = levellab.io.SerialLink(D.tel);
    mis = 1; S = []; Pm = []; replay = []; runsView = table(); picked = '';
    hw = struct('on', false, 'v', [], 't0', [], 'fault', '', 'nErr', 0, 'tEnd', Inf);
    hwTimer = []; simTimer = []; watchTimer = []; playTimer = [];
    play = struct('src', '', 'tic', [], 'speed', 1, 'tEnd', 0);
    knownPorts = {}; asking = false; busy = false; ui = struct(); tr = struct();

    % =================================================================== window
    scr = get(groot, 'ScreenSize'); W = min(1800, scr(3) - 40); H = min(1010, scr(4) - 80);
    fig = uifigure('Name', strrep(D.title, '//', '·'), 'Position', [20 40 W H], 'Color', K.bg, ...
                   'CloseRequestFcn', @(~, ~) onClose(), 'WindowKeyPressFcn', @(~, e) onKey(e));
    try, theme(fig, 'dark'); catch, end
    G = uigridlayout(fig, [3 3], 'RowHeight', {52, '1x', 206}, 'ColumnWidth', {318, '1x', '1.15x'}, ...
        'Padding', [10 8 10 10], 'RowSpacing', 8, 'ColumnSpacing', 10, 'BackgroundColor', K.bg);

    top = uigridlayout(G, [1 8], 'ColumnWidth', {250, '1x', 150, 140, 220, 80, 120, 150}, ...
        'Padding', [12 6 6 6], 'ColumnSpacing', 10, 'BackgroundColor', K.panel);
    top.Layout.Row = 1; top.Layout.Column = [1 3];
    lbl(top, D.title, 17, K.text, 'bold');
    ui.mission = lbl(top, '', 15, K.cyan, 'bold');
    ui.linkChip = chip(top, 'OFFLINE');
    ui.stateChip = chip(top, 'SIMULATION');
    ui.fw = lbl(top, A.name, 11, K.dim, 'normal');
    ui.rec = chip(top, '● REC'); ui.rec.BackgroundColor = K.red; ui.rec.Visible = 'off';
    ui.clock = lbl(top, '', 12, K.dim, 'normal'); ui.clock.FontName = K.mono;
    ui.abort = uibutton(top, 'Text', 'ABORT', 'FontSize', 16, 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~, ~) doAbort(), 'Tooltip', 'Actuator off. Esc or Space.');

    % ---- left
    L = uigridlayout(G, [140 2], 'ColumnWidth', {'1x', '1x'}, 'RowSpacing', 4, 'ColumnSpacing', 6, ...
        'Padding', [10 10 10 10], 'BackgroundColor', K.panel, 'Scrollable', 'on');
    L.Layout.Row = 2; L.Layout.Column = 1; L.RowHeight = repmat({0}, 1, 140); row = 0;
    head('MISSION');
    nr = ceil(numel(D.missions) / 2);
    mg = uigridlayout(L, [nr 2], 'Padding', [0 0 0 0], 'RowSpacing', 4, 'ColumnSpacing', 4, ...
        'RowHeight', repmat({28}, 1, nr), 'BackgroundColor', K.panel);
    place(mg, next(32 * nr - 4), [1 2]);
    ui.mb = matlab.ui.control.Button.empty;
    for k = 1:numel(D.missions)
        ui.mb(k) = uibutton(mg, 'Text', sprintf('%s · %s', D.missions(k).tag, D.missions(k).short), 'FontWeight', 'bold', ...
            'UserData', k, 'Tooltip', D.missions(k).brief, 'HorizontalAlignment', 'left', ...
            'ButtonPushedFcn', @(s, ~) selectMission(s.UserData));
        ui.mb(k).Layout.Row = ceil(k / 2); ui.mb(k).Layout.Column = mod(k - 1, 2) + 1;
    end
    ui.brief = note('', 50);
    ui.preset = uidropdown(L, 'Items', {'-'}, 'ValueChangedFcn', @(~, ~) applyPreset(), 'BackgroundColor', K.field, 'FontColor', K.text);
    place(ui.preset, next(28), [1 2]);
    ctl = struct(); ctlRows = struct();
    for s = 1:numel(D.sections)
        head(D.sections{s});
        cs = D.controls(strcmp({D.controls.section}, D.sections{s}));
        for k = 1:numel(cs), makeControl(cs(k)); end
        if strcmp(D.sections{s}, D.physicsSection)
            ui.physTxt = note('', 104); ui.physTxt.FontName = K.mono; ui.physTxt.FontSize = 10.5; ui.physTxt.FontColor = K.dim;
            ui.resetPhys = btn('RESET TO THE DEFAULT VALUES', @(~, ~) onResetPhysics(), [1 2], 28);
            if isfield(D, 'simulink'), ui.simulink = btn('OPEN IN SIMULINK', @(~, ~) onSimulink(), [1 2], 28); end
        end
    end

    % ---- centre
    Cc = uigridlayout(G, [3 1], 'RowHeight', {'1x', 84, 30}, 'Padding', [0 0 0 0], 'RowSpacing', 6, 'BackgroundColor', K.bg);
    Cc.Layout.Row = 2; Cc.Layout.Column = 2;
    axR = uiaxes(Cc); axR.BackgroundColor = K.bg; scene = D.scene(axR);
    tg = uigridlayout(Cc, [2 4], 'RowHeight', {20, '1x'}, 'Padding', [12 4 12 4], 'RowSpacing', 0, 'BackgroundColor', K.panel);
    for k = 1:4, lbl(tg, D.numbers{k, 1}, 10, K.dim, 'bold'); end
    for k = 1:4, ui.num(k) = big(tg, K.(D.numbers{k, 2})); end
    ui.say = lbl(Cc, '', 12.5, K.text, 'normal'); ui.say.HorizontalAlignment = 'center';

    % ---- right
    Pg = uigridlayout(G, [2 1], 'RowHeight', {'1.25x', '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 6, 'BackgroundColor', K.bg);
    Pg.Layout.Row = 2; Pg.Layout.Column = 3;
    axY = mkAx(Pg, D.yLabel); axU = mkAx(Pg, D.uLabel);
    tr.ref = stairs(axY, nan, nan, '--', 'Color', K.dim, 'LineWidth', 1.2);
    tr.yX = plot(axY, nan, nan, ':', 'Color', K.amber, 'LineWidth', 1.3);
    tr.yS = plot(axY, nan, nan, 'Color', K.ghost, 'LineWidth', 1.8);
    tr.yR = plot(axY, nan, nan, 'Color', K.violet, 'LineWidth', 1.5);
    tr.yH = plot(axY, nan, nan, 'Color', K.cyan, 'LineWidth', 2.0);
    tr.uS = plot(axU, nan, nan, 'Color', K.ghost, 'LineWidth', 1.4);
    tr.uR = plot(axU, nan, nan, 'Color', K.violet, 'LineWidth', 1.3);
    tr.uH = plot(axU, nan, nan, 'Color', K.orange, 'LineWidth', 1.8);
    tr.cur = [xline(axY, nan, 'Color', K.dim) xline(axU, nan, 'Color', K.dim)];
    legend(axY, [tr.yH tr.yS tr.yR tr.yX tr.ref], {'rig', 'sim', 'replay', D.extraName, 'setpoint'}, 'Location', 'northeast', ...
        'TextColor', K.dim, 'Color', 'none', 'EdgeColor', 'none', 'AutoUpdate', 'off', 'Orientation', 'horizontal');
    xlabel(axU, 't (s)'); ylim(axU, [-5 105]);

    % ---- bottom
    B1 = uigridlayout(G, [4 2], 'RowHeight', {28, 38, 38, 38}, 'ColumnWidth', {'1x', '1x'}, ...
        'Padding', [10 8 10 8], 'RowSpacing', 6, 'ColumnSpacing', 6, 'BackgroundColor', K.panel);
    B1.Layout.Row = 3; B1.Layout.Column = 1;
    ui.port = uidropdown(B1, 'Items', {'(no board)'}, 'ItemsData', {''}, 'BackgroundColor', K.field, 'FontColor', K.text);
    ui.connect = uibutton(B1, 'Text', 'CONNECT', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) onConnect());
    ui.flash = uibutton(B1, 'Text', 'FLASH FIRMWARE', 'ButtonPushedFcn', @(~, ~) onFlash());
    ui.check = uibutton(B1, 'Text', 'SENSOR CHECK', 'ButtonPushedFcn', @(~, ~) onCheck(), ...
        'Tooltip', 'Watch the live sensor reading for 3 s with the actuator off');
    ui.run = uibutton(B1, 'Text', '▶  RUN ON RIG', 'FontSize', 14, 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) onRunRig());
    ui.stop = uibutton(B1, 'Text', '■  STOP', 'FontSize', 14, 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) onStop());
    ui.clear = uibutton(B1, 'Text', 'CLEAR FAULT', 'ButtonPushedFcn', @(~, ~) onClearFault());
    ui.playSim = uibutton(B1, 'Text', 'PLAY SIMULATION', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) startPlay('sim'));

    B2 = uigridlayout(G, [2 1], 'RowHeight', {'1x', 30}, 'Padding', [10 8 10 8], 'RowSpacing', 6, 'BackgroundColor', K.panel);
    B2.Layout.Row = 3; B2.Layout.Column = 2;
    ui.table = uitable(B2, 'ColumnName', {'', 'SIM', 'RIG', 'REF'}, 'RowName', {}, 'ColumnWidth', {'1x', 74, 74, 74}, ...
        'FontSize', 12, 'BackgroundColor', K.panel, 'ForegroundColor', K.text);
    lg = uigridlayout(B2, [1 6], 'ColumnWidth', {110, 80, '1x', 60, 60, '1x'}, 'Padding', [0 0 0 0], 'ColumnSpacing', 6, 'BackgroundColor', K.panel);
    lbl(lg, 'LIVE SETPOINT', 11, K.cyan, 'bold');
    ui.liveSp = uieditfield(lg, 'numeric', 'Value', 45, 'ValueDisplayFormat', '%.1f', 'BackgroundColor', K.field, 'FontColor', K.text, ...
        'ValueChangedFcn', @(~, ~) liveTo(ui.liveSp.Value));
    ui.liveSet = uibutton(lg, 'Text', 'SEND', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) liveTo(ui.liveSp.Value));
    ui.liveDn = uibutton(lg, 'Text', '− 5', 'ButtonPushedFcn', @(~, ~) liveTo(ui.liveSp.Value - 5));
    ui.liveUp = uibutton(lg, 'Text', '+ 5', 'ButtonPushedFcn', @(~, ~) liveTo(ui.liveSp.Value + 5));
    ui.liveOff = uibutton(lg, 'Text', 'ACTUATOR OFF', 'ButtonPushedFcn', @(~, ~) onStop());

    B3 = uigridlayout(G, [3 4], 'RowHeight', {'1x', 30, 30}, 'ColumnWidth', {'1x', '1x', '1x', '1x'}, ...
        'Padding', [10 8 10 8], 'RowSpacing', 5, 'ColumnSpacing', 6, 'BackgroundColor', K.panel);
    B3.Layout.Row = 3; B3.Layout.Column = 3;
    ui.runs = uitable(B3, 'ColumnName', {'RUN', 'RESULT', 'SETTINGS'}, 'RowName', {}, 'ColumnWidth', {190, 110, 'auto'}, ...
        'FontSize', 11, 'BackgroundColor', K.panel, 'ForegroundColor', K.text, 'SelectionType', 'row', 'Multiselect', 'off', ...
        'SelectionChangedFcn', @(~, e) onPickRun(e));
    ui.runs.Layout.Row = 1; ui.runs.Layout.Column = [1 4];
    ui.runFilter = uidropdown(B3, 'Items', {'this mission', 'all runs'}, 'ValueChangedFcn', @(~, ~) refreshRuns(), ...
        'BackgroundColor', K.field, 'FontColor', K.text);
    ui.overlay = uibutton(B3, 'Text', 'OVERLAY RUN', 'ButtonPushedFcn', @(~, ~) onOverlay());
    ui.sync = uibutton(B3, 'Text', 'SYNC DATA ⇅', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) onSync(), ...
        'Tooltip', 'Commit the new rig runs and push them to GitHub (data, logs, reports only)');
    ui.nextBtn = uibutton(B3, 'Text', 'NEXT MISSION ›', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) selectMission(mod(mis, numel(D.missions)) + 1));
    ui.play = uibutton(B3, 'Text', '▶  PLAY', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) onPlayButton());
    ui.speed = uidropdown(B3, 'Items', {'10x', '30x', '100x', '1x'}, 'Value', D.playSpeed, 'BackgroundColor', K.field, 'FontColor', K.text);
    ui.scrub = uislider(B3, 'Limits', [0 10], 'MajorTicks', [], 'MinorTicks', [], ...
        'ValueChangingFcn', @(~, e) onScrub(e.Value), 'ValueChangedFcn', @(s, ~) onScrub(s.Value));
    ui.scrub.Layout.Column = [3 4];

    styleButtons(fig);
    ui.abort.BackgroundColor = K.red; ui.abort.FontColor = 'w';
    ui.run.BackgroundColor = K.cyanDim; ui.run.FontColor = 'w';

    simTimer = timer('StartDelay', 0.25, 'TimerFcn', @(~, ~) safe(@update), 'BusyMode', 'drop');
    watchTimer = timer('ExecutionMode', 'fixedSpacing', 'Period', 1, 'BusyMode', 'drop', 'TimerFcn', @(~, ~) safe(@watchTick));
    addlistener(fig, 'ObjectBeingDestroyed', @(~, ~) killTimers());
    knownPorts = levellab.io.arduinoPorts(); refreshPorts();
    selectMission(1);
    start(watchTimer);
    setEnabled();
    say(D.welcome, 'info');

    app = struct('fig', fig, 'ui', ui, 'ctl', ctl, 'selectMission', @selectMission, 'setPreset', @setPresetByIndex, ...
        'set', @setValue, 'values', @readValues, 'sim', @getS, 'metricsTable', @getTable, 'overlay', @overlayRun, ...
        'connect', @connectTo, 'runRig', @onRunRig, 'stop', @onStop, 'abort', @doAbort, 'clearFault', @onClearFault, ...
        'liveSet', @liveTo, 'state', @getHw, 'link', @getLink, 'runs', @getRuns, 'play', @startPlay, 'sync', @onSync);

    % =================================================================== controls
    function makeControl(c)
        h = lbl(L, c.label, 11.5, K.dim, 'normal'); place(h, next(26), 1); r0 = row;
        switch c.type
            case 'num'
                f = uieditfield(L, 'numeric', 'Value', c.default, 'Limits', c.lims, 'ValueDisplayFormat', c.fmt, ...
                    'BackgroundColor', K.field, 'FontColor', K.cyan, 'FontName', K.mono, 'HorizontalAlignment', 'right');
            case 'drop'
                f = uidropdown(L, 'Items', c.items, 'ItemsData', c.data, 'Value', c.default, 'BackgroundColor', K.field, 'FontColor', K.text);
            case 'text'
                f = uieditfield(L, 'text', 'Value', c.default, 'BackgroundColor', K.field, 'FontColor', K.cyan, 'FontName', K.mono, ...
                    'HorizontalAlignment', 'right');
        end
        if isfield(c, 'tip') && ~isempty(c.tip), f.Tooltip = c.tip; h.Tooltip = c.tip; end
        f.ValueChangedFcn = @(~, ~) changed();
        place(f, r0, 2);
        ctl.(c.key) = f; ctlRows.(c.key) = struct('label', h, 'row', r0, 'spec', c);
    end

    function v = readValues()
        v = struct();
        for c = D.controls, v.(c.key) = ctl.(c.key).Value; end
    end

    function setValue(key, val)
        if isfield(ctl, key), ctl.(key).Value = val; end
        changed(true);
    end

    function changed(now)
        if nargin < 1, now = false; end
        visibility();
        if isempty(simTimer) || ~isvalid(simTimer), return; end
        stop(simTimer);
        if now, update(); else, start(simTimer); end
    end

    function visibility()
        v = readValues();
        for c = D.controls
            if isfield(c, 'show') && ~isempty(c.show)
                on = c.show(v);
                ctl.(c.key).Visible = onoff(on); ctlRows.(c.key).label.Visible = onoff(on);
                L.RowHeight{ctlRows.(c.key).row} = ternary(on, 26, 0);
            end
        end
    end

    % =================================================================== missions, presets
    function selectMission(k)
        if hw.on, say('STOP the rig run before changing mission.', 'warn'); return; end
        mis = k; M = D.missions(k);
        for i = 1:numel(ui.mb), ui.mb(i).BackgroundColor = K.btn; ui.mb(i).FontColor = K.text; end
        ui.mb(k).BackgroundColor = K.cyan; ui.mb(k).FontColor = K.bg;
        ui.mission.Text = sprintf('%s · %s', upper(M.tag), upper(M.short));
        ui.brief.Text = M.brief;
        ui.preset.Items = {M.presets.label}; ui.preset.ItemsData = 1:numel(M.presets); ui.preset.Value = 1;
        clearReplay();
        applyPreset();
        refreshRuns();
    end

    function setPresetByIndex(i), ui.preset.Value = i; applyPreset(); end

    function applyPreset()
        p = D.missions(mis).presets(ui.preset.Value).set;
        busy = true;
        for f = fieldnames(p)', if isfield(ctl, f{1}), ctl.(f{1}).Value = p.(f{1}); end, end
        busy = false;
        changed(true);
    end

    % =================================================================== simulation
    function update()
        if busy || ~isvalid(fig), return; end
        v = readValues();
        [Pm, txt] = D.physics(v);
        ui.physTxt.Text = txt;
        try
            S = D.simulate(v, Pm);
        catch err
            say(['Simulation: ' err.message], 'warn'); return;
        end
        draw();
        fillTable();
        if ~hw.on, poseAt('sim', S.t(end)); end
    end

    function draw()
        set(tr.ref, 'XData', S.t, 'YData', S.r);
        set(tr.yS, 'XData', S.t, 'YData', S.y);
        set(tr.uS, 'XData', S.t, 'YData', S.u);
        if isfield(D, 'extraTrace') && ~isempty(D.extraTrace)
            [xt, yt] = D.extraTrace(S); set(tr.yX, 'XData', xt, 'YData', yt);
        end
        ui.scrub.Limits = [0 max(S.t(end), 0.1)];
        autoAxes();
    end

    function autoAxes()
        xl = [0 S.t(end)];
        if ~isempty(replay), xl(2) = max(xl(2), replay.T.t_s(end)); end
        if hw.on && link.n > 0, T = rigTable(); xl(2) = max(xl(2), T.t_s(end)); end
        xlim(axY, xl); xlim(axU, xl);
        ys = [get(tr.yS, 'YData'), get(tr.yR, 'YData'), get(tr.yH, 'YData'), get(tr.ref, 'YData'), get(tr.yX, 'YData')];
        ys = ys(isfinite(ys));
        if isempty(ys), return; end
        lo = min(ys); hi = max(ys); pad = max(D.yPad, 0.1 * (hi - lo));
        ylim(axY, [lo - pad, hi + pad]);
    end

    function fillTable()
        if isempty(S), return; end
        v = readValues();
        ms = D.metrics(S.t, S.r, S.ys, S.u, v);
        src = rigSource(); mr = [];
        if ~isempty(src), mr = D.metrics(src.t, src.r, src.y, src.u, v); end
        mt = D.ref(v, Pm);
        rows = D.rows; Dt = cell(size(rows, 1), 4);
        for k = 1:size(rows, 1)
            key = rows{k, 1};
            Dt(k, :) = {rows{k, 2}, num(getm(ms, key), rows{k, 3}), num(getm(mr, key), rows{k, 3}), num(getm(mt, key), rows{k, 3})};
        end
        ui.table.Data = Dt;
        ui.table.ColumnName = {'', 'SIM', ternary(hw.on, 'RIG LIVE', 'RIG'), 'REF'};
    end

    function s = rigSource()
        s = [];
        if hw.on && link.n > 0
            T = rigTable(); s = struct('t', T.t_s, 'r', T.setpoint, 'y', T.meas, 'u', T.u_pct);
        elseif ~isempty(replay)
            T = replay.T; s = struct('t', T.t_s, 'r', T.setpoint, 'y', T.meas, 'u', T.u_pct);
        end
    end

    % =================================================================== pose and playback
    function poseAt(src, t)
        st = struct('t', t, 'y', NaN, 'u', NaN, 'sp', NaN, 'extra', []);
        switch src
            case 'sim'
                k = max(1, min(numel(S.t), find(S.t <= t + 1e-9, 1, 'last')));
                st.y = S.y(k); st.ys = S.ys(k); st.u = S.u(k); st.sp = S.r(k); st.k = k; st.S = S;
            otherwise
                if strcmp(src, 'live'), T = rigTable(); else, T = replay.T; end
                if isempty(T) || height(T) == 0, return; end
                k = find(T.t_s <= t + 1e-9, 1, 'last'); if isempty(k), k = 1; end
                st.y = T.meas(k); st.ys = T.meas(k); st.u = T.u_pct(k); st.sp = T.setpoint(k); st.k = k; st.T = T;
        end
        D.pose(scene, st);
        for i = 1:4, ui.num(i).Text = D.numbers{i, 3}(st); end
        set(tr.cur, 'Value', t);
        ui.clock.Text = sprintf('t = %6.1f s', t);
    end

    function startPlay(src)
        if hw.on, say('Playback is off while the rig runs.', 'warn'); return; end
        if strcmp(src, 'replay') && isempty(replay), say('Pick a run under RUNS first.', 'warn'); return; end
        stopPlay();
        play.src = src; play.speed = sscanf(ui.speed.Value, '%f'); play.tic = tic;
        if strcmp(src, 'sim'), play.tEnd = S.t(end); else, play.tEnd = replay.T.t_s(end); end
        ui.play.Text = '■  PAUSE';
        playTimer = timer('ExecutionMode', 'fixedRate', 'Period', 0.05, 'BusyMode', 'drop', 'TimerFcn', @(~, ~) safe(@playTick));
        start(playTimer);
    end
    function playTick()
        if ~isvalid(fig), stopPlay(); return; end
        t = min(toc(play.tic) * play.speed, play.tEnd);
        poseAt(play.src, t); ui.scrub.Value = min(t, ui.scrub.Limits(2)); drawnow limitrate;
        if t >= play.tEnd, stopPlay(); end
    end
    function stopPlay()
        if ~isempty(playTimer) && isvalid(playTimer), stop(playTimer); delete(playTimer); end
        playTimer = [];
        if isvalid(fig), ui.play.Text = '▶  PLAY'; end
    end
    function onPlayButton()
        if ~isempty(playTimer), stopPlay(); elseif isempty(replay), startPlay('sim'); else, startPlay('replay'); end
    end
    function onScrub(t)
        if hw.on, return; end
        stopPlay(); if isempty(replay), poseAt('sim', t); else, poseAt('replay', t); end
    end

    % =================================================================== recorded runs
    function refreshRuns()
        R = levellab.data.register();
        if ~isempty(R), R = R(strcmp(R.apparatus, D.code), :); end
        if ~isempty(R) && strcmp(ui.runFilter.Value, 'this mission'), R = R(strcmp(R.mission, D.missions(mis).tag), :); end
        if ~isempty(R), R = flipud(R); end
        runsView = R;
        if isempty(R), ui.runs.Data = cell(0, 3); return; end
        ui.runs.Data = [cellfun(@shortId, R.run_id, 'UniformOutput', false), R.result, R.settings];
    end
    function onPickRun(e)
        if isempty(e.Selection) || isempty(runsView) || e.Selection(1) > height(runsView), return; end
        picked = runsView.run_id{e.Selection(1)};
        say(sprintf('%s · %s. OVERLAY RUN draws it over the simulation of its settings.', picked, runsView.result{e.Selection(1)}), 'info');
    end
    function onOverlay()
        if isempty(picked), say('Pick a run in the RUNS table first.', 'warn'); return; end
        overlayRun(picked);
    end
    function overlayRun(id)
        if hw.on, say('STOP the rig run first.', 'warn'); return; end
        [T, meta] = loadRun(id);
        if isfield(meta, 'config_sent') && isfield(meta.config_sent, 'values')
            vv = meta.config_sent.values; busy = true;
            for f = fieldnames(vv)', if isfield(ctl, f{1}), try, ctl.(f{1}).Value = vv.(f{1}); catch, end, end, end
            busy = false;
        end
        replay = struct('id', id, 'T', T);
        set(tr.yR, 'XData', T.t_s, 'YData', T.meas); set(tr.uR, 'XData', T.t_s, 'YData', T.u_pct);
        update();
        say(sprintf('Replaying %s (violet) over the simulation of its settings (grey). PLAY moves the scene.', id), 'info');
    end
    function [T, meta] = loadRun(id)
        root = levellab.data.root();
        Traw = readtable(fullfile(root, 'data', 'raw', A.folder, [id '.csv']), 'TextType', 'char');
        meta = jsondecode(fileread(fullfile(root, 'data', 'metadata', A.folder, [id '.json'])));
        T = D.fromTel(Traw);
    end
    function clearReplay()
        replay = []; set([tr.yR tr.uR], 'XData', nan, 'YData', nan);
    end

    % =================================================================== hardware
    function refreshPorts()
        [p, n] = levellab.io.arduinoPorts();
        items = p; for k = 1:numel(p), if ~isempty(n{k}), items{k} = sprintf('%s   %s', p{k}, n{k}); end, end
        if isempty(p), ui.port.Items = {'(no board)'}; ui.port.ItemsData = {''}; return; end
        cur = ''; if link.isOpen(), cur = char(link.port); end
        ui.port.Items = items; ui.port.ItemsData = p;
        if ~isempty(cur) && any(strcmp(p, cur)), ui.port.Value = cur; end
    end
    function onConnect()
        if link.isOpen()
            if hw.on, onStop(); end
            link.close(); setEnabled(); say('Disconnected.', 'info'); return;
        end
        if isempty(ui.port.Value), say('No board found. Plug in the Uno (data cable); setup lists what it sees.', 'warn'); return; end
        connectTo(ui.port.Value);
    end
    function ok = connectTo(port)
        ok = false;
        try
            link.open(port);
        catch err
            say(['Connect failed: ' err.message ' (port in use? close the Serial Monitor)'], 'warn'); setEnabled(); return;
        end
        logDir = fullfile(levellab.repoRoot(), 'results', 'evidence', 'logs');
        if ~isempty(getenv('LEVELLAB_LOG_DIR')), logDir = getenv('LEVELLAB_LOG_DIR'); end
        if ~isfolder(logDir), mkdir(logDir); end
        link.startLog(fullfile(logDir, sprintf('hw_session_%s_%s.log', lower(D.code), char(datetime('now', 'Format', 'yyyyMMdd-HHmmss')))));
        say(sprintf('Opened %s; waiting for the firmware ...', port), 'info'); setEnabled(); drawnow;
        if link.waitForHello(6)
            h = link.hello; ok = true;
            ui.fw.Text = sprintf('fw %s %s', h{1}, h{min(2, end)});
            if ~contains(h{1}, D.helloName)
                say(sprintf('Connected, but this board runs "%s", not the %s firmware: FLASH FIRMWARE.', h{1}, lower(D.code)), 'warn');
            else
                say(sprintf('Connected: %s %s. RUN ON RIG plays the settings on the left.', h{1}, h{min(2, end)}), 'ok');
            end
        else
            say('Port open, but no reply from the firmware within 6 s: press FLASH FIRMWARE.', 'warn');
        end
        setEnabled();
    end
    function onFlash()
        if hw.on, say('STOP the run before flashing.', 'warn'); return; end
        port = ui.port.Value;
        if isempty(port), say('No board found to flash. Plug in the Uno.', 'warn'); return; end
        if link.isOpen(), link.close(); end
        stop(watchTimer); c = onCleanup(@() restartWatch());
        d = uiprogressdlg(fig, 'Title', 'Firmware', 'Indeterminate', 'on', 'Message', 'Checking the Arduino toolchain ...');
        if levellab.tools.cli('version') ~= 0
            d.Message = 'Installing the Arduino toolchain (once, about 60 MB) ...';
            try, levellab.tools.install('Progress', @(m) set(d, 'Message', m)); catch err, close(d); say(['Toolchain: ' err.message], 'warn'); return; end
        end
        d.Message = sprintf('Compiling and uploading the %s firmware to %s ...', lower(D.code), port);
        R = levellab.tools.flash(A.sketch, port, 'Defines', D.defines(readValues()));
        close(d); pause(1.5); knownPorts = levellab.io.arduinoPorts();
        if R.ok, say(sprintf('Firmware %s flashed. Connecting ...', R.rev), 'ok'); drawnow; connectTo(port);
        else, uialert(fig, sprintf('%s\n\nLog: %s', R.hint, R.logFile), 'Upload failed', 'Icon', 'error'); say(['Upload failed: ' R.hint], 'warn'); end
    end
    function restartWatch(), if isvalid(watchTimer) && strcmp(watchTimer.Running, 'off'), start(watchTimer); end, end

    function onCheck()
        if ~link.isOpen(), say('Connect first.', 'warn'); return; end
        if hw.on, say('STOP the run first.', 'warn'); return; end
        n0 = size(link.eventLog, 1); link.send('PING'); t0 = tic;
        while toc(t0) < 3, link.poll(); pause(0.05); end
        Ls = link.debugLines(n0);
        say(sprintf('Sensor check: %s', strjoin(strrep(Ls(max(1, end - 2):end), '# ', ''), ' | ')), 'info');
    end

    function onRunRig()
        if hw.on, say('Already running.', 'warn'); return; end
        if ~link.isOpen(), say('Not connected: plug in the Uno and press CONNECT.', 'warn'); return; end
        if ~isempty(hw.fault), say(sprintf('The firmware stopped the last run (%s): CLEAR FAULT first.', hw.fault), 'warn'); return; end
        v = readValues();
        if ~any(strcmp(v.(D.modeKey), D.rigModes))
            say(sprintf('The firmware cannot run mode %s; on the rig: %s.', v.(D.modeKey), strjoin(D.rigModes, ', ')), 'warn'); return;
        end
        stopPlay(); clearReplay(); set([tr.yH tr.uH], 'XData', nan, 'YData', nan);
        try
            if isfield(D, 'preRun') && ~isempty(D.preRun), D.preRun(link, v); end
            f = D.cfg(v);
            % every command must be acknowledged: a frame can arrive garbled (SerialLink.command)
            if ~(link.command('CFG', f{:}) && link.setpoint(v.(D.spKey)) && link.run())
                error('the board did not acknowledge the configuration or RUN, or refused it (see the session log)');
            end
        catch err
            say(['Could not start: ' err.message], 'warn'); return;
        end
        hw.on = true; hw.v = v; hw.nErr = countErr(); hw.tEnd = v.(D.tendKey);
        ui.rec.Visible = 'on'; ui.stateChip.Text = 'RUNNING'; ui.stateChip.BackgroundColor = K.cyanDim;
        ui.liveSp.Value = v.(D.spKey);
        setEnabled();
        say(sprintf('Running on the rig for %.0f s. ABORT (Esc / Space) switches the actuator off.', hw.tEnd), 'info');
        hwTimer = timer('ExecutionMode', 'fixedSpacing', 'Period', 0.2, 'BusyMode', 'drop', 'TimerFcn', @(~, ~) safe(@hwTick));
        start(hwTimer);
    end
    function T = rigTable()
        T = table(); if link.n == 0, return; end
        T = D.fromTel(link.table());
        % frames of the previous run can still arrive after RUN (serial buffers): the run is
        % everything from the last frame numbered 0
        k0 = find(T.seq == 0, 1, 'last');            % the firmware numbers each run's frames from 0
        if isempty(k0), T = T([], :); else, T = T(k0:end, :); end
    end
    function hwTick()
        if ~isvalid(fig) || ~link.isOpen(), endRun('link closed', 'ABORTED: link closed'); return; end
        link.poll();
        T = rigTable();
        if ~isempty(T) && height(T) > 0
            set(tr.yH, 'XData', T.t_s, 'YData', T.meas); set(tr.uH, 'XData', T.t_s, 'YData', T.u_pct);
            poseAt('live', T.t_s(end)); autoAxes(); fillTable();
            % the firmware switched the pump off by itself (a guard): its RUNNING flag is off
            if height(T) > 20 && bitand(double(T.flags(end)), 1) == 0
                names = setdiff(levellab.protocol.flagNames(T.flags(end), link.telType), {'RUNNING'}, 'stable');
                reason = 'stopped by the firmware'; if ~isempty(names), reason = strjoin(lower(names), ', '); end
                hw.fault = reason; endRun('', ['STOPPED: ' reason]);
                ui.stateChip.Text = 'FAULT'; ui.stateChip.BackgroundColor = K.red;
                ui.clear.BackgroundColor = K.amber; ui.clear.FontColor = K.bg;
                say(sprintf('The firmware switched the pump off: %s. Fix the cause, then CLEAR FAULT.', reason), 'warn');
                return;
            end
            drawnow limitrate; link.poll();             % render now, then PING again: a slow frame never starves the 3 s watchdog
            if T.t_s(end) >= hw.tEnd
                try, link.stop(); catch, end
                endRun('', 'FINISHED'); say('Run finished and saved under RUNS.', 'ok'); return;
            end
        end
        ev = link.eventLog;
        if ~isempty(ev)
            bad = find(strcmp(ev(:, 2), 'ERR') & startsWith(string(ev(:, 3)), "RUN,"));
            if numel(bad) > hw.nErr
                p = strsplit(ev{bad(end), 3}, ','); reason = strtrim(p{end}); hw.fault = reason;
                endRun('', ['STOPPED: ' reason]);
                ui.stateChip.Text = 'FAULT'; ui.stateChip.BackgroundColor = K.red;
                ui.clear.BackgroundColor = K.amber; ui.clear.FontColor = K.bg;
                say(sprintf('The firmware switched the actuator off: %s. Fix the cause, then CLEAR FAULT.', reason), 'warn');
                return;
            end
        end
        drawnow limitrate;
    end
    function endRun(why, result)
        if ~isempty(hwTimer) && isvalid(hwTimer), stop(hwTimer); delete(hwTimer); end
        hwTimer = [];
        if hw.on && link.n > 0, saveRun(result); end
        hw.on = false;
        if isvalid(fig)
            ui.rec.Visible = 'off';
            if isempty(hw.fault), ui.stateChip.Text = 'STOPPED'; ui.stateChip.BackgroundColor = K.btn; end
            if ~isempty(why), say(['Run ended: ' why], 'warn'); end
            refreshRuns(); setEnabled();
        end
    end
    function saveRun(result)
        Traw = link.table(); Traw = Traw(Traw.seq >= 0, :);
        k0 = find(Traw.seq == 0 & bitand(double(Traw.flags), 1) > 0, 1, 'last');                   % this run only
        if ~isempty(k0), Traw = Traw(k0:end, :); end
        if isempty(Traw) || height(Traw) == 0, return; end
        cfg = struct('mode', hw.v.(D.modeKey), 'setpoint', hw.v.(D.spKey), 'values', hw.v);
        info = struct('port', char(link.port), 'invalidCount', link.invalidCount, 'seqGaps', link.seqGaps, ...
            'mission', D.missions(mis).tag, 'experiment', ui.preset.Items{ui.preset.Value}, 'hello', {link.hello}, ...
            'result', result);
        try
            r = levellab.data.saveRun(D.code, Traw, cfg, link.eventLog, info);
            try, exportapp(fig, fullfile(fileparts(r.meta), [r.runId '.png'])); catch, end
            say(sprintf('Saved %s (%s).', r.runId, result), ternary(startsWith(result, 'FINISHED'), 'ok', 'warn'));
        catch err
            say(['Saving the run failed: ' err.message], 'warn');
        end
    end
    function onStop()
        try, if link.isOpen(), link.stop(); end, catch err, say(['STOP failed: ' err.message ' -- switch the power off.'], 'warn'); end
        if hw.on, endRun('stopped by the operator', 'ABORTED: by the operator'); end
    end
    function doAbort(), stopPlay(); onStop(); if link.isOpen(), say('ABORT: actuator off.', 'warn'); end, end
    function onKey(e), if any(strcmp(e.Key, {'escape', 'space'})), doAbort(); end, end
    function onClearFault()
        hw.fault = ''; ui.clear.BackgroundColor = K.btn; ui.clear.FontColor = K.text;
        if link.isOpen(), try, link.stop(); catch, end, end
        say('Fault cleared. RUN is allowed again.', 'ok'); setEnabled();
    end
    function liveTo(val)
        ui.liveSp.Value = val;
        if ~hw.on || ~link.isOpen(), return; end
        try, link.setpoint(val); say(sprintf('Live setpoint %.1f sent.', val), 'info');
        catch err, say(['Setpoint not sent: ' err.message], 'warn'); end
    end
    function onSync()
        if hw.on, say('STOP the run before syncing.', 'warn'); return; end
        d = uiprogressdlg(fig, 'Title', 'SYNC DATA', 'Indeterminate', 'on', 'Message', 'Committing and pushing the rig data ...');
        r = levellab.data.sync(D.code); close(d); say(r.message, ternary(r.ok, 'ok', 'warn'));
    end
    function onResetPhysics()
        busy = true;
        for c = D.controls
            if strcmp(c.section, D.physicsSection), ctl.(c.key).Value = c.default; end
        end
        busy = false; changed(true); say('Default values restored.', 'info');
    end
    function onSimulink()
        if isempty(ver('simulink')) || ~license('test', 'Simulink')
            say('Simulink is not installed here: the app''s own simulation is the same model.', 'warn'); return;
        end
        try
            msg = D.simulink(readValues(), Pm); say(msg, 'ok');
        catch err
            say(['Simulink: ' err.message], 'warn');
        end
    end
    function watchTick()
        if ~isvalid(fig), return; end
        p = levellab.io.arduinoPorts();
        added = setdiff(p, knownPorts); removed = setdiff(knownPorts, p); knownPorts = p;
        if ~isempty(added) || ~isempty(removed), refreshPorts(); end
        if link.isOpen() && any(strcmp(removed, char(link.port)))
            if hw.on, endRun('the board was unplugged', 'ABORTED: board unplugged'); end
            try, link.close(); catch, end
            setEnabled(); say('The Uno was unplugged. Without MATLAB the firmware switches the actuator off within 3 s.', 'warn');
        end
        if ~isempty(added) && ~link.isOpen() && ~asking
            port = added{1}; asking = true; ui.port.Value = port;
            uiconfirm(fig, sprintf('Arduino found on %s.\n\nFlash the %s firmware and connect, or connect to what is on it?', port, lower(D.code)), ...
                'Board connected', 'Options', {'Flash + connect', 'Connect', 'Not now'}, 'DefaultOption', 2, 'CancelOption', 3, ...
                'CloseFcn', @(~, e) onPlugAnswer(e.SelectedOption, port));
        end
        if link.isOpen() && ~hw.on, link.poll(); end
    end
    function onPlugAnswer(opt, port)
        asking = false;
        switch opt
            case 'Flash + connect', ui.port.Value = port; onFlash();
            case 'Connect', connectTo(port);
        end
    end
    function setEnabled()
        if ~isvalid(fig), return; end
        on = link.isOpen();
        ui.linkChip.Text = ternary(on, ['RIG  ' char(link.port)], 'OFFLINE');
        ui.linkChip.BackgroundColor = ternary(on, K.green, K.btn);
        ui.connect.Text = ternary(on, 'DISCONNECT', 'CONNECT');
        ui.run.Enable = onoff(on && ~hw.on); ui.stop.Enable = onoff(on); ui.check.Enable = onoff(on && ~hw.on);
        ui.clear.Enable = onoff(on && ~hw.on); ui.flash.Enable = onoff(~hw.on);
        set([ui.liveSp ui.liveSet ui.liveDn ui.liveUp ui.liveOff], 'Enable', onoff(hw.on));
        set([ui.playSim ui.play ui.overlay ui.preset ui.sync], 'Enable', onoff(~hw.on)); set(ui.mb, 'Enable', onoff(~hw.on));
        if ~on && ~hw.on, ui.stateChip.Text = 'SIMULATION'; ui.stateChip.BackgroundColor = K.btn; end
        if on && ~hw.on && isempty(hw.fault), ui.stateChip.Text = 'READY'; ui.stateChip.BackgroundColor = K.green; end
    end
    function n = countErr()
        ev = link.eventLog; n = 0;
        if ~isempty(ev), n = nnz(strcmp(ev(:, 2), 'ERR') & startsWith(string(ev(:, 3)), "RUN,")); end
    end
    function onClose()
        try, stopPlay(); if link.isOpen(), try, link.stop(); catch, end, link.close(); end
        catch err, warning('levellab:app:close', 'closing the link: %s', err.message); end
        killTimers(); delete(fig);
    end
    function killTimers()
        for t = {simTimer, watchTimer, hwTimer, playTimer}
            h = t{1}; if ~isempty(h) && isvalid(h), stop(h); delete(h); end
        end
    end
    function safe(f)
        try, f(); catch err, if isvalid(fig), say(['Internal error: ' err.message], 'warn'); end, end
    end
    function r = getS(), r = S; end
    function r = getTable(), r = ui.table.Data; end
    function r = getRuns(), r = runsView; end
    function r = getHw(), r = hw; end
    function r = getLink(), r = link; end

    % =================================================================== layout helpers
    function r = next(h), row = row + 1; L.RowHeight{row} = h; r = row; end
    function head(txt), h = uilabel(L, 'Text', txt, 'FontSize', 11, 'FontWeight', 'bold', 'FontColor', K.dim, 'VerticalAlignment', 'bottom'); place(h, next(24), [1 2]); end
    function h = note(txt, ht), h = uilabel(L, 'Text', txt, 'FontSize', 11.5, 'FontColor', K.text, 'WordWrap', 'on', 'VerticalAlignment', 'top'); place(h, next(ht), [1 2]); end
    function h = btn(txt, fcn, cols, ht), h = uibutton(L, 'Text', txt, 'FontWeight', 'bold', 'ButtonPushedFcn', fcn); place(h, next(ht), cols); end
    function ax = mkAx(parent, ttl)
        ax = uiaxes(parent); hold(ax, 'on');
        ax.Color = K.panel; ax.XColor = K.dim; ax.YColor = K.dim; ax.GridColor = K.line; ax.GridAlpha = 1;
        ax.FontSize = 10; grid(ax, 'on'); box(ax, 'off'); ax.BackgroundColor = K.bg;
        title(ax, ttl, 'Color', K.text, 'FontWeight', 'bold', 'FontSize', 10.5); ax.TitleHorizontalAlignment = 'left';
        try, ax.Toolbar.Visible = 'off'; catch, end
    end
    function h = lbl(parent, txt, sz, col, wt), h = uilabel(parent, 'Text', txt, 'FontSize', sz, 'FontColor', col, 'FontWeight', wt); end
    function h = chip(parent, txt), h = uilabel(parent, 'Text', txt, 'FontSize', 12, 'FontWeight', 'bold', 'FontColor', 'w', 'HorizontalAlignment', 'center', 'BackgroundColor', K.btn); end
    function h = big(parent, col), h = uilabel(parent, 'Text', '—', 'FontSize', 26, 'FontWeight', 'bold', 'FontColor', col, 'FontName', K.mono); end
    function styleButtons(f)
        b = findall(f, 'Type', 'uibutton'); for i = 1:numel(b), b(i).BackgroundColor = K.btn; b(i).FontColor = K.text; end
    end
    function say(txt, kind)
        if ~isvalid(fig), return; end
        ui.say.Text = txt;
        switch kind, case 'warn', ui.say.FontColor = K.amber; case 'ok', ui.say.FontColor = K.green; otherwise, ui.say.FontColor = K.text; end
    end
end

function s = shortId(id)
    t = regexp(id, '^[A-Z]+-R(\d+)_\d{4}(\d{2})(\d{2})-(\d{2})(\d{2})\d{2}_(.*)$', 'tokens', 'once');
    if isempty(t), s = id; else, s = sprintf('R%s  %s-%s %s:%s  %s', t{:}); end
end
function v = getm(m, k), if isempty(m) || ~isfield(m, k), v = NaN; else, v = m.(k); end, end
function s = num(v, f), if isempty(v) || ~isnumeric(v) || ~isfinite(v), s = '—'; else, s = sprintf(f, v); end, end
function s = ternary(c, a, b), if c, s = a; else, s = b; end, end
function s = onoff(c), s = matlab.lang.OnOffSwitchState(logical(c)); end
function place(h, r, c), h.Layout.Row = r; h.Layout.Column = c; end
