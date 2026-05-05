function imgRes = vision_async_worker(rgb, depth, K, thisDir, runtimeDir, geomDir, modelDir)
persistent workerInited
if isempty(workerInited)
    if nargin >= 4 && ~isempty(thisDir) && isfolder(thisDir)
        addpath(thisDir);
    end
    if nargin >= 5 && ~isempty(runtimeDir) && isfolder(runtimeDir)
        addpath(runtimeDir);
    end
    if nargin >= 6 && ~isempty(geomDir) && isfolder(geomDir)
        addpath(geomDir);
    end
    if nargin >= 7 && ~isempty(modelDir) && isfolder(modelDir)
        addpath(modelDir);
    end
    workerInited = true;
end

if exist('run_recognition_frame', 'file') == 2
    imgRes = run_recognition_frame(rgb, depth, K);
    return;
end

if exist('parallel_recognition_singleframe', 'file') == 2
    imgRes = parallel_recognition_singleframe(rgb, depth, K);
    return;
end

error('vision_async_worker:entry_missing', 'run_recognition_frame not found on worker path.');
end
