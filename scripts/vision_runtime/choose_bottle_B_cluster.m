function [pcUse, midPt, axisVec, infoB, sel] = choose_bottle_B_cluster(pcMain, pcSpec, pcRaw, optsB, minAcceptScore, debugEnable, debugIdx)
    if nargin < 5 || isempty(minAcceptScore)
        minAcceptScore = 0.35;
    end
    if nargin < 6
        debugEnable = false;
    end
    if nargin < 7
        debugIdx = 0;
    end

    candNames = {"main", "special"};
    candCloud = {pcMain, pcSpec};
    candRes = repmat(struct("valid", false, "score", -inf, "midPt", [], "axisVec", [], "info", [], "count", 0), 1, 2);

    for k = 1:2
        pcK = candCloud{k};
        if isempty(pcK) || pcK.Count < 50
            continue;
        end
        try
            [~, mK, aK, infoK] = fit_caseB_target_point_bottle(pcK, pcRaw, optsB);
            [sc, parts] = score_bottle_B_candidate(infoK, pcK.Count);
            candRes(k).valid = true;
            candRes(k).score = sc;
            candRes(k).midPt = mK;
            candRes(k).axisVec = aK;
            candRes(k).info = infoK;
            candRes(k).count = pcK.Count;
            if debugEnable
                fprintf("BottleB[%d] cand=%s count=%d score=%.3f (numCand=%.2f cover=%.2f line=%.2f table=%.2f)\n", ...
                    debugIdx, candNames{k}, pcK.Count, sc, parts.numCandTerm, parts.coverTerm, parts.lineTerm, parts.tablePenalty);
            end
        catch ME
            if debugEnable
                fprintf("BottleB[%d] cand=%s fit failed: %s\n", debugIdx, candNames{k}, ME.message);
            end
        end
    end

    % default fallback
    kBest = 1;
    if candRes(2).valid && candRes(2).score > candRes(1).score
        kBest = 2;
    end
    if ~candRes(kBest).valid && candRes(1).valid
        kBest = 1;
    elseif ~candRes(kBest).valid && candRes(2).valid
        kBest = 2;
    end
    if ~candRes(kBest).valid
        % hard fallback: fit on main cluster
        [~, midPt, axisVec, infoB] = fit_caseB_target_point_bottle(pcMain, pcRaw, optsB);
        pcUse = pcMain;
        [bestScore, ~] = score_bottle_B_candidate(infoB, pcMain.Count);
        sel = struct("source", "main_fallback", "bestScore", bestScore, "lowConf", true);
        return;
    end

    % low-confidence fallback to main if special is uncertain
    if kBest == 2 && candRes(kBest).score < minAcceptScore && candRes(1).valid
        kBest = 1;
        lowConf = true;
        src = "main_lowconf_fallback";
    else
        lowConf = candRes(kBest).score < minAcceptScore;
        src = candNames{kBest};
    end

    pcUse = candCloud{kBest};
    midPt = candRes(kBest).midPt;
    axisVec = candRes(kBest).axisVec;
    infoB = candRes(kBest).info;
    sel = struct("source", string(src), "bestScore", candRes(kBest).score, "lowConf", lowConf);
end
