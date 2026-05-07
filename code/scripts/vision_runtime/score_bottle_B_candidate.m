function [score, parts] = score_bottle_B_candidate(infoB, cloudCount)
    if nargin < 2
        cloudCount = 0;
    end
    numCand = get_info_field(infoB, "numCand", 0);
    numMid = get_info_field(infoB, "numMid", 0);
    coverDeg = max(get_info_field(infoB, "coverDeg2", 0), get_info_field(infoB, "coverDeg", 0));
    radius = get_info_field(infoB, "radius", 0);
    tableFracCan = get_info_field(infoB, "tableFracCan", 0);
    linePts = get_info_field(infoB, "linePts", []);

    lineLen = 0;
    if ~isempty(linePts) && size(linePts,1) >= 2
        lineLen = norm(linePts(2,:) - linePts(1,:));
    end
    lineNorm = lineLen / max(2 * max(radius, 1e-4), 1e-4);

    numCandTerm = min(numCand / 180, 1);
    coverTerm = min(coverDeg / 200, 1);
    lineTerm = min(lineNorm / 1.5, 1);
    midTerm = min(numMid / 220, 1);
    countTerm = min(cloudCount / 1800, 1);
    tablePenalty = min(max(tableFracCan, 0), 1);

    score = 0.30 * numCandTerm + 0.25 * coverTerm + 0.18 * lineTerm + 0.12 * midTerm + 0.15 * countTerm - 0.30 * tablePenalty;
    if numCand < 35
        score = score - 0.20;
    end
    if coverDeg < 60
        score = score - 0.20;
    end

    parts = struct( ...
        "numCandTerm", numCandTerm, ...
        "coverTerm", coverTerm, ...
        "lineTerm", lineTerm, ...
        "midTerm", midTerm, ...
        "countTerm", countTerm, ...
        "tablePenalty", tablePenalty ...
        );
end
