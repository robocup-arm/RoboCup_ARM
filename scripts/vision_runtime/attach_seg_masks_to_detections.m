function detsOut = attach_seg_masks_to_detections(detsBBox, detsSeg, iouThr)
    detsOut = detsBBox;
    if nargin < 3 || isempty(iouThr)
        iouThr = 0.25;
    end
    if isempty(detsOut)
        return;
    end
    for i = 1:numel(detsOut)
        detsOut(i).maskCoeff = [];
        detsOut(i).maskBBox640 = [];
        detsOut(i).maskScore = NaN;
    end
    if isempty(detsSeg)
        return;
    end
    used = false(1, numel(detsSeg));
    for i = 1:numel(detsOut)
        b = detsOut(i).bbox640;
        bestJ = 0;
        bestIou = -inf;
        bestScore = -inf;
        for j = 1:numel(detsSeg)
            if used(j)
                continue;
            end
            iou = box_iou_pair_xyxy(b, detsSeg(j).bbox640);
            if iou > bestIou || (abs(iou - bestIou) < 1e-9 && detsSeg(j).score > bestScore)
                bestIou = iou;
                bestScore = detsSeg(j).score;
                bestJ = j;
            end
        end
        if bestJ > 0 && bestIou >= iouThr
            detsOut(i).maskCoeff = detsSeg(bestJ).maskCoeff;
            detsOut(i).maskBBox640 = detsSeg(bestJ).bbox640;
            detsOut(i).maskScore = detsSeg(bestJ).score;
            if isfield(detsSeg(bestJ), "partial")
                detsOut(i).partial = detsOut(i).partial || logical(detsSeg(bestJ).partial);
            end
            used(bestJ) = true;
        end
    end
end
