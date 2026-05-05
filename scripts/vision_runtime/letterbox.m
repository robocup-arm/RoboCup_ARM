function [Iout, scale, pad] = letterbox(I, newSize)
    h = size(I,1); w = size(I,2);
    scale = newSize / max(h,w);
    nh = round(h * scale);
    nw = round(w * scale);
    Ires = imresize(I, [nh nw]);
    padH = newSize - nh;
    padW = newSize - nw;
    top = floor(padH/2);
    bottom = padH - top;
    left = floor(padW/2);
    right = padW - left;
    Iout = padarray(Ires, [top left], 114, 'pre');
    Iout = padarray(Iout, [bottom right], 114, 'post');
    pad = [left top];
end
