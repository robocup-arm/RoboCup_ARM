function coverDeg = angleCoverageDeg(Ppts, c_perp, axisVec, e1, e2, nb)
    if isempty(Ppts)
        coverDeg = 0;
        return;
    end
    nA = axisVec(:) / norm(axisVec(:));
    Q = Ppts - c_perp;
    perp = Q - (Q * nA) * nA';
    x = perp * e1;
    y = perp * e2;
    ang = atan2(y, x);
    nb = max(8, nb);
    edges = linspace(-pi, pi, nb+1);
    counts = histcounts(ang, edges);
    coverDeg = 360 * (nnz(counts > 0) / nb);
end
