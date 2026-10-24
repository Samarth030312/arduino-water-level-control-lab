function [id, A] = resolve(anyId)
%RESOLVE  The current run id for a run id or a legacy id (e.g. MOTOR-02-HW-20261011-133631).
%
%   [id, A] = levellab.data.resolve('MOTOR-02-HW-20261011-133631')   -> 'MOTOR-R0006_...', apparatus
    id = char(anyId);
    R = levellab.data.register();
    if ~isempty(R)
        j = find(strcmp(R.run_id, id) | strcmp(R.legacy_id, id), 1);
        if ~isempty(j), id = R.run_id{j}; A = levellab.data.apparatus(R.apparatus{j}); return; end
    end
    code = regexp(id, '^(MOTOR|TEMP|WATER)', 'match', 'once');
    if isempty(code), code = 'MOTOR'; end
    A = levellab.data.apparatus(code);
end
