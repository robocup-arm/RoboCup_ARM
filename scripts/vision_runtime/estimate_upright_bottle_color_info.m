function info = estimate_upright_bottle_color_info(rgb, maskObj, cfg)
    info = default_color_info();
    [maskRing, maskSide1, maskSide2] = build_upright_bottle_side_masks(maskObj, cfg);
    infoRing = classify_color_from_mask(rgb, maskRing, "bottle", cfg, "upright_ring");
    info1 = classify_color_from_mask(rgb, maskSide1, "bottle", cfg, "upright_side1");
    info2 = classify_color_from_mask(rgb, maskSide2, "bottle", cfg, "upright_side2");

    sideInfos = [info1, info2];
    bestSide = default_color_info();
    for k = 1:numel(sideInfos)
        if ~is_color_info_valid(sideInfos(k))
            continue;
        end
        if ~is_color_info_valid(bestSide) || sideInfos(k).score > bestSide.score || ...
                (abs(sideInfos(k).score - bestSide.score) < 1e-6 && sideInfos(k).pixelCount > bestSide.pixelCount)
            bestSide = sideInfos(k);
        end
    end

    if is_color_info_valid(bestSide) && string(bestSide.label) ~= "blue" && ...
            bestSide.score >= cfg.uprightBottleMinSideScore
        if ~is_color_info_valid(infoRing) || string(infoRing.label) == "blue" || ...
                bestSide.score >= infoRing.score - cfg.uprightBottleBlueOverrideMargin
            info = bestSide;
            return;
        end
    end

    if is_color_info_valid(infoRing)
        info = infoRing;
    elseif is_color_info_valid(bestSide)
        info = bestSide;
    end
end
