function classNames = buildClassNames(nc, baseName)
    if nc <= 1
        classNames = {baseName};
        return;
    end
    classNames = cell(1,nc);
    for i = 1:nc
        classNames{i} = sprintf("c%d", i);
    end
    classNames{1} = baseName;
end
%% ---------------- marker seg helpers ----------------
