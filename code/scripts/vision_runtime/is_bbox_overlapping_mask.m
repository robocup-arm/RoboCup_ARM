function tf = is_bbox_overlapping_mask(bbox, mask)
    tf = false;
    if isempty(mask)
        return;
    end
    H = size(mask,1); W = size(mask,2);
    x1 = max(1, min(W, floor(bbox(1))));
    y1 = max(1, min(H, floor(bbox(2))));
    x2 = max(1, min(W, ceil(bbox(3))));
    y2 = max(1, min(H, ceil(bbox(4))));
    if x2 < x1 || y2 < y1
        return;
    end
    sub = mask(y1:y2, x1:x2);
    tf = any(sub(:));
end
