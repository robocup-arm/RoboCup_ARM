function [score, fracWall, spreadWall] = axis_ring_consistency(P, C, axisVec)
    n = normalize_dir3(axisVec, [0 0 1]');
    Pc = P - C;
    Q = Pc - (Pc * n) * n';
    r = sqrt(sum(Q.^2, 2));
    if isempty(r)
        score = -inf;
        fracWall = 0;
        spreadWall = 1;
        return;
    end
    r0 = prctile(r, 70);
    tol = max(0.003, 0.12 * r0);
    wallMask = abs(r - r0) <= tol;
    fracWall = nnz(wallMask) / size(P,1);
    if nnz(wallMask) < 10
        spreadWall = 1;
    else
        rw = r(wallMask);
        spreadWall = std(rw) / max(mean(rw), 1e-6);
    end
    score = fracWall - 0.40 * spreadWall;
end
