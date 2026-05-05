function info = estimate_cube_color_info(rgb, square2D, cfg)
    info = default_color_info();
    if isempty(rgb) || isempty(square2D) || size(square2D, 1) < 3
        return;
    end
    H = size(rgb, 1);
    W = size(rgb, 2);
    poly = shrink_polygon_to_center(square2D, cfg.cubeShrink);
    maskObj = poly2mask(poly(:,1), poly(:,2), H, W);
    if cfg.cubeErodeRadius > 0
        se = strel('disk', cfg.cubeErodeRadius, 0);
        maskTry = imerode(maskObj, se);
        if nnz(maskTry) >= cfg.minPixels
            maskObj = maskTry;
        end
    end
    if nnz(maskObj) < cfg.minPixels
        return;
    end
    info = classify_color_from_mask(rgb, maskObj, "cube", cfg, "topface");
end
