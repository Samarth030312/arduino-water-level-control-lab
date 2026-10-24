function c = presetConfig(name)
%PRESETCONFIG  Configuration for a named water-level preset.
    p = levellab.level.presets();
    k = find(strcmp({p.name}, name), 1);
    assert(~isempty(k), 'levellab:level:preset', 'no preset named ''%s''', name);
    c = levellab.level.defaultConfig();
    c.experiment = p(k).experiment;
    s = p(k).set;
    for i = 1:2:numel(s), c.(s{i}) = s{i + 1}; end
end
