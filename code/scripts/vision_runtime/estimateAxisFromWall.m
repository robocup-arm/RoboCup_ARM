function [axisVec, info] = estimateAxisFromWall(P)
    C = mean(P, 1);
    [~,~,V] = svd(P - C, 'econ');
    axisPCA = normalize_dir3(V(:,1), [0 0 1]');
    axisWall = axisPCA;
    for iter = 1:2
        n = axisWall(:);
        Pc = P - C; % distance-to-axis must be computed in centered coordinates
        Q = Pc - (Pc * n) * n';
        r = sqrt(sum(Q.^2, 2));
        r0 = prctile(r, 70);
        tol = max(0.003, 0.15 * r0);
        wallMask = abs(r - r0) <= tol;
        if nnz(wallMask) < 50
            break;
        end
        Pw = P(wallMask, :);
        Cw = mean(Pw, 1);
        [~,~,Vw] = svd(Pw - Cw, 'econ');
        cand = normalize_dir3(Vw(:,1), axisWall);
        if norm(cand) < 1e-9
            break;
        end
        axisWall = cand;
    end

    [scorePCA, fracPCA, spreadPCA] = axis_ring_consistency(P, C, axisPCA);
    [scoreWall, fracWall, spreadWall] = axis_ring_consistency(P, C, axisWall);
    if scoreWall >= scorePCA + 0.01
        axisVec = axisWall;
        source = "wall";
        scoreChosen = scoreWall;
    else
        axisVec = axisPCA;
        source = "pca";
        scoreChosen = scorePCA;
    end

    Cxy = mean(P(:,1:2), 1);
    rxy = sqrt(sum((P(:,1:2) - Cxy).^2, 2));
    info = struct( ...
        "center", C, ...
        "centerXY", Cxy, ...
        "rXY", prctile(rxy, 90), ...
        "axisPCA", axisPCA(:)', ...
        "axisWall", axisWall(:)', ...
        "source", source, ...
        "scoreChosen", scoreChosen, ...
        "scorePCA", scorePCA, ...
        "scoreWall", scoreWall, ...
        "fracPCA", fracPCA, ...
        "fracWall", fracWall, ...
        "spreadPCA", spreadPCA, ...
        "spreadWall", spreadWall ...
        );
end
