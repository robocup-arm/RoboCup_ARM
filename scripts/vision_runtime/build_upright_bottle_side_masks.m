function [maskRing, maskSide1, maskSide2] = build_upright_bottle_side_masks(maskObj, cfg)
    maskRing = false(size(maskObj));
    maskSide1 = false(size(maskObj));
    maskSide2 = false(size(maskObj));
    maskBase = logical(maskObj);
    if ~any(maskBase(:))
        return;
    end
    if cfg.cylErodeRadius > 0
        se = strel('disk', cfg.cylErodeRadius, 0);
        maskTry = imerode(maskBase, se);
        if nnz(maskTry) >= cfg.minPixels
            maskBase = maskTry;
        end
    end
    [vv, uu] = find(maskBase);
    if numel(uu) < cfg.minPixels
        maskRing = maskBase;
        return;
    end
    U = [double(uu), double(vv)];
    C = mean(U, 1);
    Q = U - C;
    if size(Q,1) < 3
        maskRing = maskBase;
        return;
    end
    [~, ~, V] = svd(Q, 'econ');
    t1 = Q * V(:,1);
    t2 = Q * V(:,2);
    s1 = max(prctile(abs(t1), 90), 1);
    s2 = max(prctile(abs(t2), 90), 1);
    rNorm = sqrt((t1 ./ s1) .^ 2 + (t2 ./ s2) .^ 2);
    keepRing = rNorm >= cfg.uprightBottleRingFrac;
    if nnz(keepRing) < cfg.minPixels
        keepRing = true(size(t1));
    end
    idxRing = sub2ind(size(maskBase), vv(keepRing), uu(keepRing));
    maskRing(idxRing) = true;
    keep1 = keepRing & (t1 >= 0);
    keep2 = keepRing & (t1 < 0);
    if nnz(keep1) >= cfg.minPixels
        idx1 = sub2ind(size(maskBase), vv(keep1), uu(keep1));
        maskSide1(idx1) = true;
    end
    if nnz(keep2) >= cfg.minPixels
        idx2 = sub2ind(size(maskBase), vv(keep2), uu(keep2));
        maskSide2(idx2) = true;
    end
end
