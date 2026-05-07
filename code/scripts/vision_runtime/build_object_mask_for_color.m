function maskBin = build_object_mask_for_color(det, proto, imgsz, maskThresh, maskMinArea, maskUseBBox, scaleLB, padLB, H, W, cfg)
    maskBin = false(H, W);
    useMask = ~isempty(proto) && isfield(det, "maskCoeff") && ~isempty(det.maskCoeff);
    if useMask
        if isfield(det, "maskBBox640") && ~isempty(det.maskBBox640)
            b640 = det.maskBBox640;
        else
            b640 = [];
        end
        mask640 = buildMaskFromProto(det.maskCoeff, proto, imgsz);
        if maskUseBBox && ~isempty(b640)
            x1b = max(1, floor(b640(1))); y1b = max(1, floor(b640(2)));
            x2b = min(imgsz, ceil(b640(3))); y2b = min(imgsz, ceil(b640(4)));
            mask640(:,1:max(1,x1b-1)) = 0;
            mask640(:,min(imgsz,x2b+1):end) = 0;
            mask640(1:max(1,y1b-1),:) = 0;
            mask640(min(imgsz,y2b+1):end,:) = 0;
        end
        maskOrig = unletterboxMask(mask640, scaleLB, padLB, W, H);
        maskBin = maskOrig > maskThresh;
        if maskMinArea > 0
            maskBin = bwareaopen(maskBin, maskMinArea);
        end
        if isfield(det, "bbox") && ~isempty(det.bbox)
            maskBin = keep_primary_mask_component(maskBin, det.bbox, cfg.minCompArea);
        end
    elseif isfield(det, "bbox") && ~isempty(det.bbox)
        bb = det.bbox;
        x1 = max(1, floor(bb(1))); y1 = max(1, floor(bb(2)));
        x2 = min(W, ceil(bb(3)));  y2 = min(H, ceil(bb(4)));
        if x2 >= x1 && y2 >= y1
            dx = round((x2 - x1) * cfg.bboxInsetFrac);
            dy = round((y2 - y1) * cfg.bboxInsetFrac);
            x1 = min(W, max(1, x1 + dx));
            y1 = min(H, max(1, y1 + dy));
            x2 = max(1, min(W, x2 - dx));
            y2 = max(1, min(H, y2 - dy));
            if x2 >= x1 && y2 >= y1
                maskBin(y1:y2, x1:x2) = true;
            end
        end
    end
end
