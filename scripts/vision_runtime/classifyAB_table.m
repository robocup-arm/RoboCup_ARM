function [label, info] = classifyAB_table(pcCan, pcBox, cosThr, topPct, maxDist, angDeg)
    info = struct("cosAxis", 0, "tableFound", false, "cosTable", 0, "zTable", NaN);
    P = double(pcCan.Location);
    P = P(all(isfinite(P),2),:);
    if size(P,1) < 50
        label = 1;
        return;
    end
    [axisVec, axisInfo] = estimateAxisFromWall(P);
    [nTable, zTable, found] = estimateTableNormal(pcBox, topPct, maxDist, angDeg, axisInfo.centerXY, axisInfo.rXY);
    if ~found
        nTable = [0 0 1]';
    end
    if dot(nTable, [0 0 1]') < 0
        nTable = -nTable;
    end
    cosAxis = abs(dot(axisVec, nTable));
    info.cosAxis = cosAxis;
    info.tableFound = found;
    info.cosTable = abs(dot(nTable, [0 0 1]'));
    info.zTable = zTable;
    info.axisSource = axisInfo.source;
    info.axisScore = axisInfo.scoreChosen;
    info.axisScorePCA = axisInfo.scorePCA;
    info.axisScoreWall = axisInfo.scoreWall;
    if cosAxis >= cosThr
        label = 1;
    else
        label = 2;
    end
end
