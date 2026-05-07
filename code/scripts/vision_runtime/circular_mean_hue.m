function hMean = circular_mean_hue(h, w)
    ang = 2 * pi * h(:);
    c = sum(w(:) .* cos(ang));
    s = sum(w(:) .* sin(ang));
    hMean = mod(atan2(s, c) / (2 * pi), 1);
end
