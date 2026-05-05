function [selectedId, proceed, abort] = user_command_runtime()
%#codegen
coder.extrinsic('evalin');
coder.extrinsic('assignin');
coder.extrinsic('auto_view_manager');

selectedId = double(0);
proceed = false;
abort = false;

tmpSel = double(0);
tmpProceed = false;
tmpAbort = false;

tmpSel = evalin('base', 'double(USER_SELECTED_ID)');
tmpProceed = evalin('base', 'logical(USER_PROCEED)');
tmpAbort = evalin('base', 'logical(USER_ABORT)');

selectedId = tmpSel;
proceed = tmpProceed;
abort = tmpAbort;

persistent lastResetToken autoCooldownCtr idleReadyStreak stableTargetStreak
persistent lastTargetPos retryCtr
persistent cubeWaitDebugCtr
if isempty(lastResetToken)
    lastResetToken = double(-1);
end
if isempty(autoCooldownCtr)
    autoCooldownCtr = uint16(0);
end
if isempty(idleReadyStreak)
    idleReadyStreak = uint16(0);
end
if isempty(stableTargetStreak)
    stableTargetStreak = uint16(0);
end
if isempty(lastTargetPos)
    lastTargetPos = [NaN; NaN; NaN];
end
if isempty(retryCtr)
    retryCtr = uint16(0);
end
if isempty(cubeWaitDebugCtr)
    cubeWaitDebugCtr = uint16(0);
end

resetToken = double(0);
if evalin('base', 'double(exist(''USER_RESET_TOKEN'',''var''))') ~= 0
    resetToken = evalin('base', 'double(USER_RESET_TOKEN)');
end
if ~isfinite(resetToken)
    resetToken = double(0);
end
if resetToken ~= lastResetToken
    lastResetToken = resetToken;
    autoCooldownCtr = uint16(0);
    idleReadyStreak = uint16(0);
    stableTargetStreak = uint16(0);
    lastTargetPos = [NaN; NaN; NaN];
    retryCtr = uint16(0);
    cubeWaitDebugCtr = uint16(0);
end

autoRun = false;
autoRun = evalin('base', 'logical(USER_AUTO_RUN)');
if ~autoRun
    autoCooldownCtr = uint16(0);
    idleReadyStreak = uint16(0);
    stableTargetStreak = uint16(0);
    lastTargetPos = [NaN; NaN; NaN];
    retryCtr = uint16(0);
    cubeWaitDebugCtr = uint16(0);
    return;
end

% -------- auto loop mode --------
abort = false;
proceed = false;

% Select front-most target by 2D center y (top-down image: larger y is nearer/front).
selectedId = double(1);
numDetForSel = double(0);
if evalin('base', 'double(exist(''VISION_LAST_NUMDET'',''var''))') ~= 0
    numDetForSel = evalin('base', 'double(VISION_LAST_NUMDET)');
end
if isfinite(numDetForSel) && (numDetForSel >= 1) && ...
   (evalin('base', 'double(exist(''VISION_LAST_CENTER2D'',''var''))') ~= 0)
    center2D = evalin('base', 'double(VISION_LAST_CENTER2D)');
    if isnumeric(center2D) && size(center2D,1) >= 2
        bestV = -inf;
        bestId = int32(1);
        Nsel = int32(round(numDetForSel));
        maxCols = int32(size(center2D,2));
        if Nsel > maxCols
            Nsel = maxCols;
        end
        for kk = 1:Nsel
            vv = center2D(2,kk);
            if isfinite(vv) && (vv > bestV)
                bestV = vv;
                bestId = kk;
            end
        end
        selectedId = double(bestId);
    end
end
assignin('base', 'USER_SELECTED_ID', selectedId);

% Clear stale manual proceed latch.
if tmpProceed
    assignin('base', 'USER_PROCEED', false);
end

numDet = double(0);
if evalin('base', 'double(exist(''VISION_LAST_NUMDET'',''var''))') ~= 0
    numDet = evalin('base', 'double(VISION_LAST_NUMDET)');
