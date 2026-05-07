function [gripperStatus, currentConfig, stop] = main(pickTraj, placeTraj, targetGrasped, startGrasp)
%#codegen
coder.extrinsic('assignin');
coder.extrinsic('get_cube_place_mode_runtime');
coder.extrinsic('get_user_qhome_current_runtime');
coder.extrinsic('cube_first_drop_runtime');
coder.extrinsic('finish_drop_reset_runtime');
coder.extrinsic('has_pending_view_move_runtime');
coder.extrinsic('finish_view_move_runtime');
coder.extrinsic('get_qhome_next_runtime');
coder.extrinsic('cube_debug_runtime');

stop = false;
gripperStatus = 0;

persistent state index delay waitStableCount viewMoveTraj viewMoveIndex viewMoveMode holdConfig holdValid

if isempty(state)
    state = 0;
end
if isempty(index)
    index = 1;
end
if isempty(delay)
    delay = 1;
end
if isempty(waitStableCount)
    waitStableCount = uint16(0);
end
if isempty(viewMoveTraj)
    viewMoveTraj = zeros(6,120);
end
if isempty(viewMoveIndex)
    viewMoveIndex = 1;
end
if isempty(viewMoveMode)
    viewMoveMode = 0;
end
if isempty(holdConfig)
    holdConfig = zeros(6,1);
end
if isempty(holdValid)
    holdValid = false;
end

DROP_SETTLE_TICKS = 20;
OPEN_SETTLE_TICKS = 30;
RETURN_STEPS = 120;

nPick = size(pickTraj, 2);
nPlace = size(placeTraj, 2);

currentConfig = pickTraj(:,1);

canPick = false;
if state == 0
    if waitStableCount < uint16(65535)
        waitStableCount = waitStableCount + uint16(1);
    end
    canPick = (waitStableCount >= uint16(20));
else
    waitStableCount = uint16(0);
end
assignin('base', 'USER_CAN_PICK', canPick);

if state == 0
    gripperStatus = 0;
    assignin('base', 'USER_VISION_ENABLE', true);
    if holdValid
        currentConfig = holdConfig;
    else
        currentConfig = pickTraj(:,1);
        holdConfig = currentConfig;
        holdValid = true;
    end
    cube_debug_runtime(10, state, canPick, startGrasp, currentConfig);

    hasPendingViewMove = false;
    hasPendingViewMove = has_pending_view_move_runtime();
    qNextView = currentConfig;
    if hasPendingViewMove
        qNextView = get_qhome_next_runtime(currentConfig);
        qStart = currentConfig;
        for k = 1:120
            alpha = (k-1) / (RETURN_STEPS-1);
            viewMoveTraj(:,k) = (1-alpha)*qStart + alpha*qNextView;
        end
        viewMoveIndex = 1;
        viewMoveMode = 1;
        holdValid = false;
        state = 6;
        waitStableCount = uint16(0);
        assignin('base', 'USER_VISION_ENABLE', false);
        return;
    end

    if startGrasp
        cube_debug_runtime(30, state, canPick, startGrasp, currentConfig);
        assignin('base', 'USER_VISION_ENABLE', false);
        state = 1;
        index = 1;
        delay = 1;
        waitStableCount = uint16(0);
        holdValid = false;
    end
    return;
end

if state == 1
    gripperStatus = 0;
    assignin('base', 'USER_VISION_ENABLE', false);
    currentConfig = pickTraj(:, index);
    holdConfig = currentConfig;
    holdValid = true;
    index = index + 1;
    if index > nPick
        state = 2;
        index = nPick;
    end

elseif state == 2
    gripperStatus = 1;
    assignin('base', 'USER_VISION_ENABLE', false);
    currentConfig = pickTraj(:, index);
    holdConfig = currentConfig;
    holdValid = true;
    if targetGrasped
        state = 3;
        index = 1;
    end

elseif state == 3
    gripperStatus = 1;
    assignin('base', 'USER_VISION_ENABLE', false);
    currentConfig = placeTraj(:, index);
    holdConfig = currentConfig;
    holdValid = true;
    index = index + 1;
    if index > nPlace
        state = 7;
        index = nPlace;
        delay = 1;
    end

elseif state == 7
    gripperStatus = 1;
    assignin('base', 'USER_VISION_ENABLE', false);
    currentConfig = placeTraj(:, index);
    holdConfig = currentConfig;
    holdValid = true;
    if delay <= DROP_SETTLE_TICKS
        delay = delay + 1;
    else
        state = 4;
    end

elseif state == 4
    gripperStatus = 0;
    assignin('base', 'USER_VISION_ENABLE', false);
    currentConfig = placeTraj(:, index);
    holdConfig = currentConfig;
    holdValid = true;
    state = 5;
    delay = 1;

elseif state == 5
    gripperStatus = 0;
    assignin('base', 'USER_VISION_ENABLE', false);
    currentConfig = placeTraj(:, index);
    holdConfig = currentConfig;
    holdValid = true;

    if delay <= OPEN_SETTLE_TICKS
        delay = delay + 1;
        return;
    end

    cubePlaceMode = 0;
    cubePlaceMode = get_cube_place_mode_runtime();

    if cubePlaceMode == 1
        cube_first_drop_runtime(currentConfig);
        cube_debug_runtime(20, state, canPick, startGrasp, currentConfig);
        holdConfig = currentConfig;
        holdValid = true;
        state = 0;
        index = 1;
        delay = 1;
        waitStableCount = uint16(0);
        return;
    end

    qHomeNow = pickTraj(:,1);
    if cubePlaceMode == 2
        qHomeNow = get_user_qhome_current_runtime(qHomeNow);
    end

    qStart = currentConfig;
    for k = 1:120
        alpha = (k-1) / (RETURN_STEPS-1);
        viewMoveTraj(:,k) = (1-alpha)*qStart + alpha*qHomeNow;
    end
    viewMoveIndex = 1;
    viewMoveMode = 0;
    holdValid = false;
    state = 6;
    index = 1;
    delay = 1;
    waitStableCount = uint16(0);

elseif state == 6
    gripperStatus = 0;
    assignin('base', 'USER_VISION_ENABLE', false);
    currentConfig = viewMoveTraj(:, viewMoveIndex);
    holdConfig = currentConfig;
    holdValid = true;
    viewMoveIndex = viewMoveIndex + 1;
    if viewMoveIndex > 120
        currentConfig = viewMoveTraj(:,120);
        holdConfig = currentConfig;
        holdValid = true;
        if viewMoveMode == 1
            finish_view_move_runtime(currentConfig);
        else
            finish_drop_reset_runtime();
            assignin('base', 'USER_VISION_ENABLE', true);
        end
        cube_debug_runtime(40, state, canPick, startGrasp, currentConfig);
        state = 0;
        viewMoveIndex = 1;
        viewMoveMode = 0;
        waitStableCount = uint16(0);
    end
end
end
