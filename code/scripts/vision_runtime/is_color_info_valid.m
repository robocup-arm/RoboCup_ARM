function tf = is_color_info_valid(info)
    tf = isstruct(info) && isfield(info, "label") && strlength(string(info.label)) > 0 && ...
        isfield(info, "score") && isfinite(info.score);
end
