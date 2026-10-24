function r = cycleAnalysis(t, level, pump, A, Lmax)
%CYCLEANALYSIS  Flows and ON/OFF times from an ON-OFF run (WATER S3-3, S3-4, S3-5).
%
%   r = levellab.level.cycleAnalysis(t_s, level_cm, pump_on, A_m2, Lmax_cm)
%
%   Rise rate with the pump ON and fall rate with it OFF (least-squares slopes inside each
%   phase, first 2 s after each switch skipped), then Q_out = A * fall rate and
%   Q_in = A * rise rate + Q_out (mL/s). Measured T_on / T_off are the mean phase lengths over
%   complete cycles; overshoot = highest level after each switch-off minus Lmax.
    t = t(:); level = level(:); on = pump(:) > 0;
    sw = find(diff(on) ~= 0) + 1;                       % first sample of each new phase
    edges = [1; sw; numel(t) + 1];
    rise = []; fall = []; Ton = []; Toff = []; over = [];
    for k = 1:numel(edges) - 1
        i = edges(k):edges(k + 1) - 1;
        if numel(i) < 5, continue; end
        complete = k > 1 && k < numel(edges) - 1;
        j = i(t(i) >= t(i(1)) + 2);
        if numel(j) >= 3
            p = polyfit(t(j), level(j), 1);
            if on(i(1)), rise(end + 1) = p(1); else, fall(end + 1) = -p(1); end %#ok<AGROW>
        end
        if complete
            dur = t(edges(k + 1)) - t(i(1));
            if on(i(1)), Ton(end + 1) = dur; else, Toff(end + 1) = dur; over(end + 1) = max(level(i)) - Lmax; end %#ok<AGROW>
        end
    end
    r.rise_cm_s = mean(rise); r.fall_cm_s = mean(fall);
    r.Qout_mL_s = A * 1e4 * r.fall_cm_s;                % m^2 -> cm^2, cm^3/s = mL/s
    r.Qin_mL_s = A * 1e4 * r.rise_cm_s + r.Qout_mL_s;
    r.Ton_s = mean(Ton); r.Toff_s = mean(Toff); r.period_s = r.Ton_s + r.Toff_s;
    r.overshoot_cm = mean(over); r.nCycles = min(numel(Ton), numel(Toff));
end
