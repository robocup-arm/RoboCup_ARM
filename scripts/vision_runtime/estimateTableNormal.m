function [nTable, zTable, found] = estimateTableNormal(pcBox, topPct, maxDist, angDeg, centerXY, rCan)
    nTable = [0 0 1]';
    zTable = NaN;
    found = false;
    P = double(pcBox.Location);
    P = P(all(isfinite(P),2),:);
    if size(P,1) < 100
        return;
    end
    if nargin >= 6 && ~isempty(centerXY) && isfinite(rCan) && rCan > 0
        dxy = P(:,1:2) - centerXY(:)';
        rxy = sqrt(sum(dxy.^2, 2));
        keep = rxy >= 1.2 * rCan;
        if nnz(keep) >= 100
            P = P(keep, :);
        end
    end
    Z = P(:,3);
    zCut = prctile(Z, topPct);
    idx = Z >= zCut;
    if nnz(idx) < 100
        return;
    end
    Ptop = P(idx,:);
    if exist('pcfitplane','file') == 2
        try
            pcTop = pointCloud(Ptop);
            [mdl, inlier] = pcfitplane(pcTop, maxDist, [0 0 1], angDeg);
            if ~isempty(inlier)
                n = mdl.Normal(:);
                if n(3) < 0
                    n = -n;
                end
                nTable = n / norm(n);
                zTable = mean(Ptop(inlier,3));
                found = true;
                return;
            end
        catch
        end
    end
    C = mean(Ptop, 1);
    [~,~,V] = svd(Ptop - C, 'econ');
    n = V(:,3);
    if n(3) < 0
        n = -n;
    end
    nTable = n / norm(n);
    zTable = mean(Ptop(:,3));
    found = true;
end
