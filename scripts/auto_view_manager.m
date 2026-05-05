function switched = auto_view_manager(numDet, canPick, autoRun)
% Manage camera viewpoints in auto mode:
% when current view has no graspable targets for enough frames, switch to
% the next recorded pose and reset cycle state.

persistent emptyCount
if isempty(emptyCount)
    emptyCount = uint16(0);
end

switched = false;

if ~logical(autoRun)
    emptyCount = uint16(0);
    return;
end

% Cube second stage should wait on the scale view for fresh detection.
try
    if evalin('base', 'exist(''USER_CUBE_PLACE_MODE'',''var'')') ~= 0
        cubeMode = double(evalin('base', 'USER_CUBE_PLACE_MODE'));
        if round(cubeMode) == 2
            emptyCount = uint16(0);
            return;
        end
    end
catch
end

if ~logical(canPick)
    emptyCount = uint16(0);
    return;
end

if ~isfinite(numDet) || (double(numDet) < 1)
    if emptyCount < uint16(65535)
        emptyCount = emptyCount + uint16(1);
    end
else
    emptyCount = uint16(0);
    return;
end

threshold = get_base_double_or_default('USER_VIEW_EMPTY_FRAMES', 80);
if emptyCount < uint16(max(1, round(threshold)))
    return;
end
emptyCount = uint16(0);

enabled = get_base_logical_or_default('USER_VIEW_SWITCH_ENABLED', true);
if ~enabled
    return;
end

if evalin('base', 'exist(''USER_VIEW_POSES'',''var'')') == 0
    return;
end
poses = evalin('base', 'USER_VIEW_POSES');
if ~isnumeric(poses) || size(poses,1) ~= 6 || isempty(poses)
    return;
end

n = size(poses,2);
if n < 2
    return;
end

idx = get_base_double_or_default('USER_VIEW_IDX', 1);
if ~isfinite(idx)
    idx = 1;
end
idx = round(idx);
if idx < 1 || idx > n
    idx = 1;
end

nextIdx = idx + 1;
if nextIdx > n
    nextIdx = 1;
end

qNext = poses(:, nextIdx);
if ~all(isfinite(qNext))
    return;
end

% 如果已经有一次视角移动在排队/执行，就不要重复触发
pendingMove = false;
if evalin('base', 'exist(''USER_VIEW_MOVE_PENDING'',''var'')') ~= 0
    pendingMove = logical(evalin('base', 'USER_VIEW_MOVE_PENDING'));
end
if pendingMove
    return;
end

% 不要立刻�?USER_QHOME_CURRENT
% 只发�?下一目标观察�?�?待切�?标志
assignin('base', 'USER_VIEW_IDX_NEXT', double(nextIdx));
assignin('base', 'USER_QHOME_NEXT', qNext(:));
assignin('base', 'USER_VIEW_MOVE_PENDING', true);

% 先暂停自动抓取触发，等移动完成再恢复
assignin('base', 'USER_PROCEED', false);
assignin('base', 'USER_ABORT', false);

switched = true;
fprintf('[auto_view_manager] switch to view %d/%d\n', nextIdx, n);
end

function v = get_base_double_or_default(name, defaultVal)
v = defaultVal;
try
    if evalin('base', sprintf('exist(''%s'',''var'')', name)) ~= 0
        t = evalin('base', name);
        if isnumeric(t) && isfinite(t) && isscalar(t)
            v = double(t);
        end
    end
catch
end
end

function tf = get_base_logical_or_default(name, defaultVal)
tf = defaultVal;
try
    if evalin('base', sprintf('exist(''%s'',''var'')', name)) ~= 0
        t = evalin('base', name);
        tf = logical(t);
    end
catch
end
end