end
canPick = false;
if evalin('base', 'double(exist(''USER_CAN_PICK'',''var''))') ~= 0
    canPick = evalin('base', 'logical(USER_CAN_PICK)');
end
viewMovePending = false;
if evalin('base', 'double(exist(''USER_VIEW_MOVE_PENDING'',''var''))') ~= 0
    viewMovePending = evalin('base', 'logical(USER_VIEW_MOVE_PENDING)');
end

cubePlaceMode = double(0);
if evalin('base', 'double(exist(''USER_CUBE_PLACE_MODE'',''var''))') ~= 0
    cubePlaceMode = evalin('base', 'double(USER_CUBE_PLACE_MODE)');
end
cubeWaitFreshVision = false;
if evalin('base', 'double(exist(''USER_CUBE_WAIT_FRESH_VISION'',''var''))') ~= 0
    cubeWaitFreshVision = evalin('base', 'logical(USER_CUBE_WAIT_FRESH_VISION)');
end
visionEnable = false;
if evalin('base', 'double(exist(''USER_VISION_ENABLE'',''var''))') ~= 0
    visionEnable = evalin('base', 'logical(USER_VISION_ENABLE)');
end
freshVisionJustArrived = false;

% After the first cube drop, start a synthetic second pick from the scale.
if cubeWaitFreshVision
    assignin('base', 'USER_VISION_ENABLE', false);
    visionEnable = false;
    autoCooldownCtr = uint16(0);
    idleReadyStreak = uint16(0);
    stableTargetStreak = uint16(0);
    lastTargetPos = [NaN; NaN; NaN];
    retryCtr = uint16(0);
    proceed = false;
    if cubeWaitDebugCtr < uint16(65535)
        cubeWaitDebugCtr = cubeWaitDebugCtr + uint16(1);
    end
    if cubeWaitDebugCtr == uint16(1) || mod(double(cubeWaitDebugCtr), 20) == 0 || (numDet >= 1)
        fprintf(['[cube_debug][user_command_wait] ctr=%d mode=%g waitFresh=%d ', ...
            'vision=%d numDet=%g canPick=%d viewPending=%d selectedId=%g reset=%g\n'], ...
            int32(cubeWaitDebugCtr), cubePlaceMode, cubeWaitFreshVision, ...
            visionEnable, numDet, canPick, viewMovePending, selectedId, resetToken);
    end
    if (round(cubePlaceMode) ~= 2) || ~logical(canPick) || logical(viewMovePending)
        return;
    end
    assignin('base', 'USER_CUBE_WAIT_FRESH_VISION', false);
    selectedId = double(1);
    assignin('base', 'USER_SELECTED_ID', selectedId);
    proceed = true;
    fprintf('[cube_debug][user_command_wait] synthetic scale pick proceed: mode=%g selectedId=%g\n', ...
        cubePlaceMode, selectedId);
    cubeWaitDebugCtr = uint16(0);
    return;
end

% Handle automatic viewpoint switch first.
switched = false;
if round(cubePlaceMode) ~= 2
    switched = auto_view_manager(numDet, canPick, autoRun);
end
if switched
    autoCooldownCtr = uint16(0);
    idleReadyStreak = uint16(0);
    stableTargetStreak = uint16(0);
    lastTargetPos = [NaN; NaN; NaN];
    retryCtr = uint16(0);
    proceed = false;
    return;
end

% Tunables (bounded to prevent deadlock).
settleFramesNeed = uint16(120);
if evalin('base', 'double(exist(''USER_AUTO_SETTLE_FRAMES'',''var''))') ~= 0
    t = evalin('base', 'double(USER_AUTO_SETTLE_FRAMES)');
    if isfinite(t) && (t >= 1)
        t = round(t);
        if t < 20
            t = 20;
        end
        if t > 300
            t = 300;
        end
        settleFramesNeed = uint16(t);
    end
end

