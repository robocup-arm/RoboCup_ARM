function Pm = selectMidBand(Psrc, midPt, axisVec, tableN, tableD, band, tableClear)
    if isempty(Psrc)
        Pm = zeros(0,3);
        return;
    end
    distMid = abs((Psrc - midPt) * axisVec');
    Pm = Psrc(distMid <= band, :);
    if isempty(Pm)
        return;
    end
    if tableClear > 0
        dTab = Pm * tableN + tableD;
        keep = abs(dTab) >= tableClear;
        if any(keep)
            Pm = Pm(keep, :);
        end
    end
end
