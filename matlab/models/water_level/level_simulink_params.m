function w = level_simulink_params(c)
%LEVEL_SIMULINK_PARAMS  Model-workspace variables for water_level_plant.slx.
    P = c.P;
    w = struct('A', P.A, 'H', P.H, 'h0', c.h0 / 100 * P.H, 'kout', P.k_out, 'drain', c.drainFactor, ...
        'tDrain', c.tDrain, 'Ts', P.Ts, 'resPct', 100 * P.res_us / P.H, 'Lmin', c.Lmin, 'Lmax', c.Lmax, ...
        'Qmax', P.Q_max, 'SP', c.setpoint, 'Kp', c.Kp, 'Ki', c.Ki * strcmp(c.mode, 'PI'), ...
        'dead', P.pwm_dead, 'modeSel', modeSel(c.mode), 'delay', P.delay, ...
        'tauP', P.tau_pump, 'Tend', c.Tend, ...
        'outGravity', double(~strcmp(c.outflow, 'constant')), 'Qc', c.Qout / 60000);
    ol = 1; if isfield(c, 'olPct'), ol = c.olPct / 100; end
    w.Qol = P.Q_max * max(0, (ol - P.pwm_dead) / (1 - P.pwm_dead));
end

function m = modeSel(mode)
    switch mode
        case 'ONOFF', m = 1;
        case {'P', 'PI'}, m = 2;
        case 'OL', m = 3;
        otherwise, error('levellab:simulink:mode', 'mode %s is not in the Simulink model', mode);
    end
end
