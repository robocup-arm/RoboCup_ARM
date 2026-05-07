function v = get_info_field(s, fieldName, defaultValue)
    v = defaultValue;
    if ~isstruct(s)
        return;
    end
    if isfield(s, fieldName)
        t = s.(fieldName);
        if ~isempty(t)
            v = t;
        end
    end
end
