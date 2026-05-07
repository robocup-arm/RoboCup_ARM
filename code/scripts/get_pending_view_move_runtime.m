function [hasPending, qNext] = get_pending_view_move_runtime()
hasPending = false;
qNext = zeros(6,1);
try
    if evalin('base', 'exist(''USER_VIEW_MOVE_PENDING'',''var'')') ~= 0
        hasPending = logical(evalin('base', 'USER_VIEW_MOVE_PENDING'));
    end
    if hasPending && evalin('base', 'exist(''USER_QHOME_NEXT'',''var'')') ~= 0
        tmp = double(evalin('base', 'USER_QHOME_NEXT'));
        if numel(tmp) == 6 && all(isfinite(tmp(:)))
            qNext = tmp(:);
        else
            hasPending = false;
        end
    end
catch
    hasPending = false;
    qNext = zeros(6,1);
end
end
