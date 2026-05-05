function setup_seg_axes3d(Pall)
    if nargin < 1 || isempty(Pall)
        view(35, 25);
        axis vis3d;
        return;
    end
    P = double(Pall);
    P = P(all(isfinite(P),2),:);
    if isempty(P)
        view(35, 25);
        axis vis3d;
        return;
    end
    mn = min(P, [], 1);
    mx = max(P, [], 1);
    span = mx - mn;
    maxSpan = max(span);
    if ~isfinite(maxSpan) || maxSpan < 1e-4
        maxSpan = 1e-3;
    end
    c = 0.5 * (mn + mx);
    half = 0.55 * maxSpan;
    xlim([c(1)-half, c(1)+half]);
    ylim([c(2)-half, c(2)+half]);
    zlim([c(3)-half, c(3)+half]);
    daspect([1 1 1]);
    axis vis3d;
    view(35, 25);
end
