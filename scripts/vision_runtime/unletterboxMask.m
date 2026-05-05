function maskOrig = unletterboxMask(mask640, scale, pad, W, H)
    nh = round(H * scale);
    nw = round(W * scale);
    x1 = pad(1) + 1;
    y1 = pad(2) + 1;
    x2 = min(size(mask640,2), pad(1) + nw);
    y2 = min(size(mask640,1), pad(2) + nh);
    maskCrop = mask640(y1:y2, x1:x2);
    maskOrig = imresize(maskCrop, [H W], 'bilinear');
end
%% ---------------- bottle/spam/cube helpers ----------------
