function A = apparatus(code)
%APPARATUS  The rig of this repository: run-id code, data folder, telemetry type, firmware.
%
%   A = levellab.data.apparatus()           % or apparatus('WATER')
    all = struct('code', 'WATER', 'folder', 'water_level', 'tel', 'LTEL', 'sketch', 'level', ...
        'name', 'Water level (tank, pump, HC-SR04)');
    if nargin == 0, A = all; return; end
    A = all(strcmpi({all.code}, code));
    assert(~isempty(A), 'levellab:data:apparatus', 'unknown apparatus %s (this repository: WATER)', code);
end
