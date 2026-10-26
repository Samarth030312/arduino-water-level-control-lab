function mdl = build_level_simulink(outDir)
%BUILD_LEVEL_SIMULINK  Generate water_level_plant.slx (course Assignment 3).
%
%   Tank as an integrator with inflow and outflow (course task 6):
%       A dh/dt = q_pump - q_out,   0 <= h <= H
%       q_out = k_out d(t) sqrt(h)      gravity outlet (outGravity = 1, self-regulating), or
%       q_out = Qc d(t)                 constant / pumped outflow (outGravity = 0, pure integrator)
%   Pump: dead time + first-order spin-up. Sensor: 0.1 s sampling, quantised.
%   modeSel 1: ON-OFF with the Simulink Relay block (switch off at Lmax, on at
%   Lmin), as the guideline asks; 2: PI (Discrete PID block, Ki = 0 gives P); 3: open loop
%   (fixed pump command olPct, through the pump's dead zone),
%   0..255 with clamping, PWM dead zone. Guards (overflow / dry-run) are in the
%   firmware and the MATLAB model only.

    if nargin < 1, outDir = fileparts(mfilename('fullpath')); end
    mdl = 'water_level_plant';
    if bdIsLoaded(mdl), close_system(mdl, 0); end
    new_system(mdl); cl = onCleanup(@() close_system(mdl, 0));
    set_param(mdl, 'Solver', 'ode45', 'RelTol', '1e-6', 'MaxStep', '0.05', 'StopTime', 'Tend', ...
        'SaveOutput', 'on', 'SaveFormat', 'Dataset');
    % parameters first: a block's expression (R, J, ...) must never resolve to a variable of the same name in the base workspace
    setVars(mdl, level_simulink_params(levellab.level.defaultConfig()));
    B = @(lib, n, pos, varargin) add_block(lib, [mdl '/' n], 'Position', pos, varargin{:});
    % ------------------------------------------------ tank
    B('simulink/Math Operations/Sum', 'Net flow', [620 40 640 80], 'Inputs', '+-');
    B('simulink/Math Operations/Gain', '1 over A', [670 45 710 75], 'Gain', '1/A');
    B('simulink/Continuous/Integrator', 'h (m)', [740 45 770 75], 'InitialCondition', 'h0', ...
        'LimitOutput', 'on', 'UpperSaturationLimit', 'H', 'LowerSaturationLimit', '0');
    B('simulink/Discontinuities/Saturation', 'h >= 0', [820 120 850 150], 'UpperLimit', 'inf', 'LowerLimit', '0', 'Orientation', 'left');
    B('simulink/Math Operations/Math Function', 'sqrt', [780 120 810 150], 'Operator', 'sqrt', 'Orientation', 'left');
    B('simulink/Math Operations/Gain', 'orifice k', [730 120 770 150], 'Gain', 'kout', 'Orientation', 'left');
    B('simulink/Sources/Step', 'Drain opened', [740 180 770 210], 'Time', 'tDrain', 'Before', '1', 'After', 'drain', 'SampleTime', '0');
    B('simulink/Sources/Constant', 'constant outflow', [800 220 840 240], 'Value', 'Qc', 'Orientation', 'left');
    B('simulink/Sources/Constant', 'outGravity', [800 250 840 270], 'Value', 'outGravity', 'Orientation', 'left');
    B('simulink/Signal Routing/Switch', 'Outflow model', [700 120 730 260], 'Criteria', 'u2 > Threshold', 'Threshold', '0.5', 'Orientation', 'left');
    B('simulink/Math Operations/Product', 'outflow', [640 130 670 180], 'Orientation', 'left');
    B('simulink/Math Operations/Gain', 'to percent', [810 45 850 75], 'Gain', '100/H');
    B('simulink/Discrete/Zero-Order Hold', 'Ping 100 ms', [880 45 910 75], 'SampleTime', 'Ts');
    B('simulink/Discontinuities/Quantizer', 'Sensor resolution', [940 45 980 75], 'QuantizationInterval', 'resPct');
    % ------------------------------------------------ controllers
    % The Relay block starts in its off state, as the firmware starts with the pump off: it
    % sees -level, so it switches on at -level >= -Lmin (level < Lmin) and off at
    % -level <= -Lmax (level > Lmax). The 1e-9 offsets make the block match the firmware's
    % strict < and > exactly on the sensor's quantised levels.
    B('simulink/Math Operations/Gain', 'level to relay', [100 70 125 90], 'Gain', '-1');
    B('simulink/Discontinuities/Relay', 'ON-OFF relay', [140 60 180 100], 'OnSwitchValue', '-Lmin+1e-9', ...
        'OffSwitchValue', '-Lmax-1e-9', 'OnOutputValue', '1', 'OffOutputValue', '0');
    B('simulink/Math Operations/Gain', 'relay to flow', [220 65 270 95], 'Gain', 'Qmax');
    B('simulink/Sources/Constant', 'Setpoint', [40 160 80 180], 'Value', 'SP');
    B('simulink/Math Operations/Sum', 'Error', [120 150 140 190], 'Inputs', '+-');
    B('simulink/Discrete/Discrete PID Controller', 'PI', [170 150 240 190], 'Controller', 'PI', 'P', 'Kp', 'I', 'Ki', ...
        'SampleTime', 'Ts', 'IntegratorMethod', 'Backward Euler', 'LimitOutput', 'on', ...
        'UpperSaturationLimit', '255', 'LowerSaturationLimit', '0', 'AntiWindupMode', 'clamping');
    B('simulink/Math Operations/Rounding Function', 'round', [260 155 290 185], 'Operator', 'round');
    B('simulink/Math Operations/Gain', 'duty', [300 155 330 185], 'Gain', '1/255');
    B('simulink/Math Operations/Bias', 'minus dead zone', [340 155 370 185], 'Bias', '-dead');
    B('simulink/Discontinuities/Saturation', 'no reverse flow', [380 155 410 185], 'UpperLimit', 'inf', 'LowerLimit', '0');
    B('simulink/Math Operations/Gain', 'PWM to flow', [420 155 450 185], 'Gain', 'Qmax/(1-dead)');
    B('simulink/Sources/Constant', 'modeSel', [400 100 440 120], 'Value', 'modeSel');
    B('simulink/Signal Routing/Multiport Switch', 'Controller select', [460 60 490 240], 'Inputs', '3');
    B('simulink/Sources/Constant', 'Open-loop pump flow', [380 220 440 240], 'Value', 'Qol');
    B('simulink/Continuous/Transport Delay', 'Relay + pipe delay', [510 115 560 145], 'DelayTime', 'delay', 'BufferSize', '4096');
    B('simulink/Continuous/Transfer Fcn', 'Pump spin-up', [570 115 610 145], 'Denominator', '[tauP 1]');
    B('simulink/Sinks/Out1', 'level_true_pct', [880 110 910 125]);
    B('simulink/Sinks/Out1', 'level_measured_pct', [1010 50 1040 65], 'Port', '2');
    B('simulink/Sinks/Out1', 'pump_flow', [640 200 670 215], 'Port', '3');
    L = @(a, b) add_line(mdl, a, b, 'autorouting', 'smart');
    L('Net flow/1', '1 over A/1'); L('1 over A/1', 'h (m)/1'); L('h (m)/1', 'h >= 0/1'); L('h >= 0/1', 'sqrt/1'); L('sqrt/1', 'orifice k/1');
    L('orifice k/1', 'Outflow model/1'); L('outGravity/1', 'Outflow model/2'); L('constant outflow/1', 'Outflow model/3');
    L('Outflow model/1', 'outflow/1'); L('Drain opened/1', 'outflow/2'); L('outflow/1', 'Net flow/2');
    L('h (m)/1', 'to percent/1'); L('to percent/1', 'Ping 100 ms/1'); L('Ping 100 ms/1', 'Sensor resolution/1');
    L('to percent/1', 'level_true_pct/1'); L('Sensor resolution/1', 'level_measured_pct/1');
    L('Sensor resolution/1', 'level to relay/1'); L('level to relay/1', 'ON-OFF relay/1'); L('ON-OFF relay/1', 'relay to flow/1');
    L('Setpoint/1', 'Error/1'); L('Sensor resolution/1', 'Error/2'); L('Error/1', 'PI/1');
    L('PI/1', 'round/1'); L('round/1', 'duty/1'); L('duty/1', 'minus dead zone/1');
    L('minus dead zone/1', 'no reverse flow/1'); L('no reverse flow/1', 'PWM to flow/1');
    L('modeSel/1', 'Controller select/1'); L('relay to flow/1', 'Controller select/2'); L('PWM to flow/1', 'Controller select/3');
    L('Open-loop pump flow/1', 'Controller select/4');
    L('Controller select/1', 'Relay + pipe delay/1'); L('Relay + pipe delay/1', 'Pump spin-up/1');
    L('Pump spin-up/1', 'Net flow/1'); L('Pump spin-up/1', 'pump_flow/1');
    n = Simulink.Annotation([mdl '/note']);
    n.Text = ['Water level (Assignment 3). modeSel 1: ON-OFF with the Relay block (pump off at Lmax, on at Lmin); ' ...
              '2: PI / P (Ki = 0). Tank and pump parameters ASSUMED. Set them with run_level_simulink(cfg).'];
    n.Position = [40 260 900 290];
    if ~exist(outDir, 'dir'), mkdir(outDir); end
    save_system(mdl, fullfile(outDir, [mdl '.slx']));
end

function setVars(mdl, w)
    mws = get_param(mdl, 'ModelWorkspace'); f = fieldnames(w);
    for i = 1:numel(f), assignin(mws, f{i}, w.(f{i})); end
end
