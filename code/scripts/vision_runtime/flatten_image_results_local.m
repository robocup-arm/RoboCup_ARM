function objs = flatten_image_results_local(imgRes)

tmpl = struct( ...
    'cls', "", ...
    'bbox', zeros(1,4), ...
    'score', 0, ...
    'center3D', zeros(1,3), ...
    'center2D', zeros(1,2), ...
    'axis3D', zeros(1,3), ...
    'axisLine2D', zeros(0,2), ...
    'intersectLine2D', zeros(0,2), ...
    'rect2D', zeros(0,2), ...
    'square2D', zeros(0,2), ...
    'ab', "", ...
    'partial', false ...
    );

objs = repmat(tmpl, 0, 1);
fields = {'can','bottle','spam','cube','marker'};
for f = 1:numel(fields)
    name = fields{f};
    if ~isfield(imgRes, name)
        continue;
    end
    arr = imgRes.(name);
    if isempty(arr)
        continue;
    end
    for k = 1:numel(arr)
        src = arr(k);
        dst = tmpl;
        if isfield(src, 'cls') && ~isempty(src.cls)
            dst.cls = string(src.cls);
        else
            dst.cls = string(name);
        end
        if isfield(src, 'bbox') && ~isempty(src.bbox)
            b = double(src.bbox(:)');
            if numel(b) == 4, dst.bbox = b; end
        end
        if isfield(src, 'score') && ~isempty(src.score), dst.score = double(src.score); end
        if isfield(src, 'center3D') && ~isempty(src.center3D)
            c3 = double(src.center3D(:)'); if numel(c3) == 3, dst.center3D = c3; end
        end
        if isfield(src, 'center2D') && ~isempty(src.center2D)
            c2 = double(src.center2D(:)'); if numel(c2) == 2, dst.center2D = c2; end
        end
        if isfield(src, 'partial') && ~isempty(src.partial), dst.partial = logical(src.partial); end
        if isfield(src, 'axis3D') && ~isempty(src.axis3D)
            a3 = double(src.axis3D(:)'); if numel(a3) == 3, dst.axis3D = a3; end
        end
        if isfield(src, 'axisLine2D') && ~isempty(src.axisLine2D), dst.axisLine2D = double(src.axisLine2D); end
        if isfield(src, 'intersectLine2D') && ~isempty(src.intersectLine2D), dst.intersectLine2D = double(src.intersectLine2D); end
        if isfield(src, 'ab') && ~isempty(src.ab), dst.ab = string(src.ab); end
        if isfield(src, 'rect2D') && ~isempty(src.rect2D), dst.rect2D = double(src.rect2D); end
        if isfield(src, 'square2D') && ~isempty(src.square2D), dst.square2D = double(src.square2D); end
        objs(end+1,1) = dst; %#ok<AGROW>
    end
end
end
