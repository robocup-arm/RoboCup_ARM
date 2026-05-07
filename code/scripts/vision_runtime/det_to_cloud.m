function [Pc, ok] = det_to_cloud(det, proto, depth, K, zMin, zMax, maskThresh, maskMinArea, maskUseBBox, imgsz)
    ok = false;
    Pc = zeros(0,3);
    useMask = ~isempty(proto) && isfield(det, "maskCoeff") && ~isempty(det.maskCoeff);
    if useMask
        [Pc, ok] = seg_det_to_cloud(det, proto, depth, K, zMin, zMax, maskThresh, maskMinArea, maskUseBBox, imgsz);
        if ok
            return;
        end
    end
    [Pc, ok] = bbox_to_cloud(det.bbox, depth, K, zMin, zMax);
end
