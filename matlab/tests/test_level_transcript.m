function tests = test_level_transcript
%TEST_LEVEL_TRANSCRIPT  MATLAB parses everything the real water-level firmware prints.
%   Fixture: firmware/level_controller run on the PC against an emulated
%   tank, pump and HC-SR04 (scripts/validation/build_firmware.sh). Protocol agreement, not a hardware test.
    tests = functiontests(localfunctions);
end

function setupOnce(tc)
    run(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'setup_path.m'));
    f = fullfile(levellab.repoRoot(), 'firmware', 'tests', 'fixtures', 'level_transcript.txt');
    tc.assumeTrue(isfile(f), 'run scripts/validation/build_firmware.sh first');
    L = splitlines(string(fileread(f))); L(L == "") = [];
    tc.TestData.lines = L;
end

function testEveryLineIsValid(tc)
    n = 0;
    for k = 1:numel(tc.TestData.lines)
        m = levellab.protocol.parse(tc.TestData.lines(k));
        tc.verifyNotEqual(m.kind, 'invalid', sprintf('line %d: %s (%s)', k, tc.TestData.lines(k), m.err));
        n = n + strcmp(m.kind, 'frame');
    end
    tc.verifyGreaterThan(n, 500);
end

function testEveryModeAppearsInTelemetry(tc)
    ft = FakeTransport(); link = levellab.io.SerialLink('LTEL'); link.attach(ft);
    ft.push(tc.TestData.lines{:});
    link.poll();
    T = link.table();
    tc.verifyEqual(link.invalidCount, 0);
    tc.verifyTrue(all(ismember(["ONOFF", "P"], string(T.mode))));
    tc.verifyTrue(all(T.u >= 0 & T.u <= 255));
end
