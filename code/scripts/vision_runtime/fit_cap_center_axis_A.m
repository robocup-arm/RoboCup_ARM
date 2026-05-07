function [center3D, axisVec, capMask] = fit_cap_center_axis_A(pcIn, opts)
% Reconstructed CAN Case-A top-cap center + axis fitting.
% Mirrors fit_bottom_cap_center_axis_A_bottle but uses the TOP cap.
if nargin < 2
    opts = struct;
end
opts = withDefaults(opts, struct( ...
    "topPct", 85, ...
    "planeMaxDist", 0.08, ...
    "planeAng", 15, ...
    "minTopPts", 100, ...
    "band", 0.006, ...
    "tol", 0.006 ...
    ));

P = double(pcIn.Location);
P = P(all(isfinite(P),2),:);
if size(P,1) < 30
    error("Point cloud too small.");
end

zAll = P(:,3);
zHighCut = prctile(zAll, opts.topPct);
capMask = zAll >= zHighCut - opts.band;
capPts = P(capMask,:);
if size(capPts,1) < opts.minTopPts
    capMask = zAll >= zHighCut;
    capPts = P(capMask,:);
end
if size(capPts,1) < 20
    capMask = zAll >= prctile(zAll, 75);
    capPts = P(capMask,:);
end

Cplane = mean(capPts, 1);
planeN = [];
inIdx = [];
if exist('pcfitplane','file') == 2 && size(capPts,1) >= 50
    try
        [m, inIdx] = pcfitplane(pointCloud(capPts), opts.planeMaxDist, [0 0 1], opts.planeAng);
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
planeN = planeN / max(norm(planeN), 1e-12);
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
    e1 = cross(axisVec, tmp); e1 = e1 / max(norm(e1), 1e-12);
    e2 = cross(axisVec, e1);  e2 = e2 / max(norm(e2), 1e-12);
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
