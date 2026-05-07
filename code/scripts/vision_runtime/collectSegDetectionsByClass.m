function dets = collectSegDetectionsByClass(targetClass, xywh, scoreAll, cidAll, maskCoeff, classNames, confTh, nmsIou, scale, pad, W, H, markPartial, edgeMarginPx, gripperMask, ...
    proto, imgsz, maskThresh, maskMinArea, maskUseBBox, useMaskEvidence, maskEdgeMarginPx, maskMinAreaPx, maskMinCompAreaPx, edgeRatioThr, gripRatioThr)
    dets = struct("bbox", {}, "bbox640", {}, "score", {}, "maskCoeff", {}, "partial", {});
    if nargin < 16
        proto = [];
    end
    if nargin < 17 || isempty(imgsz)
        imgsz = 640;
    end
    if nargin < 18 || isempty(maskThresh)
        maskThresh = 0.50;
    end
    if nargin < 19 || isempty(maskMinArea)
        maskMinArea = 0;
    end
    if nargin < 20 || isempty(maskUseBBox)
        maskUseBBox = true;
    end
    if nargin < 21 || isempty(useMaskEvidence)
        useMaskEvidence = false;
    end
    if nargin < 22 || isempty(maskEdgeMarginPx)
        maskEdgeMarginPx = 2;
    end
    if nargin < 23 || isempty(maskMinAreaPx)
        maskMinAreaPx = 150;
    end
    if nargin < 24 || isempty(maskMinCompAreaPx)
        maskMinCompAreaPx = 40;
    end
    if nargin < 25 || isempty(edgeRatioThr)
        edgeRatioThr = 0.03;
    end
    if nargin < 26 || isempty(gripRatioThr)
        gripRatioThr = 0.05;
    end
    if isempty(xywh)
        return;
    end
    if iscell(targetClass) || isstring(targetClass)
        tnames = cellstr(string(targetClass));
    else
        tnames = {char(string(targetClass))};
    end
    cnameDet = classNames(cidAll);
    isTarget = false(size(cidAll));
    for it = 1:numel(tnames)
        isTarget = isTarget | strcmpi(cnameDet, tnames{it});
    end
    keep = (scoreAll > confTh) & isTarget;
    if ~any(keep)
        return;
    end
    xywhK  = xywh(:,keep);
    scoreK = scoreAll(keep);
    maskK  = maskCoeff(:,keep);

    cx = xywhK(1,:); cy = xywhK(2,:);
    w  = xywhK(3,:); h  = xywhK(4,:);
    x1 = cx - w/2; y1 = cy - h/2;
    x2 = cx + w/2; y2 = cy + h/2;
    b640_xyxy = [x1' y1' x2' y2'];

    keepIdx = nms_xyxy(b640_xyxy, scoreK, nmsIou);
    b640_xyxy = b640_xyxy(keepIdx,:);
    scoreK = scoreK(keepIdx);
    maskK = maskK(:,keepIdx);

    for i = 1:size(b640_xyxy,1)
        b_best = undoLetterbox_xyxy(b640_xyxy(i,:), scale, pad);
        b_best(1) = max(1, min(W, b_best(1)));
        b_best(3) = max(1, min(W, b_best(3)));
        b_best(2) = max(1, min(H, b_best(2)));
        b_best(4) = max(1, min(H, b_best(4)));
        b_best = [min(b_best(1),b_best(3)), min(b_best(2),b_best(4)), ...
                  max(b_best(1),b_best(3)), max(b_best(2),b_best(4))];
        isPartial = false;
        if markPartial
            isPartial = is_bbox_partial(b_best, W, H, edgeMarginPx);
            if ~isPartial && ~isempty(gripperMask)
                isPartial = is_bbox_overlapping_mask(b_best, gripperMask);
            end
            if useMaskEvidence && ~isempty(proto)
                maskSoft = is_mask_partial_soft(maskK(:,i), proto, imgsz, b640_xyxy(i,:), scale, pad, W, H, ...
                    maskThresh, maskMinArea, maskUseBBox, b_best, maskEdgeMarginPx, gripperMask, ...
                    maskMinAreaPx, maskMinCompAreaPx, edgeRatioThr, gripRatioThr);
                isPartial = isPartial || maskSoft;
            end
        end
        dets(end+1) = struct("bbox", b_best, "bbox640", b640_xyxy(i,:), "score", scoreK(i), ...
            "maskCoeff", maskK(:,i), "partial", isPartial); %#ok<AGROW>
    end
end
