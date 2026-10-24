function tests = test_protocol
%TEST_PROTOCOL  Serial protocol v1 encode / parse (docs/architecture/SERIAL_PROTOCOL.md).
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    run(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'setup_path.m'));
end

function testChecksumKnownNmeaValue(tc)
    % Same XOR rule as NMEA 0183; this sentence is published with *47.
    tc.verifyEqual(levellab.protocol.checksum( ...
        'GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,'), '47');
end

function testRoundTrip(tc)
    line = levellab.protocol.encode('CFG', 'P', 'PI', 0.3, 0.03, 0, 10, 150, 180);
    tc.verifyEqual(line(1:8), '$CFG,1,P');
    m = levellab.protocol.parse(line);
    tc.verifyEqual(m.kind, 'frame'); tc.verifyEqual(m.type, 'CFG');
    tc.verifyEqual(m.fields, {'P', 'PI', '0.3', '0.03', '0', '10', '150', '180'});
end

function testTelemetryDecode(tc)
    line = levellab.protocol.encode('TEL', 12, 1200, 'P', 'PI', 90, 89.93, 0.07, 1.2, 1299, 120, '0001');
    m = levellab.protocol.parse([line char([13 10])]);
    tc.verifyEqual(m.kind, 'frame');
    t = m.tel;
    tc.verifyEqual([t.seq t.t_ms t.setpoint t.meas t.pos_counts t.spd_base_rpm t.flags], ...
                   [12 1200 90 89.93 1299 120 1]);
    tc.verifyEqual(levellab.protocol.flagNames(t.flags), {'RUNNING'});
end

function testNanFieldAllowed(tc)
    m = levellab.protocol.parse(levellab.protocol.encode('TEL', 1, 0, 'S', 'OL', 50, NaN, NaN, 50, 0, 0, '0'));
    tc.verifyEqual(m.kind, 'frame'); tc.verifyTrue(isnan(m.tel.meas));
end

function testRejectsBadChecksum(tc)
    line = levellab.protocol.encode('SET', 90);
    line(end) = char(line(end) + 1 - 2 * (line(end) == 'F'));
    m = levellab.protocol.parse(line);
    tc.verifyEqual(m.kind, 'invalid'); tc.verifySubstring(m.err, 'checksum');
end

function testRejectsWrongVersion(tc)
    body = 'SET,2,90';
    m = levellab.protocol.parse(['$' body '*' levellab.protocol.checksum(body)]);
    tc.verifyEqual(m.kind, 'invalid'); tc.verifySubstring(m.err, 'version');
end

function testRejectsMalformedTelemetry(tc)
    body = 'TEL,1,1,2,S,PI,50,49,1';                          % too few fields
    m = levellab.protocol.parse(['$' body '*' levellab.protocol.checksum(body)]);
    tc.verifyEqual(m.kind, 'invalid');
    body = 'TEL,1,1,2,X,PI,50,49,1,1,0,0,1';                  % bad loop letter
    m = levellab.protocol.parse(['$' body '*' levellab.protocol.checksum(body)]);
    tc.verifyEqual(m.kind, 'invalid');
end

function testDebugAndEmptyLines(tc)
    tc.verifyEqual(levellab.protocol.parse('# boot ok, slave 11').kind, 'debug');
    tc.verifyEqual(levellab.protocol.parse('   ').kind, 'empty');
    tc.verifyEqual(levellab.protocol.parse('garbage').kind, 'invalid');
end

function testEncodeRejectsReservedCharacters(tc)
    tc.verifyError(@() levellab.protocol.encode('SET', 'a,b'), 'levellab:protocol:field');
    tc.verifyError(@() levellab.protocol.encode('SET', 'a*b'), 'levellab:protocol:field');
end

function testDocumentedExamplesMatch(tc)
    % docs/architecture/SERIAL_PROTOCOL.md section 6 quotes these exact frames.
    tc.verifyEqual(levellab.protocol.encode('CFG', 'P', 'P', 0.3, 0, 0, 10, 150, 180), '$CFG,1,P,P,0.3,0,0,10,150,180*7E');
    tc.verifyEqual(levellab.protocol.encode('SET', 90), '$SET,1,90*7A');
    tc.verifyEqual(levellab.protocol.encode('RUN'), '$RUN,1*54');
    tc.verifyEqual(levellab.protocol.encode('TEL', 0, 0, 'P', 'P', 90, 0, 90, 27, 0, 0, '1'), '$TEL,1,0,0,P,P,90,0,90,27,0,0,1*68');
end
