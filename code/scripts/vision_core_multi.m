function [targetPosList, yawList, bboxList, classIdList, scoreList, centerList, numDet] = ...
    vision_core_multi(Image, Depth, CameraTform)

persistent inited verbose recogStride dropPartial frameCount ...
    asyncEnabled asyncPeriodSec asyncTimeoutSec asyncFuture asyncLastLaunchTic asyncPool ...
    asyncThisDir asyncRuntimeDir asyncGeomDir asyncModelDir ...
    camFrameFixR basePosBias ...
    cubeEdgeGuardEnable cubeEdgeGuardRect cubeEdgeGuardMargin cubeEdgeGuardYawFlip ...
    cacheValid cacheTargetPosList cacheYawList cacheBboxList ...
    cacheClassIdList cacheScoreList cacheCenterList cacheNumDet ...
    cacheColorIdList cacheColorPointsList cacheAbIdList cacheAxis3DList ...
    cubeDiagCtr
if isempty(inited)
    thisFile = mfilename('fullpath');
    thisDir = fileparts(thisFile);
    runtimeDir = fullfile(thisDir, 'vision_runtime');

    addpath(thisDir);
    geomDir = fullfile(thisDir, 'vision_geom');
    modelDir = fullfile(thisDir, 'model');
    if isfolder(runtimeDir)
        addpath(runtimeDir);
    end
    if isfolder(geomDir)
        addpath(geomDir);
    end
    if isfolder(modelDir)
        addpath(modelDir);
    end

    verbose = get_env_bool_local("VISION_VERBOSE", false);

    % recogStride = get_env_int_local("VISION_RECOG_STRIDE", 3);
    % if recogStride < 1
    %     recogStride = 1;
    % end

    recogStride = 1;

    dropPartial = get_env_bool_local("VISION_DROP_PARTIAL", true);
    frameCount = uint64(0);
    asyncEnabled = get_env_bool_local("VISION_ASYNC_ENABLE", false);
    asyncPeriodSec = get_env_double_local("VISION_ASYNC_PERIOD_SEC", 0.08);
    if ~isfinite(asyncPeriodSec) || asyncPeriodSec < 0
        asyncPeriodSec = 0.08;
    end
    asyncTimeoutSec = get_env_double_local("VISION_ASYNC_TIMEOUT_SEC", 1.50);
    if ~isfinite(asyncTimeoutSec) || asyncTimeoutSec <= 0
        asyncTimeoutSec = 1.50;
    end
    asyncFuture = [];
    asyncLastLaunchTic = [];
    asyncPool = [];
    asyncThisDir = thisDir;
    asyncRuntimeDir = runtimeDir;
    asyncGeomDir = geomDir;
    asyncModelDir = modelDir;
    camFrameFixR = get_cam_frame_fix_local();
    basePosBias = get_env_vec3_local("VISION_BASE_BIAS", [0;0;0]);
    basePosBias = ensure_vec3_local(basePosBias, [0;0;0]);
    [cubeEdgeGuardEnable, cubeEdgeGuardRect, cubeEdgeGuardMargin, cubeEdgeGuardYawFlip] = ...
        get_cube_edge_guard_params_local(true, [0.249, 0.549, -0.790, -0.410], 0.050, false);

    if asyncEnabled
        try
            asyncPool = ensure_process_pool_local(verbose);
            if verbose
                fprintf('[vision_core_multi] async vision enabled (period=%.3fs timeout=%.2fs).\n', ...
                    asyncPeriodSec, asyncTimeoutSec);
            end
        catch ME
            asyncEnabled = false;
            if verbose
                fprintf('[vision_core_multi] async disabled (pool init failed): %s\n', ME.message);
            end
        end
    end

    cacheValid = false;
    cacheTargetPosList = zeros(3,20);
    cacheYawList = zeros(2,20);
    cacheBboxList = zeros(4,20);
    cacheClassIdList = zeros(1,20);
    cacheScoreList = zeros(1,20);
    cacheCenterList = zeros(2,20);
    cacheColorIdList = zeros(1,20);
    cacheColorPointsList = nan(1,20);
    cacheAbIdList = zeros(1,20);
    cacheAxis3DList = zeros(3,20);
    cacheNumDet = 0;
    cubeDiagCtr = uint32(0);

    if verbose
        fprintf('[vision_core_multi] camera frame fix R =\n');
        disp(camFrameFixR);
        fprintf('[vision_core_multi] base position bias = [%.6f %.6f %.6f]\n', ...
            basePosBias(1), basePosBias(2), basePosBias(3));
    end

    inited = true;
end

MAXDET = 20;

% Refresh guard parameters every frame so world/config switches are applied
% without requiring clear/restart.
[cubeEdgeGuardEnable, cubeEdgeGuardRect, cubeEdgeGuardMargin, cubeEdgeGuardYawFlip] = ...
    get_cube_edge_guard_params_local(cubeEdgeGuardEnable, cubeEdgeGuardRect, cubeEdgeGuardMargin, cubeEdgeGuardYawFlip);

visionEnabled = true;
try
    if evalin('base', 'exist(''USER_VISION_ENABLE'',''var'')') ~= 0
        visionEnabled = logical(evalin('base', 'USER_VISION_ENABLE'));
    end
catch
    visionEnabled = true;
end

targetPosList = zeros(3,MAXDET);
yawList       = zeros(2,MAXDET);
bboxList      = zeros(4,MAXDET);
classIdList   = zeros(1,MAXDET);
scoreList     = zeros(1,MAXDET);
colorIdList   = zeros(1,MAXDET);
colorPointsList = nan(1,MAXDET);
abIdList      = zeros(1,MAXDET);
axis3DList    = zeros(3,MAXDET);
centerList    = zeros(2,MAXDET);   % 鐪熷疄鎶撳彇鐐规姇褰憋紝涓嶅啀鏄?bbox 涓績
numDet        = 0;

if ~visionEnabled
    cacheValid = false;

    publish_last_det_to_base_local( ...
        targetPosList, yawList, bboxList, classIdList, scoreList, centerList, numDet, ...
        colorIdList, colorPointsList, abIdList, axis3DList);

    return;
end

cacheValid = false;

if isempty(Image) || isempty(Depth) || isempty(CameraTform)
    if verbose
        fprintf('[vision_core_multi] empty input.\n');
    end
    publish_last_det_to_base_local(targetPosList, yawList, bboxList, classIdList, scoreList, centerList, numDet, colorIdList, colorPointsList, abIdList, axis3DList);
    return;
end

rgb = Image;
if ~isa(rgb,'uint8')
    rgb = uint8(rgb);
end

depth = double(Depth);
if isa(Depth,'uint16')
    depth = depth / 1000.0;
end

Tcb = double(CameraTform);   % camera -> base
if ~isequal(size(Tcb), [4 4])
    if verbose
        fprintf('[vision_core_multi] CameraTform size invalid: %s\n', mat2str(size(Tcb)));
    end
    publish_last_det_to_base_local(targetPosList, yawList, bboxList, classIdList, scoreList, centerList, numDet, colorIdList, colorPointsList, abIdList, axis3DList);
    return;
