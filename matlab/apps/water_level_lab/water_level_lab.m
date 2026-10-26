function app = water_level_lab()
%LEVELLAB_WATER  Water-level control: mission control for the tank rig and its model.
%
%   cd <repo>/matlab; setup level            (or: run('setup_path.m'); water_level_lab)
%
%   Missions follow the WATER handout: filling in open loop, on-off between Lmin and Lmax,
%   P and PI on a PWM pump, an outlet-valve disturbance, the physical limits (overflow,
%   a pump too small), and integral windup; LAB is free use.
%
%   SIMULATE  levellab.level.simulate: A dh/dt = q_pump - k sqrt(h) (Torricelli; nonlinear), the
%             pump's dead zone, delay, spin-up and curve, the HC-SR04 every 0.1 s, the
%             firmware's guards (overflow, dry run). A, k, the pump and the sensor come from
%             the dimensions in the physics panel (levellab.level.physics).
%   RIG       the same settings on the Arduino (level_controller, protocol $LTEL); the tank
%             geometry and air temperature are sent first ($CAL). Every run is saved and
%             registered.
%   Safety: ABORT, Esc, Space stop the pump; the firmware stops it if MATLAB is silent for 3 s,
%   above the overflow guard, on a float switch, on a dry run or a lost sensor.
    D = struct();
    D.code = 'WATER'; D.title = 'WATER LEVEL LAB'; D.tel = 'LTEL'; D.helloName = 'water_level_lab';
    D.welcome = 'Simulation of the tank from the physics panel. Pick a mission; plug in the Uno to run it on the rig.';
    D.modeKey = 'mode'; D.spKey = 'setpoint'; D.tendKey = 'Tend';
    D.rigModes = {'ONOFF', 'P', 'PI'};
    D.yLabel = 'LEVEL  (% of tank height, what the HC-SR04 reads)'; D.uLabel = 'PUMP  (% of full command)';
    D.extraName = 'true level'; D.yPad = 3; D.playSpeed = '10x';
    D.physicsSection = 'TANK · OUTLET · PUMP · SENSOR  (→ physics)';
    D.sections = {'CONTROLLER', 'DISTURBANCE', D.physicsSection};
    D.controls = controls();
    D.missions = missions();
    D.physics = @physics;
    D.simulate = @simulate;
    D.extraTrace = @(S) deal(S.t, S.level);
    D.numbers = {'LEVEL  %', 'cyan', @(st) sprintf('%5.1f', st.y); ...
                 'SETPOINT  %', 'text', @(st) spText(st); ...
                 'PUMP  %', 'orange', @(st) sprintf('%5.0f', st.u); ...
                 'IN − OUT  L/min', 'text', @(st) flowText(st)};
    D.metrics = @metrics; D.rows = rows(); D.ref = @ref;
    D.scene = @(ax) levellab.ui.waterRig(ax);
    D.pose = @pose;
    D.cfg = @(v) {v.mode, v.Lmin, v.Lmax, v.setpoint, v.Kp, v.Ki};
    D.preRun = @(link, v) preRun(link, v);
    D.defines = @defines;
    D.fromTel = @fromTel;
    D.simulink = @openSimulink;
    app = levellab.ui.missionControl(D);
end

