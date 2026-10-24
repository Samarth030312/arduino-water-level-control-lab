function m = metrics(S)
%METRICS  Water-level metrics.
%   On-off: pump starts per hour, cycle period, fill / drain times, level band.
%   P / PI: steady-state error, overshoot, settling (band 2 %), all before the
%   drain disturbance; and the error left after it.
    c = S.cfg; t = S.t; y = S.level;
    tEnd = t(end); if c.drainFactor ~= 1, tEnd = c.tDrain; end
    m.pump_starts = S.starts(end);
    m.starts_per_hour = S.starts(end) / (t(end) / 3600);
    [m.fill_time, m.drain_time, m.cycle_period, m.band_low, m.band_high, ...
     m.ss_error, m.overshoot, m.settle, m.error_after_drain] = deal(NaN);
    if strcmp(c.mode, 'ONOFF')
        on = S.u > 0; tOn = t([false; diff(on) > 0]); tOff = t([false; diff(on) < 0]);
        if numel(tOn) >= 2, m.cycle_period = mean(diff(tOn)); end
        f = []; dd = [];
        for k = 1:numel(tOn), j = find(tOff > tOn(k), 1); if ~isempty(j), f(end + 1) = tOff(j) - tOn(k); end, end %#ok<AGROW>
        for k = 1:numel(tOff), j = find(tOn > tOff(k), 1); if ~isempty(j), dd(end + 1) = tOn(j) - tOff(k); end, end %#ok<AGROW>
        if numel(f) >= 2, m.fill_time = mean(f(2:end)); end
        if ~isempty(dd), m.drain_time = mean(dd); end
        if ~isempty(tOff)
            w = t >= tOff(1) & t < tEnd;
            m.band_low = min(y(w)); m.band_high = max(y(w));
        end
        tl = t >= 0.75 * t(end);                     % pump on all the last quarter AND level flat
        if all(on(tl)) && max(y(tl)) < c.Lmax - 2 && max(y(tl)) - min(y(tl)) < 3
            m.verdict = 'Lmax UNREACHABLE - pump runs on';     % inflow cannot beat the outflow
        elseif isnan(m.cycle_period), m.verdict = 'NO CYCLES';
        else, m.verdict = 'CYCLING'; end
    else
        w = t < tEnd; tail = w & t >= 0.75 * tEnd;
        m.ss_error = c.setpoint - mean(y(tail));
        m.overshoot = max(0, max(y(w)) - c.setpoint);
        out = abs(y(w) - c.setpoint) > 2; tw = t(w);
        if out(end), m.settle = NaN; else, m.settle = tw(find(out, 1, 'last') + 1); end
        if c.drainFactor ~= 1
            m.error_after_drain = c.setpoint - mean(y(t >= t(end) - 0.15 * (t(end) - c.tDrain)));
        end
        if abs(m.ss_error) < 1, m.verdict = 'REGULATING'; else, m.verdict = 'STEADY, OFFSET'; end
    end
    if ~isempty(S.guard), m.verdict = [S.guard ' GUARD']; end
end
