function [centerW, axisW, interW] = get_seg_overlay_work(overlay)
    centerW = zeros(0,3);
    axisW = zeros(0,3);
    interW = zeros(0,3);
    if isempty(overlay) || ~isstruct(overlay)
        return;
    end
    if isfield(overlay, "centerWork") && ~isempty(overlay.centerWork)
        centerW = reshape(double(overlay.centerWork), [], 3);
    end
    if isfield(overlay, "axisLineWork") && ~isempty(overlay.axisLineWork)
        axisW = reshape(double(overlay.axisLineWork), [], 3);
    end
    if isfield(overlay, "intersectLineWork") && ~isempty(overlay.intersectLineWork)
        interW = reshape(double(overlay.intersectLineWork), [], 3);
    end
end