% ======================================================================= definition
function C = controls()
    C = struct('key', {}, 'label', {}, 'section', {}, 'type', {}, 'lims', {}, 'fmt', {}, 'items', {}, ...
               'data', {}, 'default', {}, 'show', {}, 'tip', {});
    isMode = @(varargin) @(v) any(strcmp(v.mode, varargin));
    C(end + 1) = d('mode', 'law', 'CONTROLLER', {'open loop (fixed pump)', 'on-off (Lmin / Lmax)', 'P (PWM pump)', 'PI (PWM pump)'}, ...
        {'OL', 'ONOFF', 'P', 'PI'}, 'ONOFF', [], 'On-off works with every pump wiring; P and PI need a DC pump on a MOSFET (PWM) on the rig, any pump in simulation');
    C(end + 1) = n('Lmin', 'Lmin: pump ON below (%)', 'CONTROLLER', [0 100], '%.0f', 30, isMode('ONOFF'), 'Course: 30 %');
    C(end + 1) = n('Lmax', 'Lmax: pump OFF above (%)', 'CONTROLLER', [0 100], '%.0f', 80, isMode('ONOFF'), 'Course: 80 %');
    C(end + 1) = n('setpoint', 'setpoint (%)', 'CONTROLLER', [0 100], '%.0f', 50, isMode('P', 'PI'), 'The firmware caps it 5 % under its overflow guard');
    C(end + 1) = n('olPct', 'pump command (%)', 'CONTROLLER', [0 100], '%.0f', 100, isMode('OL'), '');
    C(end + 1) = n('Kp', 'Kp  (counts / %)', 'CONTROLLER', [0 500], '%.1f', 20, isMode('P', 'PI'), 'Output 0-255 = PWM counts');
    C(end + 1) = n('Ki', 'Ki  (counts / %·s)', 'CONTROLLER', [0 20], '%.3f', 0.5, isMode('PI'), '');
    C(end + 1) = d('aw', 'integrator', 'CONTROLLER', {'clamping anti-windup (firmware)', 'plain integrator (simulation)'}, {'on', 'off'}, 'on', isMode('PI'), '');
    C(end + 1) = d('outflow', 'outflow', 'CONTROLLER', {'gravity outlet: k sqrt(h)', 'constant drain (pumped)'}, {'gravity', 'constant'}, 'gravity', [], ...
        'Inspect the rig: an open outlet at the bottom is gravity; a drain pump is constant');
    C(end + 1) = n('Qout', 'constant drain (L/min)', 'CONTROLLER', [0 20], '%.2f', 1.5, @(v) strcmp(v.outflow, 'constant'), '');
    C(end + 1) = d('guards', 'firmware guards', 'CONTROLLER', {'on (overflow, dry run)', 'off (simulation only)'}, {'on', 'off'}, 'on', [], ...
        'Off shows what the guards prevent; the firmware always has them');
    C(end + 1) = n('h0', 'starting level (%)', 'CONTROLLER', [0 100], '%.0f', 10, [], '');
    C(end + 1) = n('Tend', 'run length (s)', 'CONTROLLER', [10 7200], '%.0f', 900, [], '');
    C(end + 1) = n('valve2', 'outlet valve after (%)', 'DISTURBANCE', [0 300], '%.0f', 100, [], 'Opening after the change, % of the bore');
    C(end + 1) = n('tDrain', 'valve changes at t (s)', 'DISTURBANCE', [0 7200], '%.0f', 600, [], '');
    S = 'TANK · OUTLET · PUMP · SENSOR  (→ physics)';
    C(end + 1) = d('pump_kind', 'pump wiring', S, {'mains AC pump · SSR (on-off)', 'pump · relay module, active LOW (on-off)', 'DC pump · MOSFET (PWM: P, PI)'}, ...
        {'ssr', 'relay', 'pwm'}, 'ssr', [], 'Sets the firmware build at FLASH; on the rig, P and PI need the PWM wiring');
    C(end + 1) = n('tank_L', 'tank length (m)', S, [0.02 2], '%.3f', 0.24, [], 'Inside dimensions: 15 L jar ESTIMATED until measured');
    C(end + 1) = n('tank_W', 'tank width (m)', S, [0.02 2], '%.3f', 0.24, [], '');
    C(end + 1) = n('tank_H', 'tank height = 100 % (m)', S, [0.05 2], '%.3f', 0.26, [], 'Water depth you call 100 %: keep it 3 cm or more under the rim');
    C(end + 1) = n('h_sensor', 'sensor above the floor (m)', S, [0.05 3], '%.3f', 0.32, [], 'HC-SR04 face to the tank floor ($ZERO measures it)');
    C(end + 1) = n('d_out', 'outlet bore (mm)', S, [0.5 50], '%.1f', 8, [], 'The drain hole back to the reservoir');
    C(end + 1) = n('Cd', 'discharge coefficient Cd', S, [0.3 1], '%.2f', 0.6, [], '~0.6 sharp hole, ~0.8 short tube');
    C(end + 1) = n('valve', 'outlet valve opening (%)', S, [0 100], '%.0f', 100, [], 'Scales the outlet area');
    C(end + 1) = n('Q_max', 'pump flow at zero head (L/min)', S, [0.1 200], '%.2f', 25, [], 'From the pump label; 0.5 HP class ESTIMATED 25 (measure: S3-3)');
    C(end + 1) = n('H_max', 'pump shut-off head (m)', S, [0.1 80], '%.2f', 25, [], 'Flow falls linearly to zero at this head');
    C(end + 1) = n('h_lift', 'lift: sump to tank floor (m)', S, [0 3], '%.2f', 0.05, [], '');
    C(end + 1) = n('pwm_dead', 'pump dead zone (% PWM)', S, [0 90], '%.0f', 20, [], 'No flow below this duty');
    C(end + 1) = n('delay', 'relay + pipe delay (s)', S, [0 20], '%.1f', 1.5, [], 'Switching to water arriving: priming, pipe filling');
    C(end + 1) = n('T_air', 'air temperature (°C)', S, [-10 50], '%.0f', 20, [], 'Speed of sound for the HC-SR04 (sent to the firmware)');

    function c = n(key, label, sec, lims, fmt, def, show, tip)
        c = struct('key', key, 'label', label, 'section', sec, 'type', 'num', 'lims', lims, 'fmt', fmt, ...
                   'items', [], 'data', [], 'default', def, 'show', show, 'tip', tip);
    end
    function c = d(key, label, sec, items, data, def, show, tip)
        c = struct('key', key, 'label', label, 'section', sec, 'type', 'drop', 'lims', [], 'fmt', '', ...
                   'items', {items}, 'data', {data}, 'default', def, 'show', show, 'tip', tip);
    end
