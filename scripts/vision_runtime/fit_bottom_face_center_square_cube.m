function [center3D, square3D, planeN, side, capMask] = fit_bottom_face_center_square_cube(pcIn, opts)
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
        "squareThetaStep", 1, ...
        "squarePad", 0.0, ...
        "squarePadFrac", 0.0, ...
        "squarePct", 0, ...
        "squareUseAll", true, ...
        "squareUseHull", true ...
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

    if isfield(opts, "squareUseAll") && opts.squareUseAll
        Pfit = P;
    else
        Pfit = capPts;
    end
    Pproj = Pfit - ((Pfit - Cplane) * planeN) * planeN';
    Q = Pproj - Cplane;
    u = Q * e1;
    v = Q * e2;

    if isfield(opts, "squareUseHull") && opts.squareUseHull && numel(u) >= 10
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

    [theta, xmid, ymid, side] = minAreaSquare2D(uR, vR, opts.squareThetaStep, opts.squarePct);
    R = [cos(theta) -sin(theta); sin(theta) cos(theta)];
    a1 = e1 * R(1,1) + e2 * R(2,1);
    a2 = e1 * R(1,2) + e2 * R(2,2);
    a1 = a1 / norm(a1);
    a2 = a2 / norm(a2);

    pad = max(0, opts.squarePad);
    if isfield(opts, "squarePadFrac") && opts.squarePadFrac > 0
        pad = max(pad, opts.squarePadFrac * side);
    end
    side = side + 2 * pad;

    center3D = Cplane + xmid * a1' + ymid * a2';
    s = 0.5 * side;
    square3D = [ ...
        center3D + (-s) * a1' + (-s) * a2'; ...
        center3D + ( s) * a1' + (-s) * a2'; ...
        center3D + ( s) * a1' + ( s) * a2'; ...
        center3D + (-s) * a1' + ( s) * a2' ...
        ];
end
