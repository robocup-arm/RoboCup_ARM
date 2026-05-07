function uv = project_points(P, fx, fy, cx0, cy0)
    if isempty(P)
        uv = zeros(0,2);
        return;
    end
    if isvector(P) && numel(P) == 3
        P = reshape(P, [1 3]);
    end
    X = P(:,1); Y = P(:,2); Z = P(:,3);
    u = fx * (X ./ Z) + cx0;
    v = fy * (Y ./ Z) + cy0;
    uv = [u v];
end
