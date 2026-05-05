function [center3D, rect3D, planeN, len, wid, capMask] = fit_bottom_face_center_rect_spam(pcIn, opts)
    if nargin < 2
        opts = struct;
    end
    opts = withDefaults(opts, struct( ...
        "bottomPct", 40, ...
        "planeMaxDist", 0.004, ...
        "planeRef", [0 0 1], ...
        "planeAng", 12, ...
        "zExpand", 0.006, ...
        "zBin", 0.003, ...
        "minPts", 150, ...
        "rectThetaStep", 1, ...
        "rectPad", 0.002, ...
        "rectPadFrac", 0.05, ...
        "rectPct", 1, ...
        "rectUseAll", true, ...
        "rectUseHull", true ...
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
    if size(capPts,1) < opts.minPts
        error("Too few points for bottom face.");
    end

    Cplane = mean(capPts, 1);
    planeN = [];
    inIdx = [];
    if exist('pcfitplane','file') == 2 && size(capPts,1) >= 50
        try
            if isfield(opts, "planeRef") && isfield(opts, "planeAng")
                [m, inIdx] = pcfitplane(pointCloud(capPts), opts.planeMaxDist, ...
                    opts.planeRef, opts.planeAng);
            else
                [m, inIdx] = pcfitplane(pointCloud(capPts), opts.planeMaxDist);
            end
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

    if ~isempty(inIdx)
        idxFull = find(capMask);
        capMask(:) = false;
        capMask(idxFull(inIdx)) = true;
        capPts = P(capMask,:);
    end

    if abs(dot(planeN, [1 0 0]')) < 0.9
        tmp = [1 0 0]';
    else
        tmp = [0 1 0]';
    end
    e1 = cross(planeN, tmp); e1 = e1 / norm(e1);
    e2 = cross(planeN, e1);  e2 = e2 / norm(e2);

    if isfield(opts, "rectUseAll") && opts.rectUseAll
        Prect = P;
    else
        Prect = capPts;
    end
    Pproj = Prect - ((Prect - Cplane) * planeN) * planeN';
    Q = Pproj - Cplane;
    u = Q * e1;
    v = Q * e2;

    if isfield(opts, "rectUseHull") && opts.rectUseHull && numel(u) >= 10
        try
            k = convhull(u, v);
            uR = u(k);
            vR = v(k);
        catch
            uR = u;
            vR = v;
        end
    else
        uR = u;
        vR = v;
    end

    [theta, xmin, xmax, ymin, ymax] = minAreaRect2D(uR, vR, opts.rectThetaStep, opts.rectPct);
    R = [cos(theta) -sin(theta); sin(theta) cos(theta)];
    a1 = e1 * R(1,1) + e2 * R(2,1);
    a2 = e1 * R(1,2) + e2 * R(2,2);
    a1 = a1 / norm(a1);
    a2 = a2 / norm(a2);

    pad = max(0, opts.rectPad);
    if isfield(opts, "rectPadFrac") && opts.rectPadFrac > 0
        pad = max(pad, opts.rectPadFrac * max(xmax - xmin, ymax - ymin));
    end
    xmin = xmin - pad; xmax = xmax + pad;
    ymin = ymin - pad; ymax = ymax + pad;
    len = xmax - xmin;
    wid = ymax - ymin;

    rect3D = [ ...
        Cplane + xmin * a1' + ymin * a2'; ...
        Cplane + xmax * a1' + ymin * a2'; ...
        Cplane + xmax * a1' + ymax * a2'; ...
        Cplane + xmin * a1' + ymax * a2' ...
        ];
    center3D = Cplane + 0.5 * (xmin + xmax) * a1' + 0.5 * (ymin + ymax) * a2';
end
