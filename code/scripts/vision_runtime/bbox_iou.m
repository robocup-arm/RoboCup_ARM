function iou = bbox_iou(box, boxes)
    x1 = max(box(1), boxes(:,1));
    y1 = max(box(2), boxes(:,2));
    x2 = min(box(3), boxes(:,3));
    y2 = min(box(4), boxes(:,4));
    w = max(0, x2 - x1);
    h = max(0, y2 - y1);
    inter = w .* h;
    area1 = max(0, box(3)-box(1)) * max(0, box(4)-box(2));
    area2 = max(0, boxes(:,3)-boxes(:,1)) .* max(0, boxes(:,4)-boxes(:,2));
    iou = inter ./ max(area1 + area2 - inter, 1e-9);
end
