function q = get_user_qhome_current_runtime(defaultQ)
q = double(defaultQ(:));
try
    if evalin('base', 'exist(''USER_QHOME_CURRENT'',''var'')') ~= 0
        tmp = double(evalin('base', 'USER_QHOME_CURRENT'));
        if isnumeric(tmp) && numel(tmp) == 6 && all(isfinite(tmp(:)))
            q = tmp(:);
        end
    end
catch
end
end
