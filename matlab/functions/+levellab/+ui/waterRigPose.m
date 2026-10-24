function waterRigPose(h, st)
%WATERRIGPOSE  Water column, streams, ping, valve and marks of an levellab.ui.waterRig scene.
%   st: level (% of tank height), u (pump command %), sp (% or NaN), Lmin, Lmax (%),
%       valve (opening %), qin, qout (L/min)
    if ~isvalid(h.water), return; end
    T = h.tank; lv = min(max(st.level, 0), 105); if ~isfinite(lv), lv = 0; end
    hw = max(T.H * lv / 100, 0.0005);
    x = T.c(1) + [-1 1] * (T.L - 0.004) / 2; y = T.c(2) + [-1 1] * (T.W - 0.004) / 2; z = T.z0 + [0 hw];
    [X, Y, Z] = ndgrid(x, y, z);
    h.water.Vertices = [X(:) Y(:) Z(:)];
    zMark = @(p) T.z0 + T.H * p / 100;
    set(h.mkMin, 'ZData', zMark(st.Lmin) * [1 1]); set(h.mkMax, 'ZData', zMark(st.Lmax) * [1 1]);
    if isfinite(st.sp), set(h.mkSp, 'ZData', zMark(st.sp) * [1 1], 'Visible', 'on'); else, set(h.mkSp, 'Visible', 'off'); end
    set(h.ping, 'ZData', [h.zS - 0.012, T.z0 + hw]);
    set(h.inflow, 'LineWidth', 0.5 + 2.5 * min(max(st.qin, 0) / 4, 1), 'Visible', st.qin > 0.05);
    set(h.outflow, 'LineWidth', 0.5 + 2.5 * min(max(st.qout, 0) / 4, 1), 'Visible', st.qout > 0.05);
    a = (100 - min(max(st.valve, 0), 100)) / 100 * 90;                          % handle: along the pipe = open
    c = h.valveC; set(h.valveHandle, 'XData', c(1) + 0.02 * [-1 1] * cosd(a), 'YData', c(2) + 0.02 * [-1 1] * sind(a), 'ZData', [c(3) c(3)]);
    set(h.relayLed, 'MarkerFaceColor', [0.25 0.06 0.06] + (st.u > 0) * [0.75 0.10 0.05]);
    h.levelTxt.Position(3) = T.z0 + hw; h.levelTxt.String = sprintf(' %.0f %%', lv);
end
