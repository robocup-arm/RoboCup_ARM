function info = estimate_cylinder_color_info(rgb, det, proto, imgsz, maskThresh, maskMinArea, maskUseBBox, scaleLB, padLB, clsName, abLabel, cfg)
    info = default_color_info();
    if isempty(rgb)
        return;
    end
    H = size(rgb, 1);
    W = size(rgb, 2);
    maskObj = build_object_mask_for_color(det, proto, imgsz, maskThresh, maskMinArea, maskUseBBox, scaleLB, padLB, H, W, cfg);
    if ~any(maskObj(:))
        return;
    end
    if string(clsName) == "bottle" && string(abLabel) == "A"
        info = estimate_upright_bottle_color_info(rgb, maskObj, cfg);
        if is_color_info_valid(info)
            return;
        end
    end
    maskBody = select_cylinder_body_mask(maskObj, cfg);
    if nnz(maskBody) < cfg.minPixels
        maskBody = maskObj;
    end
    info = classify_color_from_mask(rgb, maskBody, clsName, cfg, "mask");
end
