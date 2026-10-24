function r = repoRoot()
%REPOROOT  Absolute path of the arduino-water-level-control-lab repository.
    r = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
end
