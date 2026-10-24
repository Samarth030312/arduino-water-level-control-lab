function cal = calibrate(ruler, reading, staticReadings)
%CALIBRATE  Straight-line calibration of the level sensor against a ruler (WATER S3-2).
%
%   cal = levellab.level.calibrate(ruler_cm, reading_cm)
%   cal = levellab.level.calibrate(ruler_cm, reading_cm, static_readings_cm)
%
%   ruler    true levels from the ruler (>= 5 points), reading the sensor's mean at each.
%   Fits reading = a * ruler + b; reports cal.a, cal.b, cal.maxErr (largest |reading - fit|,
%   in ruler units after inverting the fit), cal.rmse, and cal.noise = std of the static
%   readings (level not changing). cal.correct(r) maps a raw reading to a calibrated level.
    ruler = ruler(:); reading = reading(:);
    assert(numel(ruler) >= 5, 'levellab:level:cal', 'calibrate at five or more levels');
    pp = polyfit(ruler, reading, 1);
    cal.a = pp(1); cal.b = pp(2);
    cal.correct = @(r) (r - cal.b) / cal.a;
    resid = cal.correct(reading) - ruler;
    cal.maxErr = max(abs(resid)); cal.rmse = sqrt(mean(resid.^2)); cal.residuals = resid;
    if nargin >= 3, cal.noise = std(staticReadings(:)); else, cal.noise = NaN; end
end