end
if any(abs(Tcb(:)) > 1e-12)
    try
        assignin('base', 'VISION_LAST_TCB', Tcb);
    catch
    end
end

frameCount = frameCount + 1;
if ~asyncEnabled && recogStride > 1 && cacheValid
    if mod(double(frameCount) - 1, recogStride) ~= 0
        targetPosList = cacheTargetPosList;
        yawList       = cacheYawList;
        bboxList      = cacheBboxList;
        classIdList   = cacheClassIdList;
        scoreList     = cacheScoreList;
        colorIdList   = cacheColorIdList;
        colorPointsList = cacheColorPointsList;
        abIdList      = cacheAbIdList;
        axis3DList    = cacheAxis3DList;
        centerList    = cacheCenterList;
        numDet        = cacheNumDet;
        publish_last_det_to_base_local(targetPosList, yawList, bboxList, classIdList, scoreList, centerList, numDet, colorIdList, colorPointsList, abIdList, axis3DList);
        return;
    end
end

if verbose
    fprintf('\n================ vision_core_multi ================\n');
    fprintf('[vision_core_multi] CameraTform =\n');
    disp(Tcb);
    if any(abs(camFrameFixR - eye(3,3)) > 1e-12, "all")
        fprintf('[vision_core_multi] applying frame-fix rotation to center3D before CameraTform.\n');
    end
    if any(abs(basePosBias) > 1e-12)
        fprintf('[vision_core_multi] applying base bias [%.6f %.6f %.6f]\n', ...
            basePosBias(1), basePosBias(2), basePosBias(3));
    end
end

% -------- intrinsics --------
K = [1109 0 640;
     0 1109 360;
     0 0 1];
fx = K(1,1); fy = K(2,2);
cx = K(1,3); cy = K(2,3);

if verbose
    fprintf('[vision_core_multi] intrinsics: fx=%.3f fy=%.3f cx=%.3f cy=%.3f\n', ...
        fx, fy, cx, cy);
end

% ============================================================
% 鍏抽敭锛氳繖閲屼笉鍐嶈嚜宸辩敤 bbox 涓績鍙嶆姇褰?
% 鑰屾槸鐩存帴璧?璇嗗埆 + 鐐逛簯鍑犱綍鎷熷悎"寰楀埌姣忎釜鐩爣鐨?center3D / center2D
% ============================================================
if asyncEnabled
    hasFreshResult = false;
    imgRes = struct();

    if ~isempty(asyncFuture)
        stateTxt = "";
        try
            stateTxt = lower(string(asyncFuture.State));
        catch
            stateTxt = "unknown";
        end

        if stateTxt == "finished"
            try
                outs = fetchOutputs(asyncFuture);
                if ~isempty(outs)
                    if iscell(outs)
                        imgRes = outs{1};
                    else
                        imgRes = outs;
                    end
                    hasFreshResult = true;
                end
            catch ME
                if verbose
                    fprintf('[vision_core_multi] async fetch failed: %s\n', ME.message);
                    print_future_error_local(asyncFuture);
                end
                asyncEnabled = false;
                imgRes = run_recognition_frame_adapter(rgb, depth, K);
                hasFreshResult = true;
            end
            asyncFuture = [];
            asyncLastLaunchTic = [];
        elseif stateTxt == "failed"
            if verbose
                fprintf('[vision_core_multi] async worker failed, fallback sync.\n');
                print_future_error_local(asyncFuture);
            end
            asyncEnabled = false;
            imgRes = run_recognition_frame_adapter(rgb, depth, K);
            hasFreshResult = true;
            asyncFuture = [];
            asyncLastLaunchTic = [];
        elseif ~isempty(asyncLastLaunchTic) && toc(asyncLastLaunchTic) > asyncTimeoutSec
            if verbose
                fprintf('[vision_core_multi] async timeout %.2fs, cancel and fallback sync.\n', toc(asyncLastLaunchTic));
            end
            try
                cancel(asyncFuture);
            catch
            end
            asyncFuture = [];
            asyncLastLaunchTic = [];
            imgRes = run_recognition_frame_adapter(rgb, depth, K);
            hasFreshResult = true;
        end
    end

    if isempty(asyncFuture)
        needLaunch = true;
        if ~isempty(asyncLastLaunchTic)
            needLaunch = toc(asyncLastLaunchTic) >= asyncPeriodSec;
        end
        if needLaunch
            try
                if isempty(asyncPool) || ~isvalid(asyncPool)
                    asyncPool = ensure_process_pool_local(verbose);
                end
                asyncFuture = parfeval(asyncPool, @vision_async_worker, 1, ...
                    rgb, depth, K, asyncThisDir, asyncRuntimeDir, asyncGeomDir, asyncModelDir);
                asyncLastLaunchTic = tic;
            catch ME
                asyncEnabled = false;
                if verbose
                    fprintf('[vision_core_multi] async launch failed, fallback sync: %s\n', ME.message);
                end
                imgRes = run_recognition_frame_adapter(rgb, depth, K);
                hasFreshResult = true;
            end
        end
    end

    if ~hasFreshResult
        if cacheValid
            targetPosList = cacheTargetPosList;
            yawList       = cacheYawList;
            bboxList      = cacheBboxList;
            classIdList   = cacheClassIdList;
            scoreList     = cacheScoreList;
            colorIdList   = cacheColorIdList;
            colorPointsList = cacheColorPointsList;
            abIdList      = cacheAbIdList;
            axis3DList    = cacheAxis3DList;
            centerList    = cacheCenterList;
            numDet        = cacheNumDet;
            publish_last_det_to_base_local(targetPosList, yawList, bboxList, classIdList, scoreList, centerList, numDet, colorIdList, colorPointsList, abIdList, axis3DList);
            return;
        end
        % Avoid long zero-detection startup when async worker is still initializing.
        imgRes = run_recognition_frame_adapter(rgb, depth, K);
    end
else
    imgRes = run_recognition_frame_adapter(rgb, depth, K);
end

objs = flatten_image_results_local(imgRes);

cubeModeDbg = read_base_double_local('USER_CUBE_PLACE_MODE', -1);
cubeWaitDbg = read_base_logical_local('USER_CUBE_WAIT_FRESH_VISION', false);
cubeSecondStageDbg = (round(cubeModeDbg) == 2);
if cubeWaitDbg || cubeSecondStageDbg
    cubeDiagCtr = cubeDiagCtr + uint32(1);
    if cubeDiagCtr == 1 || mod(double(cubeDiagCtr), 20) == 0
        fprintf(['[cube_debug][vision_stage_raw] ctr=%d mode=%g waitFresh=%d ', ...
            'raw can=%d bottle=%d spam=%d cube=%d marker=%d flatten=%d\n'], ...
            int32(cubeDiagCtr), cubeModeDbg, cubeWaitDbg, ...
            count_imgres_items_local(imgRes, 'can'), ...
            count_imgres_items_local(imgRes, 'bottle'), ...
            count_imgres_items_local(imgRes, 'spam'), ...
            count_imgres_items_local(imgRes, 'cube'), ...
            count_imgres_items_local(imgRes, 'marker'), ...
            numel(objs));
    end
