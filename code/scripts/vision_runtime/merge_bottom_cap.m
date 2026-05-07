function pcOut = merge_bottom_cap(pcMain, pcAll)
    pcOut = pcMain;
    if pcMain.Count < 50
        return;
    end
    Pmain = pcMain.Location;
    Cxy = mean(Pmain(:,1:2), 1);
    rxy = sqrt(sum((Pmain(:,1:2) - Cxy).^2, 2));
    rMain = prctile(rxy, 90);
    zMinMain = min(Pmain(:,3));

    zCapBand = 0.015; % meters above low-Z percentile
    zLowPct  = 10;    % percentile to define low-Z band
    rExpand  = 1.30;  % radius expand

    PsegAll = pcAll.Location;
    dxyAll = sqrt(sum((PsegAll(:,1:2) - Cxy).^2, 2));
    zLow = prctile(PsegAll(:,3), zLowPct);
    capMask = (PsegAll(:,3) <= zLow + zCapBand) & (dxyAll <= rMain * rExpand);
    if nnz(capMask) < 20
        % fallback: use main-min based band
        capMask = (PsegAll(:,3) <= zMinMain + 0.03) & (dxyAll <= rMain * rExpand);
    end
    if nnz(capMask) >= 20
        Pmerge = [Pmain; PsegAll(capMask,:)];
        pcOut = pointCloud(Pmerge);
    end
end
