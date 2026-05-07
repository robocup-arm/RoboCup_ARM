function [target3D, midPt, axisVec, info] = fit_caseB_target_point(pcCan, pcRaw, opts)
% Reconstructed wrapper for CAN Case-B target extraction.
% The original project file calls fit_caseB_target_point for can objects,
% but the uploaded source only contained fit_caseB_target_point_bottle.
% Cylindrical geometry is the same, so reuse the bottle implementation.
if nargin < 3
    opts = struct;
end
[target3D, midPt, axisVec, info] = fit_caseB_target_point_bottle(pcCan, pcRaw, opts);
end