else
    cubeDiagCtr = uint32(0);
end

if isempty(objs)
    if verbose
        fprintf('[vision_core_multi] no valid objects after geometry fitting.\n');
        fprintf('===================================================\n\n');
    end
    cacheTargetPosList = targetPosList;
    cacheYawList = yawList;
    cacheBboxList = bboxList;
    cacheClassIdList = classIdList;
    cacheScoreList = scoreList;
    cacheColorIdList = colorIdList;
    cacheColorPointsList = colorPointsList;
    cacheAbIdList = abIdList;
    cacheAxis3DList = axis3DList;
    cacheCenterList = centerList;
    cacheNumDet = numDet;
    cacheValid = true;
    publish_last_det_to_base_local(targetPosList, yawList, bboxList, classIdList, scoreList, centerList, numDet, colorIdList, colorPointsList, abIdList, axis3DList);
    return;
end

% 杩囨护鏃犳晥鐩爣
keep = false(1, numel(objs));
partialFiltered = 0;
invalidFiltered = 0;
for i = 1:numel(objs)
    keep(i) = isfield(objs(i), 'center3D') && numel(objs(i).center3D) == 3 && ...
              all(isfinite(objs(i).center3D));
    if ~keep(i)
        invalidFiltered = invalidFiltered + 1;
    end
    allowPartialCube = cubeSecondStageDbg && strcmpi(char(string(objs(i).cls)), 'cube');
    if dropPartial && keep(i) && isfield(objs(i), 'partial') && logical(objs(i).partial) && ~allowPartialCube
        % partial 鐩爣鐩存帴杩囨护锛岄伩鍏嶈鎶?
        keep(i) = false;
        partialFiltered = partialFiltered + 1;
    elseif dropPartial && keep(i) && isfield(objs(i), 'partial') && logical(objs(i).partial) && allowPartialCube
        fprintf('[cube_debug][vision_partial_allow] keep partial cube during second stage\n');
    end
end
objs = objs(keep);

if cubeWaitDbg || cubeSecondStageDbg
    if cubeDiagCtr == 1 || mod(double(cubeDiagCtr), 20) == 0 || isempty(objs)
        fprintf(['[cube_debug][vision_stage_filter] mode=%g waitFresh=%d ', ...
            'kept=%d invalidFiltered=%d partialFiltered=%d dropPartial=%d\n'], ...
            cubeModeDbg, cubeWaitDbg, numel(objs), invalidFiltered, ...
            partialFiltered, dropPartial);
    end
end

if isempty(objs)
    if verbose
        fprintf('[vision_core_multi] all objects filtered out (invalid or partial).\n');
        fprintf('===================================================\n\n');
    end
    cacheTargetPosList = targetPosList;
    cacheYawList = yawList;
    cacheBboxList = bboxList;
    cacheClassIdList = classIdList;
    cacheScoreList = scoreList;
    cacheColorIdList = colorIdList;
    cacheColorPointsList = colorPointsList;
    cacheAbIdList = abIdList;
    cacheAxis3DList = axis3DList;
    cacheCenterList = centerList;
    cacheNumDet = numDet;
    cacheValid = true;
    publish_last_det_to_base_local(targetPosList, yawList, bboxList, classIdList, scoreList, centerList, numDet, colorIdList, colorPointsList, abIdList, axis3DList);
    return;
end

TcbEff = Tcb;
TcbEff(1:3,1:3) = Tcb(1:3,1:3) * camFrameFixR;
Rcb = TcbEff(1:3,1:3);

beforeIgnoreCount = numel(objs);
objs = filter_ignored_objects_local(objs, TcbEff, basePosBias, verbose);
if (cubeWaitDbg || cubeSecondStageDbg) && beforeIgnoreCount ~= numel(objs)
    fprintf('[cube_debug][vision_stage_ignore] before=%d after=%d\n', beforeIgnoreCount, numel(objs));
end

if isempty(objs)
    cacheTargetPosList = targetPosList;
    cacheYawList = yawList;
    cacheBboxList = bboxList;
    cacheClassIdList = classIdList;
    cacheScoreList = scoreList;
    cacheColorIdList = colorIdList;
    cacheColorPointsList = colorPointsList;
    cacheAbIdList = abIdList;
    cacheAxis3DList = axis3DList;
    cacheCenterList = centerList;
    cacheNumDet = numDet;
    cacheValid = true;

    publish_last_det_to_base_local( ...
        targetPosList, yawList, bboxList, classIdList, scoreList, centerList, numDet, ...
        colorIdList, colorPointsList, abIdList, axis3DList);

    return;
end

N = min(numel(objs), MAXDET);
numDet = N;


