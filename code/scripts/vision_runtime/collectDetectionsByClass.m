function dets = collectDetectionsByClass(targetClass, xywh, scoreAll, cidAll, classNames, confTh, nmsIou, scale, pad, W, H, markPartial, edgeMarginPx, gripperMask)
    dets = struct("bbox", {}, "bbox640", {}, "score", {}, "partial", {});
    if isempty(xywh)
        return;
    end
    isTarget = strcmp(classNames(cidAll), targetClass);
    keep = (scoreAll > confTh) & isTarget;
    if ~any(keep)
        return;
    end
    xywhK  = xywh(:,keep);
    scoreK = scoreAll(keep);

    cx = xywhK(1,:); cy = xywhK(2,:);
    w  = xywhK(3,:); h  = xywhK(4,:);
    x1 = cx - w/2; y1 = cy - h/2;
    x2 = cx + w/2; y2 = cy + h/2;
    b640_xyxy = [x1' y1' x2' y2'];

    keepIdx = nms_xyxy(b640_xyxy, scoreK, nmsIou);
    b640_xyxy = b640_xyxy(keepIdx,:);
    scoreK = scoreK(keepIdx);

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
        end
        dets(end+1) = struct("bbox", b_best, "bbox640", b640_xyxy(i,:), "score", scoreK(i), "partial", isPartial); %#ok<AGROW>
    end
end
