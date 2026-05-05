function mode = get_cube_place_mode_runtime()
mode = double(0);
try
    if evalin('base', 'exist(''USER_CUBE_PLACE_MODE'',''var'')') ~= 0
        mode = double(evalin('base', 'USER_CUBE_PLACE_MODE'));
    end
catch
    mode = double(0);
end
end
