function finish_view_move_runtime(currentConfig)
assignin('base', 'USER_QHOME_CURRENT', double(currentConfig(:)));
try
    if evalin('base', 'exist(''USER_VIEW_IDX_NEXT'',''var'')') ~= 0
        idxNext = double(evalin('base', 'USER_VIEW_IDX_NEXT'));
        assignin('base', 'USER_VIEW_IDX', idxNext);
    end
catch
end
assignin('base', 'USER_VIEW_MOVE_PENDING', false);
assignin('base', 'USER_VISION_ENABLE', true);
end
