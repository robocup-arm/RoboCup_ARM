function qNext = get_qhome_next_runtime(defaultQ)
qNext = double(defaultQ(:));
try
    if evalin('base', 'exist(''USER_QHOME_NEXT'',''var'')') ~= 0
        tmp = double(evalin('base', 'USER_QHOME_NEXT'));
        if numel(tmp) == 6 && all(isfinite(tmp(:)))
            qNext = tmp(:);
        end
    end
catch
end
end