end

function preRun(link, v)
    % what the firmware cannot do on this wiring would run something else under its name
    if ~strcmp(v.pump_kind, 'pwm') && any(strcmp(v.mode, {'P', 'PI'}))
        error('P and PI need a DC pump on a MOSFET (pump wiring: PWM); with an SSR or relay the rig runs on-off only (simulate P and PI)');
    end
    if strcmp(v.guards, 'off'), error('the firmware always has its guards: set them on for the rig'); end
    if ~link.command('CAL', 100 * v.h_sensor, 100 * v.tank_H, v.T_air)
        error('the board refused the geometry: sensor height must exceed the 100 %% depth by 4 cm or more');
    end
end

function d = defines(v)
    switch v.pump_kind
        case 'pwm', d = {'PUMP_PWM=1'};
        case 'relay', d = {'RELAY_ACTIVE_LOW=1'};
        otherwise, d = {};
    end
end

function M = missions()
    M = struct('tag', {}, 'short', {}, 'brief', {}, 'presets', {});
    add('W1', 'Filling', 'The pump at a fixed command from empty: where does the level stop, and why there?', ...
        {'pump 100 % from empty', struct('mode', 'OL', 'olPct', 100, 'h0', 0, 'Tend', 900); ...
         'pump 70 % from empty', struct('mode', 'OL', 'olPct', 70, 'h0', 0, 'Tend', 900); ...
         'pump 50 % from empty', struct('mode', 'OL', 'olPct', 50, 'h0', 0, 'Tend', 900)});
    add('W2', 'On-off', 'Pump on below Lmin, off above Lmax, unchanged in between: the tank cycles.', ...
        {'Lmin 30 %, Lmax 80 % (course)', struct('mode', 'ONOFF', 'Lmin', 30, 'Lmax', 80, 'Tend', 1500); ...
         'band halved: 42.5 - 67.5 %', struct('mode', 'ONOFF', 'Lmin', 42.5, 'Lmax', 67.5, 'Tend', 1500); ...
         'constant drain 1.5 L/min', struct('mode', 'ONOFF', 'Lmin', 30, 'Lmax', 80, 'outflow', 'constant', 'Tend', 1500)});
    add('W3', 'P control', 'Pump command = Kp x error. The outflow needs a pump command, so P needs an error.', ...
        {'Kp 10, 50 %', p('P', 10, 0); 'Kp 20, 50 %', p('P', 20, 0); 'Kp 50, 50 %', p('P', 50, 0)});
    add('W4', 'PI control', 'Integral action finds the pump command the outflow needs: no offset.', ...
        {'Kp 20, Ki 0.5, 50 %', p('PI', 20, 0.5); 'Kp 20, Ki 1, 50 %', p('PI', 20, 1); 'Kp 50, Ki 0.5, 50 %', p('PI', 50, 0.5)});
    add('W5', 'Valve disturbance', 'At 600 s the outlet valve opens from 100 % to 130 %. Which controller holds the level?', ...
        {'on-off', struct('mode', 'ONOFF', 'valve2', 130, 'tDrain', 600, 'Tend', 1500); ...
         'P Kp 20', struct('mode', 'P', 'Kp', 20, 'valve2', 130, 'tDrain', 600, 'Tend', 1500); ...
         'PI Kp 20 Ki 0.5', struct('mode', 'PI', 'Kp', 20, 'Ki', 0.5, 'valve2', 130, 'tDrain', 600, 'Tend', 1500)});
    add('W6', 'Limits', 'A setpoint near the rim with the outlet half closed; a pump too small for the outflow.', ...
        {'PI at 90 %, outlet 55 %, guards on', struct('mode', 'PI', 'setpoint', 90, 'valve', 55, 'Tend', 900); ...
         'pump 100 %, outlet 55 %, guards off: overflow', struct('mode', 'OL', 'olPct', 100, 'valve', 55, 'guards', 'off', 'h0', 50, 'Tend', 900); ...
         'on-off 30-80 %, pump 2.5 L/min: Lmax unreachable', struct('mode', 'ONOFF', 'Q_max', 2.5, 'Tend', 1200)});
    add('W7', 'Windup', 'The pump saturates while the level climbs to 85 %: with a plain integrator the level overshoots.', ...
        {'PI at 85 %, clamping', struct('mode', 'PI', 'setpoint', 85, 'Kp', 20, 'Ki', 1, 'aw', 'on', 'h0', 5, 'Tend', 900); ...
         'PI at 85 %, plain integrator', struct('mode', 'PI', 'setpoint', 85, 'Kp', 20, 'Ki', 1, 'aw', 'off', 'h0', 5, 'Tend', 900)});
    add('LAB', 'Free', 'Any law, any setpoint. On the rig the setpoint changes live (P / PI).', ...
        {'on-off 30-80 %', struct('mode', 'ONOFF', 'Tend', 1200); 'PI 50 %', p('PI', 20, 0.5)});
    function s = p(mode, Kp, Ki), s = struct('mode', mode, 'Kp', Kp, 'Ki', Ki, 'setpoint', 50, 'Tend', 1200); end
    function add(tag, short, brief, pr)
        base = struct('mode', 'ONOFF', 'Lmin', 30, 'Lmax', 80, 'setpoint', 50, 'olPct', 100, 'Kp', 20, 'Ki', 0.5, 'aw', 'on', ...
            'outflow', 'gravity', 'Qout', 1.5, 'guards', 'on', 'h0', 10, 'Tend', 900, 'valve2', 100, 'tDrain', 600, ...
            'valve', 100, 'Q_max', 25);
        for i = 1:size(pr, 1)
            sv = base; f = fieldnames(pr{i, 2});
            for j = 1:numel(f), sv.(f{j}) = pr{i, 2}.(f{j}); end
            if sv.valve2 == 100, sv.valve2 = sv.valve; end              % no change unless asked
            pr{i, 2} = sv;
        end
        M(end + 1) = struct('tag', tag, 'short', short, 'brief', brief, 'presets', struct('label', pr(:, 1)', 'set', pr(:, 2)'));
    end
