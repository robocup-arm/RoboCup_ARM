function s = withDefaults(s, defaults)
    f = fieldnames(defaults);
    for i = 1:numel(f)
        if ~isfield(s, f{i})
            s.(f{i}) = defaults.(f{i});
        end
    end
end

%% ---------------- color helpers ----------------
