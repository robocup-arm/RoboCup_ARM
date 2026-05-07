function showTilt = get_debug_show_tilt(cfg)
    showTilt = true;
    if nargin < 1 || isempty(cfg)
        return;
    end
    if isfield(cfg, "showTiltFrame")
        showTilt = logical(cfg.showTiltFrame);
    end
end
