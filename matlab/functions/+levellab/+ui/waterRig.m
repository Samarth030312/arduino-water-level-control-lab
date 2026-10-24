function h = waterRig(ax)
%WATERRIG  3-D water-level rig: tank, sump and pump, HC-SR04, outlet valve, relay, Uno.
%
%   h = levellab.ui.waterRig(ax);   levellab.ui.waterRigPose(h, st)
%
%   The tank is drawn at the default dimensions of levellab.level.physics (15 x 15 x 25 cm,
%   ASSUMED until measured; the model uses the values in the physics panel). HC-SR04 board
%   45 x 20 mm with two 16 mm transducers; relay module 50 x 26 mm; Uno 68.6 x 53.4 mm.
%   The water column follows the level, the inflow and outflow streams thicken with the
%   flow, the sensor's ping is drawn to the surface, the valve handle turns with its opening,
%   and Lmin / Lmax (green / red) and the setpoint (white) are marked on the tank.
    K = levellab.ui.palette();
    hold(ax, 'on'); axis(ax, 'equal'); axis(ax, 'off'); ax.Color = 'none'; ax.Clipping = 'off';
    try, ax.Toolbar.Visible = 'off'; catch, end
    try, disableDefaultInteractivity(ax); catch, end
    view(ax, 36, 16);
    xlim(ax, [-0.22 0.20]); ylim(ax, [-0.22 0.16]); zlim(ax, [0 0.40]);
    zB = 0.006; T = [0.15 0.15 0.25]; cT = [0.02 0.02]; zT = 0.05;      % tank on a 5 cm stand
    box3([0 -0.03 zB / 2], [0.42 0.38 zB], [0.13 0.14 0.17], ax);
    box3([cT zB + zT / 2], [0.17 0.17 zT], [0.20 0.21 0.25], ax);      % stand
    % glass tank: outline only (fast), water column: the one transparent object
    g = [0.75 0.85 0.95];
    for e = edges(cT, zB + zT, T), plot3(ax, e{1}(:, 1), e{1}(:, 2), e{1}(:, 3), '-', 'Color', g, 'LineWidth', 1.4); end
    h.water = box3([cT zB + zT + 0.01], [T(1) - 0.004 T(2) - 0.004 0.02], [0.15 0.50 0.95], ax);
    set(h.water, 'FaceAlpha', 0.55, 'EdgeColor', [0.4 0.7 1.0]);
    h.tank = struct('c', cT, 'z0', zB + zT, 'L', T(1), 'W', T(2), 'H', T(3));
    % level marks on the front face (y = cT(2) - W/2)
    yF = cT(2) - T(2) / 2 - 0.001;
    h.mkMin = plot3(ax, cT(1) + [-1 1] * T(1) / 2, [yF yF], [0 0], '-', 'Color', K.green, 'LineWidth', 2);
    h.mkMax = plot3(ax, cT(1) + [-1 1] * T(1) / 2, [yF yF], [0 0], '-', 'Color', K.red, 'LineWidth', 2);
    h.mkSp = plot3(ax, cT(1) + [-1 1] * T(1) / 2, [yF yF], [0 0], '--', 'Color', K.text, 'LineWidth', 1.6);
    % HC-SR04 on a bracket, 5 cm above the rim, looking down
    zS = zB + zT + T(3) + 0.05;
    plot3(ax, [cT(1) + T(1) / 2 cT(1) + T(1) / 2], [cT(2) cT(2)], [zB + zT + T(3) zS], '-', 'Color', K.dim, 'LineWidth', 2);
    plot3(ax, [cT(1) cT(1) + T(1) / 2], [cT(2) cT(2)], [zS zS] + 0.004, '-', 'Color', K.dim, 'LineWidth', 2);
    box3([cT zS], [0.045 0.020 0.0016], [0.10 0.35 0.75], ax);
    cylZ([cT(1) - 0.013 cT(2) zS - 0.012], 0.008, 0.011, [0.78 0.80 0.83], ax);
    cylZ([cT(1) + 0.013 cT(2) zS - 0.012], 0.008, 0.011, [0.78 0.80 0.83], ax);
    h.ping = plot3(ax, [cT(1) cT(1)], [cT(2) cT(2)], [zS - 0.012, zB + zT], ':', 'Color', [0.6 0.9 1.0], 'LineWidth', 1.5);
    h.zS = zS;
    % sump with water, pump, delivery pipe into the top of the tank
    cS = [-0.15 -0.04]; S = [0.10 0.14 0.07];
    for e = edges(cS, zB, S), plot3(ax, e{1}(:, 1), e{1}(:, 2), e{1}(:, 3), '-', 'Color', g * 0.8, 'LineWidth', 1.1); end
    box3([cS zB + 0.025], [S(1) - 0.004 S(2) - 0.004 0.05], [0.15 0.45 0.85], ax);
    cylZ([cS(1) cS(2) zB], 0.016, 0.035, [0.15 0.15 0.17], ax);                  % submersible pump
    pipe = [cS(1) cS(2) zB + 0.035; cS(1) cS(2) zB + zT + T(3) + 0.03; cT(1) - 0.04 cT(2) zB + zT + T(3) + 0.03; ...
            cT(1) - 0.04 cT(2) zB + zT + T(3) - 0.01];
    plot3(ax, pipe(:, 1), pipe(:, 2), pipe(:, 3), '-', 'Color', [0.85 0.85 0.88], 'LineWidth', 4);
    h.inflow = plot3(ax, [1 1] * (cT(1) - 0.04), [cT(2) cT(2)], [zB + zT + T(3) - 0.01, zB + zT], '-', 'Color', [0.45 0.75 1.0], 'LineWidth', 0.5);
    % outlet at the bottom of the tank, valve, drain back to the sump
    zO = zB + zT + 0.012; xO = cT(1) - T(1) / 2;
    plot3(ax, [xO xO - 0.06], [cT(2) cT(2)], [zO zO], '-', 'Color', [0.85 0.85 0.88], 'LineWidth', 4);
    cylZ([xO - 0.03 cT(2) zO - 0.008], 0.009, 0.016, [0.70 0.12 0.12], ax);         % valve body
    h.valveHandle = plot3(ax, [0 0], [0 0], [0 0], '-', 'Color', [0.95 0.30 0.20], 'LineWidth', 3);
    h.valveC = [xO - 0.03 cT(2) zO + 0.012];
    h.outflow = plot3(ax, [xO - 0.06 xO - 0.075 cS(1) + 0.04], [cT(2) cT(2) cS(2)], [zO zO - 0.02 zB + 0.06], '-', 'Color', [0.45 0.75 1.0], 'LineWidth', 0.5);
    % relay module and Uno (front), cables
    pR = [-0.08 -0.16 zB + 0.010];
    box3(pR, [0.050 0.026 0.017], [0.10 0.30 0.70], ax);
    box3(pR + [0.004 0 0.013], [0.019 0.015 0.0155], [0.12 0.30 0.85], ax);
    h.relayLed = plot3(ax, pR(1) - 0.018, pR(2) - 0.010, pR(3) + 0.009, 'o', 'MarkerSize', 6, 'MarkerFaceColor', [0.25 0.06 0.06], 'MarkerEdgeColor', 'none');
    pU = [0.06 -0.16 zB + 0.008];
    box3(pU, [0.0686 0.0534 0.0016], [0.00 0.44 0.55], ax);
    box3(pU + [-0.030 0.012 0.0063], [0.016 0.012 0.011], [0.70 0.72 0.75], ax);
    cable(ax, [pU + [0.03 0.0245 0.004]; cT(1) + 0.14 cT(2) - 0.02 0.20; cT(1) + 0.02 cT(2) - 0.012 zS], [0.95 0.85 0.20], 1.2);
    cable(ax, [pU + [-0.03 0 0.004]; -0.02 -0.17 0.03; pR + [0.025 0 0]], [0.25 0.45 0.95], 1.2);
    cable(ax, [pR + [-0.025 0 0.005]; -0.14 -0.12 0.04; cS(1) cS(2) zB + 0.04], [0.85 0.15 0.15], 2.0);
    lab = @(p, s) text(ax, p(1), p(2), p(3), s, 'Color', K.dim, 'FontSize', 9, 'HorizontalAlignment', 'center');
    h.labels = [lab([cT zS + 0.025], 'HC-SR04'), lab([cS zB + 0.10], 'sump · pump'), lab(pR + [0 0 0.03], 'relay'), ...
                lab(pU + [0 0 0.02], 'Arduino Uno'), lab([xO - 0.03 cT(2) zO + 0.04], 'outlet valve')];
    h.levelTxt = text(ax, cT(1) + T(1) / 2 + 0.01, yF, zB + zT, '', 'Color', [0.6 0.85 1.0], 'FontSize', 10, 'FontWeight', 'bold');
    light(ax, 'Position', [0.6 -0.8 1.0]); light(ax, 'Position', [-0.5 0.5 0.6], 'Color', [0.35 0.35 0.40]);
    h.K = K;
    levellab.ui.waterRigPose(h, struct('level', 30, 'u', 0, 'sp', NaN, 'Lmin', 30, 'Lmax', 80, 'valve', 100, 'qin', 0, 'qout', 1));
