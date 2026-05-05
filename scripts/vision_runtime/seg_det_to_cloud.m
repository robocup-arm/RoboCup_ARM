function [Pc, ok] = seg_det_to_cloud(det, proto, depth, K, zMin, zMax, maskThresh, maskMinArea, maskUseBBox, imgsz)
    Pc = zeros(0,3);
    ok = false;
    H = size(depth,1); W = size(depth,2);

    b640 = [];
    if isfield(det, "maskBBox640") && ~isempty(det.maskBBox640)
        b640 = det.maskBBox640;
    elseif isfield(det, "bbox640") && ~isempty(det.bbox640)
        b640 = det.bbox640;
    end
    mask640 = buildMaskFromProto(det.maskCoeff, proto, imgsz);
    if maskUseBBox && ~isempty(b640)
        x1b = max(1, min(imgsz, round(b640(1))));
        x2b = max(1, min(imgsz, round(b640(3))));
        y1b = max(1, min(imgsz, round(b640(2))));
        y2b = max(1, min(imgsz, round(b640(4))));
        mask640(:,1:max(1,x1b-1)) = 0;
        mask640(:,min(imgsz,x2b+1):end) = 0;
        mask640(1:max(1,y1b-1),:) = 0;
        mask640(min(imgsz,y2b+1):end,:) = 0;
    end

    scale = imgsz / max(H, W);
    nh = round(H * scale);
    nw = round(W * scale);
    pad = [floor((imgsz - nw)/2) floor((imgsz - nh)/2)];
    maskOrig = unletterboxMask(mask640, scale, pad, W, H);
    maskBin = maskOrig > maskThresh;
    if maskMinArea > 0
        maskBin = bwareaopen(maskBin, maskMinArea);
    end

    [vv, uu] = find(maskBin);
    if isempty(vv)
        return;
    end
    [Pc, ok] = pixels_to_cloud_fast(uu, vv, depth, K, zMin, zMax, 50);
end
