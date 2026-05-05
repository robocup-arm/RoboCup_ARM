function pcObj = segment_bottle_B(pcBox, debugEnable, debugIdx)
    if nargin < 2
        debugEnable = false;
    end
    if nargin < 3
        debugIdx = 0;
    end
    if pcBox.Count < 50
        pcObj = pcBox;
        return;
    end

    % Start from full cloud; remove high-Z plane(s) only
    pcSeg = pcBox;
    if exist('pcfitplane','file') == 2
        planeMaxDist = 0.005;
        planeRef = [0 0 1];
        planeAng = 10;
        planeMinFrac = 0.12;
        minPlanePts = 200;
        spreadThresh = 0.60;
        maxPlaneRemove = 3;
        for iter = 1:maxPlaneRemove
            if pcSeg.Count < 200
                break;
            end
            zSeg = pcSeg.Location(:,3);
            zCut = prctile(zSeg, 70);
            idxHigh = find(zSeg >= zCut);
            if numel(idxHigh) < minPlanePts
                break;
            end
            pcHigh = select(pcSeg, idxHigh);
            try
                [m1, in1] = pcfitplane(pcHigh, planeMaxDist, planeRef, planeAng);
            catch
                break;
            end
            if isempty(in1)
                break;
            end
            candIdx = idxHigh(in1);
            candPts = pcSeg.Location(candIdx, :);
            candFrac = numel(candIdx) / pcSeg.Count;
            candZ = mean(candPts(:,3));

            Cplane = mean(candPts, 1);
            n = m1.Normal; n = n / norm(n);
            if abs(dot(n, [1 0 0])) < 0.9
                tmp = [1 0 0];
            else
                tmp = [0 1 0];
            end
            e1 = cross(n, tmp); e1 = e1 / norm(e1);
            e2 = cross(n, e1); e2 = e2 / norm(e2);
            Q = candPts - Cplane;
            x = Q * e1';
            y = Q * e2';
            r90 = prctile(sqrt(x.^2 + y.^2), 90);
            Pxy = pcSeg.Location(:,1:2);
            Cxy = mean(Pxy,1);
            rScene = prctile(sqrt(sum((Pxy - Cxy).^2, 2)), 90);
            spreadRatio = r90 / max(rScene, 1e-6);

            zHiSeg = prctile(zSeg, 70);
            zRangeSeg = max(zSeg) - min(zSeg);
            isHigh = candZ >= max(zHiSeg, mean(zSeg) + 0.20 * zRangeSeg);
            enoughSize = (candFrac >= planeMinFrac) || (numel(candIdx) >= minPlanePts);
            isWide = spreadRatio >= spreadThresh;

            if debugEnable
                fprintf("BottleB[%d] HighZ iter%d: frac=%.2f z=%.3f spread=%.2f isHigh=%d\n", ...
                    debugIdx, iter, candFrac, candZ, spreadRatio, isHigh);
            end
            if isHigh && enoughSize && isWide
                keepIdx = setdiff(1:pcSeg.Count, candIdx);
                pcSeg = select(pcSeg, keepIdx);
            else
                break;
            end
        end
    end

    % Cluster selection: prefer thicker (larger Z-span) clusters
    minDist = 0.01;
    try
        [labels, numClusters] = pcsegdist(pcSeg, minDist);
    catch
        pcObj = pcSeg;
        return;
    end
    if numClusters < 1
        pcObj = pcSeg;
        return;
    end

    minZSpan = 0.010;  % 1 cm
    wR = 0.50;         % radius weight
    wN = 0.00005;      % small count weight
    bestScore = -inf;
    bestId = -1;
    for k = 1:numClusters
        idx = find(labels == k);
        n = numel(idx);
        if n < 50
            continue;
        end
        Pk = pcSeg.Location(idx,:);
        zSpan = prctile(Pk(:,3),95) - prctile(Pk(:,3),5);
        if zSpan < minZSpan
            if debugEnable
                fprintf("BottleB[%d] cluster %d: n=%d zSpan=%.4f -> skip (plane)\n", debugIdx, k, n, zSpan);
            end
            continue;
        end
        Cxy = mean(Pk(:,1:2),1);
        rxy = sqrt(sum((Pk(:,1:2) - Cxy).^2, 2));
        r90 = prctile(rxy, 90);
        score = zSpan + wR * r90 + wN * log(n + 1);
        if debugEnable
            fprintf("BottleB[%d] cluster %d: n=%d zSpan=%.4f r90=%.4f score=%.4f\n", ...
                debugIdx, k, n, zSpan, r90, score);
        end
        if score > bestScore
            bestScore = score;
            bestId = k;
        end
    end
    if bestId < 0
        counts = accumarray(labels(labels>0), 1);
        [~, bestId] = max(counts);
    end
    pcObj = select(pcSeg, find(labels == bestId));
end
