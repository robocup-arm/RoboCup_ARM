function Pout = sample_cloud(P, maxPts)
    if isempty(P)
        Pout = zeros(0,3);
        return;
    end
    n = size(P,1);
    if n > maxPts
        idx = randperm(n, maxPts);
        Pout = P(idx, :);
    else
        Pout = P;
    end
end
