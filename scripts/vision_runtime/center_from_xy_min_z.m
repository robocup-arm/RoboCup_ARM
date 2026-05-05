function center3D = center_from_xy_min_z(Pobj, centerIn)
    center3D = centerIn;
    if isempty(Pobj) || isempty(centerIn)
        return;
    end
    C = reshape(double(centerIn), 1, 3);
    P = double(Pobj);
    P = P(all(isfinite(P),2), :);
    if isempty(P) || any(~isfinite(C))
        return;
    end

    CxyAll = mean(P(:,1:2), 1);
    rAll = sqrt(sum((P(:,1:2) - CxyAll).^2, 2));
    r90 = prctile(rAll, 90);
    xyRadius = max(0.006, 0.20 * r90); % adaptive local XY neighborhood
    minLocalPts = min(120, size(P,1));

    dxy2 = (P(:,1) - C(1)).^2 + (P(:,2) - C(2)).^2;
    idx = dxy2 <= (xyRadius^2);
    if nnz(idx) < minLocalPts
        [~, ord] = sort(dxy2, 'ascend');
        idx = false(size(dxy2));
        idx(ord(1:minLocalPts)) = true;
    end
    zLocal = P(idx, 3);
    if isempty(zLocal)
        zLocal = P(:,3);
    end

    % In current camera/work convention, smaller Z is closer to camera (top-most grasp surface).
    zTop = prctile(zLocal, 5); % robust min to suppress isolated outliers
    if isfinite(zTop)
        center3D = [C(1), C(2), zTop];
    end
end
