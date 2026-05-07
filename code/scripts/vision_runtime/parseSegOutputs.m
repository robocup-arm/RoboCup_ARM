function [pred, proto] = parseSegOutputs(outs)
    if isa(outs, 'py.list')
        n = double(py.len(outs));
        getOut = @(k) outs{k};
    elseif iscell(outs)
        n = numel(outs);
        getOut = @(k) outs{k};
    else
        n = numel(outs);
        getOut = @(k) outs{k};
    end
    if n < 2
        error("Segmentation model should output 2 tensors.");
    end
    pred = [];
    proto = [];
    for i = 1:n
        t = single(getOut(i));
        if ndims(t) == 4
            proto = t;
        else
            pred = t;
        end
    end
    if isempty(proto) || isempty(pred)
        error("Failed to parse YOLO seg outputs.");
    end
    pred = squeeze(pred);
    proto = squeeze(proto);
end
