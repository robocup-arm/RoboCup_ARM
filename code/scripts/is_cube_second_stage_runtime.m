function tf = is_cube_second_stage_runtime()
tf = false;
try
    if evalin('base', 'exist(''USER_CUBE_PLACE_MODE'',''var'')') ~= 0
        mode = double(evalin('base', 'USER_CUBE_PLACE_MODE'));
        tf = (round(mode) == 2);
    end
catch
    tf = false;
end
end
