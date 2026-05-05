function b = undoLetterbox_xyxy(b640_xyxy, scale, pad)
    x1 = (b640_xyxy(1) - pad(1)) / scale;
    y1 = (b640_xyxy(2) - pad(2)) / scale;
    x2 = (b640_xyxy(3) - pad(1)) / scale;
    y2 = (b640_xyxy(4) - pad(2)) / scale;
    b = [x1 y1 x2 y2];
end