for i = 1:N
    obj = objs(i);

    pc = obj.center3D(:);                 % camera frame grasp point
    pb = TcbEff * [pc; 1];                % base frame grasp point
    pb = pb(:);
    bpb = ensure_vec3_local(basePosBias, [0;0;0]);
    pb(1:3) = pb(1:3) + bpb;

    targetPosList(:,i) = pb(1:3);

    if isfield(obj, 'center2D') && numel(obj.center2D) >= 2 && all(isfinite(obj.center2D))
        centerList(:,i) = obj.center2D(:);
    else
        uv = project_points_local(pc', fx, fy, cx, cy);
        centerList(:,i) = uv(:);
    end

    if isfield(obj, 'bbox') && numel(obj.bbox) == 4
        bboxList(:,i) = obj.bbox(:);
    end

    classIdList(i) = class_name_to_id_local(obj.cls);

    if isfield(obj, 'color') && ~isempty(obj.color)
        colorIdList(i) = color_name_to_id_local(obj.color);
    end

    if isfield(obj, 'points') && ~isempty(obj.points) && isfinite(obj.points)
        colorPointsList(i) = double(obj.points);
    end

    if isfield(obj, 'ab') && ~isempty(obj.ab)
        abIdList(i) = ab_name_to_id_local(obj.ab);
    end

    if isfield(obj, 'axis3D') && numel(obj.axis3D) >= 3 && all(isfinite(obj.axis3D(1:3)))
        axis3DList(:,i) = double(obj.axis3D(1:3));
    end

    if isfield(obj, 'score') && ~isempty(obj.score)
        scoreList(i) = obj.score;
    end

    yawList(:,i) = compute_yaw_candidates_local( ...
        obj, Rcb, TcbEff, basePosBias, ...
        cubeEdgeGuardEnable, cubeEdgeGuardRect, cubeEdgeGuardMargin, cubeEdgeGuardYawFlip);

    if verbose
        fprintf('\n---- det %d ----\n', i);
        fprintf('[det] cls           = %s\n', char(string(obj.cls)));
        fprintf('[det] score         = %.4f\n', scoreList(i));
        fprintf('[det] color/points  = %s / %.1f\n', ...
            char(string(id_to_color_name_local(colorIdList(i)))), colorPointsList(i));
        fprintf('[det] bbox          = [%.1f %.1f %.1f %.1f]\n', ...
            bboxList(1,i), bboxList(2,i), bboxList(3,i), bboxList(4,i));
        fprintf('[det] center2D      = [%.2f %.2f]\n', centerList(1,i), centerList(2,i));
        fprintf('[det] center3D cam  = [%.6f %.6f %.6f]\n', pc(1), pc(2), pc(3));
        fprintf('[det] targetPos base= [%.6f %.6f %.6f]\n', ...
            targetPosList(1,i), targetPosList(2,i), targetPosList(3,i));
        fprintf('[det] yaw cand      = [%.3f %.3f]\n', yawList(1,i), yawList(2,i));
    end
end

cacheTargetPosList = targetPosList;
cacheYawList = yawList;
cacheBboxList = bboxList;
cacheClassIdList = classIdList;
cacheScoreList = scoreList;
cacheColorIdList = colorIdList;
cacheColorPointsList = colorPointsList;
cacheAbIdList = abIdList;
cacheAxis3DList = axis3DList;
cacheCenterList = centerList;
cacheNumDet = numDet;
cacheValid = true;
publish_last_det_to_base_local(targetPosList, yawList, bboxList, classIdList, scoreList, centerList, numDet, colorIdList, colorPointsList, abIdList, axis3DList);

if verbose
    fprintf('===================================================\n\n');
end

end

% ============================================================
% Adapter: 浼樺厛璋冪敤浣犲凡鏈夌殑鍗曞抚鍑犱綍璇嗗埆鍏ュ彛
% ============================================================
function imgRes = run_recognition_frame_adapter(rgb, depth, K)

% 浣犲鏋滃凡缁忓崟鐙皝瑁呭ソ浜嗗崟甯ц瘑鍒叆鍙ｏ紝浼樺厛鐢ㄥ畠
if exist('run_recognition_frame', 'file') == 2
    imgRes = run_recognition_frame(rgb, depth, K);
    return;
end

if exist('parallel_recognition_singleframe', 'file') == 2
    imgRes = parallel_recognition_singleframe(rgb, depth, K);
    return;
end

% 濡傛灉杩樻病灏佽濂藉绫诲叆鍙ｏ紝鑷冲皯 cube 鍏堣蛋鍑犱綍鎷熷悎锛屼繚璇佹姄鍙栫偣涓嶆槸 bbox 涓績
imgRes = run_cube_only_geometry_fallback(rgb, depth, K);

end

% ============================================================
% Fallback锛氳嚦灏戝厛鎶?cube 鎶撳彇鐐规敼鎴愬嚑浣曚腑蹇?
% ============================================================
function imgRes = run_cube_only_geometry_fallback(rgb, depth, K)

fx = K(1,1); fy = K(2,2);
cx0 = K(1,3); cy0 = K(2,3);

imgRes = struct();
imgRes.can    = struct([]);
imgRes.bottle = struct([]);
imgRes.spam   = struct([]);
imgRes.marker = struct([]);
imgRes.cube   = struct([]);

verbose = false;
tok = str2double(getenv("VISION_VERBOSE"));
if ~isnan(tok) && tok ~= 0
    verbose = true;
end

persistent warnedMissingDetector;
if isempty(warnedMissingDetector)
    warnedMissingDetector = false;
end

if exist('runCubeBboxOnnx', 'file') ~= 2
    if verbose && ~warnedMissingDetector
        fprintf('[vision_core_multi] fallback detector runCubeBboxOnnx not found.\n');
        warnedMissingDetector = true;
    end
    return;
end

detAll = runCubeBboxOnnx(rgb);
if verbose
    fprintf('[vision_core_multi] fallback num det total = %d\n', numel(detAll));
end

if isempty(detAll)
    return;
end

zMin = 0.05;
zMax = 2.50;

optsC = struct("bottomPct", 40, "planeMaxDist", 0.002, "zExpand", 0.006, ...
               "zBin", 0.003, "minPts", 150, ...
               "planeRef", [0 0 1], "planeAng", 12, ...
               "squareThetaStep", 0.5, "squarePad", 0.0, ...
               "squarePadFrac", 0.0, "squarePct", 2, ...
               "squareUseAll", false, "squareUseHull", true);

cubeObjs = struct([]);

for i = 1:numel(detAll)
    det = detAll(i);
    bbox = det.bbox;

    [Pc, ok] = bbox_to_cloud_local(bbox, depth, K, zMin, zMax);
    if ~ok
        continue;
    end

    pcBox = pointCloud(Pc);
    pcObj = segment_largest_cluster_local(pcBox);

    if pcObj.Count < 50
        continue;
    end

    try
        [center3D, square3D, ~, side, ~] = fit_bottom_face_center_square_cube(pcObj, optsC);
    catch
        continue;
    end

    center2D = project_points_local(center3D, fx, fy, cx0, cy0);
    square2D = project_points_local(square3D, fx, fy, cx0, cy0);

    obj = struct( ...
        "cls", "cube", ...
        "bbox", double(bbox(:))', ...
        "score", double(det.score), ...
        "center3D", center3D, ...
        "center2D", center2D, ...
        "square3D", square3D, ...
        "square2D", square2D, ...
        "side", side, ...
        "partial", false ...
        );

    cubeObjs = [cubeObjs; obj]; %#ok<AGROW>
end

imgRes.cube = cubeObjs;

end

% ============================================================
% 鎶婁簲绫荤粺涓€灞曞紑
% ============================================================
function objs = flatten_image_results_local(imgRes)

tmpl = struct( ...
    'cls', "", ...
    'color', "", ...
    'bbox', zeros(1,4), ...
    'score', 0, ...
    'points', nan, ...
    'center3D', zeros(1,3), ...
    'center2D', zeros(1,2), ...
    'axis3D', zeros(1,3), ...
    'axisLine2D', zeros(0,2), ...
    'intersectLine2D', zeros(0,2), ...
    'rect2D', zeros(0,2), ...
    'rect3D', zeros(0,3), ...
    'square2D', zeros(0,2), ...
    'square3D', zeros(0,3), ...
    'ab', "", ...
    'partial', false ...
    );

objs = repmat(tmpl, 0, 1);

fields = {'can','bottle','spam','cube','marker'};

for f = 1:numel(fields)
    name = fields{f};

    if ~isfield(imgRes, name)
        continue;
    end

    arr = imgRes.(name);
    if isempty(arr)
        continue;
    end

    for k = 1:numel(arr)
        src = arr(k);
        dst = tmpl;

        % 缁熶竴绫诲悕
        if isfield(src, 'cls') && ~isempty(src.cls)
            dst.cls = string(src.cls);
        else
            dst.cls = string(name);
        end

        % 閫氱敤瀛楁
        if isfield(src, 'bbox') && ~isempty(src.bbox)
            b = double(src.bbox(:)');
            if numel(b) == 4
                dst.bbox = b;
            end
        end

        if isfield(src, 'score') && ~isempty(src.score)
            dst.score = double(src.score);
        end

        if isfield(src, 'color') && ~isempty(src.color)
            dst.color = string(src.color);
        end

        if isfield(src, 'points') && ~isempty(src.points) && isfinite(src.points)
            dst.points = double(src.points);
        end

        if isfield(src, 'center3D') && ~isempty(src.center3D)
            c3 = double(src.center3D(:)');
            if numel(c3) == 3
                dst.center3D = c3;
            end
        end

        if isfield(src, 'center2D') && ~isempty(src.center2D)
            c2 = double(src.center2D(:)');
            if numel(c2) == 2
                dst.center2D = c2;
            end
        end

        if isfield(src, 'partial') && ~isempty(src.partial)
            dst.partial = logical(src.partial);
        end

        % 鍦嗘煴绫?marker 甯哥敤
        if isfield(src, 'axis3D') && ~isempty(src.axis3D)
            a3 = double(src.axis3D(:)');
            if numel(a3) == 3
                dst.axis3D = a3;
            end
        end

        if isfield(src, 'axisLine2D') && ~isempty(src.axisLine2D)
            dst.axisLine2D = double(src.axisLine2D);
        end

        if isfield(src, 'intersectLine2D') && ~isempty(src.intersectLine2D)
            dst.intersectLine2D = double(src.intersectLine2D);
        end

        if isfield(src, 'ab') && ~isempty(src.ab)
            dst.ab = string(src.ab);
        end

        % spam
        if isfield(src, 'rect2D') && ~isempty(src.rect2D)
            dst.rect2D = double(src.rect2D);
        end

        % cube
        if isfield(src, 'square2D') && ~isempty(src.square2D)
            dst.square2D = double(src.square2D);
        end

        if isfield(src, 'square3D') && ~isempty(src.square3D)
            dst.square3D = double(src.square3D);
        end        

        objs(end+1,1) = dst; %#ok<AGROW>
    end
end

end

% ============================================================
% class name -> id
% 鎸変綘鍘熶範鎯細bottle/can/marker/cube/spam
% ============================================================
function cid = class_name_to_id_local(cls)

switch lower(char(string(cls)))
    case 'bottle'
        cid = 1;
    case 'can'
        cid = 2;
    case 'marker'
        cid = 3;
    case 'cube'
        cid = 4;
    case 'spam'
        cid = 5;
    otherwise
        cid = 0;
end

end

function cid = color_name_to_id_local(colorName)
switch lower(strtrim(char(string(colorName))))
    case 'red'
        cid = 1;
    case 'yellow'
        cid = 2;
    case 'green'
        cid = 3;
    case 'blue'
        cid = 4;
    case 'purple'
        cid = 5;
    otherwise
        cid = 0;
end
end

function name = id_to_color_name_local(cid)
switch round(double(cid))
    case 1
        name = "red";
    case 2
        name = "yellow";
    case 3
        name = "green";
    case 4
        name = "blue";
    case 5
        name = "purple";
    otherwise
        name = "unknown";
end
end

function id = ab_name_to_id_local(abName)
ab = upper(strtrim(char(string(abName))));
if strcmp(ab, 'A')
    id = 1;
elseif strcmp(ab, 'B')
    id = 2;
else
    id = 0;
end
end

% ============================================================
% yaw 鍊欓€?
% 鍦嗘煴绫讳紭鍏堢敤杞存柟鍚?
% 鏂瑰潡/鐭╁舰浼樺厛鐢?2D 澶氳竟褰㈣竟鏂瑰悜
% ============================================================
function yaw2 = compute_yaw_candidates_local(obj, Rcb, TcbEff, basePosBias, edgeGuardEnable, edgeGuardRect, edgeGuardMargin, edgeGuardYawFlip)

yaw2 = [0; pi/2];

objCls = lower(strtrim(char(string(obj.cls))));
objAb  = "";
if isfield(obj, 'ab') && ~isempty(obj.ab)
    objAb = upper(strtrim(char(string(obj.ab))));
end

% 1) SPAM: only use the short side direction
if strcmp(objCls, 'spam') && isfield(obj, 'rect2D') && ~isempty(obj.rect2D)
    poly = double(obj.rect2D);

    if size(poly,1) >= 4
        e12 = poly(2,:) - poly(1,:);
        e23 = poly(3,:) - poly(2,:);

        len12 = norm(e12);
        len23 = norm(e23);

        if len12 > 1e-6 && len23 > 1e-6
            if len12 <= len23
                dShort = e12;
            else
                dShort = e23;
            end

            yaw = atan2(dShort(2), dShort(1));

            % Only provide the short-side yaw. Keep 2x1 interface.
            yaw2 = wrap_to_pi_local([yaw; yaw]);
            return;
        end
    end
end

% 2) CAN/BOTTLE: use 3D cylinder axis
if isfield(obj, 'axis3D') && numel(obj.axis3D) == 3 && all(isfinite(obj.axis3D))
    aCam = obj.axis3D(:);
    aBase = Rcb * aCam;
    aBase(3) = 0;  % only use planar yaw

    if norm(aBase(1:2)) > 1e-6
        yawAxis = atan2(aBase(2), aBase(1));

        % Fallen can/bottle: prefer grasping across the short side / diameter,
        % so use direction perpendicular to the cylinder long axis.
        if (strcmp(objCls, 'can') || strcmp(objCls, 'bottle')) && strcmp(objAb, 'B')
            yawGrip = yawAxis;
            yaw2 = wrap_to_pi_local([yawGrip; yawGrip]);
        else
            % Upright cylinder / marker / other axis-based objects: keep original candidates.
            yaw2 = wrap_to_pi_local([yawAxis; yawAxis + pi/2]);
        end

        return;
    end
end

% 3) CUBE: use true 3D edge direction in base XY plane
cubeYawComputed = false;
if strcmp(objCls, 'cube') && isfield(obj, 'square3D') && ~isempty(obj.square3D)
    square3D = double(obj.square3D);

    if size(square3D,1) >= 2 && size(square3D,2) >= 3
        q1Base = TcbEff * [square3D(1,1:3).'; 1];
        q2Base = TcbEff * [square3D(2,1:3).'; 1];
        dBase = q2Base(1:3) - q1Base(1:3);
        dBase(3) = 0;

        if norm(dBase(1:2)) > 1e-6
            yaw = atan2(dBase(2), dBase(1));
            yaw2 = wrap_to_pi_local([yaw; yaw + pi/2]);
            cubeYawComputed = true;
        end
    end
end

% 4) CUBE fallback: keep two orthogonal candidates from image edge
if strcmp(objCls, 'cube') && ~cubeYawComputed && isfield(obj, 'square2D') && ~isempty(obj.square2D)
    poly = double(obj.square2D);

    if size(poly,1) >= 2
        d = poly(2,:) - poly(1,:);
        if norm(d) > 1e-6
            yaw = atan2(d(2), d(1));
            yaw2 = wrap_to_pi_local([yaw; yaw + pi/2]);
        end
    end
end

% 5) CUBE near-bin-edge guard:
% If cube is close to a bin edge, force yaw parallel to that nearest edge
% to reduce gripper/bin wall collision risk.
if strcmp(objCls, 'cube')
    yaw2 = apply_cube_bin_edge_guard_local( ...
        obj, yaw2, TcbEff, basePosBias, edgeGuardEnable, edgeGuardRect, edgeGuardMargin, edgeGuardYawFlip);
end

end

function yaw2 = apply_cube_bin_edge_guard_local(obj, yaw2, TcbEff, basePosBias, enableGuard, rect, edgeMargin, yawFlip)
yaw2In = wrap_to_pi_local(yaw2(:));
yaw2 = yaw2In;

x = NaN; y = NaN;
xMin = NaN; xMax = NaN; yMin = NaN; yMax = NaN;
d = [NaN NaN NaN NaN];
dMin = NaN;
idxMin = 0;
dClear = NaN;
cubeHalf = 0;
yawDesired = NaN;
yBest = yaw2In(1);
reason = 'init';

if ~enableGuard
    reason = 'guard_disabled';
    publish_cube_edge_guard_debug_local(false, reason, idxMin, x, y, ...
        [xMin xMax yMin yMax], d, dMin, dClear, cubeHalf, edgeMargin, yaw2In, yawDesired, yBest);
    return;
end

if ~isfield(obj, 'center3D') || isempty(obj.center3D) || numel(obj.center3D) ~= 3
    reason = 'no_center3d';
    publish_cube_edge_guard_debug_local(false, reason, idxMin, x, y, ...
        [xMin xMax yMin yMax], d, dMin, dClear, cubeHalf, edgeMargin, yaw2In, yawDesired, yBest);
    return;
end

pc = double(obj.center3D(:));
if ~all(isfinite(pc))
    reason = 'center3d_nonfinite';
    publish_cube_edge_guard_debug_local(false, reason, idxMin, x, y, ...
        [xMin xMax yMin yMax], d, dMin, dClear, cubeHalf, edgeMargin, yaw2In, yawDesired, yBest);
    return;
end

pb = TcbEff * [pc; 1];
pb = pb(:);
bpb = ensure_vec3_local(basePosBias, [0;0;0]);
pb = pb(1:3) + bpb;
x = pb(1);
y = pb(2);

xMin = rect(1); xMax = rect(2);
yMin = rect(3); yMax = rect(4);

if ~(x >= (xMin - edgeMargin) && x <= (xMax + edgeMargin) && ...
     y >= (yMin - edgeMargin) && y <= (yMax + edgeMargin))
    reason = 'outside_rect_band';
    publish_cube_edge_guard_debug_local(false, reason, idxMin, x, y, ...
        [xMin xMax yMin yMax], d, dMin, dClear, cubeHalf, edgeMargin, yaw2In, yawDesired, yBest);
    return;
end

% Distances to [left right bottom top] edge lines.
d = [abs(x - xMin), abs(xMax - x), abs(y - yMin), abs(yMax - y)];
[dMin, idxMin] = min(d);
if ~isfinite(dMin)
    reason = 'dmin_nonfinite';
    publish_cube_edge_guard_debug_local(false, reason, idxMin, x, y, ...
        [xMin xMax yMin yMax], d, dMin, dClear, cubeHalf, edgeMargin, yaw2In, yawDesired, yBest);
    return;
end

if isfield(obj, 'side')
    s = double(obj.side);
    if isfinite(s) && s > 0
        cubeHalf = 0.5 * s;
    end
end

dClear = dMin - cubeHalf;
if ~isfinite(dClear)
    reason = 'dclear_nonfinite';
    publish_cube_edge_guard_debug_local(false, reason, idxMin, x, y, ...
        [xMin xMax yMin yMax], d, dMin, dClear, cubeHalf, edgeMargin, yaw2In, yawDesired, yBest);
    return;
end
edgeTol = read_base_double_local('USER_CUBE_EDGE_MARGIN_TOL', 0.002);
if ~isfinite(edgeTol) || edgeTol < 0
    edgeTol = 0;
end
if dClear > (edgeMargin + edgeTol)
    reason = 'not_near_edge';
    publish_cube_edge_guard_debug_local(false, reason, idxMin, x, y, ...
        [xMin xMax yMin yMax], d, dMin, dClear, cubeHalf, edgeMargin, yaw2In, yawDesired, yBest);
    return;
end

% Default mapping:
% left/right edge (x = const) -> yaw along +X
% lower/upper edge (y = const) -> yaw along +Y
if idxMin <= 2
    yawDesired = 0;
else
    yawDesired = pi/2;
end

if yawFlip
    yawDesired = wrap_to_pi_local(yawDesired + pi/2);
end

y1 = yaw2In(1);
y2c = yaw2In(min(2, numel(yaw2In)));
if numel(yaw2In) < 2
    y2c = y1 + pi/2;
end

d1 = yaw_axis_distance_local(y1, yawDesired);
d2 = yaw_axis_distance_local(y2c, yawDesired);
if d2 < d1
    yBest = y2c;
else
    yBest = y1;
end

% Force one yaw to avoid planner selecting the orthogonal direction.
yaw2 = wrap_to_pi_local([yBest; yBest]);
reason = 'forced';
publish_cube_edge_guard_debug_local(true, reason, idxMin, x, y, ...
    [xMin xMax yMin yMax], d, dMin, dClear, cubeHalf, edgeMargin, yaw2In, yawDesired, yBest);
end

function publish_cube_edge_guard_debug_local(ok, reason, idxMin, x, y, rect, d, dMin, dClear, cubeHalf, edgeMargin, yawIn, yawDesired, yawOut)
edgeName = edge_name_from_idx_local(idxMin);
mode = read_base_double_local('USER_CUBE_PLACE_MODE', -1);
try
    assignin('base', 'VISION_CUBE_EDGE_GUARD_OK', logical(ok));
    assignin('base', 'VISION_CUBE_EDGE_GUARD_REASON', char(reason));
    assignin('base', 'VISION_CUBE_EDGE_GUARD_EDGE', char(edgeName));
    assignin('base', 'VISION_CUBE_EDGE_GUARD_LAST', ...
        [x, y, double(idxMin), d(1), d(2), d(3), d(4), dMin, dClear, cubeHalf, yawDesired, yawOut, edgeMargin, mode]);
catch
end

debugOn = read_base_logical_local('USER_CUBE_EDGE_GUARD_DEBUG', false);
if ~debugOn
    debugOn = get_env_bool_local("VISION_CUBE_EDGE_GUARD_DEBUG", false);
end
debugFailOn = read_base_logical_local('USER_CUBE_EDGE_GUARD_DEBUG_FAIL', false);
if ~debugFailOn
    debugFailOn = get_env_bool_local("VISION_CUBE_EDGE_GUARD_DEBUG_FAIL", false);
end
if debugOn && (ok || debugFailOn)
    yin1 = yawIn(1);
    yin2 = yawIn(min(2, numel(yawIn)));
    fprintf(['[cube_edge_guard] ok=%d reason=%s mode=%g edge=%s idx=%d ', ...
        'xy=[%.4f %.4f] rect=[%.4f %.4f %.4f %.4f] ', ...
        'd=[%.4f %.4f %.4f %.4f] dMin=%.4f dClear=%.4f half=%.4f m=%.4f ', ...
        'yawIn=[%.3f %.3f] yawDesired=%.3f yawOut=%.3f\n'], ...
        double(ok), char(reason), mode, char(edgeName), int32(idxMin), ...
        x, y, rect(1), rect(2), rect(3), rect(4), ...
        d(1), d(2), d(3), d(4), dMin, dClear, cubeHalf, edgeMargin, ...
        yin1, yin2, yawDesired, yawOut);
end
end

function name = edge_name_from_idx_local(idx)
switch int32(idx)
    case 1
        name = 'left';
    case 2
        name = 'right';
    case 3
        name = 'bottom';
    case 4
        name = 'top';
    otherwise
        name = 'none';
end
end

function d = yaw_axis_distance_local(yaw, yawRef)
d = abs(wrap_to_pi_local(yaw - yawRef));
if d > pi/2
    d = pi - d;
end
end

% ============================================================
% 绠€鍗曟姇褰?
% ============================================================
function uv = project_points_local(P, fx, fy, cx0, cy0)

if isempty(P)
    uv = zeros(0,2);
    return;
end

if isvector(P) && numel(P) == 3
    P = reshape(P, [1 3]);
end

X = P(:,1); Y = P(:,2); Z = P(:,3);
u = fx * (X ./ Z) + cx0;
v = fy * (Y ./ Z) + cy0;
uv = [u v];

end

% ============================================================
% fallback: bbox -> cloud
% ============================================================
function [Pc, ok] = bbox_to_cloud_local(bbox, depth, K, zMin, zMax)

H = size(depth,1);
W = size(depth,2);

fx  = K(1,1); fy  = K(2,2);
cx0 = K(1,3); cy0 = K(2,3);

x1 = max(1, min(W, round(bbox(1))));
y1 = max(1, min(H, round(bbox(2))));
x2 = max(1, min(W, round(bbox(3))));
y2 = max(1, min(H, round(bbox(4))));

if x2 <= x1 || y2 <= y1
    Pc = zeros(0,3);
    ok = false;
    return;
end

[uu2, vv2] = meshgrid(x1:x2, y1:y2);
uu = uu2(:);
vv = vv2(:);

ind = sub2ind(size(depth), vv, uu);
Z = depth(ind);

mask = isfinite(Z) & (Z > zMin) & (Z < zMax);
uu = uu(mask);
vv = vv(mask);
Z  = Z(mask);

if numel(Z) < 50
    Pc = zeros(0,3);
    ok = false;
    return;
end

Xc = (double(uu) - cx0) .* double(Z) / fx;
Yc = (double(vv) - cy0) .* double(Z) / fy;

Pc = [Xc(:), Yc(:), double(Z(:))];
ok = true;

end

% ============================================================
% fallback: 鏈€澶ц仛绫?
% ============================================================
function pcObj = segment_largest_cluster_local(pcBox)

if pcBox.Count < 50
    pcObj = pcBox;
    return;
end

try
    [labels, numClusters] = pcsegdist(pcBox, 0.01);
catch
    pcObj = pcBox;
    return;
end

if numClusters < 1
    pcObj = pcBox;
    return;
end

counts = accumarray(labels(labels>0), 1);
[~, bestId] = max(counts);
idxObj = find(labels == bestId);
pcObj = select(pcBox, idxObj);

end

% ============================================================
% wrapToPi 鏇夸唬
% ============================================================
function a = wrap_to_pi_local(a)
a = mod(a + pi, 2*pi) - pi;
end

function publish_last_det_to_base_local(targetPosList, yawList, bboxList, classIdList, scoreList, centerList, numDet, colorIdList, colorPointsList, abIdList, axis3DList)
persistent debugCtr
if isempty(debugCtr)
    debugCtr = uint32(0);
end
if nargin < 8 || isempty(colorIdList)
    colorIdList = zeros(1,20);
end
if nargin < 9 || isempty(colorPointsList)
    colorPointsList = nan(1,20);
end
if nargin < 10 || isempty(abIdList)
    abIdList = zeros(1,20);
end
if nargin < 11 || isempty(axis3DList)
    axis3DList = zeros(3,20);
end
try
    assignin('base', 'VISION_LAST_TARGETPOS', targetPosList);
    assignin('base', 'VISION_LAST_YAW', yawList);
    assignin('base', 'VISION_LAST_BBOX', bboxList);
    assignin('base', 'VISION_LAST_CLASSID', classIdList);
    assignin('base', 'VISION_LAST_SCORE', scoreList);
    assignin('base', 'VISION_LAST_CENTER2D', centerList);
    assignin('base', 'VISION_LAST_COLORID', colorIdList);
    assignin('base', 'VISION_LAST_COLORPOINTS', colorPointsList);
    assignin('base', 'VISION_LAST_ABID', abIdList);
    assignin('base', 'VISION_LAST_AXIS3D', axis3DList);
    assignin('base', 'VISION_LAST_NUMDET', numDet);
catch
end

mode = read_base_double_local('USER_CUBE_PLACE_MODE', -1);
waitFresh = read_base_logical_local('USER_CUBE_WAIT_FRESH_VISION', false);
visionEnable = read_base_logical_local('USER_VISION_ENABLE', false);
if waitFresh || round(mode) == 2
    debugCtr = debugCtr + uint32(1);
    if debugCtr == 1 || mod(double(debugCtr), 20) == 0 || double(numDet) >= 1
        classHead = 0;
        scoreHead = 0;
        posHead = [NaN; NaN; NaN];
        if double(numDet) >= 1
            classHead = classIdList(1);
            scoreHead = scoreList(1);
            posHead = targetPosList(:,1);
        end
        fprintf(['[cube_debug][vision_core_multi_publish] ctr=%d mode=%g waitFresh=%d ', ...
            'vision=%d numDet=%g class1=%g score1=%.3f pos1=[%.4f %.4f %.4f]\n'], ...
            int32(debugCtr), mode, waitFresh, visionEnable, double(numDet), ...
            classHead, scoreHead, posHead(1), posHead(2), posHead(3));
    end
else
    debugCtr = uint32(0);
end
end

function v = read_base_double_local(name, defaultVal)
v = defaultVal;
try
    if evalin('base', sprintf('exist(''%s'',''var'')', name)) ~= 0
        t = evalin('base', name);
        if isnumeric(t) && isscalar(t)
            v = double(t);
        end
    end
catch
end
end

function tf = read_base_logical_local(name, defaultVal)
tf = defaultVal;
try
    if evalin('base', sprintf('exist(''%s'',''var'')', name)) ~= 0
        tf = logical(evalin('base', name));
    end
catch
end
end

function n = count_imgres_items_local(imgRes, fieldName)
n = 0;
try
    if isstruct(imgRes) && isfield(imgRes, fieldName)
        arr = imgRes.(fieldName);
        n = numel(arr);
    end
catch
    n = 0;
end
end

function R = get_cam_frame_fix_local()
R = eye(3);

% Optional explicit 3x3 matrix (row-major, nine numbers).
matStr = strtrim(getenv("VISION_CAM_FRAME_FIX_MAT"));
if ~isempty(matStr)
    nums = parse_num_list_local(matStr);
    if numel(nums) >= 9
        Rcand = reshape(nums(1:9), [3 3])';
        if all(isfinite(Rcand), "all")
            R = Rcand;
            return;
        end
    end
end

mode = lower(strtrim(getenv("VISION_CAM_FRAME_FIX")));
if isempty(mode) || any(strcmp(mode, {'none','off','0','identity'}))
    return;
end

switch mode
    case {'swap_xy_negx','rz_m90','xy_y_negx'}
        % [x'; y'; z'] = [ y; -x; z ]
        R = [0 1 0; -1 0 0; 0 0 1];
    case {'swap_xy_posx','xy_y_x'}
        % [x'; y'; z'] = [ y; x; z ]
        R = [0 1 0; 1 0 0; 0 0 1];
    case {'neg_xy'}
        % [x'; y'; z'] = [ -x; -y; z ]
        R = [-1 0 0; 0 -1 0; 0 0 1];
    case {'neg_x'}
        R = [-1 0 0; 0 1 0; 0 0 1];
    case {'neg_y'}
        R = [1 0 0; 0 -1 0; 0 0 1];
    case {'neg_z'}
        R = [1 0 0; 0 1 0; 0 0 -1];
    otherwise
        % Keep identity for unknown mode.
end
end

function v = get_env_vec3_local(name, defaultVal)
v = double(defaultVal(:));
s = strtrim(getenv(name));
if isempty(s)
    return;
end
nums = parse_num_list_local(s);
if numel(nums) >= 3 && all(isfinite(nums(1:3)))
    v = double(nums(1:3));
end
end

function nums = parse_num_list_local(s)
s = regexprep(char(s), '[,;]+', ' ');
nums = sscanf(s, '%f');
end

function v3 = ensure_vec3_local(v, defaultVal)
v3 = double(defaultVal(:));
try
    t = double(v(:));
catch
    t = [];
end
if numel(t) >= 3 && all(isfinite(t(1:3)))
    v3 = t(1:3);
elseif numel(t) > 0
    n = min(3, numel(t));
    v3(1:n) = t(1:n);
end
if numel(v3) < 3
    v3(3,1) = 0;
end
end
function p = ensure_process_pool_local(verbose)
p = gcp('nocreate');
if ~isempty(p) && ~isa(p, 'parallel.ProcessPool')
    if verbose
        fprintf('[vision_core_multi] replacing %s with process pool.\n', class(p));
    end
    delete(p);
    p = [];
end
if isempty(p)
    p = parpool('Processes', 1);
end
end

function print_future_error_local(f)
try
    if isempty(f)
        return;
    end
    e = f.Error;
    if isempty(e)
        return;
    end
    fprintf('[vision_core_multi] async future error id=%s msg=%s\n', string(e.identifier), string(e.message));
catch
end
end

function v = get_env_int_local(name, defaultVal)
v = defaultVal;
s = strtrim(getenv(name));
if isempty(s)
    return;
end
t = str2double(s);
if isfinite(t)
    v = round(t);
end
end

function v = get_env_double_local(name, defaultVal)
v = defaultVal;
s = strtrim(getenv(name));
if isempty(s)
    return;
end
t = str2double(s);
if isfinite(t)
    v = t;
end
end

function tf = get_env_bool_local(name, defaultVal)
tf = defaultVal;
s = lower(strtrim(getenv(name)));
if isempty(s)
    return;
end
if any(strcmp(s, {'1','true','on','yes'}))
    tf = true;
elseif any(strcmp(s, {'0','false','off','no'}))
    tf = false;
end
end

function [enableGuard, rect, edgeMargin, yawFlip] = get_cube_edge_guard_params_local(defaultEnable, defaultRect, defaultMargin, defaultYawFlip)
% rect = [xMin xMax yMin yMax] in base frame
enableGuard = defaultEnable;
rect = defaultRect;
edgeMargin = defaultMargin;
yawFlip = defaultYawFlip;

try
    if evalin('base', 'exist(''USER_CUBE_EDGE_GUARD_ENABLE'',''var'')') ~= 0
        enableGuard = logical(evalin('base', 'USER_CUBE_EDGE_GUARD_ENABLE'));
    end
catch
end

try
    if evalin('base', 'exist(''USER_CUBE_BIN_RECT'',''var'')') ~= 0
        r = double(evalin('base', 'USER_CUBE_BIN_RECT'));
        r = reshape(r, 1, []);
        if numel(r) >= 4 && all(isfinite(r(1:4)))
            rect = r(1:4);
        end
    end
catch
end

try
    if evalin('base', 'exist(''USER_CUBE_EDGE_MARGIN'',''var'')') ~= 0
        m = double(evalin('base', 'USER_CUBE_EDGE_MARGIN'));
        if isfinite(m) && m > 0
            edgeMargin = m;
        end
    end
catch
end

try
    if evalin('base', 'exist(''USER_CUBE_EDGE_YAW_FLIP'',''var'')') ~= 0
        yawFlip = logical(evalin('base', 'USER_CUBE_EDGE_YAW_FLIP'));
    end
catch
end
end

function objsOut = filter_ignored_objects_local(objs, TcbEff, basePosBias, verbose)
objsOut = objs;
if isempty(objs)
    return;
end

ignorePos = zeros(3,20);
hasIgnore = false;

try
    if evalin('base', 'exist(''USER_IGNORE_TARGETS'',''var'')') ~= 0
        p = evalin('base', 'double(USER_IGNORE_TARGETS)');
        if isnumeric(p) && size(p,1) == 3
            cols = min(20, size(p,2));
            ignorePos(:,1:cols) = p(:,1:cols);
            hasIgnore = any(any(abs(ignorePos) > 0));
        end
    end
catch
end

if ~hasIgnore
    return;
end

matchThr = 0.04;
try
    if evalin('base', 'exist(''USER_IGNORE_MATCH_THR'',''var'')') ~= 0
        t = evalin('base', 'double(USER_IGNORE_MATCH_THR)');
        if isfinite(t) && t > 0
            matchThr = t;
        end
    end
catch
end

keep = true(1, numel(objs));

for i = 1:numel(objs)
    if ~isfield(objs(i), 'center3D') || numel(objs(i).center3D) ~= 3
        continue;
    end

    pc = double(objs(i).center3D(:));
    if ~all(isfinite(pc))
        continue;
    end

    pb = TcbEff * [pc; 1];
    pb = pb(:);
    bpb = ensure_vec3_local(basePosBias, [0;0;0]);
    pb = pb(1:3) + bpb;

    for k = 1:size(ignorePos,2)
        if all(ignorePos(:,k) == 0)
            continue;
        end

        d = norm(pb(:) - ignorePos(:,k));

        if d <= matchThr
            keep(i) = false;

            if verbose
                fprintf('[vision_ignore] filter det=%d ignore=%d dist=%.4f thr=%.4f pos=[%.4f %.4f %.4f]\n', ...
                    i, k, d, matchThr, pb(1), pb(2), pb(3));
            end

            break;
        end
    end
end

objsOut = objs(keep);
end









