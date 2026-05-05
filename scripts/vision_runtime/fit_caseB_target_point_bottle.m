function [target3D, midPt, axisVec, info] = fit_caseB_target_point_bottle(pcCan, pcRaw, opts)
    if nargin < 3
        opts = struct;
    end
    opts = withDefaults(opts, struct( ...
        "midBand", 0.004, ...
        "wallTol", 0.004, ...
        "tableMaxDist", 0.006, ...
        "tableAng", 10, ...
        "tableTopPct", 90, ...
        "tableMinPts", 200, ...
        "minCand", 50, ...
        "thickPct", 80, ...
        "thickTol", 0.003, ...
        "lineTol", 0.003, ...
        "targetMode", 2, ...
        "midUseRaw", false, ...
        "minMidPts", 120, ...
        "tableClear", 0.006, ...
        "refineAxis", true, ...
        "axisRefineCos", 0.95, ...
        "axisMode", "3d", ...
        "numSlices", 12, ...
        "minSlicePts", 60, ...
        "minCoverDeg", 120, ...
        "coverBins", 18, ...
        "coverExpand", 2.0, ...
        "wallExpand", 1.5, ...
        "debugB", false ...
        ));

    Pcan = double(pcCan.Location);
    Pcan = Pcan(all(isfinite(Pcan),2),:);
    if size(Pcan,1) < 50
        error("pcCan too small for case B.");
    end
    Praw = double(pcRaw.Location);
    Praw = Praw(all(isfinite(Praw),2),:);
    if size(Praw,1) < 50
        error("pcRaw too small for case B.");
    end

    Cxy = mean(Pcan(:,1:2), 1);
    rxy = sqrt(sum((Pcan(:,1:2) - Cxy).^2, 2));
    rCan = prctile(rxy, 90);
    [tableN, tableZ, found] = estimateTableNormal(pcRaw, opts.tableTopPct, opts.tableMaxDist, ...
        opts.tableAng, Cxy, rCan);
    if ~found
        tableN = [0 0 1]';
        tableZ = prctile(Praw(:,3), opts.tableTopPct);
    end
    if tableN(3) < 0
        tableN = -tableN;
    end
    tableD = -tableZ;
    tableIn = abs(Praw * tableN + tableD) <= opts.tableMaxDist;
    tableFrac = nnz(tableIn) / max(1, size(Praw,1));

    if abs(dot(tableN, [1 0 0]')) < 0.9
        tmp = [1 0 0]';
    else
        tmp = [0 1 0]';
    end
    eT1 = cross(tableN, tmp); eT1 = eT1 / norm(eT1);
    eT2 = cross(tableN, eT1); eT2 = eT2 / norm(eT2);

    tableClear = max(opts.tableClear, opts.tableMaxDist);
    dTabCan = Pcan * tableN + tableD;
    keepCan = abs(dTabCan) > tableClear;
    if nnz(keepCan) >= max(50, round(0.2 * size(Pcan,1)))
        PcanAxis = Pcan(keepCan, :);
    else
        PcanAxis = Pcan;
    end

    C0 = mean(PcanAxis, 1);
    Q0 = PcanAxis - C0;
    axisMode = "3d";
    if isfield(opts, 'axisMode')
        axisMode = string(opts.axisMode);
    end
    if axisMode == "wall"
        [axisVec, ~] = estimateAxisFromWall(PcanAxis);
        axisVec = axisVec(:);
        axisVec = axisVec - dot(axisVec, tableN) * tableN;
    elseif axisMode == "proj"
        u = Q0 * eT1;
        v = Q0 * eT2;
        [~,~,Vuv] = svd([u v], 'econ');
        dir2 = Vuv(:,1);
        axisVec = (dir2(1) * eT1 + dir2(2) * eT2)';
    else
        [~,~,V3] = svd(Q0, 'econ');
        axisVec = V3(:,1);
        axisVec = axisVec - dot(axisVec, tableN) * tableN;
    end
    if norm(axisVec) < 1e-9
        u = Q0 * eT1;
        v = Q0 * eT2;
        [~,~,Vuv] = svd([u v], 'econ');
        dir2 = Vuv(:,1);
        axisVec = (dir2(1) * eT1 + dir2(2) * eT2)';
    end
    axisVec = axisVec(:)';
    axisVec = axisVec / max(norm(axisVec), 1e-9);

    [centers, rSlice, tSlice] = sliceCenters(PcanAxis, C0, axisVec, opts);

    axisRefined = false;
    if opts.refineAxis && size(centers,1) >= 4
        Cc = mean(centers, 1);
        if axisMode == "proj" || axisMode == "wall"
            uc = (centers - Cc) * eT1;
            vc = (centers - Cc) * eT2;
            [~,~,Vuv] = svd([uc vc], 'econ');
            dir2 = Vuv(:,1);
            axisVec2 = (dir2(1) * eT1 + dir2(2) * eT2)';
        else
            [~,~,Vc] = svd(centers - Cc, 'econ');
            axisVec2 = Vc(:,1);
        end
        axisVec2 = axisVec2 - dot(axisVec2, tableN) * tableN;
        if norm(axisVec2) > 1e-9
            axisVec2 = axisVec2(:);
            axisVecCol = axisVec(:);
            if numel(axisVec2) == numel(axisVecCol)
                axisVec2 = axisVec2 / norm(axisVec2);
                if dot(axisVec2, axisVecCol) < 0
                    axisVec2 = -axisVec2;
                end
                if abs(dot(axisVec2, axisVecCol)) < opts.axisRefineCos
                    axisVec = axisVec2';
                    axisRefined = true;
                    [centers, rSlice, tSlice] = sliceCenters(PcanAxis, C0, axisVec, opts);
                end
            end
        end
    end

    nB = axisVec(:) / norm(axisVec(:));
    if abs(dot(nB, [1 0 0]')) < 0.9
        tmp = [1 0 0]';
    else
        tmp = [0 1 0]';
    end
    e1 = cross(nB, tmp); e1 = e1 / norm(e1);
    e2 = cross(nB, e1);  e2 = e2 / norm(e2);

    tAll = (PcanAxis - C0) * axisVec';
    tLoAll = prctile(tAll, 5);
    tHiAll = prctile(tAll, 95);

    if ~isempty(centers)
        Ccent = median(centers, 1);
        axisOrigin = Ccent;
    else
        axisOrigin = mean(Pcan, 1);
    end
    shift = dot(axisOrigin - C0, axisVec);

    if ~isempty(rSlice)
        rThr = prctile(rSlice, opts.thickPct);
        thickSlice = rSlice >= (rThr - opts.thickTol);
        if nnz(thickSlice) == 0
            thickSlice = rSlice >= rThr;
        end
        r0 = median(rSlice(thickSlice));
        tSlice2 = tSlice - shift;
        tLo = min(tSlice2(thickSlice));
        tHi = max(tSlice2(thickSlice));
    else
        Qp = (PcanAxis - axisOrigin) - ((PcanAxis - axisOrigin) * nB) * nB';
        rAll = sqrt(sum(Qp.^2, 2));
        r0 = prctile(rAll, 70);
        tAll2 = (PcanAxis - axisOrigin) * axisVec';
        tLo = prctile(tAll2, 5);
        tHi = prctile(tAll2, 95);
    end
    if ~isfinite(r0) || r0 <= 0
        r0 = prctile(abs(tAll), 70);
    end
    if ~isfinite(tLo) || ~isfinite(tHi) || tLo >= tHi
        tLo = tLoAll;
        tHi = tHiAll;
    end
    midT = 0.5 * (tLo + tHi);
    midPt = axisOrigin + midT * axisVec;

    useRaw = isfield(opts, 'midUseRaw') && opts.midUseRaw;
    PmidSrc = Pcan; midSource = "can";
    if useRaw
        PmidSrc = Praw; midSource = "raw";
    end
    Pm = selectMidBand(PmidSrc, midPt, axisVec, tableN, tableD, opts.midBand, opts.tableClear);
    if size(Pm,1) < opts.minMidPts && ~useRaw
        PmRaw = selectMidBand(Praw, midPt, axisVec, tableN, tableD, opts.midBand, opts.tableClear);
        if size(PmRaw,1) > size(Pm,1)
            Pm = PmRaw; midSource = "raw";
        end
    end
    if isempty(Pm)
        target3D = midPt;
        info = struct("reason", "empty_midband");
        return;
    end

    tp = (Pm - axisOrigin) * axisVec';
    perpP = (Pm - axisOrigin) - tp * axisVec;
    rp = sqrt(sum(perpP.^2, 2));
    wallMask = abs(rp - r0) <= opts.wallTol;
    Pcand = Pm(wallMask, :);
    if size(Pcand,1) < opts.minCand
        Pcand = Pm;
    end

    coverDeg = angleCoverageDeg(Pm, axisOrigin, axisVec, e1, e2, opts.coverBins);
    coverDeg2 = coverDeg;
    if coverDeg < opts.minCoverDeg
        Pm2 = selectMidBand(PmidSrc, midPt, axisVec, tableN, tableD, opts.midBand * opts.coverExpand, opts.tableClear);
        if ~isempty(Pm2)
            tp2 = (Pm2 - axisOrigin) * axisVec';
            perpP2 = (Pm2 - axisOrigin) - tp2 * axisVec;
            rp2 = sqrt(sum(perpP2.^2, 2));
            wallMask2 = abs(rp2 - r0) <= (opts.wallTol * opts.wallExpand);
            Pcand2 = Pm2(wallMask2, :);
            if size(Pcand2,1) < opts.minCand
                Pcand = Pm2;
            else
                Pcand = Pcand2;
            end
            coverDeg2 = angleCoverageDeg(Pcand, axisOrigin, axisVec, e1, e2, opts.coverBins);
        end
    end

    Cline = mean(Pcand, 1);
    [~,~,Vline] = svd(Pcand - Cline, 'econ');
    dirLine = Vline(:,1)'; dirLine = dirLine / norm(dirLine);
    tline = (Pcand - Cline) * dirLine';
    proj = Cline + tline * dirLine;
    dline = sqrt(sum((Pcand - proj).^2, 2));
    keepLine = dline <= opts.lineTol;
    if nnz(keepLine) >= max(10, round(0.1 * size(Pcand,1)))
        Pline = Pcand(keepLine, :);
    else
        Pline = Pcand;
    end
    tline = (Pline - Cline) * dirLine';
    tlo = prctile(tline, 5);
    thi = prctile(tline, 95);
    p1 = Cline + tlo * dirLine;
    p2 = Cline + thi * dirLine;

    switch opts.targetMode
        case 2
            Psel = Pline;
        case 3
            Psel = [p1; p2];
        otherwise
            Psel = Pcand;
    end
    if isempty(Psel)
        Psel = Pcand;
    end
    distTable = Psel * tableN + tableD;
    valid = isfinite(distTable);
    PcValid = Psel(valid, :);
    distTable = distTable(valid);
    if isempty(distTable)
        target3D = midPt;
    else
        distMid = midPt * tableN + tableD;
        if distMid < 0
            [~, idxSel] = min(distTable);
        else
            [~, idxSel] = max(distTable);
        end
        target3D = PcValid(idxSel, :);
    end

    tableFracCan = nnz(abs(Pcan * tableN + tableD) <= tableClear) / max(1, size(Pcan,1));
    info = struct( ...
        "axis", axisVec, ...
        "midPt", midPt, ...
        "radius", r0, ...
        "numMid", size(Pm,1), ...
        "numCand", size(Pcand,1), ...
        "tableN", tableN', ...
        "tableZ", tableZ, ...
        "tableFrac", tableFrac, ...
        "tableFracCan", tableFracCan, ...
        "coverDeg", coverDeg, ...
        "coverDeg2", coverDeg2, ...
        "axisMode", axisMode, ...
        "midPts", Pm, ...
        "candPts", Pcand, ...
        "linePts", [p1; p2], ...
        "lineDir", dirLine, ...
        "targetMode", opts.targetMode, ...
        "midSource", midSource, ...
        "axisRefined", axisRefined ...
        );
end
