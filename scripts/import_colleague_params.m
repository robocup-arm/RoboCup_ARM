function import_colleague_params(matFile)
%IMPORT_COLLEAGUE_PARAMS Import compatible runtime parameters from matlab2.mat.
% This intentionally avoids loading the whole MAT file into base workspace,
% because matlab2.mat also contains stale detection caches and old path vars.

if nargin < 1 || strlength(string(matFile)) == 0
    matFile = "D:\WeChat\xwechat_files\wxid_8063780637211_b3e3\msg\file\2026-04\matlab2.mat";
end
matFile = string(matFile);

if exist(matFile, "file") ~= 2
    error("import_colleague_params:FileNotFound", "MAT file not found: %s", matFile);
end

S = load(matFile, ...
    "USER_QHOME_CURRENT", ...
    "USER_VIEW_POSES", ...
    "USER_VIEW_COUNT", ...
    "USER_VIEW_IDX", ...
    "USER_VIEW_EMPTY_FRAMES", ...
    "USER_VIEW_SWITCH_ENABLED", ...
    "USER_VIEW_SETTLE_FRAMES", ...
    "USER_AUTO_ARMED", ...
    "USER_AUTO_LOOP_ENABLE");

if isfield(S, "USER_QHOME_CURRENT") && isnumeric(S.USER_QHOME_CURRENT) ...
        && numel(S.USER_QHOME_CURRENT) == 6 && all(isfinite(S.USER_QHOME_CURRENT(:)))
    assignin("base", "USER_QHOME_CURRENT", double(S.USER_QHOME_CURRENT(:)));
end

if isfield(S, "USER_VIEW_POSES") && isnumeric(S.USER_VIEW_POSES) ...
        && size(S.USER_VIEW_POSES, 1) == 6 && ~isempty(S.USER_VIEW_POSES)
    poses = double(S.USER_VIEW_POSES);
    goodCols = all(isfinite(poses), 1);
    poses = poses(:, goodCols);
    if ~isempty(poses)
        assignin("base", "USER_VIEW_POSES", poses);
        assignin("base", "USER_VIEW_COUNT", double(size(poses, 2)));
    end
end

if isfield(S, "USER_VIEW_IDX") && isnumeric(S.USER_VIEW_IDX) && isscalar(S.USER_VIEW_IDX) ...
        && isfinite(S.USER_VIEW_IDX)
    assignin("base", "USER_VIEW_IDX", double(round(S.USER_VIEW_IDX)));
end

if isfield(S, "USER_VIEW_EMPTY_FRAMES") && isnumeric(S.USER_VIEW_EMPTY_FRAMES) ...
        && isscalar(S.USER_VIEW_EMPTY_FRAMES) && isfinite(S.USER_VIEW_EMPTY_FRAMES)
    assignin("base", "USER_VIEW_EMPTY_FRAMES", double(S.USER_VIEW_EMPTY_FRAMES));
end

if isfield(S, "USER_VIEW_SWITCH_ENABLED")
    assignin("base", "USER_VIEW_SWITCH_ENABLED", logical(S.USER_VIEW_SWITCH_ENABLED));
end

if isfield(S, "USER_VIEW_SETTLE_FRAMES") && isnumeric(S.USER_VIEW_SETTLE_FRAMES) ...
        && isscalar(S.USER_VIEW_SETTLE_FRAMES) && isfinite(S.USER_VIEW_SETTLE_FRAMES)
    assignin("base", "USER_AUTO_COOLDOWN_FRAMES", double(S.USER_VIEW_SETTLE_FRAMES));
end

legacyAutoOn = false;
if isfield(S, "USER_AUTO_ARMED")
    legacyAutoOn = legacyAutoOn || logical(S.USER_AUTO_ARMED);
end
if isfield(S, "USER_AUTO_LOOP_ENABLE")
    legacyAutoOn = legacyAutoOn || logical(S.USER_AUTO_LOOP_ENABLE);
end
assignin("base", "USER_AUTO_RUN", legacyAutoOn);

fprintf("[import_colleague_params] Imported compatible parameters from %s\n", matFile);
fprintf("[import_colleague_params] USER_AUTO_RUN=%d\n", int32(legacyAutoOn));
end
