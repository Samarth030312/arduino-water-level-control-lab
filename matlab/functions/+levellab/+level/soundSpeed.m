function [v, levelErr] = soundSpeed(Tair, Tassumed, sensorToFloor, level)
%SOUNDSPEED  Speed of sound in air and the HC-SR04 level error from a wrong temperature.
%
%   v = levellab.level.soundSpeed(Tair)                       m/s, v = 331.3 + 0.606 T (WATER S3-1)
%   [v, err] = levellab.level.soundSpeed(Tair, Tassumed, sensorToFloor, level)
%
%   The code converts echo time t to distance with v(Tassumed): d_code = v(Tassumed) t / 2,
%   while the sound really travelled d = v(Tair) t / 2. Level = sensorToFloor - d, so
%   err = level_code - level_true = d (1 - v(Tassumed)/v(Tair)) (same unit as the inputs, > 0 when
%   the air is warmer than assumed: the level reads too high).
    v = 331.3 + 0.606 * Tair;
    if nargin < 2, levelErr = []; return; end
    d = sensorToFloor - level;
    levelErr = d .* (1 - (331.3 + 0.606 * Tassumed) ./ v);
end
