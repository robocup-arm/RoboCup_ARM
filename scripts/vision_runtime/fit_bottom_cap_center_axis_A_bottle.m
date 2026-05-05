function [center3D, axisVec, capMask] = fit_bottom_cap_center_axis_A_bottle(pcIn, opts)
    if nargin < 2
        opts = struct;
    end
    opts = withDefaults(opts, struct( ...
        "bottomPct", 40, ...
        "planeMaxDist", 0.004, ...
        "zBand", 0.004, ...
        "zExpand", 0.006, ...
        "zBin", 0.003, ...
        "minPts", 120 ...
        ));
    P = double(pcIn.Location);
    P = P(all(isfinite(P),2),:);
    if size(P,1) < 30
        error("Point cloud too small.");
    end

    zAll = P(:,3);
    zLowCut = prctile(zAll, opts.bottomPct);
    zBin = opts.zBin;
    if ~isfinite(zBin) || zBin <= 0
        zBin = 0.003;
    end
    edges = (min(zAll) - zBin):zBin:(zLowCut + zBin);
    [counts, edges] = histcounts(zAll, edges);
    if isempty(counts) || max(counts) == 0
        bestZ = prctile(zAll, 10);
    else
        [~, b] = max(counts);
        bestZ = (edges(b) + edges(b+1)) * 0.5;
    end

    capMask = abs(zAll - bestZ) <= opts.zExpand;
    capPts = P(capMask,:);
    if size(capPts,1) < opts.minPts
        capMask = zAll <= zLowCut;
        capPts = P(capMask,:);
    end

    Cplane = mean(capPts, 1);
    planeN = [];
    inIdx = [];
    if exist('pcfitplane','file') == 2 && size(capPts,1) >= 50
        try
            [m, inIdx] = pcfitplane(pointCloud(capPts), opts.planeMaxDist);
            if ~isempty(inIdx)
                planeN = m.Normal(:);
                Cplane = mean(capPts(inIdx,:), 1);
            end
        catch
        end
    end
    if isempty(planeN)
        [~,~,Vn] = svd(capPts - Cplane, 'econ');
        planeN = Vn(:,3);
    end
    planeN = planeN / norm(planeN);
    if planeN(3) < 0
        planeN = -planeN;
    end
    axisVec = planeN';

    if ~isempty(inIdx)
        idxFull = find(capMask);
        capMask(:) = false;
        capMask(idxFull(inIdx)) = true;
        capPts = P(capMask,:);
    end

    Pproj = capPts - ((capPts - Cplane) * planeN) * planeN';
    E = null(axisVec');
    if size(E,2) < 2
        if abs(dot(axisVec, [1 0 0])) < 0.9
            tmp = [1 0 0];
        else
            tmp = [0 1 0];
        end
        e1 = cross(axisVec, tmp); e1 = e1 / norm(e1);
        e2 = cross(axisVec, e1); e2 = e2 / norm(e2);
        e1 = e1(:); e2 = e2(:);
    else
        e1 = E(:,1); e2 = E(:,2);
    end
    Q = Pproj - Cplane;
    x = Q * e1;
    y = Q * e2;
    if numel(x) >= 3
        [cx, cy] = fitCircle2D(x, y);
        center3D = Cplane + cx * e1' + cy * e2';
    else
        center3D = Cplane;
    end
end
