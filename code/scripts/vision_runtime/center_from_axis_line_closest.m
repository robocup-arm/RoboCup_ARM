function center3D = center_from_axis_line_closest(midPt, axisVec, linePts)
    center3D = midPt;
    if isempty(midPt) || isempty(axisVec) || isempty(linePts) || size(linePts,1) < 2
        return;
    end
    pAxis = reshape(double(midPt), 1, 3);
    dAxis = reshape(double(axisVec), 1, 3);
    p1 = reshape(double(linePts(1,:)), 1, 3);
    p2 = reshape(double(linePts(2,:)), 1, 3);
    if any(~isfinite([pAxis dAxis p1 p2]))
        return;
    end
    nAxis = norm(dAxis);
    dSeg = p2 - p1;
    nSeg = norm(dSeg);
    if nAxis < 1e-9 || nSeg < 1e-9
        return;
    end
    dAxis = dAxis / nAxis;

    w0 = pAxis - p1;
    a = dot(dAxis, dAxis);   % ~1
    b = dot(dAxis, dSeg);
    c = dot(dSeg, dSeg);
    d = dot(dAxis, w0);
    e = dot(dSeg, w0);
    den = a * c - b * b;

    if abs(den) > 1e-12
        t = (a * e - b * d) / den;
    else
        t = e / max(c, 1e-12);
    end

    % linePts is a finite segment from fitted candidates; keep t on segment.
    t = min(1, max(0, t));
    qSeg = p1 + t * dSeg;
    s = dot(dAxis, (qSeg - pAxis));
    qAxis = pAxis + s * dAxis;

    if all(isfinite(qAxis))
        center3D = qAxis;
    end
end
