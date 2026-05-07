function idxStr = extractIndex(name)
    idxStr = "";
    m = regexp(name, 'rgb_(\d+)\.png', 'tokens', 'once');
    if ~isempty(m)
        idxStr = m{1};
    end
end
