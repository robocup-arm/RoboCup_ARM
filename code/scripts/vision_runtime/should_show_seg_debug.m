function tf = should_show_seg_debug(cfg, clsTag, imgName, detIdx)
    tf = false;
    if nargin < 1 || isempty(cfg) || ~isfield(cfg, "enable") || ~cfg.enable
        return;
    end
    if nargin < 2
        return;
    end
    clsWant = "all";
    if isfield(cfg, "class") && strlength(string(cfg.class)) > 0
        clsWant = lower(string(cfg.class));
    end
    if clsWant ~= "all" && clsWant ~= lower(string(clsTag))
        return;
    end
    if isfield(cfg, "imageName") && strlength(string(cfg.imageName)) > 0
        if string(imgName) ~= string(cfg.imageName)
            return;
        end
    end
    if isfield(cfg, "detIndex") && ~isempty(cfg.detIndex)
        if detIdx ~= cfg.detIndex
            return;
        end
    end
    tf = true;
end