end

function R = rows()
    R = {'steady', 'steady level (%)', '%.1f'; 't63', 'time to 63 % of it (s)', '%.0f'; ...
         'ess', 'steady error (%)', '%.2f'; 'over', 'overshoot (%)', '%.1f'; 'settle', 'settling, ±2 % (s)', '%.0f'; ...
         'period', 'on-off cycle period (s)', '%.0f'; 'starts', 'pump starts per hour', '%.1f'; ...
         'band', 'level band, peak to peak (%)', '%.1f'; 'distErr', 'error after the valve change (%)', '%.2f'; ...
         'recov', 'back within 2 % after it (s)', '%.0f'; 'spill', 'water over the rim (L)', '%.2f'};
end

% ======================================================================= physics and simulation
function [P, txt] = physics(v)
    spec = struct();
    for f = {'tank_L', 'tank_W', 'tank_H', 'h_sensor', 'd_out', 'Cd', 'valve', 'Q_max', 'H_max', 'h_lift', 'pwm_dead', 'delay', 'T_air'}
        spec.(f{1}) = v.(f{1});
    end
    [P, D] = levellab.level.physics(spec);
    P.derived = D;
    txt = sprintf(['A %.0f cm²   outlet a %.1f mm²\nk = Cd a sqrt(2g) %.3g m^2.5/s\nfull pump holds %.0f %% (%.1f cm)\n' ...
        'K %.0f s/m²   τ %.0f s (at %.0f cm)\nfill from empty ≥ %.0f s   %.1f L\n%s'], ...
        1e4 * D.A, 1e6 * D.a, D.k, D.pct_full_pump, 100 * D.h_full_pump, D.K, D.tau, 100 * D.h0, D.t_fill_empty, D.V_L, D.tf);