end

function E = edges(c, z0, d)
    x = c(1) + [-1 1] * d(1) / 2; y = c(2) + [-1 1] * d(2) / 2; z = z0 + [0 d(3)];
    E = {};
    for i = 1:2, for j = 1:2
        E{end + 1} = [x(i) y(j) z(1); x(i) y(j) z(2)];                         %#ok<AGROW> verticals
        E{end + 1} = [x(1) y(i) z(j); x(2) y(i) z(j)];                         %#ok<AGROW>
        E{end + 1} = [x(i) y(1) z(j); x(i) y(2) z(j)];                         %#ok<AGROW>
    end, end
end

function p = box3(c, d, col, parent)
    [X, Y, Z] = ndgrid([-1 1] * d(1) / 2, [-1 1] * d(2) / 2, [-1 1] * d(3) / 2);
    V = [X(:) Y(:) Z(:)] + c;
    F = [1 2 4 3; 5 6 8 7; 1 2 6 5; 3 4 8 7; 1 3 7 5; 2 4 8 6];
    shade = [0.70 0.70 0.86 0.86 0.78 1.00]';
    p = patch('Vertices', V, 'Faces', F, 'FaceVertexCData', min(1, shade * col), 'FaceColor', 'flat', ...
              'EdgeColor', col * 0.5, 'LineWidth', 0.5, 'FaceLighting', 'none', 'Parent', parent);
end

function cylZ(base, rad, len, col, parent)
    [X, Y, Z] = cylinder(rad, 24); Z = Z * len;
    surf(X + base(1), Y + base(2), Z + base(3), 'FaceColor', col, 'EdgeColor', 'none', 'FaceLighting', 'gouraud', 'Parent', parent);
    th = linspace(0, 2 * pi, 25);
    patch(base(1) + rad * cos(th), base(2) + rad * sin(th), base(3) + len + 0 * th, col, 'EdgeColor', 'none', 'Parent', parent);
end

function cable(ax, P, col, w)
    t = linspace(0, 1, 24)';
    B = (1 - t).^2 .* P(1, :) + 2 * (1 - t) .* t .* P(2, :) + t.^2 .* P(3, :);
    plot3(ax, B(:, 1), B(:, 2), B(:, 3), '-', 'Color', col, 'LineWidth', w);
end
