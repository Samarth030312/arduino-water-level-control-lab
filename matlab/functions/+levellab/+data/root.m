function r = root()
%ROOT  Where run data lives: the repository, or LEVELLAB_DATA_ROOT (tests write elsewhere).
    r = levellab.repoRoot();
    if ~isempty(getenv('LEVELLAB_DATA_ROOT')), r = getenv('LEVELLAB_DATA_ROOT'); end
end
