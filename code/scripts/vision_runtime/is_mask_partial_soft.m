function tf = is_mask_partial_soft(maskCoeff, proto, imgsz, bbox640, scale, pad, W, H, ...
    maskThresh, maskMinArea, maskUseBBox, bboxOrig, edgeMarginPx, gripperMask, ...
    maskMinAreaPx, maskMinCompAreaPx, edgeRatioThr, gripRatioThr)
    tf = false;
    if isempty(maskCoeff) || isempty(proto) || W <= 0 || H <= 0
        return;
    end

    if nargin < 9 || isempty(maskThresh)
        maskThresh = 0.50;
    end
    if nargin < 10 || isempty(maskMinArea)
        maskMinArea = 0;
    end
    if nargin < 11 || isempty(maskUseBBox)
        maskUseBBox = true;
    end
    if nargin < 13 || isempty(edgeMarginPx)
        edgeMarginPx = 2;
    end
    if nargin < 15 || isempty(maskMinAreaPx)
        maskMinAreaPx = 150;
    end
    if nargin < 16 || isempty(maskMinCompAreaPx)
        maskMinCompAreaPx = 40;
    end
    if nargin < 17 || isempty(edgeRatioThr)
        edgeRatioThr = 0.03;
    end
    if nargin < 18 || isempty(gripRatioThr)
        gripRatioThr = 0.05;
    end

    mask640 = buildMaskFromProto(maskCoeff, proto, imgsz);
    if maskUseBBox && ~isempty(bbox640)
        x1b = max(1, min(imgsz, round(bbox640(1))));
        x2b = max(1, min(imgsz, round(bbox640(3))));
        y1b = max(1, min(imgsz, round(bbox640(2))));
        y2b = max(1, min(imgsz, round(bbox640(4))));
        mask640(:,1:max(1,x1b-1)) = 0;
        mask640(:,min(imgsz,x2b+1):end) = 0;
        mask640(1:max(1,y1b-1),:) = 0;
        mask640(min(imgsz,y2b+1):end,:) = 0;
    end

    maskOrig = unletterboxMask(mask640, scale, pad, W, H);
    maskBin = maskOrig > maskThresh;
    if maskMinArea > 0
        maskBin = bwareaopen(maskBin, maskMinArea);
    end
    if ~isempty(bboxOrig)
        x1 = max(1, min(W, floor(bboxOrig(1))));
        x2 = max(1, min(W, ceil(bboxOrig(3))));
        y1 = max(1, min(H, floor(bboxOrig(2))));
        y2 = max(1, min(H, ceil(bboxOrig(4))));
        if x2 >= x1 && y2 >= y1
            maskRoi = false(H, W);
            maskRoi(y1:y2, x1:x2) = true;
            maskBin = maskBin & maskRoi;
        end
    end

    maskBin = keep_primary_mask_component(maskBin, bboxOrig, maskMinCompAreaPx);
    area = nnz(maskBin);
    if area < max(1, maskMinAreaPx)
        return;
    end

    m = max(1, round(edgeMarginPx));
    edgeBand = false(H, W);
    edgeBand(1:min(H,m), :) = true;
    edgeBand(max(1,H-m+1):H, :) = true;
    edgeBand(:, 1:min(W,m)) = true;
    edgeBand(:, max(1,W-m+1):W) = true;
    edgeFrac = nnz(maskBin & edgeBand) / area;

    gripFrac = 0;
    if ~isempty(gripperMask) && isequal(size(gripperMask,1), H) && isequal(size(gripperMask,2), W)
        gripFrac = nnz(maskBin & logical(gripperMask)) / area;
    end

    tf = (edgeFrac >= edgeRatioThr) || (gripFrac >= gripRatioThr);
end
