function R = run_level_simulink(c, modelDir)
%RUN_LEVEL_SIMULINK  Run water_level_plant.slx with an levellab.level config.
%   R.t, R.level (true %), R.meas (sensor %), R.q (pump flow, m^3/s), every 0.1 s.
    here = fileparts(mfilename('fullpath')); if nargin >= 2, here = modelDir; end
    mdl = 'water_level_plant';
    if ~isfile(fullfile(here, [mdl '.slx'])), build_level_simulink(here); end
    load_system(fullfile(here, [mdl '.slx'])); cl = onCleanup(@() close_system(mdl, 0));
    aw = 'clamping'; if isfield(c, 'antiWindup') && ~c.antiWindup, aw = 'none'; end
    set_param([mdl '/PI'], 'AntiWindupMode', aw);
    w = level_simulink_params(c);
    in = Simulink.SimulationInput(mdl); f = fieldnames(w);
    for k = 1:numel(f), in = in.setVariable(f{k}, w.(f{k}), 'Workspace', mdl); end
    tg = (0:0.1:c.Tend);
    in = in.setModelParameter('SaveOutput', 'on', 'OutputSaveName', 'yout', 'SaveFormat', 'Dataset', ...
        'ReturnWorkspaceOutputs', 'on', 'OutputOption', 'SpecifiedOutputTimes', 'OutputTimes', mat2str(tg));
    out = sim(in); y = out.yout; v = @(k) y.getElement(k).Values;
    R.t = v(1).Time; R.level = v(1).Data;
    R.meas = interp1(v(2).Time, v(2).Data, R.t, 'previous', 'extrap');
    R.q = interp1(v(3).Time, v(3).Data, R.t, 'linear', 'extrap');
end
