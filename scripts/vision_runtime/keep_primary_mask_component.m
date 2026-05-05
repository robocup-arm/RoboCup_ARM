function maskOut = keep_primary_mask_component(maskBin, bbox, minCompAreaPx)
    maskOut = logical(maskBin);
    if isempty(maskOut) || ~any(maskOut(:))
        return;
    end
    if nargin < 3 || isempty(minCompAreaPx)
        minCompAreaPx = 0;
    end
    if minCompAreaPx > 0
        maskOut = bwareaopen(maskOut, max(1, round(minCompAreaPx)));
        if ~any(maskOut(:))
            return;
        end
    end

    CC = bwconncomp(maskOut, 8);
    if CC.NumObjects <= 1
        return;
    end

    hasBBox = nargin >= 2 && ~isempty(bbox) && numel(bbox) >= 4;
    bboxMask = false(size(maskOut));
    if hasBBox
        H = size(maskOut,1);
        W = size(maskOut,2);
        x1 = max(1, min(W, floor(bbox(1))));
        x2 = max(1, min(W, ceil(bbox(3))));
        y1 = max(1, min(H, floor(bbox(2))));
        y2 = max(1, min(H, ceil(bbox(4))));
        if x2 >= x1 && y2 >= y1
            bboxMask(y1:y2, x1:x2) = true;
        else
            hasBBox = false;
        end
    end

    bestK = 1;
    bestScore = -inf;
    bestArea = -inf;
    for k = 1:CC.NumObjects
        idx = CC.PixelIdxList{k};
        area = numel(idx);
        ov = 0;
        if hasBBox
            ov = nnz(bboxMask(idx));
        end
        score = ov * 10 + area;
        if score > bestScore || (abs(score - bestScore) < 1e-9 && area > bestArea)
            bestScore = score;
            bestArea = area;
            bestK = k;
        end
    end

    keep = false(size(maskOut));
    keep(CC.PixelIdxList{bestK}) = true;
    maskOut = keep;
end
