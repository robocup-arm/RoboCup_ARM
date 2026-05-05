function [centers, rSlice, tSlice] = sliceCenters(Pcan, C0, axisVec, opts)
    axisCol = axisVec(:);
    axisRow = axisCol';
    nB = axisCol / norm(axisCol);
    if abs(dot(nB, [1 0 0]')) < 0.9
        tmp = [1 0 0]';
    else
        tmp = [0 1 0]';
    end
    e1 = cross(nB, tmp); e1 = e1 / norm(e1);
    e2 = cross(nB, e1);  e2 = e2 / norm(e2);
    tAll = (Pcan - C0) * axisCol;
    tLoAll = prctile(tAll, 5);
    tHiAll = prctile(tAll, 95);
    edges = linspace(tLoAll, tHiAll, max(4, opts.numSlices) + 1);
    centers = [];
    rSlice = [];
    tSlice = [];
    for i = 1:numel(edges)-1
        idx = tAll >= edges(i) & tAll < edges(i+1);
        if nnz(idx) < opts.minSlicePts
            continue;
        end
        Pi = Pcan(idx, :);
        Pshift = Pi - C0;
        Qp = Pshift - (Pshift * nB) * nB';
        x = Qp * e1;
        y = Qp * e2;
        if numel(x) >= 6
            [cx, cy] = fitCircle2D(x, y);
        else
            cx = mean(x); cy = mean(y);
        end
        r90 = prctile(sqrt((x - cx).^2 + (y - cy).^2), 90);
        tMean = mean(tAll(idx));
        center3D = C0 + cx * e1' + cy * e2' + tMean * axisRow;
        centers = [centers; center3D]; %#ok<AGROW>
        rSlice = [rSlice; r90]; %#ok<AGROW>
        tSlice = [tSlice; tMean]; %#ok<AGROW>
    end
end
