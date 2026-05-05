function tf = has_pending_view_move_runtime()
tf = false;
try
    if evalin('base', 'exist(''USER_VIEW_MOVE_PENDING'',''var'')') ~= 0
        tf = logical(evalin('base', 'USER_VIEW_MOVE_PENDING'));
    end
catch
    tf = false;
end
end
