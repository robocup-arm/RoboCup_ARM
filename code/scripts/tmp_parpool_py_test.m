cd(''F:/robocup/project_v3/RoboCup_ARM/RoboCup_ARM/scripts'');
try
    p = gcp(''nocreate'');
    if isempty(p)
        p = parpool(''Processes'',1);
    end
    f = parfeval(p, @worker_py_providers, 1);
    wait(f);
    out = fetchOutputs(f);
    disp(out{1});
catch ME
    disp(getReport(ME,''basic'',''hyperlinks'',''off''));
end

function s = worker_py_providers()
    ort = py.importlib.import_module(''onnxruntime'');
    s = char(string(py.builtins.repr(ort.get_available_providers())));
end
