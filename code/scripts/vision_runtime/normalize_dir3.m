function v = normalize_dir3(vIn, vFallback)
    v = reshape(vIn, [3 1]);
    n = norm(v);
    if n < 1e-12 || any(~isfinite(v))
        v = reshape(vFallback, [3 1]);
        n = norm(v);
    end
    if n < 1e-12
        v = [0;0;1];
    else
        v = v / n;
    end
end
