function finish_drop_reset_runtime()
try
    resetToken = double(evalin('base', 'USER_RESET_TOKEN'));
catch
    resetToken = double(0);
end
assignin('base', 'USER_RESET_TOKEN', resetToken + 1);
assignin('base', 'USER_AUTO_NEED_RESET', false);
assignin('base', 'USER_PROCEED', false);
assignin('base', 'USER_ABORT', false);
end
