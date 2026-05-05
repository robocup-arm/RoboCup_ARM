function isPartial = is_bbox_partial(bbox, W, H, marginPx)
    if nargin < 4 || isempty(marginPx)
        marginPx = 0;
    end
    x1 = bbox(1); y1 = bbox(2); x2 = bbox(3); y2 = bbox(4);
    isPartial = (x1 <= 1 + marginPx) || (y1 <= 1 + marginPx) || ...
                (x2 >= W - marginPx) || (y2 >= H - marginPx);
end
