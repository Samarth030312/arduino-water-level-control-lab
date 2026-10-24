function P = params()
%PARAMS  Water-level rig parameters (tank, DC pump, HC-SR04), with provenance.
%
%   P = levellab.level.params()
%
%   The course gives no tank or pump data (SRC-001 p.23). Everything physical
%   here is ASSUMED / ESTIMATED for a small bench tank and a 12 V mini pump and
%   must be replaced by LEVEL-01 measurements (fill and drain timing).

    P = struct(); P.meta = struct();
    add('A',        0.15 * 0.15, 'm^2',  'ASSUMED',   '', '15 x 15 cm tank cross-section');
    add('H',        0.25,   'm',     'ASSUMED',   '', 'tank height = 100 %');
    add('h_sensor', 0.30,   'm',     'ASSUMED',   '', 'HC-SR04 face above the tank floor');
    add('Q_max',    4 / 60000, 'm^3/s', 'ASSUMED', '', '12 V mini pump, 4 L/min at low head');
    add('tau_pump', 0.5,    's',     'ESTIMATED', '', 'pump spin-up');
    add('delay',    1.0,    's',     'ESTIMATED', '', 'relay + pipe fill delay');
    add('k_out',    (4 / 60000) / sqrt(0.24), 'm^2.5/s', 'ESTIMATED', '', 'outlet Q = k sqrt(h); full pump settles at 24 cm (96 %)');
    add('pwm_dead', 0.20,   '-',     'ESTIMATED', '', 'pump does not turn below 20 % duty');
    add('res_us',   0.003,  'm',     'ESTIMATED', 'SRC-014', 'HC-SR04 ~3 mm resolution (datasheet not yet filed)');
    add('noise_us', 0.002,  'm',     'ESTIMATED', '', 'ranging noise on a water surface, 1 sigma');
    add('Ts',       0.1,    's',     'ESTIMATED', 'SRC-014', 'ping period >= 60 ms recommended; 100 ms used');
    add('L_min',    30,     '%',     'VERIFIED_FROM_MANUAL', 'SRC-001', 'course example Lmin 30 % (p.24)');
    add('L_max',    80,     '%',     'VERIFIED_FROM_MANUAL', 'SRC-001', 'course example Lmax 80 % (p.24)');
    add('t_dry',    60,     's',     'ASSUMED',   '', 'firmware: full command for this long without 2 % rise -> dry-run stop');
    add('L_over',   92,     '%',     'ASSUMED',   '', 'firmware: pump forced off above this (overflow guard)');

    function add(name, value, unit, status, source, note)
        P.(name) = value;
        P.meta.(name) = struct('unit', unit, 'status', status, 'source', source, 'note', note);
    end
end