end

function S = simulate(v, P)
    c = levellab.level.defaultConfig();
    c.P = P; c.mode = v.mode; c.Lmin = v.Lmin; c.Lmax = v.Lmax; c.setpoint = v.setpoint; c.Kp = v.Kp; c.Ki = v.Ki;
    c.antiWindup = strcmp(v.aw, 'on'); c.outflow = v.outflow; c.Qout = v.Qout; c.guards = strcmp(v.guards, 'on');
    c.h0 = v.h0; c.Tend = v.Tend; c.olPct = v.olPct;
    c.drainFactor = v.valve2 / max(v.valve, 1e-6); c.tDrain = v.tDrain;
    R = levellab.level.simulate(c);
    r = repmat(v.setpoint, size(R.t)); if ~any(strcmp(v.mode, {'P', 'PI'})), r(:) = NaN; end
    S = struct('t', R.t, 'y', R.meas, 'ys', R.meas, 'level', R.level, 'r', r, 'u', 100 * R.u / 255, ...
        'qin', R.qin, 'qout', R.qout, 'spill', R.spill, 'guard', R.guard, 'v', v);
end

% ======================================================================= numbers
function m = metrics(t, r, y, u, v)
    m = struct();
    ok = isfinite(t) & isfinite(y); t = t(ok); y = y(ok); r = r(ok); u = u(ok);
    if numel(t) < 5, return; end
    tEnd = t(end); dist = v.valve2 ~= v.valve && v.tDrain < t(end);
    if dist, tEnd = v.tDrain; end
    w = t <= tEnd; tw = t(w); yw = y(w);
    tail = tw >= tw(end) - 0.2 * (tw(end) - tw(1));
    m.steady = mean(yw(tail));
    k63 = find(yw >= yw(1) + 0.632 * (m.steady - yw(1)), 1);
    if strcmp(v.mode, 'OL') && ~isempty(k63), m.t63 = tw(k63) - tw(1); end
    on = u > 0; st = find(diff(on) > 0) + 1;
    m.starts = numel(st) / ((t(end) - t(1)) / 3600);
    if strcmp(v.mode, 'ONOFF')
        if numel(st) >= 3, m.period = mean(diff(t(st(2:end)))); end
        if numel(st) >= 2, j = tw >= t(st(2)); if any(j), m.band = max(yw(j)) - min(yw(j)); end, end
    end
    if any(strcmp(v.mode, {'P', 'PI'}))
        sp = v.setpoint;
        m.ess = sp - m.steady;
        m.over = max(0, max(yw) - sp);
        out = abs(yw - sp) > 2;
        if ~out(end), j = find(out, 1, 'last'); if isempty(j), m.settle = 0; else, m.settle = tw(j + 1) - tw(1); end, end
        if dist
            j = t >= v.tDrain; tt = t(j) - v.tDrain; yy = y(j);
            m.distErr = sp - mean(yy(tt >= tt(end) - 0.2 * tt(end)));
            bad = abs(yy - sp) > 2;
            if ~bad(end), jl = find(bad, 1, 'last'); if isempty(jl), m.recov = 0; else, m.recov = tt(jl + 1); end, end
        end
    end
end

