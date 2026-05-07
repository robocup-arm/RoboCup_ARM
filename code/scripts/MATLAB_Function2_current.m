function [targetPos, yawCandidates, valid] = TargetSelect(targetPosList, yawList, numDet, selectedId, proceed, reset)
%#codegen
coder.extrinsic('evalin');
coder.extrinsic('assignin');
coder.extrinsic('fprintf');
coder.extrinsic('cube_target_reset_runtime');
coder.extrinsic('get_cube_place_mode_runtime');

targetPos = zeros(3,1);
yawCandidates = zeros(1,2);
valid = false;

persistent locked latchedTarget latchedYaw lastProceed lastResetToken

if isempty(locked)
    locked = false;
end
if isempty(latchedTarget)
    latchedTarget = zeros(3,1);
end
if isempty(latchedYaw)
    latchedYaw = zeros(1,2);
end
if isempty(lastProceed)
    lastProceed = false;
end
if isempty(lastResetToken)
    lastResetToken = double(0);
end

resetToken = double(0);
resetToken = evalin('base', 'double(USER_RESET_TOKEN)');
tokenReset = (resetToken ~= lastResetToken);

if reset
    locked = false;
    valid = false;
    assignin('base', 'USER_CUBE_ACTIVE', false);
    assignin('base', 'USER_CUBE_SECOND_PICK_PENDING', false);
    assignin('base', 'USER_CUBE_PLACE_MODE', 0);
    assignin('base', 'USER_CUBE_USE_SECOND_HOME', false);
    lastProceed = logical(proceed);
    lastResetToken = resetToken;
    return;
end

if tokenReset
    locked = false;
    valid = false;
    cube_target_reset_runtime();
    lastProceed = logical(proceed);
    lastResetToken = resetToken;
    return;
end


if locked
    targetPos = latchedTarget;
    yawCandidates = latchedYaw;
    valid = true;
    lastProceed = logical(proceed);
    lastResetToken = resetToken;
    return;
end

proceedRise = logical(proceed) && ~logical(lastProceed);
cubePlaceMode = double(0);
cubePlaceMode = get_cube_place_mode_runtime();

if proceedRise && cubePlaceMode == 2
    latchedTarget = [0.799; 0.4; -0.052];
    latchedYaw = [0, 0];

    locked = true;
    assignin('base', 'USER_ACTIVE_TARGET_POS', double(latchedTarget));
    assignin('base', 'USER_ACTIVE_SELECTED_ID', double(1));
    assignin('base', 'USER_CUBE_WAIT_FRESH_VISION', false);
    assignin('base', 'USER_VISION_ENABLE', false);

    targetPos = latchedTarget;
    yawCandidates = latchedYaw;
    valid = true;

    fprintf(['[target_select] SYNTHETIC CUBE SCALE PICK ', ...
        'targetPos=[%.4f %.4f %.4f] yaw=[%.4f %.4f]\n'], ...
        targetPos(1), targetPos(2), targetPos(3), ...
        yawCandidates(1), yawCandidates(2));

elseif proceedRise && selectedId >= 1 && selectedId <= numDet
    latchedTarget = targetPosList(:, selectedId);
    latchedYaw = yawList(:, selectedId).';
    locked = true;

    assignin('base', 'USER_ACTIVE_TARGET_POS', double(latchedTarget));
    assignin('base', 'USER_ACTIVE_SELECTED_ID', double(selectedId));
    assignin('base', 'USER_CUBE_LATCHED_YAW', double(latchedYaw));
    assignin('base', 'USER_VISION_ENABLE', false);

    targetPos = latchedTarget;
    yawCandidates = latchedYaw;
    valid = true;

    fprintf(['[target_select] LATCH selectedId=%d numDet=%d ', ...
        'targetPos=[%.4f %.4f %.4f] yaw=[%.4f %.4f]\n'], ...
        int32(selectedId), int32(numDet), ...
        targetPos(1), targetPos(2), targetPos(3), ...
        yawCandidates(1), yawCandidates(2));
end

lastProceed = logical(proceed);
lastResetToken = resetToken;
end
