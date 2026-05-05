function [pickTraj, placeTraj, startGrasp] = planner(targetPos, yawCandidates, valid, reset)
%#codegen

coder.extrinsic('planner_core');
coder.extrinsic('evalin');
coder.extrinsic('fprintf');

pickTraj   = zeros(6,251);
placeTraj  = zeros(6,351);
startGrasp = false;

persistent lastValid planned latchedPick latchedPlace lastResetToken

if isempty(lastValid)
    lastValid = false;
end
if isempty(planned)
    planned = false;
end
if isempty(latchedPick)
    latchedPick = zeros(6,251);
end
if isempty(latchedPlace)
    latchedPlace = zeros(6,351);
end
if isempty(lastResetToken)
    lastResetToken = double(0);
end

resetToken = double(0);
resetToken = evalin('base', 'double(USER_RESET_TOKEN)');
tokenReset = (resetToken ~= lastResetToken);

% reset from manual abort or from auto-loop token
if reset || tokenReset
    planned = false;
    lastValid = false;
    latchedPick  = zeros(6,251);
    latchedPlace = zeros(6,351);
    lastResetToken = resetToken;

    dbgprintf('[planner] reset -> clear latched trajectories\n');
    return;
end

% one pulse when target becomes valid
startGrasp = logical(valid) && ~logical(lastValid);

% plan once then latch
if startGrasp && ~planned
    fprintf(['[planner_start] startGrasp=1 targetPos=[%.4f %.4f %.4f] ', ...
        'yaw=[%.4f %.4f]\n'], ...
        targetPos(1), targetPos(2), targetPos(3), ...
        yawCandidates(1), yawCandidates(2));
    [latchedPick, latchedPlace] = planner_core(targetPos, yawCandidates, true);
    planned = true;
    dbgprintf('[planner] trajectory planned and latched once.\n');
end

if planned
    pickTraj  = latchedPick;
    placeTraj = latchedPlace;
else
    [pickTraj, placeTraj] = planner_core(targetPos, yawCandidates, false);
end

dbgprintf('[planner] valid=%.0f lastValid=%.0f startGrasp=%.0f planned=%.0f\n', ...
    double(valid), double(lastValid), double(startGrasp), double(planned));

lastValid = logical(valid);
lastResetToken = resetToken;

end

function dbgprintf(varargin)
% suppress per-step console output
end