function m = ref(v, P)
    % theory from the physics: Torricelli steady states (pump curve and dead zone included),
    % the P offset that keeps the pump running, the linearised time constant
    D = P.derived; m = struct();
    k = D.k; Q = P.Q_max; H = P.H;
    flow = @(duty, h) Q * max(0, (duty - P.pwm_dead) / (1 - P.pwm_dead)) * max(0, 1 - (P.h_lift + h) / P.H_max);
    switch v.mode
        case 'OL'
            duty = v.olPct / 100; hs = 0;
            for it = 1:80, hs = min((flow(duty, hs) / k)^2, H); end
            m.steady = 100 * hs / H; m.t63 = 2 * P.A * sqrt(max(hs, 1e-6)) / k;
        case 'P'                                                  % e such that Kp e gives the needed flow
            h = v.setpoint / 100 * H; need = k * sqrt(h);
            e = fzeroSafe(@(e) flow(min(max(v.Kp * e, 0), 255) / 255, (v.setpoint - e) / 100 * H) - k * sqrt(max((v.setpoint - e) / 100 * H, 0)), [0 v.setpoint]);
            m.ess = e; m.steady = v.setpoint - e; if need > flow(1, h), m.ess = NaN; end
        case 'PI'
            m.ess = 0;
        case 'ONOFF'
            hm = (v.Lmin + v.Lmax) / 200 * H; qo = k * sqrt(hm); qi = flow(1, hm);
            if qi > qo
                dV = P.A * (v.Lmax - v.Lmin) / 100 * H;
                m.period = dV / (qi - qo) + dV / qo; m.band = v.Lmax - v.Lmin;
            end
    end
end

function e = fzeroSafe(f, b)
    try, e = fzero(f, b); catch, e = NaN; end
end

% ======================================================================= scene, rig
function pose(h, st)
    if isfield(st, 'S')
        S = st.S; k = st.k; v = S.v;
        lv = S.level(k); qin = S.qin(k); qout = S.qout(k);
        valve = v.valve; if v.valve2 ~= v.valve && S.t(k) >= v.tDrain, valve = v.valve2; end
        Lmin = v.Lmin; Lmax = v.Lmax;
    else
        lv = st.y; qin = NaN; qout = NaN; valve = 100; Lmin = 30; Lmax = 80;
    end
    levellab.ui.waterRigPose(h, struct('level', lv, 'u', st.u, 'sp', st.sp, 'Lmin', Lmin, 'Lmax', Lmax, ...
        'valve', valve, 'qin', qin, 'qout', qout));
end

function s = spText(st)
    if isfinite(st.sp), s = sprintf('%5.1f', st.sp); elseif isfield(st, 'S'), s = sprintf('%g-%g', st.S.v.Lmin, st.S.v.Lmax); else, s = '—'; end
end

function s = flowText(st)
    if isfield(st, 'S'), s = sprintf('%+5.2f', st.S.qin(st.k) - st.S.qout(st.k)); else, s = '—'; end
end

function T = fromTel(Traw)
    % the firmware streams $LTEL all the time; a run is the frames with the RUNNING flag
    run = bitand(double(Traw.flags), 1) > 0;
    Traw = Traw(run, :);                         % idle frames (before RUN, after STOP) never count
    T = Traw;
    T.t_s = Traw.t_ms / 1000;
    T.meas = Traw.level_pct;
    T.u_pct = 100 * Traw.u / 255;
end

function msg = openSimulink(v, P)
    here = fullfile(levellab.repoRoot(), 'matlab', 'models', 'water_level');
    mdl = 'water_level_plant';
    c = levellab.level.defaultConfig(); c.P = P;
    for f = {'mode', 'Lmin', 'Lmax', 'setpoint', 'Kp', 'Ki', 'outflow', 'Qout', 'h0', 'Tend', 'olPct', 'tDrain'}
        c.(f{1}) = v.(f{1});
    end
    c.drainFactor = v.valve2 / max(v.valve, 1e-6); c.antiWindup = strcmp(v.aw, 'on');
    if ~isfile(fullfile(here, [mdl '.slx'])), build_level_simulink(here); end
    w = level_simulink_params(c);
    load_system(fullfile(here, [mdl '.slx']));
    if c.antiWindup, aw = 'clamping'; else, aw = 'none'; end
    set_param([mdl '/PI'], 'AntiWindupMode', aw);
    mw = get_param(mdl, 'ModelWorkspace');
    for f = fieldnames(w)', assignin(mw, f{1}, w.(f{1})); end
    open_system(mdl);
    msg = sprintf('%s opened with these settings (no pump curve, guards in MATLAB only): press Run in Simulink.', mdl);
end
