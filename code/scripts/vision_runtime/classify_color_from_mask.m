function info = classify_color_from_mask(rgb, maskBin, clsName, cfg, sourceTag)
    info = default_color_info();
    if isempty(rgb) || isempty(maskBin) || ~any(maskBin(:))
        return;
    end
    rgbD = im2double(rgb);
    hsvI = rgb2hsv(rgbD);
    H = hsvI(:,:,1);
    S = hsvI(:,:,2);
    V = hsvI(:,:,3);
    minSat = cfg.minSatCylinder;
    if string(clsName) == "cube"
        minSat = cfg.minSatCube;
    end
    valid = maskBin & isfinite(H) & isfinite(S) & isfinite(V) & (V >= cfg.minVal) & (V <= cfg.maxVal + 1e-6);
    strong = valid & (S >= minSat);
    if nnz(strong) >= cfg.minPixels
        useMask = strong;
        src = string(sourceTag) + "_sat";
    elseif nnz(valid) >= cfg.minPixels
        useMask = valid;
        src = string(sourceTag) + "_relaxed";
    else
        return;
    end
    hp = H(useMask);
    sp = S(useMask);
    vp = V(useMask);
    rgbFlat = reshape(rgbD, [], 3);
    rgbPx = rgbFlat(useMask(:), :);
    w = max(sp, 0.05) .^ cfg.satWeightPow;
    w = w / max(sum(w), eps);
    [candNames, candHues] = get_color_candidates(clsName);
    if isempty(candNames)
        return;
    end
    scores = zeros(1, numel(candNames));
    for k = 1:numel(candNames)
        dh = abs(hp - candHues(k));
        dh = min(dh, 1 - dh);
        scores(k) = sum(w .* exp(-0.5 * (dh ./ cfg.hueSigma) .^ 2));
    end
    [bestScore, bestIdx] = max(scores);
    if numel(scores) > 1
        scoreOthers = scores;
        scoreOthers(bestIdx) = -inf;
        secondScore = max(scoreOthers);
        if ~isfinite(secondScore)
            secondScore = 0;
        end
    else
        secondScore = 0;
    end
    info.label = candNames(bestIdx);
    info.score = max(0, min(1, 0.65 * bestScore + 0.35 * max(0, bestScore - secondScore)));
    info.source = src;
    info.meanHSV = [circular_mean_hue(hp, w), sum(w .* sp), sum(w .* vp)];
    info.meanRGB = sum(rgbPx .* w, 1);
    info.pixelCount = nnz(useMask);

    % Cube-only fix: promote blue -> purple when hue clearly in purple band.
    if string(clsName) == "cube" && string(info.label) == "blue"
        hMean = info.meanHSV(1);
        sMean = info.meanHSV(2);
        vMean = info.meanHSV(3);
        if isfinite(hMean) && isfinite(sMean) && isfinite(vMean) && ...
                (hMean >= cfg.cubePurpleHueMin) && (hMean <= cfg.cubePurpleHueMax) && ...
                (sMean >= cfg.cubePurpleMinSat) && (vMean <= cfg.cubePurpleMaxVal)
            info.label = "purple";
            info.source = info.source + "_purple_fix";
        end
    end

    [info.points, info.targetBin] = map_color_to_scoring(clsName, info.label);
end
