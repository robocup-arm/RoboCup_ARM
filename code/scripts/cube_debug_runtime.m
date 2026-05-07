function cube_debug_runtime(eventCode, stateCode, canPick, startGrasp, currentConfig)
% Runtime-only debug logging for the cube scale handoff.
persistent waitCtr
if isempty(waitCtr)
    waitCtr = uint32(0);
end

mode = read_base_double('USER_CUBE_PLACE_MODE', -1);
waitFresh = read_base_logical('USER_CUBE_WAIT_FRESH_VISION', false);
visionEnable = read_base_logical('USER_VISION_ENABLE', false);
numDet = read_base_double('VISION_LAST_NUMDET', -1);
viewPending = read_base_logical('USER_VIEW_MOVE_PENDING', false);
resetToken = read_base_double('USER_RESET_TOKEN', -1);

if eventCode == 10
    waitCtr = waitCtr + uint32(1);
    if waitCtr == 1 || mod(double(waitCtr), 20) == 0 || waitFresh
        fprintf(['[cube_debug][grc_wait] state=%d mode=%g waitFresh=%d ', ...
            'vision=%d numDet=%g canPick=%d startGrasp=%d viewPending=%d ', ...
            'reset=%g q=[%.4f %.4f %.4f %.4f %.4f %.4f]\n'], ...
            int32(stateCode), mode, waitFresh, visionEnable, numDet, ...
            logical(canPick), logical(startGrasp), viewPending, resetToken, ...
            currentConfig(1), currentConfig(2), currentConfig(3), ...
            currentConfig(4), currentConfig(5), currentConfig(6));
    end
elseif eventCode == 20
    waitCtr = uint32(0);
    fprintf(['[cube_debug][first_drop] mode=%g waitFresh=%d vision=%d ', ...
        'numDet=%g reset=%g q=[%.4f %.4f %.4f %.4f %.4f %.4f]\n'], ...
        mode, waitFresh, visionEnable, numDet, resetToken, ...
        currentConfig(1), currentConfig(2), currentConfig(3), ...
        currentConfig(4), currentConfig(5), currentConfig(6));
elseif eventCode == 30
    fprintf(['[cube_debug][start_grasp] mode=%g waitFresh=%d vision=%d ', ...
        'numDet=%g reset=%g q=[%.4f %.4f %.4f %.4f %.4f %.4f]\n'], ...
        mode, waitFresh, visionEnable, numDet, resetToken, ...
        currentConfig(1), currentConfig(2), currentConfig(3), ...
        currentConfig(4), currentConfig(5), currentConfig(6));
elseif eventCode == 40
    fprintf(['[cube_debug][return_done] mode=%g waitFresh=%d vision=%d ', ...
        'numDet=%g reset=%g q=[%.4f %.4f %.4f %.4f %.4f %.4f]\n'], ...
        mode, waitFresh, visionEnable, numDet, resetToken, ...
        currentConfig(1), currentConfig(2), currentConfig(3), ...
        currentConfig(4), currentConfig(5), currentConfig(6));
end
end

function v = read_base_double(name, defaultVal)
v = defaultVal;
try
    if evalin('base', sprintf('exist(''%s'',''var'')', name)) ~= 0
        t = evalin('base', name);
        if isnumeric(t) && isscalar(t)
            v = double(t);
        end
    end
catch
end
end

function tf = read_base_logical(name, defaultVal)
tf = defaultVal;
try
    if evalin('base', sprintf('exist(''%s'',''var'')', name)) ~= 0
        tf = logical(evalin('base', name));
    end
catch
end
end
