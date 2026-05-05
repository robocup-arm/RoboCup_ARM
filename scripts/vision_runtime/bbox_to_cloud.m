function [Pc, ok] = bbox_to_cloud(b_best, depth, K, zMin, zMax)
    H = size(depth,1); W = size(depth,2);
    x1o = round(b_best(1)); y1o = round(b_best(2));
    x2o = round(b_best(3)); y2o = round(b_best(4));
    x1o = max(1, min(W, x1o));
    x2o = max(1, min(W, x2o));
    y1o = max(1, min(H, y1o));
    y2o = max(1, min(H, y2o));
    [uu2, vv2] = meshgrid(x1o:x2o, y1o:y2o);
    uu = uu2(:); vv = vv2(:);
    [Pc, ok] = pixels_to_cloud_fast(uu, vv, depth, K, zMin, zMax, 50);
end
