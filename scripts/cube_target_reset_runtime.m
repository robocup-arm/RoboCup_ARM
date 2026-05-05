function cube_target_reset_runtime()
mode = double(0);
try
    if evalin('base', 'exist(''USER_CUBE_PLACE_MODE'',''var'')') ~= 0
        mode = double(evalin('base', 'USER_CUBE_PLACE_MODE'));
    end
catch
    mode = double(0);
end

if mode == 1
    assignin('base', 'USER_CUBE_ACTIVE', true);
    assignin('base', 'USER_CUBE_SECOND_PICK_PENDING', false);
    assignin('base', 'USER_CUBE_PLACE_MODE', 2);
    assignin('base', 'USER_CUBE_WAIT_FRESH_VISION', true);
    assignin('base', 'USER_VISION_ENABLE', false);
    fprintf('[cube_debug][cube_target_reset_runtime] token reset: mode 1 -> 2, synthetic scale pick enabled\n');
elseif mode == 2
    assignin('base', 'USER_CUBE_ACTIVE', false);
    assignin('base', 'USER_CUBE_SECOND_PICK_PENDING', false);
    assignin('base', 'USER_CUBE_PLACE_MODE', 0);
    assignin('base', 'USER_CUBE_WAIT_FRESH_VISION', false);
    assignin('base', 'USER_CUBE_USE_SECOND_HOME', false);
    fprintf('[cube_debug][cube_target_reset_runtime] token reset: mode 2 -> 0, clear cube state\n');
end
end
