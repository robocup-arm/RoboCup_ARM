function suffix = format_color_suffix(obj)
    suffix = "";
    if isfield(obj, "color") && strlength(string(obj.color)) > 0
        suffix = " " + string(obj.color);
        if isfield(obj, "colorScore") && isfinite(obj.colorScore)
            suffix = suffix + sprintf("(%.2f)", obj.colorScore);
        end
    end
end
