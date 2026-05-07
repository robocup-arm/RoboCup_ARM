function [xywh, cls, maskCoeff, nc] = splitPred(pred, nm)
    if size(pred,2) > size(pred,1)
        d = size(pred,1);
    else
        pred = pred';
        d = size(pred,1);
    end
    if d <= (4 + nm)
        error("Unexpected prediction shape.");
    end
    nc = d - 4 - nm;
    xywh = pred(1:4,:);
    cls = pred(5:4+nc,:);
    maskCoeff = pred(5+nc:4+nc+nm,:);
end