stableFramesNeed = uint16(3);
if evalin('base', 'double(exist(''USER_AUTO_STABLE_FRAMES'',''var''))') ~= 0
    t = evalin('base', 'double(USER_AUTO_STABLE_FRAMES)');
    if isfinite(t) && (t >= 1)
        t = round(t);
        if t < 2
            t = 2;
        end
        if t > 10
            t = 10;
        end
        stableFramesNeed = uint16(t);
    end
end

stablePosThr = 0.015;
if evalin('base', 'double(exist(''USER_AUTO_STABLE_POS_THR'',''var''))') ~= 0
    t = evalin('base', 'double(USER_AUTO_STABLE_POS_THR)');
    if isfinite(t) && (t > 0)
        if t < 0.005
            t = 0.005;
        end
        if t > 0.05
            t = 0.05;
        end
        stablePosThr = t;
    end
end

retryFrames = uint16(15);   % resend proceed pulse every N idle frames
maxWaitFrames = uint16(180); % timeout fallback if stability never satisfied

if freshVisionJustArrived
    settleFramesNeed = uint16(1);
    stableFramesNeed = uint16(1);
    retryFrames = uint16(1);
end

if autoCooldownCtr < uint16(65535)
    autoCooldownCtr = autoCooldownCtr + uint16(1);
end

idleReady = logical(canPick) && ~logical(viewMovePending);
if idleReady && (numDet >= 1)
    if idleReadyStreak < uint16(65535)
        idleReadyStreak = idleReadyStreak + uint16(1);
    end
    if retryCtr < uint16(65535)
        retryCtr = retryCtr + uint16(1);
    end

    curTargetPos = [NaN; NaN; NaN];
    if evalin('base', 'double(exist(''VISION_LAST_TARGETPOS'',''var''))') ~= 0
        targetPosMat = evalin('base', 'double(VISION_LAST_TARGETPOS)');
        if isnumeric(targetPosMat) && size(targetPosMat,1) >= 3
            idx = int32(round(selectedId));
            if idx < int32(1)
                idx = int32(1);
            end
            cols = int32(size(targetPosMat,2));
            if idx <= cols
                curTargetPos = targetPosMat(:, idx);
            end
        end
    end

    if numel(curTargetPos) == 3 && all(isfinite(curTargetPos))
        if all(isfinite(lastTargetPos)) && (norm(curTargetPos(:) - lastTargetPos(:)) <= stablePosThr)
            if stableTargetStreak < uint16(65535)
                stableTargetStreak = stableTargetStreak + uint16(1);
            end
        else
            stableTargetStreak = uint16(1);
        end
        lastTargetPos = curTargetPos(:);
    else
        stableTargetStreak = uint16(0);
        lastTargetPos = [NaN; NaN; NaN];
    end
else
    idleReadyStreak = uint16(0);
    stableTargetStreak = uint16(0);
    lastTargetPos = [NaN; NaN; NaN];
    retryCtr = uint16(0);
end

baseReady = (autoCooldownCtr >= settleFramesNeed) && idleReady && (numDet >= 1);
stableReady = (stableTargetStreak >= stableFramesNeed);
timeoutReady = (idleReadyStreak >= maxWaitFrames);
retryReady = (retryCtr >= retryFrames);

% Retrigger proceed periodically while waiting in auto mode.
if baseReady && retryReady && (stableReady || timeoutReady)
    proceed = true;
    retryCtr = uint16(0);
    assignin('base', 'USER_SELECTED_ID', selectedId);
    if round(cubePlaceMode) == 2 || freshVisionJustArrived
        fprintf(['[cube_debug][user_command_proceed] mode=%g numDet=%g ', ...
            'selectedId=%g baseReady=%d stableReady=%d timeoutReady=%d ', ...
            'idle=%d cooldown=%d settle=%d stable=%d/%d\n'], ...
            cubePlaceMode, numDet, selectedId, baseReady, stableReady, timeoutReady, ...
            idleReady, int32(autoCooldownCtr), int32(settleFramesNeed), ...
            int32(stableTargetStreak), int32(stableFramesNeed));
    end
end
end
