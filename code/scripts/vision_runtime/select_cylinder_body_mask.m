function maskBody = select_cylinder_body_mask(maskObj, cfg)
    maskBody = logical(maskObj);
    if ~any(maskBody(:))
        return;
    end
    if cfg.cylErodeRadius > 0
        se = strel('disk', cfg.cylErodeRadius, 0);
        maskTry = imerode(maskBody, se);
        if nnz(maskTry) >= cfg.minPixels
            maskBody = maskTry;
        end
    end
    [vv, uu] = find(maskBody);
    if numel(uu) < cfg.minPixels
        return;
    end
    U = [double(uu), double(vv)];
    C = mean(U, 1);
    Q = U - C;
    if size(Q,1) < 3
        return;
    end
    [~, ~, V] = svd(Q, 'econ');
    tMajor = Q * V(:,1);
    thr = prctile(abs(tMajor), cfg.cylBodyMajorPct);
    keep = abs(tMajor) <= thr;
    if nnz(keep) < cfg.minPixels
        return;
    end
    maskMid = false(size(maskBody));
    idx = sub2ind(size(maskBody), vv(keep), uu(keep));
    maskMid(idx) = true;
    if nnz(maskMid) >= cfg.minPixels
        maskBody = maskMid;
    end
end
