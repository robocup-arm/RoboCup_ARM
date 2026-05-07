function cube_first_drop_runtime(currentConfig)
try
    resetToken = double(evalin('base', 'USER_RESET_TOKEN'));
catch
    resetToken = double(0);
end

assignin('base', 'USER_CUBE_SECOND_HOME', double(currentConfig(:)));
assignin('base', 'USER_CUBE_USE_SECOND_HOME', true);
assignin('base', 'USER_CUBE_WAIT_FRESH_VISION', true);

% Force the second stage to wait for a fresh vision result from the scale.
assignin('base', 'VISION_LAST_NUMDET', 0);
assignin('base', 'USER_SELECTED_ID', 0);
assignin('base', 'USER_PROCEED', false);
assignin('base', 'USER_ABORT', false);
assignin('base', 'USER_AUTO_NEED_RESET', false);
assignin('base', 'USER_VISION_ENABLE', true);

assignin('base', 'USER_RESET_TOKEN', resetToken + 1);
fprintf(['[cube_debug][cube_first_drop_runtime] set secondHome, waitFresh=1, ', ...
    'vision=1, reset %g -> %g, q=[%.4f %.4f %.4f %.4f %.4f %.4f]\n'], ...
    resetToken, resetToken + 1, currentConfig(1), currentConfig(2), ...
    currentConfig(3), currentConfig(4), currentConfig(5), currentConfig(6));
end
