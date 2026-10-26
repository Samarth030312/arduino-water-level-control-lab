function P = params()
%PARAMS  Water-level rig parameters (tank, DC pump, HC-SR04), with provenance.
%
%   P = levellab.level.params()
%
%   The course gives no tank or pump data. The defaults describe the lab's rig as built on
%   2026-10-26: a 15 L jar filled from a 500 L tank by a 0.5 HP-class mains pump switched by an
%   SSR. Dimensions and flows are ESTIMATED until measured (jar dimensions, fill and drain timing).

    P = struct(); P.meta = struct();
    add('A',        0.24 * 0.24, 'm^2',  'ESTIMATED', '', '15 L jar, about 24 x 24 cm inside: measure');
    add('H',        0.26,   'm',     'ESTIMATED', '', 'water depth called 100 %, 3 cm or more under the rim');
    add('h_sensor', 0.32,   'm',     'ESTIMATED', '', 'HC-SR04 face above the jar floor ($ZERO measures it)');
    add('Q_max',    25 / 60000, 'm^3/s', 'ESTIMATED', '', '0.5 HP-class monoblock at low head (catalogues: 1500-2000 L/h max): measure');
    add('tau_pump', 0.3,    's',     'ESTIMATED', '', 'induction motor run-up');
    add('delay',    1.5,    's',     'ESTIMATED', '', 'SSR (<= 10 ms zero-cross) + priming and pipe filling');
    add('k_out',    0.6 * pi * 0.004^2 * sqrt(2 * 9.81), 'm^2.5/s', 'ESTIMATED', '', 'outlet Q = Cd a sqrt(2 g h): 8 mm hole, Cd 0.6');
    add('pwm_dead', 0.20,   '-',     'ESTIMATED', '', 'pump does not turn below 20 % duty');
    add('res_us',   0.003,  'm',     'ESTIMATED', 'SRC-014', 'HC-SR04 ~3 mm resolution (datasheet not yet filed)');
    add('noise_us', 0.002,  'm',     'ESTIMATED', '', 'ranging noise on a water surface, 1 sigma');
    add('Ts',       0.1,    's',     'ESTIMATED', 'SRC-014', 'ping period >= 60 ms recommended; 100 ms used');
    add('L_min',    30,     '%',     'VERIFIED_FROM_MANUAL', 'SRC-001', 'course example Lmin 30 % (p.24)');
    add('L_max',    80,     '%',     'VERIFIED_FROM_MANUAL', 'SRC-001', 'course example Lmax 80 % (p.24)');
    add('t_dry',    20,     's',     'VERIFIED_FROM_MANUAL', 'firmware', 'firmware: pump on this long with less than 1 cm rise -> dry-run stop');
    add('L_over',   92,     '%',     'VERIFIED_FROM_MANUAL', 'firmware', 'firmware: pump forced off above this (overflow guard)');
    add('H_rim',    0.29,   'm',     'ESTIMATED', '', 'the rim: water spills above it (3 cm above 100 %)');
    add('rise_cm',  1.0,    'cm',    'VERIFIED_FROM_MANUAL', 'firmware', 'firmware: least rise per t_dry window with the pump on');
    add('t_maxon',  180,    's',     'VERIFIED_FROM_MANUAL', 'firmware', 'firmware: longest continuous run in ON-OFF');

    function add(name, value, unit, status, source, note)
        P.(name) = value;
        P.meta.(name) = struct('unit', unit, 'status', status, 'source', source, 'note', note);
    end
end
