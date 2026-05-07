function keep = nms_xyxy(boxes, scores, iouThr)
    if isempty(boxes)
        keep = [];
        return;
    end
    [~, order] = sort(scores, 'descend');
    keep = [];
    while ~isempty(order)
        i = order(1);
        keep(end+1,1) = i; %#ok<AGROW>
        if numel(order) == 1
            break;
        end
        rest = order(2:end);
        ious = bbox_iou(boxes(i,:), boxes(rest,:));
        order = rest(ious < iouThr);
    end
end
