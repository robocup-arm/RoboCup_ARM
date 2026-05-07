function tf = has_cloud_points(objs)
    tf = false;
    for k = 1:numel(objs)
        if isfield(objs(k), 'cloud') && ~isempty(objs(k).cloud) && size(objs(k).cloud,1) > 0
            tf = true;
            return;
        end
    end
end
