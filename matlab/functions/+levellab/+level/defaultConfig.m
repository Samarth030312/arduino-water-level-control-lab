function c = defaultConfig()
%DEFAULTCONFIG  Runnable water-level configuration.
%   mode 'ONOFF' (relay module, Lmin / Lmax, course task 3) | 'P' | 'PI' (PWM pump
%   through a MOSFET, setpoint in %). Disturbance: outlet opened by drainFactor at tDrain.
    c.mode = 'ONOFF';
    c.Lmin = 30; c.Lmax = 80;          % %
    c.setpoint = 50;                   % % (P / PI)
    c.Kp = 20; c.Ki = 0.5;             % PWM counts per %, per %*s
    c.h0 = 10;                         % initial level, %
    c.drainFactor = 1; c.tDrain = 400; % s
    c.outflow = 'gravity';             % 'gravity' (k sqrt(h), self-regulating) | 'constant' (pumped, integrator)
    c.Qout = 1.5;                      % L/min, constant outflow only (ASSUMED until measured, S3-3)
    c.pumpFailAt = Inf;                % s: no water reaches the tank from then on (dry run, S3-11)
    c.antiWindup = true;               % PI clamping; false = plain integrator (S3-8 demonstration)
    c.Tend = 900;
    c.seed = 1;
    c.experiment = '';
    c.P = levellab.level.params();
end
