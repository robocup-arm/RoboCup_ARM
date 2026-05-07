function iou = box_iou_pair_xyxy(b1, b2)
    x1 = max(b1(1), b2(1));
    y1 = max(b1(2), b2(2));
    x2 = min(b1(3), b2(3));
    y2 = min(b1(4), b2(4));
    w = max(0, x2 - x1);
    h = max(0, y2 - y1);
    inter = w * h;
    a1 = max(0, b1(3)-b1(1)) * max(0, b1(4)-b1(2));
    a2 = max(0, b2(3)-b2(1)) * max(0, b2(4)-b2(2));
    iou = inter / max(a1 + a2 - inter, 1e-9);
end
