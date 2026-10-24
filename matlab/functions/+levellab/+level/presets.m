function p = presets()
%PRESETS  Named water-level experiments (course guideline, SRC-001 p.23-24).
    p = struct('name', {}, 'experiment', {}, 'set', {});
    add('On-off 30-80 % (course)',              'LEVEL-03', {});
    add('On-off 50-55 % (narrow band, chatter)','LEVEL-05', {'Lmin', 50, 'Lmax', 55});
    add('On-off 30-80 %, drain opened 1.2x',    'LEVEL-06', {'drainFactor', 1.2});
    add('P control Kp = 10, 50 %',              'LEVEL-07', {'mode', 'P', 'Kp', 10});
    add('P control Kp = 50, 50 %',              'LEVEL-07', {'mode', 'P', 'Kp', 50});
    add('PI control Kp = 20 Ki = 0.5, 50 %',    'LEVEL-07', {'mode', 'PI'});
    add('PI, drain opened 1.2x',                'LEVEL-07', {'mode', 'PI', 'drainFactor', 1.2});
    add('P Kp = 10, drain opened 1.2x',         'LEVEL-07', {'mode', 'P', 'Kp', 10, 'drainFactor', 1.2});

    function add(name, exp, set)
        p(end + 1) = struct('name', name, 'experiment', exp, 'set', {set});
    end
end
