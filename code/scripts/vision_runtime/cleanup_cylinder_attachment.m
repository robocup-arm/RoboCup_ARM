function pcOut = cleanup_cylinder_attachment(pcIn, debugEnable, tag)
    if nargin < 2
        debugEnable = false;
    end
    if nargin < 3
        tag = "";
    end
    pcOut = pcIn;
    if isempty(pcIn) || pcIn.Count < 120
        return;
    end
    P = double(pcIn.Location);
    P = P(all(isfinite(P),2),:);
    n0 = size(P,1);
    if n0 < 120
        pcOut = pointCloud(P);
        return;
    end
    P0 = P;
    zSpan0 = max(P0(:,3)) - min(P0(:,3));
    C0 = mean(P0(:,1:2), 1);
    r0 = sqrt(sum((P0(:,1:2) - C0).^2, 2));
    rXY900 = prctile(r0, 90);

    % 1) Trim points that are too far from a robust cylinder axis.
    keep = true(n0,1);
    for iter = 1:2
        Pk = P(keep,:);
        if size(Pk,1) < 80
            break;
        end
        Ck = mean(Pk,1);
        [~,~,V] = svd(Pk - Ck, 'econ');
        axis = V(:,1);
        axis = axis / max(norm(axis), 1e-12);

        Q = P - Ck;
        d = sqrt(sum((Q - (Q * axis) * axis').^2, 2));
        dNow = d(keep);
        dMed = median(dNow);
        dMad = median(abs(dNow - dMed));
        dP85 = prctile(dNow, 85);
        thr = max(dP85 * 1.15, dMed + 2.5 * max(dMad, 0.002));
        keepNew = d <= thr;
        if nnz(keepNew) < 80
            break;
        end
        keep = keepNew;
    end
    if nnz(keep) >= 80 && nnz(keep) <= round(0.98 * n0)
        P = P(keep,:);
    end

    % 2) Remove a dominant non-table plane (common for box side walls).
    if size(P,1) >= 120 && exist('pcfitplane','file') == 2
        try
            [mdl, inl] = pcfitplane(pointCloud(P), 0.004);
            fracPlane = numel(inl) / size(P,1);
            nz = abs(mdl.Normal(3));
            if fracPlane >= 0.32 && nz <= 0.75
                keep2 = true(size(P,1),1);
                keep2(inl) = false;
                if nnz(keep2) >= 80
                    P = P(keep2,:);
                end
            end
        catch
        end
    end

    % 3) Final tight clustering to cut thin bridges to the background.
    if size(P,1) >= 80
        try
            [labels, numClusters] = pcsegdist(pointCloud(P), 0.008);
            if numClusters >= 1
                counts = accumarray(labels(labels>0), 1);
                [~, bestId] = max(counts);
                idx = find(labels == bestId);
                if numel(idx) >= 60
                    P = P(idx,:);
                end
            end
        catch
        end
    end

    % 4) Safety gate: reject cleanup if geometry is damaged too much.
    n1 = size(P,1);
    if n1 < 60
        P = P0;
        n1 = n0;
    end
    zSpan1 = max(P(:,3)) - min(P(:,3));
    C1 = mean(P(:,1:2), 1);
    r1 = sqrt(sum((P(:,1:2) - C1).^2, 2));
    rXY901 = prctile(r1, 90);
    keepFrac = n1 / max(n0, 1);
    zFrac = zSpan1 / max(zSpan0, 1e-6);
    rFrac = rXY901 / max(rXY900, 1e-6);
    isOverTrim = (keepFrac < 0.55) || (zFrac < 0.65) || (rFrac < 0.55);
    if isOverTrim
        P = P0;
        n1 = n0;
    end

    pcOut = pointCloud(P);
    if debugEnable
        fprintf("%s cleanup: %d -> %d pts (keep=%.2f zFrac=%.2f rFrac=%.2f %s)\n", ...
            char(string(tag)), n0, n1, keepFrac, zFrac, rFrac, ternary(isOverTrim, "revert", "accept"));
    end
end
