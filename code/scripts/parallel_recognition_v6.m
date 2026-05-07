%% =========================================================
%  Multi-image, multi-class recognition (CAN/BOTTLE/SPAM/MARKER/CUBE)
%  - bbox model: best10.onnx (b,c,p,s)
%  - seg model : best10_seg_v3.onnx (8 classes; downstream uses bottle/can/marker/spam/cube)
%  Output: MATLAB struct + .mat file (parallel_recognition_results.mat)
%% =========================================================
clc; clear; close all;
addpath("matlab");

%% ---------------- dataset paths ----------------
% datasetPath = "D:\vision_project\robocup\vision_offline_test\data\dataset_V2";
datasetPath = "F:\robocup\environment\RoboCup_ARM\tmp_replay_test";
rgbDir = fullfile(datasetPath, "rgb");
depthDir = fullfile(datasetPath, "depth");
KPath = fullfile(datasetPath, "K.txt");
% poseDir = fullfile(fileparts(datasetPath), "pose_v3");
poseDir = fullfile(datasetPath, "pose_v2");

scriptDir = fileparts(mfilename('fullpath'));
onnxPathBBox = fullfile(scriptDir, "model", "best10.onnx");
onnxPathSeg  = fullfile(scriptDir, "model", "best10_seg_v3.onnx");

%% ---------------- params ----------------
imgsz   = 640;
confTh  = 0.70;
nmsIou  = 0.50;
showVis = true;
showVis3D = true;
saveCloud = false;
saveResults = true;
useBBoxModel = false;           % false: run segmentation-only pipeline (do NOT run best10.onnx)
markPartial = true;
edgeMarginPx = 1;
partialUseMaskEvidence = true;  % partial = bbox_hard OR mask_soft (for seg classes)
partialMaskEdgeMarginPx = 2;    % mask edge band width in pixels
partialMaskMinAreaPx = 150;     % ignore tiny masks for partial decision
partialMaskMinCompAreaPx = 40;  % remove tiny connected components before ratio checks
partialMaskEdgeRatioThr = 0.03; % edge-touch pixels / mask area
partialMaskGripRatioThr = 0.05; % gripper-overlap pixels / mask area
useGripperROI = true;
gripperROIPath = fullfile(datasetPath, "gripper_roi.mat");
usePoseTiltComp = true;
requirePoseTilt = false;
debugSegView = struct( ...
    "enable", true, ...          % true: enable per-object 3D segmentation debug
    "class", "b", ...             % one of: b,c,s,p,m or "all"
    "imageName", "rgb_000468.png", ... % empty string: all images
    "detIndex", [], ...            % []: all detections in selected class
    "showTiltFrame", true ...     % show rotated working-frame subplot
    );
forceBottleBUseMainCluster = false; % hard override: true -> always use main cluster
bottleBAutoSelect = true;           % true -> evaluate main/special candidates and auto-select
bottleBMinAcceptScore = 0.35;       % if best candidate score below this, fallback to main cluster
debugBottle = false;
debugBottleMax = 3;
debugCan = false;
debugCanMax = 3;
canTallZSpanAbsThr = 0.085; % CAN AB override: absolute tall threshold (m)
canTallZtoRFactor = 1.8;    % CAN AB override: relative tall threshold vs rXY90
canForceTallMinCos = 0.55;  % CAN AB override gate: only allow tall->A when cosAxis is already near A
cylEdgeCleanupEnable = true; % remove attached box-edge planes for can/bottle clusters
cylEdgeCleanupDebug = false;

zMin = 0.30; zMax = 2.50;
gridStep   = 0.003;
outlierNb  = 20;
outlierStd = 2.0;

maskThresh  = 0.50;
maskMinArea = 0;
maskUseBBox = true;
useSegMaskForCanBottle = true;  % detect for object list, seg mask for can/bottle cloud extraction
useSegMaskForSpam = true;       % detect for object list, seg mask for spam cloud extraction
segMatchIouThr = 0.25;          % IoU threshold when attaching seg instance to bbox detection
useSegAsPrimaryForCanBottleSpam = true; % true: can/bottle/spam use segmentation detections as primary
useSegAsPrimaryForCube = true;          % true: cube uses segmentation detections as primary
spamRectUseAll = false;         % spam rect fit: false -> fit on target face points only
spamRectPadFrac = 0.005;        % spam rect pad fraction (smaller than default to reduce over-expansion)
enableColorRecognition = true;  % estimate object color for can/bottle/cube
colorCfg = default_color_config();

classNamesBBox = {'b','c','m','p','s'};

if ~useBBoxModel && (~useSegAsPrimaryForCanBottleSpam || ~useSegAsPrimaryForCube)
    error("useBBoxModel=false requires useSegAsPrimaryForCanBottleSpam=true and useSegAsPrimaryForCube=true.");
end

%% ---------------- load K ----------------
K = load(KPath);
fx  = K(1,1); fy  = K(2,2);
cx0 = K(1,3); cy0 = K(2,3);

%% ---------------- init onnxruntime ----------------
pyenv;
ort  = py.importlib.import_module('onnxruntime');
np   = py.importlib.import_module('numpy');
availProvTxt = string(py.builtins.repr(ort.get_available_providers()));
providersCell = {};
if contains(availProvTxt, "CUDAExecutionProvider")
    providersCell{end+1} = 'CUDAExecutionProvider';
end
if contains(availProvTxt, "DmlExecutionProvider")
    providersCell{end+1} = 'DmlExecutionProvider';
end
providersCell{end+1} = 'CPUExecutionProvider';
providersPref = py.list(providersCell);
if useBBoxModel
    if exist(onnxPathBBox, 'file') ~= 2
        error("BBox model not found: %s", onnxPathBBox);
    end
    try
        sessBBox = ort.InferenceSession(char(onnxPathBBox), pyargs('providers', providersPref));
    catch ME
        warning('BBox preferred GPU providers init failed, fallback to default: %s', ME.message);
        sessBBox = ort.InferenceSession(char(onnxPathBBox));
    end
    try
        disp("[ORT] bbox providers = " + string(py.builtins.repr(sessBBox.get_providers())));
    catch
        disp("[ORT] bbox providers query failed.");
    end
else
    sessBBox = [];
end
if exist(onnxPathSeg, 'file') ~= 2
    error("Seg model not found: %s", onnxPathSeg);
end
try
    sessSeg = ort.InferenceSession(char(onnxPathSeg), pyargs('providers', providersPref));
catch ME
    warning('Seg preferred GPU providers init failed, fallback to default: %s', ME.message);
    sessSeg = ort.InferenceSession(char(onnxPathSeg));
end
try
    disp("[ORT] seg providers = " + string(py.builtins.repr(sessSeg.get_providers())));
catch
    disp("[ORT] seg providers query failed.");
end
if useBBoxModel
    disp('ONNX Runtime ready (bbox + seg).');
else
    disp('ONNX Runtime ready (seg only).');
end
%% ---------------- list image pairs ----------------
rgbFiles = dir(fullfile(rgbDir, "rgb_*.png"));
if isempty(rgbFiles)
    error("No rgb_*.png found in %s", rgbDir);
end
[~, order] = sort({rgbFiles.name});
rgbFiles = rgbFiles(order);

results = struct("datasetPath", datasetPath, "K", K, "images", []);

for i = 1:numel(rgbFiles)
    rgbPath = fullfile(rgbDir, rgbFiles(i).name);
    idxStr = extractIndex(rgbFiles(i).name);
    if isempty(idxStr)
        warning("Skip %s (cannot parse index).", rgbFiles(i).name);
        continue;
    end
    depthPath = fullfile(depthDir, sprintf("depth_%s.npy", idxStr));
    if ~exist(depthPath, "file")
        warning("Skip %s (missing depth %s).", rgbFiles(i).name, depthPath);
        continue;
    end

    rgb = imread(rgbPath);
    depth = readNPY(depthPath);
    H = size(rgb,1); W = size(rgb,2);

    fprintf("Image %d/%d: %s\n", i, numel(rgbFiles), rgbFiles(i).name);

    posePath = fullfile(poseDir, sprintf("pose_%s.txt", idxStr));
    upAxisCam = [0 0 -1];
    if usePoseTiltComp
        if exist(posePath, "file")
            try
                upAxisCam = load_up_axis_from_pose_file(posePath);
            catch ME
                if requirePoseTilt
                    warning("Skip %s (invalid pose %s): %s", rgbFiles(i).name, posePath, ME.message);
                    continue;
                else
                    warning("Invalid pose %s: %s (fallback to default axis)", posePath, ME.message);
                end
            end
        else
            if requirePoseTilt
                warning("Skip %s (missing pose %s).", rgbFiles(i).name, posePath);
                continue;
            end
        end
    end
    tiltTf = build_tilt_tf(upAxisCam);

    % ---------------- gripper ROI mask (optional) ----------------
    gripperMask = [];
    if useGripperROI && exist(gripperROIPath, "file")
        Sg = load(gripperROIPath);
        if isfield(Sg, "mask")
            m = Sg.mask;
            if isequal(size(m,1), H) && isequal(size(m,2), W)
                gripperMask = logical(m);
            end
        elseif isfield(Sg, "poly")
            poly = Sg.poly;
            if ~isempty(poly) && size(poly,2) == 2
                gripperMask = poly2mask(poly(:,1), poly(:,2), H, W);
            end
        end
    end

    % ---------------- shared input tensor ----------------
    [I640, scale, pad] = letterbox(rgb, imgsz);
    X = im2single(I640);
    X = permute(X,[3 1 2]);
    X = reshape(X,[1 3 size(I640,1) size(I640,2)]);
    Xnp = np.array(X);

    % bbox detections are optional (seg-only mode keeps them empty)
    detB = struct("bbox", {}, "bbox640", {}, "score", {}, "partial", {});
    detC = struct("bbox", {}, "bbox640", {}, "score", {}, "partial", {});
    detP = struct("bbox", {}, "bbox640", {}, "score", {}, "partial", {});
    detS = struct("bbox", {}, "bbox640", {}, "score", {}, "partial", {});
    if useBBoxModel
        outs = sessBBox.run(py.list(), py.dict(pyargs('images', Xnp)));
        Y = single(outs{1});
        Y = squeeze(Y);

        xywh = Y(1:4,:);
        cls  = Y(5:end,:);
        if min(cls(:)) < 0 || max(cls(:)) > 1
            cls = 1 ./ (1 + exp(-cls));
        end
        [scoreAll, cidAll] = max(cls,[],1);

        % all detections (b,c,p,s) after per-class NMS
        detB = collectDetectionsByClass('b', xywh, scoreAll, cidAll, classNamesBBox, confTh, nmsIou, scale, pad, W, H, markPartial, edgeMarginPx, gripperMask);
        detC = collectDetectionsByClass('c', xywh, scoreAll, cidAll, classNamesBBox, confTh, nmsIou, scale, pad, W, H, markPartial, edgeMarginPx, gripperMask);
        detP = collectDetectionsByClass('p', xywh, scoreAll, cidAll, classNamesBBox, confTh, nmsIou, scale, pad, W, H, markPartial, edgeMarginPx, gripperMask);
        detS = collectDetectionsByClass('s', xywh, scoreAll, cidAll, classNamesBBox, confTh, nmsIou, scale, pad, W, H, markPartial, edgeMarginPx, gripperMask);
    end

    % ---------------- segmentation inference ----------------
    outsS = sessSeg.run(py.list(), py.dict(pyargs('images', Xnp)));
    [pred, proto] = parseSegOutputs(outsS);
    nm = size(proto,1);
    [xywhS, clsS, maskCoeffS, ncS] = splitPred(pred, nm);
    if ncS == 8
        classNamesSeg = {'bottle','can','marker','spam','cube','cardboard_box','tray','scale'};
    elseif ncS == 5
        classNamesSeg = {'bottle','can','marker','spam','cube'};
    elseif ncS == 1
        classNamesSeg = {'marker'};
    else
        classNamesSeg = buildClassNames(ncS, 'marker');
    end
    if min(clsS(:)) < 0 || max(clsS(:)) > 1
        clsS = 1 ./ (1 + exp(-clsS));
    end
    [scoreS, cidS] = max(clsS, [], 1);
    detBSeg = collectSegDetectionsByClass({'bottle','b'}, xywhS, scoreS, cidS, maskCoeffS, classNamesSeg, ...
        confTh, nmsIou, scale, pad, W, H, markPartial, edgeMarginPx, gripperMask, ...
        proto, imgsz, maskThresh, maskMinArea, maskUseBBox, ...
        partialUseMaskEvidence, partialMaskEdgeMarginPx, partialMaskMinAreaPx, partialMaskMinCompAreaPx, ...
        partialMaskEdgeRatioThr, partialMaskGripRatioThr);
    detCSeg = collectSegDetectionsByClass({'can','c'}, xywhS, scoreS, cidS, maskCoeffS, classNamesSeg, ...
        confTh, nmsIou, scale, pad, W, H, markPartial, edgeMarginPx, gripperMask, ...
        proto, imgsz, maskThresh, maskMinArea, maskUseBBox, ...
        partialUseMaskEvidence, partialMaskEdgeMarginPx, partialMaskMinAreaPx, partialMaskMinCompAreaPx, ...
        partialMaskEdgeRatioThr, partialMaskGripRatioThr);
    detSSeg = collectSegDetectionsByClass({'spam','s'}, xywhS, scoreS, cidS, maskCoeffS, classNamesSeg, ...
        confTh, nmsIou, scale, pad, W, H, markPartial, edgeMarginPx, gripperMask, ...
        proto, imgsz, maskThresh, maskMinArea, maskUseBBox, ...
        partialUseMaskEvidence, partialMaskEdgeMarginPx, partialMaskMinAreaPx, partialMaskMinCompAreaPx, ...
        partialMaskEdgeRatioThr, partialMaskGripRatioThr);
    detM = collectSegDetectionsByClass({'marker','m'}, xywhS, scoreS, cidS, maskCoeffS, classNamesSeg, ...
        confTh, nmsIou, scale, pad, W, H, markPartial, edgeMarginPx, gripperMask, ...
        proto, imgsz, maskThresh, maskMinArea, maskUseBBox, ...
        partialUseMaskEvidence, partialMaskEdgeMarginPx, partialMaskMinAreaPx, partialMaskMinCompAreaPx, ...
        partialMaskEdgeRatioThr, partialMaskGripRatioThr);
    
    detPSeg = collectSegDetectionsByClass({'cube','p'}, xywhS, scoreS, cidS, maskCoeffS, classNamesSeg, ...
        confTh, nmsIou, scale, pad, W, H, markPartial, edgeMarginPx, gripperMask, ...
        proto, imgsz, maskThresh, maskMinArea, maskUseBBox, ...
        partialUseMaskEvidence, partialMaskEdgeMarginPx, partialMaskMinAreaPx, partialMaskMinCompAreaPx, ...
        partialMaskEdgeRatioThr, partialMaskGripRatioThr);

    if useSegAsPrimaryForCanBottleSpam
        detBProc = detBSeg;
        detCProc = detCSeg;
        detSProc = detSSeg;
    else
        if useSegMaskForCanBottle
            detBProc = attach_seg_masks_to_detections(detB, detBSeg, segMatchIouThr);
            detCProc = attach_seg_masks_to_detections(detC, detCSeg, segMatchIouThr);
        else
            detBProc = detB;
            detCProc = detC;
        end
        if useSegMaskForSpam
            detSProc = attach_seg_masks_to_detections(detS, detSSeg, segMatchIouThr);
        else
            detSProc = detS;
        end
    end

    if useSegAsPrimaryForCube
        detPProc = detPSeg;
    else
        detPProc = detP;
    end

    % ---------------- process classes ----------------
    canObjs    = process_can(detCProc, depth, K, fx, fy, cx0, cy0, zMin, zMax, saveCloud, debugCan, debugCanMax, ...
        tiltTf, debugSegView, rgbFiles(i).name, canTallZSpanAbsThr, canTallZtoRFactor, canForceTallMinCos, ...
        cylEdgeCleanupEnable, cylEdgeCleanupDebug, proto, imgsz, maskThresh, maskMinArea, maskUseBBox, ...
        rgb, scale, pad, enableColorRecognition, colorCfg);
    bottleObjs = process_bottle(detBProc, depth, K, fx, fy, cx0, cy0, zMin, zMax, saveCloud, debugBottle, debugBottleMax, ...
        tiltTf, debugSegView, rgbFiles(i).name, forceBottleBUseMainCluster, bottleBAutoSelect, bottleBMinAcceptScore, ...
        cylEdgeCleanupEnable, cylEdgeCleanupDebug, proto, imgsz, maskThresh, maskMinArea, maskUseBBox, ...
        rgb, scale, pad, enableColorRecognition, colorCfg);
    spamObjs   = process_spam(detSProc, depth, K, fx, fy, cx0, cy0, zMin, zMax, saveCloud, tiltTf, debugSegView, rgbFiles(i).name, ...
        proto, imgsz, maskThresh, maskMinArea, maskUseBBox, spamRectUseAll, spamRectPadFrac);
    cubeObjs   = process_cube(detPProc, depth, K, fx, fy, cx0, cy0, zMin, zMax, saveCloud, tiltTf, debugSegView, rgbFiles(i).name, ...
        proto, imgsz, maskThresh, maskMinArea, maskUseBBox, rgb, enableColorRecognition, colorCfg);
    markerObjs = process_marker(detM, proto, depth, K, fx, fy, cx0, cy0, ...
        zMin, zMax, maskThresh, maskMinArea, maskUseBBox, imgsz, saveCloud, tiltTf, debugSegView, rgbFiles(i).name);

    imgRes = struct( ...
        "name", rgbFiles(i).name, ...
        "rgbPath", rgbPath, ...
        "depthPath", depthPath, ...
        "posePath", posePath, ...
        "upAxisCam", upAxisCam, ...
        "can", canObjs, ...
        "bottle", bottleObjs, ...
        "spam", spamObjs, ...
        "marker", markerObjs, ...
        "cube", cubeObjs ...
        );
    results.images = [results.images; imgRes];
    if showVis
        show_image_results(rgb, imgRes, gripperMask);
        drawnow;
    end
    if showVis3D
        show_3d_results(imgRes);
        drawnow;
    end
end

if saveResults
    save("parallel_recognition_results.mat", "results");
    disp("Saved: parallel_recognition_results.mat");
else
    disp("Skip saving results (saveResults=false).");
end

%% =========================================================
%  Helper functions
%% =========================================================
function idxStr = extractIndex(name)
    idxStr = ";
    m = regexp(name, 'rgb_(\d+)\.png', 'tokens', 'once');
    if ~isempty(m)
        idxStr = m{1};
    end
end

function upAxisCam = load_up_axis_from_pose_file(posePath)
    txt = fileread(posePath);
    qTok = regexp(txt, 'quaternion_xyzw:\s*\[([^\]]+)\]', 'tokens', 'once');
    if isempty(qTok)
        error("Pose file missing quaternion_xyzw");
    end
    q = sscanf(qTok{1}, '%f, %f, %f, %f');
    if numel(q) ~= 4
        error("Invalid quaternion format in %s", posePath);
    end
    q = q(:)' ./ max(norm(q), 1e-12);
    Rwc = quat_xyzw_to_rotm(q);
    upAxisCam = (Rwc' * [0;0;1])';
    if any(~isfinite(upAxisCam)) || norm(upAxisCam) < 1e-9
        upAxisCam = [0 0 -1];
    else
        upAxisCam = upAxisCam / norm(upAxisCam);
    end
end

function R = quat_xyzw_to_rotm(qxyzw)
    qxyzw = reshape(double(qxyzw), [1 4]);
    x = qxyzw(1); y = qxyzw(2); z = qxyzw(3); w = qxyzw(4);
    R = [ ...
        1 - 2*(y*y + z*z), 2*(x*y - z*w),     2*(x*z + y*w); ...
        2*(x*y + z*w),     1 - 2*(x*x + z*z), 2*(y*z - x*w); ...
        2*(x*z - y*w),     2*(y*z + x*w),     1 - 2*(x*x + y*y) ...
        ];
end

function tf = build_tilt_tf(upAxisCam)
    upAxisCam = upAxisCam(:);
    if numel(upAxisCam) ~= 3 || any(~isfinite(upAxisCam)) || norm(upAxisCam) < 1e-9
        upAxisCam = [0;0;-1];
    end
    upAxisCam = upAxisCam / norm(upAxisCam);
    target = [0;0;-1];
    R = align_vectors_rotm(upAxisCam, target);
    tf = struct("R", R, "Rt", R', "enabled", norm(R - eye(3), 'fro') > 1e-9);
end

function Pout = apply_tilt_points(Pin, tf)
    if isempty(Pin)
        Pout = zeros(0,3);
        return;
    end
    if ~tf.enabled
        Pout = Pin;
        return;
    end
    if isvector(Pin) && numel(Pin) == 3
        Pin = reshape(Pin, [1 3]);
    end
    Pout = (tf.R * Pin')';
end

function Pout = undo_tilt_points(Pin, tf)
    if isempty(Pin)
        Pout = zeros(0,3);
        return;
    end
    if ~tf.enabled
        Pout = Pin;
        return;
    end
    if isvector(Pin) && numel(Pin) == 3
        Pin = reshape(Pin, [1 3]);
    end
    Pout = (tf.Rt * Pin')';
end

function vOut = undo_tilt_dir(vIn, tf)
    if isempty(vIn)
        vOut = zeros(1,3);
        return;
    end
    v = reshape(vIn, [3 1]);
    if tf.enabled
        v = tf.Rt * v;
    end
    n = norm(v);
    if n > 1e-12
        v = v / n;
    end
    vOut = v(:)';
end

function R = align_vectors_rotm(a, b)
    a = a(:) / max(norm(a), 1e-12);
    b = b(:) / max(norm(b), 1e-12);
    v = cross(a, b);
    c = dot(a, b);
    s = norm(v);
    if s < 1e-12
        if c > 0
            R = eye(3);
            return;
        end
        % 180 deg: choose axis orthogonal to a
        if abs(a(1)) < 0.9
            u = [1;0;0];
        else
            u = [0;1;0];
        end
        v = cross(a, u);
        v = v / max(norm(v), 1e-12);
        K = [0 -v(3) v(2); v(3) 0 -v(1); -v(2) v(1) 0];
        R = eye(3) + 2 * (K * K);
        return;
    end
    K = [0 -v(3) v(2); v(3) 0 -v(1); -v(2) v(1) 0];
    R = eye(3) + K + K*K*((1-c)/(s^2));
end

function cfg = default_seg_debug()
    cfg = struct( ...
        "enable", false, ...
        "class", "all", ...
        "imageName", ", ...
        "detIndex", [], ...
        "showTiltFrame", true ...
        );
end

function showTilt = get_debug_show_tilt(cfg)
    showTilt = true;
    if nargin < 1 || isempty(cfg)
        return;
    end
    if isfield(cfg, "showTiltFrame")
        showTilt = logical(cfg.showTiltFrame);
    end
end

function tf = should_show_seg_debug(cfg, clsTag, imgName, detIdx)
    tf = false;
    if nargin < 1 || isempty(cfg) || ~isfield(cfg, "enable") || ~cfg.enable
        return;
    end
    if nargin < 2
        return;
    end
    clsWant = "all";
    if isfield(cfg, "class") && strlength(string(cfg.class)) > 0
        clsWant = lower(string(cfg.class));
    end
    if clsWant ~= "all" && clsWant ~= lower(string(clsTag))
        return;
    end
    if isfield(cfg, "imageName") && strlength(string(cfg.imageName)) > 0
        if string(imgName) ~= string(cfg.imageName)
            return;
        end
    end
    if isfield(cfg, "detIndex") && ~isempty(cfg.detIndex)
        if detIdx ~= cfg.detIndex
            return;
        end
    end
    tf = true;
end

function show_segmentation_debug_cloud(figTitle, PbeforeCam, PbeforeWork, PafterWork, tiltTf, showTiltFrame, overlay)
    if nargin < 6
        showTiltFrame = true;
    end
    if nargin < 7 || isempty(overlay)
        overlay = struct();
    end
    PbCam = sample_cloud(PbeforeCam, 12000);
    Pw = sample_cloud(PbeforeWork, 12000);
    PaW = sample_cloud(PafterWork, 12000);
    PaCam = undo_tilt_points(PaW, tiltTf);
    [centerW, axisW, interW] = get_seg_overlay_work(overlay);
    centerCam = undo_tilt_points(centerW, tiltTf);
    axisCam = undo_tilt_points(axisW, tiltTf);
    interCam = undo_tilt_points(interW, tiltTf);
    overlayWorkAll = [centerW; axisW; interW];
    overlayCamAll = [centerCam; axisCam; interCam];

    hFig = figure('Name', figTitle);
    rotate3d(hFig, 'on');
    if showTiltFrame
        t = tiledlayout(1,3, "Padding","compact", "TileSpacing","compact");
        title(t, figTitle);

        nexttile;
        hold on; grid on; axis equal;
        if ~isempty(PbCam)
            scatter3(PbCam(:,1), PbCam(:,2), PbCam(:,3), 4, [0.5 0.5 0.5], 'filled');
        end
        plot_seg_overlay3d(centerCam, axisCam, interCam);
        xlabel('X'); ylabel('Y'); zlabel('Z');
        setup_seg_axes3d([PbCam; overlayCamAll]);
        title('Before (camera)');
        hold off;

        nexttile;
        hold on; grid on; axis equal;
        if ~isempty(Pw)
            scatter3(Pw(:,1), Pw(:,2), Pw(:,3), 4, [0.5 0.5 0.5], 'filled');
        end
        if ~isempty(PaW)
            scatter3(PaW(:,1), PaW(:,2), PaW(:,3), 6, [0.0 0.7 0.2], 'filled');
        end
        plot_seg_overlay3d(centerW, axisW, interW);
        xlabel('X'); ylabel('Y'); zlabel('Z');
        setup_seg_axes3d([Pw; PaW; overlayWorkAll]);
        title('Work Frame (gray=before, green=after)');
        hold off;

        nexttile;
        hold on; grid on; axis equal;
        if ~isempty(PbCam)
            scatter3(PbCam(:,1), PbCam(:,2), PbCam(:,3), 4, [0.5 0.5 0.5], 'filled');
        end
        if ~isempty(PaCam)
            scatter3(PaCam(:,1), PaCam(:,2), PaCam(:,3), 6, [0.0 0.7 0.2], 'filled');
        end
        plot_seg_overlay3d(centerCam, axisCam, interCam);
        xlabel('X'); ylabel('Y'); zlabel('Z');
        setup_seg_axes3d([PbCam; PaCam; overlayCamAll]);
        title('Camera Frame (gray=before, green=after)');
        hold off;
    else
        t = tiledlayout(1,2, "Padding","compact", "TileSpacing","compact");
        title(t, figTitle);

        nexttile;
        hold on; grid on; axis equal;
        if ~isempty(PbCam)
            scatter3(PbCam(:,1), PbCam(:,2), PbCam(:,3), 4, [0.5 0.5 0.5], 'filled');
        end
        plot_seg_overlay3d(centerCam, axisCam, interCam);
        xlabel('X'); ylabel('Y'); zlabel('Z');
        setup_seg_axes3d([PbCam; overlayCamAll]);
        title('Before (camera)');
        hold off;

        nexttile;
        hold on; grid on; axis equal;
        if ~isempty(PbCam)
            scatter3(PbCam(:,1), PbCam(:,2), PbCam(:,3), 4, [0.5 0.5 0.5], 'filled');
        end
        if ~isempty(PaCam)
            scatter3(PaCam(:,1), PaCam(:,2), PaCam(:,3), 6, [0.0 0.7 0.2], 'filled');
        end
        plot_seg_overlay3d(centerCam, axisCam, interCam);
        xlabel('X'); ylabel('Y'); zlabel('Z');
        setup_seg_axes3d([PbCam; PaCam; overlayCamAll]);
        title('After Segmentation (camera)');
        hold off;
    end
end

function [centerW, axisW, interW] = get_seg_overlay_work(overlay)
    centerW = zeros(0,3);
    axisW = zeros(0,3);
    interW = zeros(0,3);
    if isempty(overlay) || ~isstruct(overlay)
        return;
    end
    if isfield(overlay, "centerWork") && ~isempty(overlay.centerWork)
        centerW = reshape(double(overlay.centerWork), [], 3);
    end
    if isfield(overlay, "axisLineWork") && ~isempty(overlay.axisLineWork)
        axisW = reshape(double(overlay.axisLineWork), [], 3);
    end
    if isfield(overlay, "intersectLineWork") && ~isempty(overlay.intersectLineWork)
        interW = reshape(double(overlay.intersectLineWork), [], 3);
    end
end

function plot_seg_overlay3d(center3D, axisLine3D, intersectLine3D)
    if nargin < 1
        center3D = zeros(0,3);
    end
    if nargin < 2
        axisLine3D = zeros(0,3);
    end
    if nargin < 3
        intersectLine3D = zeros(0,3);
    end
    if size(axisLine3D,1) >= 2
        plot3(axisLine3D(:,1), axisLine3D(:,2), axisLine3D(:,3), '-', ...
            'Color', [0.2 0.9 1.0], 'LineWidth', 2.2);
    end
    if size(intersectLine3D,1) >= 2
        plot3(intersectLine3D(:,1), intersectLine3D(:,2), intersectLine3D(:,3), '-', ...
            'Color', [0.1 1.0 0.1], 'LineWidth', 2.2);
    end
    if size(center3D,1) >= 1
        c = center3D(1,:);
        if all(isfinite(c))
            plot3(c(1), c(2), c(3), 'o', ...
                'MarkerSize', 9, 'MarkerFaceColor', [1.0 0.85 0.0], 'MarkerEdgeColor', 'k', 'LineWidth', 1.2);
        end
    end
end

function setup_seg_axes3d(Pall)
    if nargin < 1 || isempty(Pall)
        view(35, 25);
        axis vis3d;
        return;
    end
    P = double(Pall);
    P = P(all(isfinite(P),2),:);
    if isempty(P)
        view(35, 25);
        axis vis3d;
        return;
    end
    mn = min(P, [], 1);
    mx = max(P, [], 1);
    span = mx - mn;
    maxSpan = max(span);
    if ~isfinite(maxSpan) || maxSpan < 1e-4
        maxSpan = 1e-3;
    end
    c = 0.5 * (mn + mx);
    half = 0.55 * maxSpan;
    xlim([c(1)-half, c(1)+half]);
    ylim([c(2)-half, c(2)+half]);
    zlim([c(3)-half, c(3)+half]);
    daspect([1 1 1]);
    axis vis3d;
    view(35, 25);
end

function dets = collectDetectionsByClass(targetClass, xywh, scoreAll, cidAll, classNames, confTh, nmsIou, scale, pad, W, H, markPartial, edgeMarginPx, gripperMask)
    dets = struct("bbox", {}, "bbox640", {}, "score", {}, "partial", {});
    if isempty(xywh)
        return;
    end
    isTarget = strcmp(classNames(cidAll), targetClass);
    keep = (scoreAll > confTh) & isTarget;
    if ~any(keep)
        return;
    end
    xywhK  = xywh(:,keep);
    scoreK = scoreAll(keep);

    cx = xywhK(1,:); cy = xywhK(2,:);
    w  = xywhK(3,:); h  = xywhK(4,:);
    x1 = cx - w/2; y1 = cy - h/2;
    x2 = cx + w/2; y2 = cy + h/2;
    b640_xyxy = [x1' y1' x2' y2'];

    keepIdx = nms_xyxy(b640_xyxy, scoreK, nmsIou);
    b640_xyxy = b640_xyxy(keepIdx,:);
    scoreK = scoreK(keepIdx);

    for i = 1:size(b640_xyxy,1)
        b_best = undoLetterbox_xyxy(b640_xyxy(i,:), scale, pad);
        b_best(1) = max(1, min(W, b_best(1)));
        b_best(3) = max(1, min(W, b_best(3)));
        b_best(2) = max(1, min(H, b_best(2)));
        b_best(4) = max(1, min(H, b_best(4)));
        b_best = [min(b_best(1),b_best(3)), min(b_best(2),b_best(4)), ...
                  max(b_best(1),b_best(3)), max(b_best(2),b_best(4))];
        isPartial = false;
        if markPartial
            isPartial = is_bbox_partial(b_best, W, H, edgeMarginPx);
            if ~isPartial && ~isempty(gripperMask)
                isPartial = is_bbox_overlapping_mask(b_best, gripperMask);
            end
        end
        dets(end+1) = struct("bbox", b_best, "bbox640", b640_xyxy(i,:), "score", scoreK(i), "partial", isPartial); %#ok<AGROW>
    end
end

function dets = collectSegDetectionsByClass(targetClass, xywh, scoreAll, cidAll, maskCoeff, classNames, confTh, nmsIou, scale, pad, W, H, markPartial, edgeMarginPx, gripperMask, ...
    proto, imgsz, maskThresh, maskMinArea, maskUseBBox, useMaskEvidence, maskEdgeMarginPx, maskMinAreaPx, maskMinCompAreaPx, edgeRatioThr, gripRatioThr)
    dets = struct("bbox", {}, "bbox640", {}, "score", {}, "maskCoeff", {}, "partial", {});
    if nargin < 16
        proto = [];
    end
    if nargin < 17 || isempty(imgsz)
        imgsz = 640;
    end
    if nargin < 18 || isempty(maskThresh)
        maskThresh = 0.50;
    end
    if nargin < 19 || isempty(maskMinArea)
        maskMinArea = 0;
    end
    if nargin < 20 || isempty(maskUseBBox)
        maskUseBBox = true;
    end
    if nargin < 21 || isempty(useMaskEvidence)
        useMaskEvidence = false;
    end
    if nargin < 22 || isempty(maskEdgeMarginPx)
        maskEdgeMarginPx = 2;
    end
    if nargin < 23 || isempty(maskMinAreaPx)
        maskMinAreaPx = 150;
    end
    if nargin < 24 || isempty(maskMinCompAreaPx)
        maskMinCompAreaPx = 40;
    end
    if nargin < 25 || isempty(edgeRatioThr)
        edgeRatioThr = 0.03;
    end
    if nargin < 26 || isempty(gripRatioThr)
        gripRatioThr = 0.05;
    end
    if isempty(xywh)
        return;
    end
    if iscell(targetClass) || isstring(targetClass)
        tnames = cellstr(string(targetClass));
    else
        tnames = {char(string(targetClass))};
    end
    cnameDet = classNames(cidAll);
    isTarget = false(size(cidAll));
    for it = 1:numel(tnames)
        isTarget = isTarget | strcmpi(cnameDet, tnames{it});
    end
    keep = (scoreAll > confTh) & isTarget;
    if ~any(keep)
        return;
    end
    xywhK  = xywh(:,keep);
    scoreK = scoreAll(keep);
    maskK  = maskCoeff(:,keep);

    cx = xywhK(1,:); cy = xywhK(2,:);
    w  = xywhK(3,:); h  = xywhK(4,:);
    x1 = cx - w/2; y1 = cy - h/2;
    x2 = cx + w/2; y2 = cy + h/2;
    b640_xyxy = [x1' y1' x2' y2'];

    keepIdx = nms_xyxy(b640_xyxy, scoreK, nmsIou);
    b640_xyxy = b640_xyxy(keepIdx,:);
    scoreK = scoreK(keepIdx);
    maskK = maskK(:,keepIdx);

    for i = 1:size(b640_xyxy,1)
        b_best = undoLetterbox_xyxy(b640_xyxy(i,:), scale, pad);
        b_best(1) = max(1, min(W, b_best(1)));
        b_best(3) = max(1, min(W, b_best(3)));
        b_best(2) = max(1, min(H, b_best(2)));
        b_best(4) = max(1, min(H, b_best(4)));
        b_best = [min(b_best(1),b_best(3)), min(b_best(2),b_best(4)), ...
                  max(b_best(1),b_best(3)), max(b_best(2),b_best(4))];
        isPartial = false;
        if markPartial
            isPartial = is_bbox_partial(b_best, W, H, edgeMarginPx);
            if ~isPartial && ~isempty(gripperMask)
                isPartial = is_bbox_overlapping_mask(b_best, gripperMask);
            end
            if useMaskEvidence && ~isempty(proto)
                maskSoft = is_mask_partial_soft(maskK(:,i), proto, imgsz, b640_xyxy(i,:), scale, pad, W, H, ...
                    maskThresh, maskMinArea, maskUseBBox, b_best, maskEdgeMarginPx, gripperMask, ...
                    maskMinAreaPx, maskMinCompAreaPx, edgeRatioThr, gripRatioThr);
                isPartial = isPartial || maskSoft;
            end
        end
        dets(end+1) = struct("bbox", b_best, "bbox640", b640_xyxy(i,:), "score", scoreK(i), ...
            "maskCoeff", maskK(:,i), "partial", isPartial); %#ok<AGROW>
    end
end

function detsOut = attach_seg_masks_to_detections(detsBBox, detsSeg, iouThr)
    detsOut = detsBBox;
    if nargin < 3 || isempty(iouThr)
        iouThr = 0.25;
    end
    if isempty(detsOut)
        return;
    end
    for i = 1:numel(detsOut)
        detsOut(i).maskCoeff = [];
        detsOut(i).maskBBox640 = [];
        detsOut(i).maskScore = NaN;
    end
    if isempty(detsSeg)
        return;
    end
    used = false(1, numel(detsSeg));
    for i = 1:numel(detsOut)
        b = detsOut(i).bbox640;
        bestJ = 0;
        bestIou = -inf;
        bestScore = -inf;
        for j = 1:numel(detsSeg)
            if used(j)
                continue;
            end
            iou = box_iou_pair_xyxy(b, detsSeg(j).bbox640);
            if iou > bestIou || (abs(iou - bestIou) < 1e-9 && detsSeg(j).score > bestScore)
                bestIou = iou;
                bestScore = detsSeg(j).score;
                bestJ = j;
            end
        end
        if bestJ > 0 && bestIou >= iouThr
            detsOut(i).maskCoeff = detsSeg(bestJ).maskCoeff;
            detsOut(i).maskBBox640 = detsSeg(bestJ).bbox640;
            detsOut(i).maskScore = detsSeg(bestJ).score;
            if isfield(detsSeg(bestJ), "partial")
                detsOut(i).partial = detsOut(i).partial || logical(detsSeg(bestJ).partial);
            end
            used(bestJ) = true;
        end
    end
end

function iou = box_iou_pair_xyxy(b1, b2)
    x1 = max(b1(1), b2(1));
    y1 = max(b1(2), b2(2));
    x2 = min(b1(3), b2(3));
    y2 = min(b1(4), b2(4));
    w = max(0, x2 - x1);
    h = max(0, y2 - y1);
    inter = w * h;
    a1 = max(0, b1(3)-b1(1)) * max(0, b1(4)-b1(2));
    a2 = max(0, b2(3)-b2(1)) * max(0, b2(4)-b2(2));
    iou = inter / max(a1 + a2 - inter, 1e-9);
end
function out = process_can(dets, depth, K, fx, fy, cx0, cy0, zMin, zMax, saveCloud, debugCan, debugCanMax, tiltTf, debugSegView, imgName, tallZSpanAbsThr, tallZtoRFactor, forceTallMinCos, edgeCleanupEnable, edgeCleanupDebug, protoSeg, imgsz, maskThresh, maskMinArea, maskUseBBox, rgb, scaleLB, padLB, enableColorRecognition, colorCfg)
    out = struct([]);
    if isempty(dets)
        return;
    end
    if nargin < 11
        debugCan = false;
    end
    if nargin < 12
        debugCanMax = 3;
    end
    if nargin < 13
        tiltTf = build_tilt_tf([0 0 -1]);
    end
    if nargin < 14
        debugSegView = default_seg_debug();
    end
    if nargin < 15
        imgName = ";
    end
    if nargin < 16
        tallZSpanAbsThr = 0.085;
    end
    if nargin < 17
        tallZtoRFactor = 1.8;
    end
    if nargin < 18
        forceTallMinCos = 0.55;
    end
    if nargin < 19
        edgeCleanupEnable = true;
    end
    if nargin < 20
        edgeCleanupDebug = false;
    end
    if nargin < 21
        protoSeg = [];
    end
    if nargin < 22
        imgsz = 640;
    end
    if nargin < 23
        maskThresh = 0.50;
    end
    if nargin < 24
        maskMinArea = 0;
    end
    if nargin < 25
        maskUseBBox = true;
    end
    if nargin < 26
        rgb = [];
    end
    if nargin < 27
        scaleLB = 1;
    end
    if nargin < 28
        padLB = [0 0];
    end
    if nargin < 29
        enableColorRecognition = false;
    end
    if nargin < 30 || isempty(colorCfg)
        colorCfg = default_color_config();
    end
    optsA = struct("topPct", 85, "planeMaxDist", 0.08, "planeAng", 15, ...
                   "minTopPts", 100, "band", 0.006, "tol", 0.006);
    optsB = struct("midBand", 0.004, "wallTol", 0.004, "tableMaxDist", 0.006, "tableAng", 10);
    abCosThr = 0.60;
    thinZSpanThr = 0.03; % if segmented cloud is too thin, force A
    tableTopPct = 80;
    tableMaxDist = 0.006;
    tableAng = 15;

    for i = 1:numel(dets)
        [Pc, ok] = det_to_cloud(dets(i), protoSeg, depth, K, zMin, zMax, maskThresh, maskMinArea, maskUseBBox, imgsz);
        if ~ok
            continue;
        end
        PcWork = apply_tilt_points(Pc, tiltTf);
        pcBox = pointCloud(PcWork);
        if debugCan && i <= debugCanMax
            fprintf("Can[%d] raw cloud points: %d\n", i, pcBox.Count);
            zAll = pcBox.Location(:,3);
            fprintf("Can[%d] raw Z range: %.4f ~ %.4f (span=%.4f)\n", i, min(zAll), max(zAll), max(zAll)-min(zAll));
        end
        pcObj = segment_largest_cluster(pcBox, debugCan && i <= debugCanMax, i);
        if pcObj.Count < 50
            continue;
        end
        if debugCan && i <= debugCanMax
            zSeg = pcObj.Location(:,3);
            fprintf("Can[%d] seg points: %d\n", i, pcObj.Count);
            fprintf("Can[%d] seg Z range: %.4f ~ %.4f (span=%.4f)\n", i, min(zSeg), max(zSeg), max(zSeg)-min(zSeg));
            figure('Name', sprintf('Can segmented cloud [%d]', i));
            pcshow(pcObj); xlabel('X'); ylabel('Y'); zlabel('Z');
            title(sprintf('Can segmented cloud [%d]', i));
        end
        % merge possible bottom-cap points that were split into a small cluster
        pcObj = merge_bottom_cap(pcObj, pcBox);
        pcObjAB = pcObj;  % keep AB judgement on pre-clean cloud to avoid over-clean side effects
        pcObjFit = pcObj;
        if edgeCleanupEnable
            pcObjFit = cleanup_cylinder_attachment(pcObjFit, edgeCleanupDebug || (debugCan && i <= debugCanMax), sprintf("Can[%d]", i));
        end
        segDbgEnable = should_show_seg_debug(debugSegView, "c", imgName, i);
        segDbgShowTilt = get_debug_show_tilt(debugSegView);
        zSpan = max(pcObjAB.Location(:,3)) - min(pcObjAB.Location(:,3));
        CxyObj = mean(pcObjAB.Location(:,1:2), 1);
        rObj = sqrt(sum((pcObjAB.Location(:,1:2) - CxyObj).^2, 2));
        rXY90 = prctile(rObj, 90);
        [abLabel, abInfo] = classifyAB_table(pcObjAB, pcBox, abCosThr, tableTopPct, tableMaxDist, tableAng);
        forceAThin = zSpan < thinZSpanThr;
        % Guard force-tall override: only allow when geometric AB score is already near A
        forceATall = abInfo.tableFound && (abInfo.cosAxis >= forceTallMinCos) && ...
            (zSpan > max(tallZSpanAbsThr, tallZtoRFactor * rXY90));
        if forceAThin || forceATall
            abLabel = 1; % force A when cloud is nearly planar
        end
        if debugCan && i <= debugCanMax
            if isfield(abInfo, "axisSource")
                fprintf("Can[%d] AB: cosAxis=%.3f tableFound=%d cosTable=%.3f zTable=%.3f zSpan=%.4f rXY90=%.4f forceThin=%d forceTall=%d axis=%s sc=%.3f(pca=%.3f wall=%.3f) -> %s\n", ...
                    i, abInfo.cosAxis, abInfo.tableFound, abInfo.cosTable, abInfo.zTable, zSpan, ...
                    rXY90, forceAThin, forceATall, string(abInfo.axisSource), abInfo.axisScore, ...
                    abInfo.axisScorePCA, abInfo.axisScoreWall, ternary(abLabel==1,"A","B"));
            else
                fprintf("Can[%d] AB: cosAxis=%.3f tableFound=%d cosTable=%.3f zTable=%.3f zSpan=%.4f rXY90=%.4f forceThin=%d forceTall=%d -> %s\n", ...
                    i, abInfo.cosAxis, abInfo.tableFound, abInfo.cosTable, abInfo.zTable, zSpan, rXY90, ...
                    forceAThin, forceATall, ternary(abLabel==1,"A","B"));
            end
        end
        if abLabel == 1
            [center3DWork, axisVecWork, ~] = fit_cap_center_axis_A(pcObjFit, optsA);
            axisLine3DWork = axis_line_from_cloud(pcObjFit.Location, axisVecWork, center3DWork);
            if segDbgEnable
                dbgOverlay = struct("centerWork", center3DWork, "axisLineWork", axisLine3DWork, "intersectLineWork", []);
                show_segmentation_debug_cloud(sprintf("SegDebug CAN %s det#%d", imgName, i), ...
                    Pc, PcWork, pcObjFit.Location, tiltTf, segDbgShowTilt, dbgOverlay);
            end
            center3D = undo_tilt_points(center3DWork, tiltTf);
            axisVec = undo_tilt_dir(axisVecWork, tiltTf);
            axisLine3D = undo_tilt_points(axisLine3DWork, tiltTf);
            center2D = project_points(center3D, fx, fy, cx0, cy0);
            axisLine2D = project_points(axisLine3D, fx, fy, cx0, cy0);
            colorInfo = default_color_info();
            if enableColorRecognition
                colorInfo = estimate_cylinder_color_info(rgb, dets(i), protoSeg, imgsz, maskThresh, maskMinArea, ...
                    maskUseBBox, scaleLB, padLB, "can", "A", colorCfg);
            end
            obj = struct("bbox", dets(i).bbox, "score", dets(i).score, "ab", "A", ...
                "center3D", center3D, "center2D", center2D, ...
                "axis3D", axisVec, "axisLine3D", axisLine3D, "axisLine2D", axisLine2D, ...
                "intersectLine3D", [], "intersectLine2D", [], "partial", dets(i).partial, ...
                "color", colorInfo.label, "colorScore", colorInfo.score, "colorSource", colorInfo.source, ...
                "colorHSV", colorInfo.meanHSV, "colorRGB", colorInfo.meanRGB, "colorPixelCount", colorInfo.pixelCount, ...
                "points", colorInfo.points, "targetBin", colorInfo.targetBin);
            if saveCloud
                obj.cloud = sample_cloud(undo_tilt_points(pcObjFit.Location, tiltTf), 5000);
            end
        else
            [~, midPtWork, axisVecWork, infoB] = fit_caseB_target_point(pcObjFit, pcBox, optsB);
            line3DWork = infoB.linePts;
            centerAxisWork = center_from_axis_line_closest(midPtWork, axisVecWork, line3DWork);
            center3DWork = center_from_xy_min_z(pcObjFit.Location, centerAxisWork);
            axisLine3DWork = axis_line_from_cloud(pcObjFit.Location, axisVecWork, centerAxisWork);
            if segDbgEnable
                dbgOverlay = struct("centerWork", center3DWork, "axisLineWork", axisLine3DWork, "intersectLineWork", line3DWork);
                show_segmentation_debug_cloud(sprintf("SegDebug CAN %s det#%d", imgName, i), ...
                    Pc, PcWork, pcObjFit.Location, tiltTf, segDbgShowTilt, dbgOverlay);
            end
            center3D = undo_tilt_points(center3DWork, tiltTf);
            axisVec = undo_tilt_dir(axisVecWork, tiltTf);
            axisLine3D = undo_tilt_points(axisLine3DWork, tiltTf);
            line3D = undo_tilt_points(line3DWork, tiltTf);
            center2D = project_points(center3D, fx, fy, cx0, cy0);
            axisLine2D = project_points(axisLine3D, fx, fy, cx0, cy0);
            line2D = project_points(line3D, fx, fy, cx0, cy0);
            colorInfo = default_color_info();
            if enableColorRecognition
                colorInfo = estimate_cylinder_color_info(rgb, dets(i), protoSeg, imgsz, maskThresh, maskMinArea, ...
                    maskUseBBox, scaleLB, padLB, "can", "B", colorCfg);
            end
            obj = struct("bbox", dets(i).bbox, "score", dets(i).score, "ab", "B", ...
                "center3D", center3D, "center2D", center2D, ...
                "axis3D", axisVec, "axisLine3D", axisLine3D, "axisLine2D", axisLine2D, ...
                "intersectLine3D", line3D, "intersectLine2D", line2D, "partial", dets(i).partial, ...
                "color", colorInfo.label, "colorScore", colorInfo.score, "colorSource", colorInfo.source, ...
                "colorHSV", colorInfo.meanHSV, "colorRGB", colorInfo.meanRGB, "colorPixelCount", colorInfo.pixelCount, ...
                "points", colorInfo.points, "targetBin", colorInfo.targetBin);
            if saveCloud
                obj.cloud = sample_cloud(undo_tilt_points(pcObjFit.Location, tiltTf), 5000);
            end
        end
        out = [out; obj]; %#ok<AGROW>
    end
end

function out = process_bottle(dets, depth, K, fx, fy, cx0, cy0, zMin, zMax, saveCloud, debugBottle, debugBottleMax, ...
    tiltTf, debugSegView, imgName, forceBUseMainCluster, bottleBAutoSelect, bottleBMinAcceptScore, edgeCleanupEnable, edgeCleanupDebug, ...
    protoSeg, imgsz, maskThresh, maskMinArea, maskUseBBox, rgb, scaleLB, padLB, enableColorRecognition, colorCfg)
    out = struct([]);
    if isempty(dets)
        return;
    end
    if nargin < 11
        debugBottle = false;
    end
    if nargin < 12
        debugBottleMax = 3;
    end
    if nargin < 13
        tiltTf = build_tilt_tf([0 0 -1]);
    end
    if nargin < 14
        debugSegView = default_seg_debug();
    end
    if nargin < 15
        imgName = ";
    end
    if nargin < 16
        forceBUseMainCluster = false;
    end
    if nargin < 17
        bottleBAutoSelect = true;
    end
    if nargin < 18
        bottleBMinAcceptScore = 0.35;
    end
    if nargin < 19
        edgeCleanupEnable = true;
    end
    if nargin < 20
        edgeCleanupDebug = false;
    end
    if nargin < 21
        protoSeg = [];
    end
    if nargin < 22
        imgsz = 640;
    end
    if nargin < 23
        maskThresh = 0.50;
    end
    if nargin < 24
        maskMinArea = 0;
    end
    if nargin < 25
        maskUseBBox = true;
    end
    if nargin < 26
        rgb = [];
    end
    if nargin < 27
        scaleLB = 1;
    end
    if nargin < 28
        padLB = [0 0];
    end
    if nargin < 29
        enableColorRecognition = false;
    end
    if nargin < 30 || isempty(colorCfg)
        colorCfg = default_color_config();
    end
    optsA = struct("bottomPct", 40, "planeMaxDist", 0.004, "zBand", 0.004, ...
                   "zExpand", 0.006, "zBin", 0.003, "minPts", 120);
    optsB = struct("midBand", 0.008, "wallTol", 0.006, "tableMaxDist", 0.006, ...
                   "tableAng", 10, "thickPct", 70, "thickTol", 0.005, "minCand", 50, ...
                   "axisMode", "wall", "debugB", false);
    abCosThr = 0.60;
    tableTopPct = 80;
    tableMaxDist = 0.006;
    tableAng = 15;

    for i = 1:numel(dets)
        [Pc, ok] = det_to_cloud(dets(i), protoSeg, depth, K, zMin, zMax, maskThresh, maskMinArea, maskUseBBox, imgsz);
        if ~ok
            continue;
        end
        PcWork = apply_tilt_points(Pc, tiltTf);
        pcBox = pointCloud(PcWork);
        if debugBottle && i <= debugBottleMax
            fprintf("Bottle[%d] raw cloud points: %d\n", i, pcBox.Count);
            zAll = pcBox.Location(:,3);
            fprintf("Bottle[%d] raw Z range: %.4f ~ %.4f (span=%.4f)\n", i, min(zAll), max(zAll), max(zAll)-min(zAll));
        end
        pcObj = segment_largest_cluster(pcBox, debugBottle && i <= debugBottleMax, i);
        if pcObj.Count < 50
            continue;
        end
        % merge possible bottom-cap points that were split into a small cluster
        pcObj = merge_bottom_cap(pcObj, pcBox);
        pcObjAB = pcObj;
        pcObjMainFit = pcObj;
        if edgeCleanupEnable
            pcObjMainFit = cleanup_cylinder_attachment(pcObjMainFit, edgeCleanupDebug || (debugBottle && i <= debugBottleMax), sprintf("Bottle[%d]-main", i));
        end
        if debugBottle && i <= debugBottleMax
            zSeg = pcObjMainFit.Location(:,3);
            fprintf("Bottle[%d] seg points: %d\n", i, pcObjMainFit.Count);
            fprintf("Bottle[%d] seg Z range: %.4f ~ %.4f (span=%.4f)\n", i, min(zSeg), max(zSeg), max(zSeg)-min(zSeg));
            figure('Name', sprintf('Bottle segmented cloud [%d]', i));
            pcshow(pcObjMainFit); xlabel('X'); ylabel('Y'); zlabel('Z');
            title(sprintf('Bottle segmented cloud [%d]', i));
        end
        segDbgEnable = should_show_seg_debug(debugSegView, "b", imgName, i);
        segDbgShowTilt = get_debug_show_tilt(debugSegView);
        [abLabel, ~] = classifyAB_table(pcObjAB, pcBox, abCosThr, tableTopPct, tableMaxDist, tableAng);
        if abLabel == 1
            [center3DWork, axisVecWork, ~] = fit_bottom_cap_center_axis_A_bottle(pcObjMainFit, optsA);
            axisLine3DWork = axis_line_from_cloud(pcObjMainFit.Location, axisVecWork, center3DWork);
            if segDbgEnable
                dbgOverlay = struct("centerWork", center3DWork, "axisLineWork", axisLine3DWork, "intersectLineWork", []);
                show_segmentation_debug_cloud(sprintf("SegDebug BOTTLE %s det#%d", imgName, i), ...
                    Pc, PcWork, pcObjMainFit.Location, tiltTf, segDbgShowTilt, dbgOverlay);
            end
            center3D = undo_tilt_points(center3DWork, tiltTf);
            axisVec = undo_tilt_dir(axisVecWork, tiltTf);
            axisLine3D = undo_tilt_points(axisLine3DWork, tiltTf);
            center2D = project_points(center3D, fx, fy, cx0, cy0);
            axisLine2D = project_points(axisLine3D, fx, fy, cx0, cy0);
            colorInfo = default_color_info();
            if enableColorRecognition
                colorInfo = estimate_cylinder_color_info(rgb, dets(i), protoSeg, imgsz, maskThresh, maskMinArea, ...
                    maskUseBBox, scaleLB, padLB, "bottle", "A", colorCfg);
            end
            obj = struct("bbox", dets(i).bbox, "score", dets(i).score, "ab", "A", ...
                "center3D", center3D, "center2D", center2D, ...
                "axis3D", axisVec, "axisLine3D", axisLine3D, "axisLine2D", axisLine2D, ...
                "intersectLine3D", [], "intersectLine2D", [], ...
                "clusterSource", "A", "clusterScore", NaN, "clusterLowConf", false, ...
                "partial", dets(i).partial, ...
                "color", colorInfo.label, "colorScore", colorInfo.score, "colorSource", colorInfo.source, ...
                "colorHSV", colorInfo.meanHSV, "colorRGB", colorInfo.meanRGB, "colorPixelCount", colorInfo.pixelCount, ...
                "points", colorInfo.points, "targetBin", colorInfo.targetBin);
            if saveCloud
                obj.cloud = sample_cloud(undo_tilt_points(pcObjMainFit.Location, tiltTf), 5000);
            end
        else
            % B-class: use a separate segmentation method (only for bottle B)
            sel = struct("source","main","bestScore",NaN,"lowConf",false);
            if forceBUseMainCluster
                pcUse = pcObjMainFit;
                [~, midPtWork, axisVecWork, infoB] = fit_caseB_target_point_bottle(pcUse, pcBox, optsB);
                sel.source = "main_forced";
                [sel.bestScore, ~] = score_bottle_B_candidate(infoB, pcUse.Count);
            else
                pcObjB = segment_bottle_B(pcBox, debugBottle && i <= debugBottleMax, i);
                if edgeCleanupEnable
                    pcObjB = cleanup_cylinder_attachment(pcObjB, edgeCleanupDebug || (debugBottle && i <= debugBottleMax), sprintf("Bottle[%d]-spec", i));
                end
                if bottleBAutoSelect
                    [pcUse, midPtWork, axisVecWork, infoB, sel] = choose_bottle_B_cluster( ...
                        pcObjMainFit, pcObjB, pcBox, optsB, bottleBMinAcceptScore, debugBottle && i <= debugBottleMax, i);
                else
                    if pcObjB.Count >= 50
                        pcUse = pcObjB;
                        sel.source = "special_direct";
                    else
                        pcUse = pcObjMainFit;
                        sel.source = "main_direct";
                    end
                    [~, midPtWork, axisVecWork, infoB] = fit_caseB_target_point_bottle(pcUse, pcBox, optsB);
                    [sel.bestScore, ~] = score_bottle_B_candidate(infoB, pcUse.Count);
                end
            end
            line3DWork = infoB.linePts;
            centerAxisWork = center_from_axis_line_closest(midPtWork, axisVecWork, line3DWork);
            center3DWork = center_from_xy_min_z(pcUse.Location, centerAxisWork);
            axisLine3DWork = axis_line_from_cloud(pcUse.Location, axisVecWork, centerAxisWork);
            if segDbgEnable
                dbgOverlay = struct("centerWork", center3DWork, "axisLineWork", axisLine3DWork, "intersectLineWork", line3DWork);
                show_segmentation_debug_cloud(sprintf("SegDebug BOTTLE %s det#%d", imgName, i), ...
                    Pc, PcWork, pcUse.Location, tiltTf, segDbgShowTilt, dbgOverlay);
            end
            center3D = undo_tilt_points(center3DWork, tiltTf);
            axisVec = undo_tilt_dir(axisVecWork, tiltTf);
            axisLine3D = undo_tilt_points(axisLine3DWork, tiltTf);
            line3D = undo_tilt_points(line3DWork, tiltTf);
            center2D = project_points(center3D, fx, fy, cx0, cy0);
            axisLine2D = project_points(axisLine3D, fx, fy, cx0, cy0);
            line2D = project_points(line3D, fx, fy, cx0, cy0);
            colorInfo = default_color_info();
            if enableColorRecognition
                colorInfo = estimate_cylinder_color_info(rgb, dets(i), protoSeg, imgsz, maskThresh, maskMinArea, ...
                    maskUseBBox, scaleLB, padLB, "bottle", "B", colorCfg);
            end
            obj = struct("bbox", dets(i).bbox, "score", dets(i).score, "ab", "B", ...
                "center3D", center3D, "center2D", center2D, ...
                "axis3D", axisVec, "axisLine3D", axisLine3D, "axisLine2D", axisLine2D, ...
                "intersectLine3D", line3D, "intersectLine2D", line2D, ...
                "clusterSource", sel.source, "clusterScore", sel.bestScore, "clusterLowConf", sel.lowConf, ...
                "partial", dets(i).partial, ...
                "color", colorInfo.label, "colorScore", colorInfo.score, "colorSource", colorInfo.source, ...
                "colorHSV", colorInfo.meanHSV, "colorRGB", colorInfo.meanRGB, "colorPixelCount", colorInfo.pixelCount, ...
                "points", colorInfo.points, "targetBin", colorInfo.targetBin);
            if saveCloud
                obj.cloud = sample_cloud(undo_tilt_points(pcUse.Location, tiltTf), 5000);
            end
        end
        out = [out; obj]; %#ok<AGROW>
    end
end

function [pcUse, midPt, axisVec, infoB, sel] = choose_bottle_B_cluster(pcMain, pcSpec, pcRaw, optsB, minAcceptScore, debugEnable, debugIdx)
    if nargin < 5 || isempty(minAcceptScore)
        minAcceptScore = 0.35;
    end
    if nargin < 6
        debugEnable = false;
    end
    if nargin < 7
        debugIdx = 0;
    end

    candNames = {"main", "special"};
    candCloud = {pcMain, pcSpec};
    candRes = repmat(struct("valid", false, "score", -inf, "midPt", [], "axisVec", [], "info", [], "count", 0), 1, 2);

    for k = 1:2
        pcK = candCloud{k};
        if isempty(pcK) || pcK.Count < 50
            continue;
        end
        try
            [~, mK, aK, infoK] = fit_caseB_target_point_bottle(pcK, pcRaw, optsB);
            [sc, parts] = score_bottle_B_candidate(infoK, pcK.Count);
            candRes(k).valid = true;
            candRes(k).score = sc;
            candRes(k).midPt = mK;
            candRes(k).axisVec = aK;
            candRes(k).info = infoK;
            candRes(k).count = pcK.Count;
            if debugEnable
                fprintf("BottleB[%d] cand=%s count=%d score=%.3f (numCand=%.2f cover=%.2f line=%.2f table=%.2f)\n", ...
                    debugIdx, candNames{k}, pcK.Count, sc, parts.numCandTerm, parts.coverTerm, parts.lineTerm, parts.tablePenalty);
            end
        catch ME
            if debugEnable
                fprintf("BottleB[%d] cand=%s fit failed: %s\n", debugIdx, candNames{k}, ME.message);
            end
        end
    end

    % default fallback
    kBest = 1;
    if candRes(2).valid && candRes(2).score > candRes(1).score
        kBest = 2;
    end
    if ~candRes(kBest).valid && candRes(1).valid
        kBest = 1;
    elseif ~candRes(kBest).valid && candRes(2).valid
        kBest = 2;
    end
    if ~candRes(kBest).valid
        % hard fallback: fit on main cluster
        [~, midPt, axisVec, infoB] = fit_caseB_target_point_bottle(pcMain, pcRaw, optsB);
        pcUse = pcMain;
        [bestScore, ~] = score_bottle_B_candidate(infoB, pcMain.Count);
        sel = struct("source", "main_fallback", "bestScore", bestScore, "lowConf", true);
        return;
    end

    % low-confidence fallback to main if special is uncertain
    if kBest == 2 && candRes(kBest).score < minAcceptScore && candRes(1).valid
        kBest = 1;
        lowConf = true;
        src = "main_lowconf_fallback";
    else
        lowConf = candRes(kBest).score < minAcceptScore;
        src = candNames{kBest};
    end

    pcUse = candCloud{kBest};
    midPt = candRes(kBest).midPt;
    axisVec = candRes(kBest).axisVec;
    infoB = candRes(kBest).info;
    sel = struct("source", string(src), "bestScore", candRes(kBest).score, "lowConf", lowConf);
end

function [score, parts] = score_bottle_B_candidate(infoB, cloudCount)
    if nargin < 2
        cloudCount = 0;
    end
    numCand = get_info_field(infoB, "numCand", 0);
    numMid = get_info_field(infoB, "numMid", 0);
    coverDeg = max(get_info_field(infoB, "coverDeg2", 0), get_info_field(infoB, "coverDeg", 0));
    radius = get_info_field(infoB, "radius", 0);
    tableFracCan = get_info_field(infoB, "tableFracCan", 0);
    linePts = get_info_field(infoB, "linePts", []);

    lineLen = 0;
    if ~isempty(linePts) && size(linePts,1) >= 2
        lineLen = norm(linePts(2,:) - linePts(1,:));
    end
    lineNorm = lineLen / max(2 * max(radius, 1e-4), 1e-4);

    numCandTerm = min(numCand / 180, 1);
    coverTerm = min(coverDeg / 200, 1);
    lineTerm = min(lineNorm / 1.5, 1);
    midTerm = min(numMid / 220, 1);
    countTerm = min(cloudCount / 1800, 1);
    tablePenalty = min(max(tableFracCan, 0), 1);

    score = 0.30 * numCandTerm + 0.25 * coverTerm + 0.18 * lineTerm + 0.12 * midTerm + 0.15 * countTerm - 0.30 * tablePenalty;
    if numCand < 35
        score = score - 0.20;
    end
    if coverDeg < 60
        score = score - 0.20;
    end

    parts = struct( ...
        "numCandTerm", numCandTerm, ...
        "coverTerm", coverTerm, ...
        "lineTerm", lineTerm, ...
        "midTerm", midTerm, ...
        "countTerm", countTerm, ...
        "tablePenalty", tablePenalty ...
        );
end

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
function out = process_spam(dets, depth, K, fx, fy, cx0, cy0, zMin, zMax, saveCloud, tiltTf, debugSegView, imgName, ...
    protoSeg, imgsz, maskThresh, maskMinArea, maskUseBBox, rectUseAll, rectPadFrac)
    out = struct([]);
    if isempty(dets)
        return;
    end
    if nargin < 11
        tiltTf = build_tilt_tf([0 0 -1]);
    end
    if nargin < 12
        debugSegView = default_seg_debug();
    end
    if nargin < 13
        imgName = ";
    end
    if nargin < 14
        protoSeg = [];
    end
    if nargin < 15
        imgsz = 640;
    end
    if nargin < 16
        maskThresh = 0.50;
    end
    if nargin < 17
        maskMinArea = 0;
    end
    if nargin < 18
        maskUseBBox = true;
    end
    if nargin < 19
        rectUseAll = false;
    end
    if nargin < 20
        rectPadFrac = 0.005;
    end
    optsS = struct("bottomPct", 40, "planeMaxDist", 0.002, "zExpand", 0.006, ...
                   "zBin", 0.003, "minPts", 150, ...
                   "planeRef", [0 0 1], "planeAng", 12, ...
                   "rectThetaStep", 0.5, "rectPad", 0.002, "rectPadFrac", 0.01, ...
                   "rectPct", 1, "rectUseAll", rectUseAll, "rectUseHull", true);
    optsS.rectPadFrac = rectPadFrac;
    H = size(depth,1); W = size(depth,2);
    scaleLB = imgsz / max(H, W);
    nh = round(H * scaleLB);
    nw = round(W * scaleLB);
    padLB = [floor((imgsz - nw)/2) floor((imgsz - nh)/2)];

    for i = 1:numel(dets)
        [Pc, ok] = det_to_cloud(dets(i), protoSeg, depth, K, zMin, zMax, maskThresh, maskMinArea, maskUseBBox, imgsz);
        if ~ok
            continue;
        end
        PcWork = apply_tilt_points(Pc, tiltTf);
        pcBox = pointCloud(PcWork);
        pcObj = segment_largest_cluster(pcBox);
        if pcObj.Count < 50
            continue;
        end
        if should_show_seg_debug(debugSegView, "s", imgName, i)
            show_segmentation_debug_cloud(sprintf("SegDebug SPAM %s det#%d", imgName, i), ...
                Pc, PcWork, pcObj.Location, tiltTf, get_debug_show_tilt(debugSegView));
        end
        try
            [center3DWork, rect3DWork, ~, len, wid, ~] = fit_bottom_face_center_rect_spam(pcObj, optsS);
        catch
            continue;
        end
        center3D = undo_tilt_points(center3DWork, tiltTf);
        rect3D = undo_tilt_points(rect3DWork, tiltTf);
        center2D = project_points(center3D, fx, fy, cx0, cy0);
        rect2D = project_points(rect3D, fx, fy, cx0, cy0);
        bboxDraw = dets(i).bbox;
        if isfield(dets(i), "maskBBox640") && ~isempty(dets(i).maskBBox640)
            bMask = undoLetterbox_xyxy(dets(i).maskBBox640, scaleLB, padLB);
            bMask(1) = max(1, min(W, bMask(1)));
            bMask(3) = max(1, min(W, bMask(3)));
            bMask(2) = max(1, min(H, bMask(2)));
            bMask(4) = max(1, min(H, bMask(4)));
            bMask = [min(bMask(1),bMask(3)), min(bMask(2),bMask(4)), ...
                     max(bMask(1),bMask(3)), max(bMask(2),bMask(4))];
            if (bMask(3) - bMask(1)) >= 3 && (bMask(4) - bMask(2)) >= 3
                bboxDraw = bMask;
            end
        end
        obj = struct("bbox", bboxDraw, "score", dets(i).score, ...
            "center3D", center3D, "center2D", center2D, ...
            "rect3D", rect3D, "rect2D", rect2D, ...
            "len", len, "wid", wid, "partial", dets(i).partial);
        if saveCloud
            obj.cloud = sample_cloud(undo_tilt_points(pcObj.Location, tiltTf), 5000);
        end
        out = [out; obj]; %#ok<AGROW>
    end
end

function out = process_cube(dets, depth, K, fx, fy, cx0, cy0, zMin, zMax, saveCloud, tiltTf, debugSegView, imgName, ...
    protoSeg, imgsz, maskThresh, maskMinArea, maskUseBBox, rgb, enableColorRecognition, colorCfg)
    out = struct([]);
    if isempty(dets)
        return;
    end
    if nargin < 11
        tiltTf = build_tilt_tf([0 0 -1]);
    end
    if nargin < 12
        debugSegView = default_seg_debug();
    end
    if nargin < 13
        imgName = ";
    end
    if nargin < 19
        rgb = [];
    end
    if nargin < 20
        enableColorRecognition = false;
    end
    if nargin < 21 || isempty(colorCfg)
        colorCfg = default_color_config();
    end
    if nargin < 14
        protoSeg = [];
    end
    if nargin < 15 || isempty(imgsz)
        imgsz = 640;
    end
    if nargin < 16 || isempty(maskThresh)
        maskThresh = 0.50;
    end
    if nargin < 17 || isempty(maskMinArea)
        maskMinArea = 0;
    end
    if nargin < 18 || isempty(maskUseBBox)
        maskUseBBox = true;
    end
    optsC = struct("bottomPct", 40, "planeMaxDist", 0.002, "zExpand", 0.006, ...
                   "zBin", 0.003, "minPts", 150, ...
                   "planeRef", [0 0 1], "planeAng", 12, ...
                   "squareThetaStep", 0.5, "squarePad", 0.0, "squarePadFrac", 0.0, ...
                   "squarePct", 2, "squareUseAll", false, "squareUseHull", true);

    for i = 1:numel(dets)
        [Pc, ok] = det_to_cloud(dets(i), protoSeg, depth, K, zMin, zMax, maskThresh, maskMinArea, maskUseBBox, imgsz);
        if ~ok
            continue;
        end
        PcWork = apply_tilt_points(Pc, tiltTf);
        pcBox = pointCloud(PcWork);
        pcObj = segment_largest_cluster(pcBox);
        if pcObj.Count < 50
            continue;
        end
        if should_show_seg_debug(debugSegView, "p", imgName, i)
            show_segmentation_debug_cloud(sprintf("SegDebug CUBE %s det#%d", imgName, i), ...
                Pc, PcWork, pcObj.Location, tiltTf, get_debug_show_tilt(debugSegView));
        end
        try
            [center3DWork, square3DWork, ~, side, ~] = fit_bottom_face_center_square_cube(pcObj, optsC);
        catch
            continue;
        end
        center3D = undo_tilt_points(center3DWork, tiltTf);
        square3D = undo_tilt_points(square3DWork, tiltTf);
        center2D = project_points(center3D, fx, fy, cx0, cy0);
        square2D = project_points(square3D, fx, fy, cx0, cy0);
        colorInfo = default_color_info();
        if enableColorRecognition
            colorInfo = estimate_cube_color_info(rgb, square2D, colorCfg);
        end
        obj = struct("bbox", dets(i).bbox, "score", dets(i).score, ...
            "center3D", center3D, "center2D", center2D, ...
            "square3D", square3D, "square2D", square2D, "side", side, "partial", dets(i).partial, ...
            "color", colorInfo.label, "colorScore", colorInfo.score, "colorSource", colorInfo.source, ...
            "colorHSV", colorInfo.meanHSV, "colorRGB", colorInfo.meanRGB, "colorPixelCount", colorInfo.pixelCount, ...
            "points", colorInfo.points, "targetBin", colorInfo.targetBin);
        if saveCloud
            obj.cloud = sample_cloud(undo_tilt_points(pcObj.Location, tiltTf), 5000);
        end
        out = [out; obj]; %#ok<AGROW>
    end
end

function out = process_marker(dets, proto, depth, K, fx, fy, cx0, cy0, zMin, zMax, maskThresh, maskMinArea, maskUseBBox, imgsz, saveCloud, tiltTf, debugSegView, imgName)
    out = struct([]);
    if isempty(dets)
        return;
    end
    if nargin < 16
        tiltTf = build_tilt_tf([0 0 -1]);
    end
    if nargin < 17
        debugSegView = default_seg_debug();
    end
    if nargin < 18
        imgName = ";
    end
    H = size(depth,1); W = size(depth,2);
    scale = imgsz / max(H, W);
    nh = round(H * scale);
    nw = round(W * scale);
    pad = [floor((imgsz - nw)/2) floor((imgsz - nh)/2)];
    optsB = struct("midBand", 0.008, "wallTol", 0.006, "tableMaxDist", 0.006, ...
                   "tableAng", 10, "thickPct", 70, "thickTol", 0.005, "minCand", 50, ...
                   "axisMode", "proj", "debugB", false);

    for i = 1:numel(dets)
        b640 = dets(i).bbox640;
        maskBest = dets(i).maskCoeff;
        mask640 = buildMaskFromProto(maskBest, proto, imgsz);
        if maskUseBBox
            x1b = max(1, min(imgsz, round(b640(1))));
            x2b = max(1, min(imgsz, round(b640(3))));
            y1b = max(1, min(imgsz, round(b640(2))));
            y2b = max(1, min(imgsz, round(b640(4))));
            mask640(:,1:max(1,x1b-1)) = 0;
            mask640(:,min(imgsz,x2b+1):end) = 0;
            mask640(1:max(1,y1b-1),:) = 0;
            mask640(min(imgsz,y2b+1):end,:) = 0;
        end
        maskOrig = unletterboxMask(mask640, scale, pad, W, H);
        maskBin = maskOrig > maskThresh;
        if maskMinArea > 0
            maskBin = bwareaopen(maskBin, maskMinArea);
        end
        [vvM, uuM] = find(maskBin);
        if isempty(vvM)
            continue;
        end
        indM = sub2ind(size(depth), vvM, uuM);
        ZM = depth(indM);
        maskZM = isfinite(ZM) & (ZM > zMin) & (ZM < zMax);
        uuM = uuM(maskZM); vvM = vvM(maskZM); ZM = ZM(maskZM);
        if numel(ZM) < 50
            continue;
        end
        XcM = (double(uuM) - cx0) .* double(ZM) / fx;
        YcM = (double(vvM) - cy0) .* double(ZM) / fy;
        Pm = [XcM(:), YcM(:), double(ZM(:))];
        PmWork = apply_tilt_points(Pm, tiltTf);
        pcMarker = pointCloud(PmWork);
        [PcBox, ok] = bbox_to_cloud(dets(i).bbox, depth, K, zMin, zMax);
        if ~ok
            continue;
        end
        PcBoxWork = apply_tilt_points(PcBox, tiltTf);
        pcBox = pointCloud(PcBoxWork);

        [~, midPtWork, axisVecWork, infoB] = fit_caseB_target_point_bottle(pcMarker, pcBox, optsB);
        if should_show_seg_debug(debugSegView, "m", imgName, i)
            Pafter = pcMarker.Location;
            if isfield(infoB, "candPts") && ~isempty(infoB.candPts)
                Pafter = infoB.candPts;
            end
            show_segmentation_debug_cloud(sprintf("SegDebug MARKER %s det#%d", imgName, i), ...
                Pm, PmWork, Pafter, tiltTf, get_debug_show_tilt(debugSegView));
        end
        axisLine3DWork = axis_line_from_cloud(pcMarker.Location, axisVecWork, midPtWork);
        line3DWork = infoB.linePts;
        midPt = undo_tilt_points(midPtWork, tiltTf);
        axisVec = undo_tilt_dir(axisVecWork, tiltTf);
        axisLine3D = undo_tilt_points(axisLine3DWork, tiltTf);
        line3D = undo_tilt_points(line3DWork, tiltTf);
        center2D = project_points(midPt, fx, fy, cx0, cy0);
        axisLine2D = project_points(axisLine3D, fx, fy, cx0, cy0);
        line2D = project_points(line3D, fx, fy, cx0, cy0);

        obj = struct("bbox", dets(i).bbox, "score", dets(i).score, ...
            "center3D", midPt, "center2D", center2D, ...
            "axis3D", axisVec, "axisLine3D", axisLine3D, "axisLine2D", axisLine2D, ...
            "intersectLine3D", line3D, "intersectLine2D", line2D, "partial", dets(i).partial);
        if saveCloud
            obj.cloud = sample_cloud(undo_tilt_points(pcMarker.Location, tiltTf), 5000);
        end
        out = [out; obj]; %#ok<AGROW>
    end
end

function [Pc, ok] = det_to_cloud(det, proto, depth, K, zMin, zMax, maskThresh, maskMinArea, maskUseBBox, imgsz)
    ok = false;
    Pc = zeros(0,3);
    useMask = ~isempty(proto) && isfield(det, "maskCoeff") && ~isempty(det.maskCoeff);
    if useMask
        [Pc, ok] = seg_det_to_cloud(det, proto, depth, K, zMin, zMax, maskThresh, maskMinArea, maskUseBBox, imgsz);
        if ok
            return;
        end
    end
    [Pc, ok] = bbox_to_cloud(det.bbox, depth, K, zMin, zMax);
end

function [Pc, ok] = seg_det_to_cloud(det, proto, depth, K, zMin, zMax, maskThresh, maskMinArea, maskUseBBox, imgsz)
    Pc = zeros(0,3);
    ok = false;
    H = size(depth,1); W = size(depth,2);
    fx  = K(1,1); fy  = K(2,2);
    cx0 = K(1,3); cy0 = K(2,3);

    b640 = [];
    if isfield(det, "maskBBox640") && ~isempty(det.maskBBox640)
        b640 = det.maskBBox640;
    elseif isfield(det, "bbox640") && ~isempty(det.bbox640)
        b640 = det.bbox640;
    end
    mask640 = buildMaskFromProto(det.maskCoeff, proto, imgsz);
    if maskUseBBox && ~isempty(b640)
        x1b = max(1, min(imgsz, round(b640(1))));
        x2b = max(1, min(imgsz, round(b640(3))));
        y1b = max(1, min(imgsz, round(b640(2))));
        y2b = max(1, min(imgsz, round(b640(4))));
        mask640(:,1:max(1,x1b-1)) = 0;
        mask640(:,min(imgsz,x2b+1):end) = 0;
        mask640(1:max(1,y1b-1),:) = 0;
        mask640(min(imgsz,y2b+1):end,:) = 0;
    end

    scale = imgsz / max(H, W);
    nh = round(H * scale);
    nw = round(W * scale);
    pad = [floor((imgsz - nw)/2) floor((imgsz - nh)/2)];
    maskOrig = unletterboxMask(mask640, scale, pad, W, H);
    maskBin = maskOrig > maskThresh;
    if maskMinArea > 0
        maskBin = bwareaopen(maskBin, maskMinArea);
    end

    [vv, uu] = find(maskBin);
    if isempty(vv)
        return;
    end
    ind = sub2ind(size(depth), vv, uu);
    Z = depth(ind);
    valid = isfinite(Z) & (Z > zMin) & (Z < zMax);
    uu = uu(valid); vv = vv(valid); Z = Z(valid);
    if numel(Z) < 50
        return;
    end
    Xc = (double(uu) - cx0) .* double(Z) / fx;
    Yc = (double(vv) - cy0) .* double(Z) / fy;
    Pc = [Xc(:), Yc(:), double(Z(:))];
    ok = true;
end

function [Pc, ok] = bbox_to_cloud(b_best, depth, K, zMin, zMax)
    H = size(depth,1); W = size(depth,2);
    fx  = K(1,1); fy  = K(2,2);
    cx0 = K(1,3); cy0 = K(2,3);
    x1o = round(b_best(1)); y1o = round(b_best(2));
    x2o = round(b_best(3)); y2o = round(b_best(4));
    x1o = max(1, min(W, x1o));
    x2o = max(1, min(W, x2o));
    y1o = max(1, min(H, y1o));
    y2o = max(1, min(H, y2o));
    [uu2, vv2] = meshgrid(x1o:x2o, y1o:y2o);
    uu = uu2(:); vv = vv2(:);
    ind = sub2ind(size(depth), vv, uu);
    Z = depth(ind);
    mask = isfinite(Z) & (Z > zMin) & (Z < zMax);
    uu = uu(mask); vv = vv(mask); Z = Z(mask);
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

function pcObj = segment_largest_cluster(pcBox, debugEnable, debugIdx)
    if nargin < 2
        debugEnable = false;
    end
    if nargin < 3
        debugIdx = 0;
    end
    if pcBox.Count < 50
        pcObj = pcBox;
        return;
    end
    % keep all Z (do NOT drop low-Z cap); only remove high-Z plane later
    pcSeg = pcBox;
    if exist('pcfitplane','file') == 2
        planeMaxDist = 0.005;
        planeRef = [0 0 1];
        planeAng = 10;
        planeMinFrac = 0.12;
        minPlanePts = 200;
        spreadThresh = 0.60;
        maxPlaneRemove = 3;
        for iter = 1:maxPlaneRemove
            if pcSeg.Count < 200
                break;
            end
            zSeg = pcSeg.Location(:,3);
            zCut = prctile(zSeg, 70);
            idxHigh = find(zSeg >= zCut);
            if numel(idxHigh) < minPlanePts
                break;
            end
            pcHigh = select(pcSeg, idxHigh);
            try
                [m1, in1] = pcfitplane(pcHigh, planeMaxDist, planeRef, planeAng);
            catch
                break;
            end
            if isempty(in1)
                break;
            end
            candIdx = idxHigh(in1);
            candPts = pcSeg.Location(candIdx, :);
            candFrac = numel(candIdx) / pcSeg.Count;
            candZ = mean(candPts(:,3));

            Cplane = mean(candPts, 1);
            n = m1.Normal;
            n = n / norm(n);
            if abs(dot(n, [1 0 0])) < 0.9
                tmp = [1 0 0];
            else
                tmp = [0 1 0];
            end
            e1 = cross(n, tmp); e1 = e1 / norm(e1);
            e2 = cross(n, e1); e2 = e2 / norm(e2);
            Q = candPts - Cplane;
            x = Q * e1';
            y = Q * e2';
            r90 = prctile(sqrt(x.^2 + y.^2), 90);
            Pxy = pcSeg.Location(:,1:2);
            Cxy = mean(Pxy,1);
            rScene = prctile(sqrt(sum((Pxy - Cxy).^2, 2)), 90);
            spreadRatio = r90 / max(rScene, 1e-6);

            zHiSeg = prctile(zSeg, 70);
            zRangeSeg = max(zSeg) - min(zSeg);
            isHigh = candZ >= max(zHiSeg, mean(zSeg) + 0.20 * zRangeSeg);
            enoughSize = (candFrac >= planeMinFrac) || (numel(candIdx) >= minPlanePts);
            isWide = spreadRatio >= spreadThresh;

            if debugEnable
                fprintf("Obj[%d] HighZ iter%d: frac=%.2f z=%.3f spread=%.2f isHigh=%d\n", ...
                    debugIdx, iter, candFrac, candZ, spreadRatio, isHigh);
            end
            if isHigh && enoughSize && isWide
                keepIdx = setdiff(1:pcSeg.Count, candIdx);
                pcSeg = select(pcSeg, keepIdx);
            else
                break;
            end
        end
    end
    % no fallback to median-band filter
    minDist = 0.01;
    try
        [labels, numClusters] = pcsegdist(pcSeg, minDist);
    catch
        pcObj = pcSeg;
        return;
    end
    if numClusters < 1
        pcObj = pcSeg;
        return;
    end
    counts = accumarray(labels(labels>0), 1);
    [~, bestId] = max(counts);
    idxObj = find(labels == bestId);
    pcObj = select(pcSeg, idxObj);
end

function pcOut = merge_bottom_cap(pcMain, pcAll)
    pcOut = pcMain;
    if pcMain.Count < 50
        return;
    end
    Pmain = pcMain.Location;
    Cxy = mean(Pmain(:,1:2), 1);
    rxy = sqrt(sum((Pmain(:,1:2) - Cxy).^2, 2));
    rMain = prctile(rxy, 90);
    zMinMain = min(Pmain(:,3));

    zCapBand = 0.015; % meters above low-Z percentile
    zLowPct  = 10;    % percentile to define low-Z band
    rExpand  = 1.30;  % radius expand

    PsegAll = pcAll.Location;
    dxyAll = sqrt(sum((PsegAll(:,1:2) - Cxy).^2, 2));
    zLow = prctile(PsegAll(:,3), zLowPct);
    capMask = (PsegAll(:,3) <= zLow + zCapBand) & (dxyAll <= rMain * rExpand);
    if nnz(capMask) < 20
        % fallback: use main-min based band
        capMask = (PsegAll(:,3) <= zMinMain + 0.03) & (dxyAll <= rMain * rExpand);
    end
    if nnz(capMask) >= 20
        Pmerge = [Pmain; PsegAll(capMask,:)];
        pcOut = pointCloud(Pmerge);
    end
end

function pcOut = cleanup_cylinder_attachment(pcIn, debugEnable, tag)
    if nargin < 2
        debugEnable = false;
    end
    if nargin < 3
        tag = ";
    end
    pcOut = pcIn;
    if isempty(pcIn) || pcIn.Count < 120
        return;
    end
    P = double(pcIn.Location);
    P = P(all(isfinite(P),2),:);
    n0 = size(P,1);
    if n0 < 120
        pcOut = pointCloud(P);
        return;
    end
    P0 = P;
    zSpan0 = max(P0(:,3)) - min(P0(:,3));
    C0 = mean(P0(:,1:2), 1);
    r0 = sqrt(sum((P0(:,1:2) - C0).^2, 2));
    rXY900 = prctile(r0, 90);

    % 1) Trim points that are too far from a robust cylinder axis.
    keep = true(n0,1);
    for iter = 1:2
        Pk = P(keep,:);
        if size(Pk,1) < 80
            break;
        end
        Ck = mean(Pk,1);
        [~,~,V] = svd(Pk - Ck, 'econ');
        axis = V(:,1);
        axis = axis / max(norm(axis), 1e-12);

        Q = P - Ck;
        d = sqrt(sum((Q - (Q * axis) * axis').^2, 2));
        dNow = d(keep);
        dMed = median(dNow);
        dMad = median(abs(dNow - dMed));
        dP85 = prctile(dNow, 85);
        thr = max(dP85 * 1.15, dMed + 2.5 * max(dMad, 0.002));
        keepNew = d <= thr;
        if nnz(keepNew) < 80
            break;
        end
        keep = keepNew;
    end
    if nnz(keep) >= 80 && nnz(keep) <= round(0.98 * n0)
        P = P(keep,:);
    end

    % 2) Remove a dominant non-table plane (common for box side walls).
    if size(P,1) >= 120 && exist('pcfitplane','file') == 2
        try
            [mdl, inl] = pcfitplane(pointCloud(P), 0.004);
            fracPlane = numel(inl) / size(P,1);
            nz = abs(mdl.Normal(3));
            if fracPlane >= 0.32 && nz <= 0.75
                keep2 = true(size(P,1),1);
                keep2(inl) = false;
                if nnz(keep2) >= 80
                    P = P(keep2,:);
                end
            end
        catch
        end
    end

    % 3) Final tight clustering to cut thin bridges to the background.
    if size(P,1) >= 80
        try
            [labels, numClusters] = pcsegdist(pointCloud(P), 0.008);
            if numClusters >= 1
                counts = accumarray(labels(labels>0), 1);
                [~, bestId] = max(counts);
                idx = find(labels == bestId);
                if numel(idx) >= 60
                    P = P(idx,:);
                end
            end
        catch
        end
    end

    % 4) Safety gate: reject cleanup if geometry is damaged too much.
    n1 = size(P,1);
    if n1 < 60
        P = P0;
        n1 = n0;
    end
    zSpan1 = max(P(:,3)) - min(P(:,3));
    C1 = mean(P(:,1:2), 1);
    r1 = sqrt(sum((P(:,1:2) - C1).^2, 2));
    rXY901 = prctile(r1, 90);
    keepFrac = n1 / max(n0, 1);
    zFrac = zSpan1 / max(zSpan0, 1e-6);
    rFrac = rXY901 / max(rXY900, 1e-6);
    isOverTrim = (keepFrac < 0.55) || (zFrac < 0.65) || (rFrac < 0.55);
    if isOverTrim
        P = P0;
        n1 = n0;
    end

    pcOut = pointCloud(P);
    if debugEnable
        fprintf("%s cleanup: %d -> %d pts (keep=%.2f zFrac=%.2f rFrac=%.2f %s)\n", ...
            char(string(tag)), n0, n1, keepFrac, zFrac, rFrac, ternary(isOverTrim, "revert", "accept"));
    end
end

function pcObj = segment_bottle_B(pcBox, debugEnable, debugIdx)
    if nargin < 2
        debugEnable = false;
    end
    if nargin < 3
        debugIdx = 0;
    end
    if pcBox.Count < 50
        pcObj = pcBox;
        return;
    end

    % Start from full cloud; remove high-Z plane(s) only
    pcSeg = pcBox;
    if exist('pcfitplane','file') == 2
        planeMaxDist = 0.005;
        planeRef = [0 0 1];
        planeAng = 10;
        planeMinFrac = 0.12;
        minPlanePts = 200;
        spreadThresh = 0.60;
        maxPlaneRemove = 3;
        for iter = 1:maxPlaneRemove
            if pcSeg.Count < 200
                break;
            end
            zSeg = pcSeg.Location(:,3);
            zCut = prctile(zSeg, 70);
            idxHigh = find(zSeg >= zCut);
            if numel(idxHigh) < minPlanePts
                break;
            end
            pcHigh = select(pcSeg, idxHigh);
            try
                [m1, in1] = pcfitplane(pcHigh, planeMaxDist, planeRef, planeAng);
            catch
                break;
            end
            if isempty(in1)
                break;
            end
            candIdx = idxHigh(in1);
            candPts = pcSeg.Location(candIdx, :);
            candFrac = numel(candIdx) / pcSeg.Count;
            candZ = mean(candPts(:,3));

            Cplane = mean(candPts, 1);
            n = m1.Normal; n = n / norm(n);
            if abs(dot(n, [1 0 0])) < 0.9
                tmp = [1 0 0];
            else
                tmp = [0 1 0];
            end
            e1 = cross(n, tmp); e1 = e1 / norm(e1);
            e2 = cross(n, e1); e2 = e2 / norm(e2);
            Q = candPts - Cplane;
            x = Q * e1';
            y = Q * e2';
            r90 = prctile(sqrt(x.^2 + y.^2), 90);
            Pxy = pcSeg.Location(:,1:2);
            Cxy = mean(Pxy,1);
            rScene = prctile(sqrt(sum((Pxy - Cxy).^2, 2)), 90);
            spreadRatio = r90 / max(rScene, 1e-6);

            zHiSeg = prctile(zSeg, 70);
            zRangeSeg = max(zSeg) - min(zSeg);
            isHigh = candZ >= max(zHiSeg, mean(zSeg) + 0.20 * zRangeSeg);
            enoughSize = (candFrac >= planeMinFrac) || (numel(candIdx) >= minPlanePts);
            isWide = spreadRatio >= spreadThresh;

            if debugEnable
                fprintf("BottleB[%d] HighZ iter%d: frac=%.2f z=%.3f spread=%.2f isHigh=%d\n", ...
                    debugIdx, iter, candFrac, candZ, spreadRatio, isHigh);
            end
            if isHigh && enoughSize && isWide
                keepIdx = setdiff(1:pcSeg.Count, candIdx);
                pcSeg = select(pcSeg, keepIdx);
            else
                break;
            end
        end
    end

    % Cluster selection: prefer thicker (larger Z-span) clusters
    minDist = 0.01;
    try
        [labels, numClusters] = pcsegdist(pcSeg, minDist);
    catch
        pcObj = pcSeg;
        return;
    end
    if numClusters < 1
        pcObj = pcSeg;
        return;
    end

    minZSpan = 0.010;  % 1 cm
    wR = 0.50;         % radius weight
    wN = 0.00005;      % small count weight
    bestScore = -inf;
    bestId = -1;
    for k = 1:numClusters
        idx = find(labels == k);
        n = numel(idx);
        if n < 50
            continue;
        end
        Pk = pcSeg.Location(idx,:);
        zSpan = prctile(Pk(:,3),95) - prctile(Pk(:,3),5);
        if zSpan < minZSpan
            if debugEnable
                fprintf("BottleB[%d] cluster %d: n=%d zSpan=%.4f -> skip (plane)\n", debugIdx, k, n, zSpan);
            end
            continue;
        end
        Cxy = mean(Pk(:,1:2),1);
        rxy = sqrt(sum((Pk(:,1:2) - Cxy).^2, 2));
        r90 = prctile(rxy, 90);
        score = zSpan + wR * r90 + wN * log(n + 1);
        if debugEnable
            fprintf("BottleB[%d] cluster %d: n=%d zSpan=%.4f r90=%.4f score=%.4f\n", ...
                debugIdx, k, n, zSpan, r90, score);
        end
        if score > bestScore
            bestScore = score;
            bestId = k;
        end
    end
    if bestId < 0
        counts = accumarray(labels(labels>0), 1);
        [~, bestId] = max(counts);
    end
    pcObj = select(pcSeg, find(labels == bestId));
end

function [axisLine3D] = axis_line_from_cloud(P, axisVec, center3D)
    axisVec = axisVec(:)' / max(norm(axisVec), 1e-9);
    t = (P - center3D) * axisVec';
    tLo = prctile(t, 5);
    tHi = prctile(t, 95);
    axisLine3D = [center3D + tLo * axisVec; center3D + tHi * axisVec];
end

function center3D = center_from_axis_line_closest(midPt, axisVec, linePts)
    center3D = midPt;
    if isempty(midPt) || isempty(axisVec) || isempty(linePts) || size(linePts,1) < 2
        return;
    end
    pAxis = reshape(double(midPt), 1, 3);
    dAxis = reshape(double(axisVec), 1, 3);
    p1 = reshape(double(linePts(1,:)), 1, 3);
    p2 = reshape(double(linePts(2,:)), 1, 3);
    if any(~isfinite([pAxis dAxis p1 p2]))
        return;
    end
    nAxis = norm(dAxis);
    dSeg = p2 - p1;
    nSeg = norm(dSeg);
    if nAxis < 1e-9 || nSeg < 1e-9
        return;
    end
    dAxis = dAxis / nAxis;

    w0 = pAxis - p1;
    a = dot(dAxis, dAxis);   % ~1
    b = dot(dAxis, dSeg);
    c = dot(dSeg, dSeg);
    d = dot(dAxis, w0);
    e = dot(dSeg, w0);
    den = a * c - b * b;

    if abs(den) > 1e-12
        t = (a * e - b * d) / den;
    else
        t = e / max(c, 1e-12);
    end

    % linePts is a finite segment from fitted candidates; keep t on segment.
    t = min(1, max(0, t));
    qSeg = p1 + t * dSeg;
    s = dot(dAxis, (qSeg - pAxis));
    qAxis = pAxis + s * dAxis;

    if all(isfinite(qAxis))
        center3D = qAxis;
    end
end

function center3D = center_from_xy_min_z(Pobj, centerIn)
    center3D = centerIn;
    if isempty(Pobj) || isempty(centerIn)
        return;
    end
    C = reshape(double(centerIn), 1, 3);
    P = double(Pobj);
    P = P(all(isfinite(P),2), :);
    if isempty(P) || any(~isfinite(C))
        return;
    end

    CxyAll = mean(P(:,1:2), 1);
    rAll = sqrt(sum((P(:,1:2) - CxyAll).^2, 2));
    r90 = prctile(rAll, 90);
    xyRadius = max(0.006, 0.20 * r90); % adaptive local XY neighborhood
    minLocalPts = min(120, size(P,1));

    dxy2 = (P(:,1) - C(1)).^2 + (P(:,2) - C(2)).^2;
    idx = dxy2 <= (xyRadius^2);
    if nnz(idx) < minLocalPts
        [~, ord] = sort(dxy2, 'ascend');
        idx = false(size(dxy2));
        idx(ord(1:minLocalPts)) = true;
    end
    zLocal = P(idx, 3);
    if isempty(zLocal)
        zLocal = P(:,3);
    end

    % In current camera/work convention, smaller Z is closer to camera (top-most grasp surface).
    zTop = prctile(zLocal, 5); % robust min to suppress isolated outliers
    if isfinite(zTop)
        center3D = [C(1), C(2), zTop];
    end
end

function uv = project_points(P, fx, fy, cx0, cy0)
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

function Pout = sample_cloud(P, maxPts)
    if isempty(P)
        Pout = zeros(0,3);
        return;
    end
    n = size(P,1);
    if n > maxPts
        idx = randperm(n, maxPts);
        Pout = P(idx, :);
    else
        Pout = P;
    end
end

function [Iout, scale, pad] = letterbox(I, newSize)
    h = size(I,1); w = size(I,2);
    scale = newSize / max(h,w);
    nh = round(h * scale);
    nw = round(w * scale);
    Ires = imresize(I, [nh nw]);
    padH = newSize - nh;
    padW = newSize - nw;
    top = floor(padH/2);
    bottom = padH - top;
    left = floor(padW/2);
    right = padW - left;
    Iout = padarray(Ires, [top left], 114, 'pre');
    Iout = padarray(Iout, [bottom right], 114, 'post');
    pad = [left top];
end

function b = undoLetterbox_xyxy(b640_xyxy, scale, pad)
    x1 = (b640_xyxy(1) - pad(1)) / scale;
    y1 = (b640_xyxy(2) - pad(2)) / scale;
    x2 = (b640_xyxy(3) - pad(1)) / scale;
    y2 = (b640_xyxy(4) - pad(2)) / scale;
    b = [x1 y1 x2 y2];
end

function keep = nms_xyxy(boxes, scores, iouThr)
    if isempty(boxes)
        keep = [];
        return;
    end
    [~, order] = sort(scores, 'descend');
    keep = [];
    while ~isempty(order)
        i = order(1);
        keep(end+1,1) = i; %#ok<AGROW>
        if numel(order) == 1
            break;
        end
        rest = order(2:end);
        ious = bbox_iou(boxes(i,:), boxes(rest,:));
        order = rest(ious < iouThr);
    end
end

function iou = bbox_iou(box, boxes)
    x1 = max(box(1), boxes(:,1));
    y1 = max(box(2), boxes(:,2));
    x2 = min(box(3), boxes(:,3));
    y2 = min(box(4), boxes(:,4));
    w = max(0, x2 - x1);
    h = max(0, y2 - y1);
    inter = w .* h;
    area1 = max(0, box(3)-box(1)) * max(0, box(4)-box(2));
    area2 = max(0, boxes(:,3)-boxes(:,1)) .* max(0, boxes(:,4)-boxes(:,2));
    iou = inter ./ max(area1 + area2 - inter, 1e-9);
end

function classNames = buildClassNames(nc, baseName)
    if nc <= 1
        classNames = {baseName};
        return;
    end
    classNames = cell(1,nc);
    for i = 1:nc
        classNames{i} = sprintf("c%d", i);
    end
    classNames{1} = baseName;
end
%% ---------------- marker seg helpers ----------------
function [pred, proto] = parseSegOutputs(outs)
    if isa(outs, 'py.list')
        n = double(py.len(outs));
        getOut = @(k) outs{k};
    elseif iscell(outs)
        n = numel(outs);
        getOut = @(k) outs{k};
    else
        n = numel(outs);
        getOut = @(k) outs{k};
    end
    if n < 2
        error("Segmentation model should output 2 tensors.");
    end
    pred = [];
    proto = [];
    for i = 1:n
        t = single(getOut(i));
        if ndims(t) == 4
            proto = t;
        else
            pred = t;
        end
    end
    if isempty(proto) || isempty(pred)
        error("Failed to parse YOLO seg outputs.");
    end
    pred = squeeze(pred);
    proto = squeeze(proto);
end

function [xywh, cls, maskCoeff, nc] = splitPred(pred, nm)
    if size(pred,2) > size(pred,1)
        d = size(pred,1);
    else
        pred = pred';
        d = size(pred,1);
    end
    if d <= (4 + nm)
        error("Unexpected prediction shape.");
    end
    nc = d - 4 - nm;
    xywh = pred(1:4,:);
    cls = pred(5:4+nc,:);
    maskCoeff = pred(5+nc:4+nc+nm,:);
end

function mask640 = buildMaskFromProto(maskCoeff, proto, outSize)
    nm = size(proto,1);
    hp = size(proto,2);
    wp = size(proto,3);
    proto2 = reshape(proto, [nm, hp*wp]);
    m = (maskCoeff(:)' * proto2);
    m = 1 ./ (1 + exp(-m));
    maskSmall = reshape(m, [hp, wp]);
    mask640 = imresize(maskSmall, [outSize outSize], 'bilinear');
end

function maskOrig = unletterboxMask(mask640, scale, pad, W, H)
    nh = round(H * scale);
    nw = round(W * scale);
    x1 = pad(1) + 1;
    y1 = pad(2) + 1;
    x2 = min(size(mask640,2), pad(1) + nw);
    y2 = min(size(mask640,1), pad(2) + nh);
    maskCrop = mask640(y1:y2, x1:x2);
    maskOrig = imresize(maskCrop, [H W], 'bilinear');
end
%% ---------------- bottle/spam/cube helpers ----------------
function [label, info] = classifyAB_table(pcCan, pcBox, cosThr, topPct, maxDist, angDeg)
    info = struct("cosAxis", 0, "tableFound", false, "cosTable", 0, "zTable", NaN);
    P = double(pcCan.Location);
    P = P(all(isfinite(P),2),:);
    if size(P,1) < 50
        label = 1;
        return;
    end
    [axisVec, axisInfo] = estimateAxisFromWall(P);
    [nTable, zTable, found] = estimateTableNormal(pcBox, topPct, maxDist, angDeg, axisInfo.centerXY, axisInfo.rXY);
    if ~found
        nTable = [0 0 1]';
    end
    if dot(nTable, [0 0 1]') < 0
        nTable = -nTable;
    end
    cosAxis = abs(dot(axisVec, nTable));
    info.cosAxis = cosAxis;
    info.tableFound = found;
    info.cosTable = abs(dot(nTable, [0 0 1]'));
    info.zTable = zTable;
    info.axisSource = axisInfo.source;
    info.axisScore = axisInfo.scoreChosen;
    info.axisScorePCA = axisInfo.scorePCA;
    info.axisScoreWall = axisInfo.scoreWall;
    if cosAxis >= cosThr
        label = 1;
    else
        label = 2;
    end
end

function [axisVec, info] = estimateAxisFromWall(P)
    C = mean(P, 1);
    [~,~,V] = svd(P - C, 'econ');
    axisPCA = normalize_dir3(V(:,1), [0 0 1]');
    axisWall = axisPCA;
    for iter = 1:2
        n = axisWall(:);
        Pc = P - C; % distance-to-axis must be computed in centered coordinates
        Q = Pc - (Pc * n) * n';
        r = sqrt(sum(Q.^2, 2));
        r0 = prctile(r, 70);
        tol = max(0.003, 0.15 * r0);
        wallMask = abs(r - r0) <= tol;
        if nnz(wallMask) < 50
            break;
        end
        Pw = P(wallMask, :);
        Cw = mean(Pw, 1);
        [~,~,Vw] = svd(Pw - Cw, 'econ');
        cand = normalize_dir3(Vw(:,1), axisWall);
        if norm(cand) < 1e-9
            break;
        end
        axisWall = cand;
    end

    [scorePCA, fracPCA, spreadPCA] = axis_ring_consistency(P, C, axisPCA);
    [scoreWall, fracWall, spreadWall] = axis_ring_consistency(P, C, axisWall);
    if scoreWall >= scorePCA + 0.01
        axisVec = axisWall;
        source = "wall";
        scoreChosen = scoreWall;
    else
        axisVec = axisPCA;
        source = "pca";
        scoreChosen = scorePCA;
    end

    Cxy = mean(P(:,1:2), 1);
    rxy = sqrt(sum((P(:,1:2) - Cxy).^2, 2));
    info = struct( ...
        "center", C, ...
        "centerXY", Cxy, ...
        "rXY", prctile(rxy, 90), ...
        "axisPCA", axisPCA(:)', ...
        "axisWall", axisWall(:)', ...
        "source", source, ...
        "scoreChosen", scoreChosen, ...
        "scorePCA", scorePCA, ...
        "scoreWall", scoreWall, ...
        "fracPCA", fracPCA, ...
        "fracWall", fracWall, ...
        "spreadPCA", spreadPCA, ...
        "spreadWall", spreadWall ...
        );
end

function [score, fracWall, spreadWall] = axis_ring_consistency(P, C, axisVec)
    n = normalize_dir3(axisVec, [0 0 1]');
    Pc = P - C;
    Q = Pc - (Pc * n) * n';
    r = sqrt(sum(Q.^2, 2));
    if isempty(r)
        score = -inf;
        fracWall = 0;
        spreadWall = 1;
        return;
    end
    r0 = prctile(r, 70);
    tol = max(0.003, 0.12 * r0);
    wallMask = abs(r - r0) <= tol;
    fracWall = nnz(wallMask) / size(P,1);
    if nnz(wallMask) < 10
        spreadWall = 1;
    else
        rw = r(wallMask);
        spreadWall = std(rw) / max(mean(rw), 1e-6);
    end
    score = fracWall - 0.40 * spreadWall;
end

function v = normalize_dir3(vIn, vFallback)
    v = reshape(vIn, [3 1]);
    n = norm(v);
    if n < 1e-12 || any(~isfinite(v))
        v = reshape(vFallback, [3 1]);
        n = norm(v);
    end
    if n < 1e-12
        v = [0;0;1];
    else
        v = v / n;
    end
end

function [nTable, zTable, found] = estimateTableNormal(pcBox, topPct, maxDist, angDeg, centerXY, rCan)
    nTable = [0 0 1]';
    zTable = NaN;
    found = false;
    P = double(pcBox.Location);
    P = P(all(isfinite(P),2),:);
    if size(P,1) < 100
        return;
    end
    if nargin >= 6 && ~isempty(centerXY) && isfinite(rCan) && rCan > 0
        dxy = P(:,1:2) - centerXY(:)';
        rxy = sqrt(sum(dxy.^2, 2));
        keep = rxy >= 1.2 * rCan;
        if nnz(keep) >= 100
            P = P(keep, :);
        end
    end
    Z = P(:,3);
    zCut = prctile(Z, topPct);
    idx = Z >= zCut;
    if nnz(idx) < 100
        return;
    end
    Ptop = P(idx,:);
    if exist('pcfitplane','file') == 2
        try
            pcTop = pointCloud(Ptop);
            [mdl, inlier] = pcfitplane(pcTop, maxDist, [0 0 1], angDeg);
            if ~isempty(inlier)
                n = mdl.Normal(:);
                if n(3) < 0
                    n = -n;
                end
                nTable = n / norm(n);
                zTable = mean(Ptop(inlier,3));
                found = true;
                return;
            end
        catch
        end
    end
    C = mean(Ptop, 1);
    [~,~,V] = svd(Ptop - C, 'econ');
    n = V(:,3);
    if n(3) < 0
        n = -n;
    end
    nTable = n / norm(n);
    zTable = mean(Ptop(:,3));
    found = true;
end
function [center3D, axisVec, capMask] = fit_bottom_cap_center_axis_A_bottle(pcIn, opts)
    if nargin < 2
        opts = struct;
    end
    opts = withDefaults(opts, struct( ...
        "bottomPct", 40, ...
        "planeMaxDist", 0.004, ...
        "zBand", 0.004, ...
        "zExpand", 0.006, ...
        "zBin", 0.003, ...
        "minPts", 120 ...
        ));
    P = double(pcIn.Location);
    P = P(all(isfinite(P),2),:);
    if size(P,1) < 30
        error("Point cloud too small.");
    end

    zAll = P(:,3);
    zLowCut = prctile(zAll, opts.bottomPct);
    zBin = opts.zBin;
    if ~isfinite(zBin) || zBin <= 0
        zBin = 0.003;
    end
    edges = (min(zAll) - zBin):zBin:(zLowCut + zBin);
    [counts, edges] = histcounts(zAll, edges);
    if isempty(counts) || max(counts) == 0
        bestZ = prctile(zAll, 10);
    else
        [~, b] = max(counts);
        bestZ = (edges(b) + edges(b+1)) * 0.5;
    end

    capMask = abs(zAll - bestZ) <= opts.zExpand;
    capPts = P(capMask,:);
    if size(capPts,1) < opts.minPts
        capMask = zAll <= zLowCut;
        capPts = P(capMask,:);
    end

    Cplane = mean(capPts, 1);
    planeN = [];
    inIdx = [];
    if exist('pcfitplane','file') == 2 && size(capPts,1) >= 50
        try
            [m, inIdx] = pcfitplane(pointCloud(capPts), opts.planeMaxDist);
            if ~isempty(inIdx)
                planeN = m.Normal(:);
                Cplane = mean(capPts(inIdx,:), 1);
            end
        catch
        end
    end
    if isempty(planeN)
        [~,~,Vn] = svd(capPts - Cplane, 'econ');
        planeN = Vn(:,3);
    end
    planeN = planeN / norm(planeN);
    if planeN(3) < 0
        planeN = -planeN;
    end
    axisVec = planeN';

    if ~isempty(inIdx)
        idxFull = find(capMask);
        capMask(:) = false;
        capMask(idxFull(inIdx)) = true;
        capPts = P(capMask,:);
    end

    Pproj = capPts - ((capPts - Cplane) * planeN) * planeN';
    E = null(axisVec');
    if size(E,2) < 2
        if abs(dot(axisVec, [1 0 0])) < 0.9
            tmp = [1 0 0];
        else
            tmp = [0 1 0];
        end
        e1 = cross(axisVec, tmp); e1 = e1 / norm(e1);
        e2 = cross(axisVec, e1); e2 = e2 / norm(e2);
        e1 = e1(:); e2 = e2(:);
    else
        e1 = E(:,1); e2 = E(:,2);
    end
    Q = Pproj - Cplane;
    x = Q * e1;
    y = Q * e2;
    if numel(x) >= 3
        [cx, cy] = fitCircle2D(x, y);
        center3D = Cplane + cx * e1' + cy * e2';
    else
        center3D = Cplane;
    end
end
function [center3D, rect3D, planeN, len, wid, capMask] = fit_bottom_face_center_rect_spam(pcIn, opts)
    if nargin < 2
        opts = struct;
    end
    opts = withDefaults(opts, struct( ...
        "bottomPct", 40, ...
        "planeMaxDist", 0.004, ...
        "planeRef", [0 0 1], ...
        "planeAng", 12, ...
        "zExpand", 0.006, ...
        "zBin", 0.003, ...
        "minPts", 150, ...
        "rectThetaStep", 1, ...
        "rectPad", 0.002, ...
        "rectPadFrac", 0.05, ...
        "rectPct", 1, ...
        "rectUseAll", true, ...
        "rectUseHull", true ...
        ));

    P = double(pcIn.Location);
    P = P(all(isfinite(P),2),:);
    if size(P,1) < 30
        error("Point cloud too small.");
    end

    zAll = P(:,3);
    zLowCut = prctile(zAll, opts.bottomPct);
    zBin = opts.zBin;
    if ~isfinite(zBin) || zBin <= 0
        zBin = 0.003;
    end
    edges = (min(zAll) - zBin):zBin:(zLowCut + zBin);
    [counts, edges] = histcounts(zAll, edges);
    if isempty(counts) || max(counts) == 0
        bestZ = prctile(zAll, 10);
    else
        [~, b] = max(counts);
        bestZ = (edges(b) + edges(b+1)) * 0.5;
    end

    capMask = abs(zAll - bestZ) <= opts.zExpand;
    capPts = P(capMask,:);
    if size(capPts,1) < opts.minPts
        capMask = zAll <= zLowCut;
        capPts = P(capMask,:);
    end
    if size(capPts,1) < opts.minPts
        error("Too few points for bottom face.");
    end

    Cplane = mean(capPts, 1);
    planeN = [];
    inIdx = [];
    if exist('pcfitplane','file') == 2 && size(capPts,1) >= 50
        try
            if isfield(opts, "planeRef") && isfield(opts, "planeAng")
                [m, inIdx] = pcfitplane(pointCloud(capPts), opts.planeMaxDist, ...
                    opts.planeRef, opts.planeAng);
            else
                [m, inIdx] = pcfitplane(pointCloud(capPts), opts.planeMaxDist);
            end
            if ~isempty(inIdx)
                planeN = m.Normal(:);
                Cplane = mean(capPts(inIdx,:), 1);
            end
        catch
        end
    end
    if isempty(planeN)
        [~,~,Vn] = svd(capPts - Cplane, 'econ');
        planeN = Vn(:,3);
    end
    planeN = planeN / norm(planeN);
    if planeN(3) < 0
        planeN = -planeN;
    end

    if ~isempty(inIdx)
        idxFull = find(capMask);
        capMask(:) = false;
        capMask(idxFull(inIdx)) = true;
        capPts = P(capMask,:);
    end

    if abs(dot(planeN, [1 0 0]')) < 0.9
        tmp = [1 0 0]';
    else
        tmp = [0 1 0]';
    end
    e1 = cross(planeN, tmp); e1 = e1 / norm(e1);
    e2 = cross(planeN, e1);  e2 = e2 / norm(e2);

    if isfield(opts, "rectUseAll") && opts.rectUseAll
        Prect = P;
    else
        Prect = capPts;
    end
    Pproj = Prect - ((Prect - Cplane) * planeN) * planeN';
    Q = Pproj - Cplane;
    u = Q * e1;
    v = Q * e2;

    if isfield(opts, "rectUseHull") && opts.rectUseHull && numel(u) >= 10
        try
            k = convhull(u, v);
            uR = u(k);
            vR = v(k);
        catch
            uR = u;
            vR = v;
        end
    else
        uR = u;
        vR = v;
    end

    [theta, xmin, xmax, ymin, ymax] = minAreaRect2D(uR, vR, opts.rectThetaStep, opts.rectPct);
    R = [cos(theta) -sin(theta); sin(theta) cos(theta)];
    a1 = e1 * R(1,1) + e2 * R(2,1);
    a2 = e1 * R(1,2) + e2 * R(2,2);
    a1 = a1 / norm(a1);
    a2 = a2 / norm(a2);

    pad = max(0, opts.rectPad);
    if isfield(opts, "rectPadFrac") && opts.rectPadFrac > 0
        pad = max(pad, opts.rectPadFrac * max(xmax - xmin, ymax - ymin));
    end
    xmin = xmin - pad; xmax = xmax + pad;
    ymin = ymin - pad; ymax = ymax + pad;
    len = xmax - xmin;
    wid = ymax - ymin;

    rect3D = [ ...
        Cplane + xmin * a1' + ymin * a2'; ...
        Cplane + xmax * a1' + ymin * a2'; ...
        Cplane + xmax * a1' + ymax * a2'; ...
        Cplane + xmin * a1' + ymax * a2' ...
        ];
    center3D = Cplane + 0.5 * (xmin + xmax) * a1' + 0.5 * (ymin + ymax) * a2';
end
function [center3D, square3D, planeN, side, capMask] = fit_bottom_face_center_square_cube(pcIn, opts)
    if nargin < 2
        opts = struct;
    end
    opts = withDefaults(opts, struct( ...
        "bottomPct", 40, ...
        "planeMaxDist", 0.004, ...
        "planeRef", [0 0 1], ...
        "planeAng", 12, ...
        "zExpand", 0.006, ...
        "zBin", 0.003, ...
        "minPts", 150, ...
        "squareThetaStep", 1, ...
        "squarePad", 0.0, ...
        "squarePadFrac", 0.0, ...
        "squarePct", 0, ...
        "squareUseAll", true, ...
        "squareUseHull", true ...
        ));

    P = double(pcIn.Location);
    P = P(all(isfinite(P),2),:);
    if size(P,1) < 30
        error("Point cloud too small.");
    end

    zAll = P(:,3);
    zLowCut = prctile(zAll, opts.bottomPct);
    zBin = opts.zBin;
    if ~isfinite(zBin) || zBin <= 0
        zBin = 0.003;
    end
    edges = (min(zAll) - zBin):zBin:(zLowCut + zBin);
    [counts, edges] = histcounts(zAll, edges);
    if isempty(counts) || max(counts) == 0
        bestZ = prctile(zAll, 10);
    else
        [~, b] = max(counts);
        bestZ = (edges(b) + edges(b+1)) * 0.5;
    end

    capMask = abs(zAll - bestZ) <= opts.zExpand;
    capPts = P(capMask,:);
    if size(capPts,1) < opts.minPts
        capMask = zAll <= zLowCut;
        capPts = P(capMask,:);
    end
    if size(capPts,1) < opts.minPts
        error("Too few points for bottom face.");
    end

    Cplane = mean(capPts, 1);
    planeN = [];
    inIdx = [];
    if exist('pcfitplane','file') == 2 && size(capPts,1) >= 50
        try
            if isfield(opts, "planeRef") && isfield(opts, "planeAng")
                [m, inIdx] = pcfitplane(pointCloud(capPts), opts.planeMaxDist, ...
                    opts.planeRef, opts.planeAng);
            else
                [m, inIdx] = pcfitplane(pointCloud(capPts), opts.planeMaxDist);
            end
            if ~isempty(inIdx)
                planeN = m.Normal(:);
                Cplane = mean(capPts(inIdx,:), 1);
            end
        catch
        end
    end
    if isempty(planeN)
        [~,~,Vn] = svd(capPts - Cplane, 'econ');
        planeN = Vn(:,3);
    end
    planeN = planeN / norm(planeN);
    if planeN(3) < 0
        planeN = -planeN;
    end

    if ~isempty(inIdx)
        idxFull = find(capMask);
        capMask(:) = false;
        capMask(idxFull(inIdx)) = true;
        capPts = P(capMask,:);
    end

    if abs(dot(planeN, [1 0 0]')) < 0.9
        tmp = [1 0 0]';
    else
        tmp = [0 1 0]';
    end
    e1 = cross(planeN, tmp); e1 = e1 / norm(e1);
    e2 = cross(planeN, e1);  e2 = e2 / norm(e2);

    if isfield(opts, "squareUseAll") && opts.squareUseAll
        Pfit = P;
    else
        Pfit = capPts;
    end
    Pproj = Pfit - ((Pfit - Cplane) * planeN) * planeN';
    Q = Pproj - Cplane;
    u = Q * e1;
    v = Q * e2;

    if isfield(opts, "squareUseHull") && opts.squareUseHull && numel(u) >= 10
        try
            k = convhull(u, v);
            uR = u(k);
            vR = v(k);
        catch
            uR = u;
            vR = v;
        end
    else
        uR = u;
        vR = v;
    end

    [theta, xmid, ymid, side] = minAreaSquare2D(uR, vR, opts.squareThetaStep, opts.squarePct);
    R = [cos(theta) -sin(theta); sin(theta) cos(theta)];
    a1 = e1 * R(1,1) + e2 * R(2,1);
    a2 = e1 * R(1,2) + e2 * R(2,2);
    a1 = a1 / norm(a1);
    a2 = a2 / norm(a2);

    pad = max(0, opts.squarePad);
    if isfield(opts, "squarePadFrac") && opts.squarePadFrac > 0
        pad = max(pad, opts.squarePadFrac * side);
    end
    side = side + 2 * pad;

    center3D = Cplane + xmid * a1' + ymid * a2';
    s = 0.5 * side;
    square3D = [ ...
        center3D + (-s) * a1' + (-s) * a2'; ...
        center3D + ( s) * a1' + (-s) * a2'; ...
        center3D + ( s) * a1' + ( s) * a2'; ...
        center3D + (-s) * a1' + ( s) * a2' ...
        ];
end
function [theta, xmin, xmax, ymin, ymax] = minAreaRect2D(u, v, stepDeg, pct)
    P = [u(:) v(:)];
    P = P(all(isfinite(P),2),:);
    if size(P,1) < 5
        theta = 0;
        xmin = min(u); xmax = max(u);
        ymin = min(v); ymax = max(v);
        return;
    end
    if nargin < 3 || isempty(stepDeg) || stepDeg <= 0
        stepDeg = 1;
    end
    if nargin < 4 || isempty(pct)
        pct = 0;
    end
    thetaList = 0:deg2rad(stepDeg):pi/2;
    bestArea = inf;
    theta = 0; xmin = 0; xmax = 0; ymin = 0; ymax = 0;
    for t = thetaList
        R = [cos(t) -sin(t); sin(t) cos(t)];
        Pr = P * R;
        if pct > 0
            xmin_t = prctile(Pr(:,1), pct);
            xmax_t = prctile(Pr(:,1), 100 - pct);
            ymin_t = prctile(Pr(:,2), pct);
            ymax_t = prctile(Pr(:,2), 100 - pct);
        else
            xmin_t = min(Pr(:,1));
            xmax_t = max(Pr(:,1));
            ymin_t = min(Pr(:,2));
            ymax_t = max(Pr(:,2));
        end
        area = (xmax_t - xmin_t) * (ymax_t - ymin_t);
        if area < bestArea
            bestArea = area;
            theta = t;
            xmin = xmin_t; xmax = xmax_t;
            ymin = ymin_t; ymax = ymax_t;
        end
    end
end

function [theta, xmid, ymid, side] = minAreaSquare2D(u, v, stepDeg, pct)
    P = [u(:) v(:)];
    P = P(all(isfinite(P),2),:);
    if size(P,1) < 5
        theta = 0;
        xmin = min(u); xmax = max(u);
        ymin = min(v); ymax = max(v);
        xmid = 0.5 * (xmin + xmax);
        ymid = 0.5 * (ymin + ymax);
        side = max(xmax - xmin, ymax - ymin);
        return;
    end
    if nargin < 3 || isempty(stepDeg) || stepDeg <= 0
        stepDeg = 1;
    end
    if nargin < 4 || isempty(pct)
        pct = 0;
    end
    thetaList = 0:deg2rad(stepDeg):pi/2;
    bestArea = inf;
    theta = 0; xmid = 0; ymid = 0; side = 0;
    for t = thetaList
        R = [cos(t) -sin(t); sin(t) cos(t)];
        Pr = P * R;
        if pct > 0
            xmin_t = prctile(Pr(:,1), pct);
            xmax_t = prctile(Pr(:,1), 100 - pct);
            ymin_t = prctile(Pr(:,2), pct);
            ymax_t = prctile(Pr(:,2), 100 - pct);
        else
            xmin_t = min(Pr(:,1));
            xmax_t = max(Pr(:,1));
            ymin_t = min(Pr(:,2));
            ymax_t = max(Pr(:,2));
        end
        w = xmax_t - xmin_t;
        h = ymax_t - ymin_t;
        s = max(w, h);
        area = s * s;
        if area < bestArea
            bestArea = area;
            theta = t;
            xmid = 0.5 * (xmin_t + xmax_t);
            ymid = 0.5 * (ymin_t + ymax_t);
            side = s;
        end
    end
end
function [target3D, midPt, axisVec, info] = fit_caseB_target_point_bottle(pcCan, pcRaw, opts)
    if nargin < 3
        opts = struct;
    end
    opts = withDefaults(opts, struct( ...
        "midBand", 0.004, ...
        "wallTol", 0.004, ...
        "tableMaxDist", 0.006, ...
        "tableAng", 10, ...
        "tableTopPct", 90, ...
        "tableMinPts", 200, ...
        "minCand", 50, ...
        "thickPct", 80, ...
        "thickTol", 0.003, ...
        "lineTol", 0.003, ...
        "targetMode", 2, ...
        "midUseRaw", false, ...
        "minMidPts", 120, ...
        "tableClear", 0.006, ...
        "refineAxis", true, ...
        "axisRefineCos", 0.95, ...
        "axisMode", "3d", ...
        "numSlices", 12, ...
        "minSlicePts", 60, ...
        "minCoverDeg", 120, ...
        "coverBins", 18, ...
        "coverExpand", 2.0, ...
        "wallExpand", 1.5, ...
        "debugB", false ...
        ));

    Pcan = double(pcCan.Location);
    Pcan = Pcan(all(isfinite(Pcan),2),:);
    if size(Pcan,1) < 50
        error("pcCan too small for case B.");
    end
    Praw = double(pcRaw.Location);
    Praw = Praw(all(isfinite(Praw),2),:);
    if size(Praw,1) < 50
        error("pcRaw too small for case B.");
    end

    Cxy = mean(Pcan(:,1:2), 1);
    rxy = sqrt(sum((Pcan(:,1:2) - Cxy).^2, 2));
    rCan = prctile(rxy, 90);
    [tableN, tableZ, found] = estimateTableNormal(pcRaw, opts.tableTopPct, opts.tableMaxDist, ...
        opts.tableAng, Cxy, rCan);
    if ~found
        tableN = [0 0 1]';
        tableZ = prctile(Praw(:,3), opts.tableTopPct);
    end
    if tableN(3) < 0
        tableN = -tableN;
    end
    tableD = -tableZ;
    tableIn = abs(Praw * tableN + tableD) <= opts.tableMaxDist;
    tableFrac = nnz(tableIn) / max(1, size(Praw,1));

    if abs(dot(tableN, [1 0 0]')) < 0.9
        tmp = [1 0 0]';
    else
        tmp = [0 1 0]';
    end
    eT1 = cross(tableN, tmp); eT1 = eT1 / norm(eT1);
    eT2 = cross(tableN, eT1); eT2 = eT2 / norm(eT2);

    tableClear = max(opts.tableClear, opts.tableMaxDist);
    dTabCan = Pcan * tableN + tableD;
    keepCan = abs(dTabCan) > tableClear;
    if nnz(keepCan) >= max(50, round(0.2 * size(Pcan,1)))
        PcanAxis = Pcan(keepCan, :);
    else
        PcanAxis = Pcan;
    end

    C0 = mean(PcanAxis, 1);
    Q0 = PcanAxis - C0;
    axisMode = "3d";
    if isfield(opts, 'axisMode')
        axisMode = string(opts.axisMode);
    end
    if axisMode == "wall"
        [axisVec, ~] = estimateAxisFromWall(PcanAxis);
        axisVec = axisVec(:);
        axisVec = axisVec - dot(axisVec, tableN) * tableN;
    elseif axisMode == "proj"
        u = Q0 * eT1;
        v = Q0 * eT2;
        [~,~,Vuv] = svd([u v], 'econ');
        dir2 = Vuv(:,1);
        axisVec = (dir2(1) * eT1 + dir2(2) * eT2)';
    else
        [~,~,V3] = svd(Q0, 'econ');
        axisVec = V3(:,1);
        axisVec = axisVec - dot(axisVec, tableN) * tableN;
    end
    if norm(axisVec) < 1e-9
        u = Q0 * eT1;
        v = Q0 * eT2;
        [~,~,Vuv] = svd([u v], 'econ');
        dir2 = Vuv(:,1);
        axisVec = (dir2(1) * eT1 + dir2(2) * eT2)';
    end
    axisVec = axisVec(:)';
    axisVec = axisVec / max(norm(axisVec), 1e-9);

    [centers, rSlice, tSlice] = sliceCenters(PcanAxis, C0, axisVec, opts);

    axisRefined = false;
    if opts.refineAxis && size(centers,1) >= 4
        Cc = mean(centers, 1);
        if axisMode == "proj" || axisMode == "wall"
            uc = (centers - Cc) * eT1;
            vc = (centers - Cc) * eT2;
            [~,~,Vuv] = svd([uc vc], 'econ');
            dir2 = Vuv(:,1);
            axisVec2 = (dir2(1) * eT1 + dir2(2) * eT2)';
        else
            [~,~,Vc] = svd(centers - Cc, 'econ');
            axisVec2 = Vc(:,1);
        end
        axisVec2 = axisVec2 - dot(axisVec2, tableN) * tableN;
        if norm(axisVec2) > 1e-9
            axisVec2 = axisVec2(:);
            axisVecCol = axisVec(:);
            if numel(axisVec2) == numel(axisVecCol)
                axisVec2 = axisVec2 / norm(axisVec2);
                if dot(axisVec2, axisVecCol) < 0
                    axisVec2 = -axisVec2;
                end
                if abs(dot(axisVec2, axisVecCol)) < opts.axisRefineCos
                    axisVec = axisVec2';
                    axisRefined = true;
                    [centers, rSlice, tSlice] = sliceCenters(PcanAxis, C0, axisVec, opts);
                end
            end
        end
    end

    nB = axisVec(:) / norm(axisVec(:));
    if abs(dot(nB, [1 0 0]')) < 0.9
        tmp = [1 0 0]';
    else
        tmp = [0 1 0]';
    end
    e1 = cross(nB, tmp); e1 = e1 / norm(e1);
    e2 = cross(nB, e1);  e2 = e2 / norm(e2);

    tAll = (PcanAxis - C0) * axisVec';
    tLoAll = prctile(tAll, 5);
    tHiAll = prctile(tAll, 95);

    if ~isempty(centers)
        Ccent = median(centers, 1);
        axisOrigin = Ccent;
    else
        axisOrigin = mean(Pcan, 1);
    end
    shift = dot(axisOrigin - C0, axisVec);

    if ~isempty(rSlice)
        rThr = prctile(rSlice, opts.thickPct);
        thickSlice = rSlice >= (rThr - opts.thickTol);
        if nnz(thickSlice) == 0
            thickSlice = rSlice >= rThr;
        end
        r0 = median(rSlice(thickSlice));
        tSlice2 = tSlice - shift;
        tLo = min(tSlice2(thickSlice));
        tHi = max(tSlice2(thickSlice));
    else
        Qp = (PcanAxis - axisOrigin) - ((PcanAxis - axisOrigin) * nB) * nB';
        rAll = sqrt(sum(Qp.^2, 2));
        r0 = prctile(rAll, 70);
        tAll2 = (PcanAxis - axisOrigin) * axisVec';
        tLo = prctile(tAll2, 5);
        tHi = prctile(tAll2, 95);
    end
    if ~isfinite(r0) || r0 <= 0
        r0 = prctile(abs(tAll), 70);
    end
    if ~isfinite(tLo) || ~isfinite(tHi) || tLo >= tHi
        tLo = tLoAll;
        tHi = tHiAll;
    end
    midT = 0.5 * (tLo + tHi);
    midPt = axisOrigin + midT * axisVec;

    useRaw = isfield(opts, 'midUseRaw') && opts.midUseRaw;
    PmidSrc = Pcan; midSource = "can";
    if useRaw
        PmidSrc = Praw; midSource = "raw";
    end
    Pm = selectMidBand(PmidSrc, midPt, axisVec, tableN, tableD, opts.midBand, opts.tableClear);
    if size(Pm,1) < opts.minMidPts && ~useRaw
        PmRaw = selectMidBand(Praw, midPt, axisVec, tableN, tableD, opts.midBand, opts.tableClear);
        if size(PmRaw,1) > size(Pm,1)
            Pm = PmRaw; midSource = "raw";
        end
    end
    if isempty(Pm)
        target3D = midPt;
        info = struct("reason", "empty_midband");
        return;
    end

    tp = (Pm - axisOrigin) * axisVec';
    perpP = (Pm - axisOrigin) - tp * axisVec;
    rp = sqrt(sum(perpP.^2, 2));
    wallMask = abs(rp - r0) <= opts.wallTol;
    Pcand = Pm(wallMask, :);
    if size(Pcand,1) < opts.minCand
        Pcand = Pm;
    end

    coverDeg = angleCoverageDeg(Pm, axisOrigin, axisVec, e1, e2, opts.coverBins);
    coverDeg2 = coverDeg;
    if coverDeg < opts.minCoverDeg
        Pm2 = selectMidBand(PmidSrc, midPt, axisVec, tableN, tableD, opts.midBand * opts.coverExpand, opts.tableClear);
        if ~isempty(Pm2)
            tp2 = (Pm2 - axisOrigin) * axisVec';
            perpP2 = (Pm2 - axisOrigin) - tp2 * axisVec;
            rp2 = sqrt(sum(perpP2.^2, 2));
            wallMask2 = abs(rp2 - r0) <= (opts.wallTol * opts.wallExpand);
            Pcand2 = Pm2(wallMask2, :);
            if size(Pcand2,1) < opts.minCand
                Pcand = Pm2;
            else
                Pcand = Pcand2;
            end
            coverDeg2 = angleCoverageDeg(Pcand, axisOrigin, axisVec, e1, e2, opts.coverBins);
        end
    end

    Cline = mean(Pcand, 1);
    [~,~,Vline] = svd(Pcand - Cline, 'econ');
    dirLine = Vline(:,1)'; dirLine = dirLine / norm(dirLine);
    tline = (Pcand - Cline) * dirLine';
    proj = Cline + tline * dirLine;
    dline = sqrt(sum((Pcand - proj).^2, 2));
    keepLine = dline <= opts.lineTol;
    if nnz(keepLine) >= max(10, round(0.1 * size(Pcand,1)))
        Pline = Pcand(keepLine, :);
    else
        Pline = Pcand;
    end
    tline = (Pline - Cline) * dirLine';
    tlo = prctile(tline, 5);
    thi = prctile(tline, 95);
    p1 = Cline + tlo * dirLine;
    p2 = Cline + thi * dirLine;

    switch opts.targetMode
        case 2
            Psel = Pline;
        case 3
            Psel = [p1; p2];
        otherwise
            Psel = Pcand;
    end
    if isempty(Psel)
        Psel = Pcand;
    end
    distTable = Psel * tableN + tableD;
    valid = isfinite(distTable);
    PcValid = Psel(valid, :);
    distTable = distTable(valid);
    if isempty(distTable)
        target3D = midPt;
    else
        distMid = midPt * tableN + tableD;
        if distMid < 0
            [~, idxSel] = min(distTable);
        else
            [~, idxSel] = max(distTable);
        end
        target3D = PcValid(idxSel, :);
    end

    tableFracCan = nnz(abs(Pcan * tableN + tableD) <= tableClear) / max(1, size(Pcan,1));
    info = struct( ...
        "axis", axisVec, ...
        "midPt", midPt, ...
        "radius", r0, ...
        "numMid", size(Pm,1), ...
        "numCand", size(Pcand,1), ...
        "tableN", tableN', ...
        "tableZ", tableZ, ...
        "tableFrac", tableFrac, ...
        "tableFracCan", tableFracCan, ...
        "coverDeg", coverDeg, ...
        "coverDeg2", coverDeg2, ...
        "axisMode", axisMode, ...
        "midPts", Pm, ...
        "candPts", Pcand, ...
        "linePts", [p1; p2], ...
        "lineDir", dirLine, ...
        "targetMode", opts.targetMode, ...
        "midSource", midSource, ...
        "axisRefined", axisRefined ...
        );
end
function coverDeg = angleCoverageDeg(Ppts, c_perp, axisVec, e1, e2, nb)
    if isempty(Ppts)
        coverDeg = 0;
        return;
    end
    nA = axisVec(:) / norm(axisVec(:));
    Q = Ppts - c_perp;
    perp = Q - (Q * nA) * nA';
    x = perp * e1;
    y = perp * e2;
    ang = atan2(y, x);
    nb = max(8, nb);
    edges = linspace(-pi, pi, nb+1);
    counts = histcounts(ang, edges);
    coverDeg = 360 * (nnz(counts > 0) / nb);
end

function Pm = selectMidBand(Psrc, midPt, axisVec, tableN, tableD, band, tableClear)
    if isempty(Psrc)
        Pm = zeros(0,3);
        return;
    end
    distMid = abs((Psrc - midPt) * axisVec');
    Pm = Psrc(distMid <= band, :);
    if isempty(Pm)
        return;
    end
    if tableClear > 0
        dTab = Pm * tableN + tableD;
        keep = abs(dTab) >= tableClear;
        if any(keep)
            Pm = Pm(keep, :);
        end
    end
end

function [centers, rSlice, tSlice] = sliceCenters(Pcan, C0, axisVec, opts)
    axisCol = axisVec(:);
    axisRow = axisCol';
    nB = axisCol / norm(axisCol);
    if abs(dot(nB, [1 0 0]')) < 0.9
        tmp = [1 0 0]';
    else
        tmp = [0 1 0]';
    end
    e1 = cross(nB, tmp); e1 = e1 / norm(e1);
    e2 = cross(nB, e1);  e2 = e2 / norm(e2);
    tAll = (Pcan - C0) * axisCol;
    tLoAll = prctile(tAll, 5);
    tHiAll = prctile(tAll, 95);
    edges = linspace(tLoAll, tHiAll, max(4, opts.numSlices) + 1);
    centers = [];
    rSlice = [];
    tSlice = [];
    for i = 1:numel(edges)-1
        idx = tAll >= edges(i) & tAll < edges(i+1);
        if nnz(idx) < opts.minSlicePts
            continue;
        end
        Pi = Pcan(idx, :);
        Pshift = Pi - C0;
        Qp = Pshift - (Pshift * nB) * nB';
        x = Qp * e1;
        y = Qp * e2;
        if numel(x) >= 6
            [cx, cy] = fitCircle2D(x, y);
        else
            cx = mean(x); cy = mean(y);
        end
        r90 = prctile(sqrt((x - cx).^2 + (y - cy).^2), 90);
        tMean = mean(tAll(idx));
        center3D = C0 + cx * e1' + cy * e2' + tMean * axisRow;
        centers = [centers; center3D]; %#ok<AGROW>
        rSlice = [rSlice; r90]; %#ok<AGROW>
        tSlice = [tSlice; tMean]; %#ok<AGROW>
    end
end

function [cx, cy] = fitCircle2D(x, y)
    x = x(:); y = y(:);
    A = [x y ones(size(x))];
    b = -(x.^2 + y.^2);
    p = A \ b;
    cx = -0.5 * p(1);
    cy = -0.5 * p(2);
end

function s = withDefaults(s, defaults)
    f = fieldnames(defaults);
    for i = 1:numel(f)
        if ~isfield(s, f{i})
            s.(f{i}) = defaults.(f{i});
        end
    end
end

%% ---------------- color helpers ----------------
function cfg = default_color_config()
    cfg = struct( ...
        "cubeShrink", 0.82, ...
        "cubeErodeRadius", 2, ...
        "cylErodeRadius", 2, ...
        "cylBodyMajorPct", 68, ...
        "bboxInsetFrac", 0.12, ...
        "minPixels", 40, ...
        "minCompArea", 40, ...
        "hueSigma", 0.075, ...
        "satWeightPow", 1.4, ...
        "minVal", 0.08, ...
        "maxVal", 1.00, ...
        "minSatCube", 0.10, ...
        "minSatCylinder", 0.16, ...
        "uprightBottleRingFrac", 0.58, ...
        "uprightBottleMinSideScore", 0.22, ...
        "uprightBottleBlueOverrideMargin", 0.18 ...
        );
end

function info = default_color_info()
    info = struct( ...
        "label", ", ...
        "score", NaN, ...
        "source", ", ...
        "meanHSV", [NaN NaN NaN], ...
        "meanRGB", [NaN NaN NaN], ...
        "pixelCount", 0, ...
        "points", NaN, ...
        "targetBin", " ...
        );
end

function info = estimate_cylinder_color_info(rgb, det, proto, imgsz, maskThresh, maskMinArea, maskUseBBox, scaleLB, padLB, clsName, abLabel, cfg)
    info = default_color_info();
    if isempty(rgb)
        return;
    end
    H = size(rgb, 1);
    W = size(rgb, 2);
    maskObj = build_object_mask_for_color(det, proto, imgsz, maskThresh, maskMinArea, maskUseBBox, scaleLB, padLB, H, W, cfg);
    if ~any(maskObj(:))
        return;
    end
    if string(clsName) == "bottle" && string(abLabel) == "A"
        info = estimate_upright_bottle_color_info(rgb, maskObj, cfg);
        if is_color_info_valid(info)
            return;
        end
    end
    maskBody = select_cylinder_body_mask(maskObj, cfg);
    if nnz(maskBody) < cfg.minPixels
        maskBody = maskObj;
    end
    info = classify_color_from_mask(rgb, maskBody, clsName, cfg, "mask");
end

function info = estimate_upright_bottle_color_info(rgb, maskObj, cfg)
    info = default_color_info();
    [maskRing, maskSide1, maskSide2] = build_upright_bottle_side_masks(maskObj, cfg);
    infoRing = classify_color_from_mask(rgb, maskRing, "bottle", cfg, "upright_ring");
    info1 = classify_color_from_mask(rgb, maskSide1, "bottle", cfg, "upright_side1");
    info2 = classify_color_from_mask(rgb, maskSide2, "bottle", cfg, "upright_side2");

    sideInfos = [info1, info2];
    bestSide = default_color_info();
    for k = 1:numel(sideInfos)
        if ~is_color_info_valid(sideInfos(k))
            continue;
        end
        if ~is_color_info_valid(bestSide) || sideInfos(k).score > bestSide.score || ...
                (abs(sideInfos(k).score - bestSide.score) < 1e-6 && sideInfos(k).pixelCount > bestSide.pixelCount)
            bestSide = sideInfos(k);
        end
    end

    if is_color_info_valid(bestSide) && string(bestSide.label) ~= "blue" && ...
            bestSide.score >= cfg.uprightBottleMinSideScore
        if ~is_color_info_valid(infoRing) || string(infoRing.label) == "blue" || ...
                bestSide.score >= infoRing.score - cfg.uprightBottleBlueOverrideMargin
            info = bestSide;
            return;
        end
    end

    if is_color_info_valid(infoRing)
        info = infoRing;
    elseif is_color_info_valid(bestSide)
        info = bestSide;
    end
end

function info = estimate_cube_color_info(rgb, square2D, cfg)
    info = default_color_info();
    if isempty(rgb) || isempty(square2D) || size(square2D, 1) < 3
        return;
    end
    H = size(rgb, 1);
    W = size(rgb, 2);
    poly = shrink_polygon_to_center(square2D, cfg.cubeShrink);
    maskObj = poly2mask(poly(:,1), poly(:,2), H, W);
    if cfg.cubeErodeRadius > 0
        se = strel('disk', cfg.cubeErodeRadius, 0);
        maskTry = imerode(maskObj, se);
        if nnz(maskTry) >= cfg.minPixels
            maskObj = maskTry;
        end
    end
    if nnz(maskObj) < cfg.minPixels
        return;
    end
    info = classify_color_from_mask(rgb, maskObj, "cube", cfg, "topface");
end

function maskBin = build_object_mask_for_color(det, proto, imgsz, maskThresh, maskMinArea, maskUseBBox, scaleLB, padLB, H, W, cfg)
    maskBin = false(H, W);
    useMask = ~isempty(proto) && isfield(det, "maskCoeff") && ~isempty(det.maskCoeff);
    if useMask
        if isfield(det, "maskBBox640") && ~isempty(det.maskBBox640)
            b640 = det.maskBBox640;
        else
            b640 = [];
        end
        mask640 = buildMaskFromProto(det.maskCoeff, proto, imgsz);
        if maskUseBBox && ~isempty(b640)
            x1b = max(1, floor(b640(1))); y1b = max(1, floor(b640(2)));
            x2b = min(imgsz, ceil(b640(3))); y2b = min(imgsz, ceil(b640(4)));
            mask640(:,1:max(1,x1b-1)) = 0;
            mask640(:,min(imgsz,x2b+1):end) = 0;
            mask640(1:max(1,y1b-1),:) = 0;
            mask640(min(imgsz,y2b+1):end,:) = 0;
        end
        maskOrig = unletterboxMask(mask640, scaleLB, padLB, W, H);
        maskBin = maskOrig > maskThresh;
        if maskMinArea > 0
            maskBin = bwareaopen(maskBin, maskMinArea);
        end
        if isfield(det, "bbox") && ~isempty(det.bbox)
            maskBin = keep_primary_mask_component(maskBin, det.bbox, cfg.minCompArea);
        end
    elseif isfield(det, "bbox") && ~isempty(det.bbox)
        bb = det.bbox;
        x1 = max(1, floor(bb(1))); y1 = max(1, floor(bb(2)));
        x2 = min(W, ceil(bb(3)));  y2 = min(H, ceil(bb(4)));
        if x2 >= x1 && y2 >= y1
            dx = round((x2 - x1) * cfg.bboxInsetFrac);
            dy = round((y2 - y1) * cfg.bboxInsetFrac);
            x1 = min(W, max(1, x1 + dx));
            y1 = min(H, max(1, y1 + dy));
            x2 = max(1, min(W, x2 - dx));
            y2 = max(1, min(H, y2 - dy));
            if x2 >= x1 && y2 >= y1
                maskBin(y1:y2, x1:x2) = true;
            end
        end
    end
end

function maskBody = select_cylinder_body_mask(maskObj, cfg)
    maskBody = logical(maskObj);
    if ~any(maskBody(:))
        return;
    end
    if cfg.cylErodeRadius > 0
        se = strel('disk', cfg.cylErodeRadius, 0);
        maskTry = imerode(maskBody, se);
        if nnz(maskTry) >= cfg.minPixels
            maskBody = maskTry;
        end
    end
    [vv, uu] = find(maskBody);
    if numel(uu) < cfg.minPixels
        return;
    end
    U = [double(uu), double(vv)];
    C = mean(U, 1);
    Q = U - C;
    if size(Q,1) < 3
        return;
    end
    [~, ~, V] = svd(Q, 'econ');
    tMajor = Q * V(:,1);
    thr = prctile(abs(tMajor), cfg.cylBodyMajorPct);
    keep = abs(tMajor) <= thr;
    if nnz(keep) < cfg.minPixels
        return;
    end
    maskMid = false(size(maskBody));
    idx = sub2ind(size(maskBody), vv(keep), uu(keep));
    maskMid(idx) = true;
    if nnz(maskMid) >= cfg.minPixels
        maskBody = maskMid;
    end
end

function [maskRing, maskSide1, maskSide2] = build_upright_bottle_side_masks(maskObj, cfg)
    maskRing = false(size(maskObj));
    maskSide1 = false(size(maskObj));
    maskSide2 = false(size(maskObj));
    maskBase = logical(maskObj);
    if ~any(maskBase(:))
        return;
    end
    if cfg.cylErodeRadius > 0
        se = strel('disk', cfg.cylErodeRadius, 0);
        maskTry = imerode(maskBase, se);
        if nnz(maskTry) >= cfg.minPixels
            maskBase = maskTry;
        end
    end
    [vv, uu] = find(maskBase);
    if numel(uu) < cfg.minPixels
        maskRing = maskBase;
        return;
    end
    U = [double(uu), double(vv)];
    C = mean(U, 1);
    Q = U - C;
    if size(Q,1) < 3
        maskRing = maskBase;
        return;
    end
    [~, ~, V] = svd(Q, 'econ');
    t1 = Q * V(:,1);
    t2 = Q * V(:,2);
    s1 = max(prctile(abs(t1), 90), 1);
    s2 = max(prctile(abs(t2), 90), 1);
    rNorm = sqrt((t1 ./ s1) .^ 2 + (t2 ./ s2) .^ 2);
    keepRing = rNorm >= cfg.uprightBottleRingFrac;
    if nnz(keepRing) < cfg.minPixels
        keepRing = true(size(t1));
    end
    idxRing = sub2ind(size(maskBase), vv(keepRing), uu(keepRing));
    maskRing(idxRing) = true;
    keep1 = keepRing & (t1 >= 0);
    keep2 = keepRing & (t1 < 0);
    if nnz(keep1) >= cfg.minPixels
        idx1 = sub2ind(size(maskBase), vv(keep1), uu(keep1));
        maskSide1(idx1) = true;
    end
    if nnz(keep2) >= cfg.minPixels
        idx2 = sub2ind(size(maskBase), vv(keep2), uu(keep2));
        maskSide2(idx2) = true;
    end
end

function info = classify_color_from_mask(rgb, maskBin, clsName, cfg, sourceTag)
    info = default_color_info();
    if isempty(rgb) || isempty(maskBin) || ~any(maskBin(:))
        return;
    end
    rgbD = im2double(rgb);
    hsvI = rgb2hsv(rgbD);
    H = hsvI(:,:,1);
    S = hsvI(:,:,2);
    V = hsvI(:,:,3);
    minSat = cfg.minSatCylinder;
    if string(clsName) == "cube"
        minSat = cfg.minSatCube;
    end
    valid = maskBin & isfinite(H) & isfinite(S) & isfinite(V) & (V >= cfg.minVal) & (V <= cfg.maxVal + 1e-6);
    strong = valid & (S >= minSat);
    if nnz(strong) >= cfg.minPixels
        useMask = strong;
        src = string(sourceTag) + "_sat";
    elseif nnz(valid) >= cfg.minPixels
        useMask = valid;
        src = string(sourceTag) + "_relaxed";
    else
        return;
    end
    hp = H(useMask);
    sp = S(useMask);
    vp = V(useMask);
    rgbFlat = reshape(rgbD, [], 3);
    rgbPx = rgbFlat(useMask(:), :);
    w = max(sp, 0.05) .^ cfg.satWeightPow;
    w = w / max(sum(w), eps);
    [candNames, candHues] = get_color_candidates(clsName);
    if isempty(candNames)
        return;
    end
    scores = zeros(1, numel(candNames));
    for k = 1:numel(candNames)
        dh = abs(hp - candHues(k));
        dh = min(dh, 1 - dh);
        scores(k) = sum(w .* exp(-0.5 * (dh ./ cfg.hueSigma) .^ 2));
    end
    [bestScore, bestIdx] = max(scores);
    if numel(scores) > 1
        scoreOthers = scores;
        scoreOthers(bestIdx) = -inf;
        secondScore = max(scoreOthers);
        if ~isfinite(secondScore)
            secondScore = 0;
        end
    else
        secondScore = 0;
    end
    info.label = candNames(bestIdx);
    info.score = max(0, min(1, 0.65 * bestScore + 0.35 * max(0, bestScore - secondScore)));
    info.source = src;
    info.meanHSV = [circular_mean_hue(hp, w), sum(w .* sp), sum(w .* vp)];
    info.meanRGB = sum(rgbPx .* w, 1);
    info.pixelCount = nnz(useMask);
    [info.points, info.targetBin] = map_color_to_scoring(clsName, info.label);
end

function tf = is_color_info_valid(info)
    tf = isstruct(info) && isfield(info, "label") && strlength(string(info.label)) > 0 && ...
        isfield(info, "score") && isfinite(info.score);
end

function [names, hues] = get_color_candidates(clsName)
    switch string(clsName)
        case "can"
            names = ["red", "yellow", "green"];
            hues = [0.00, 0.15, 0.33];
        case "bottle"
            names = ["red", "yellow", "blue"];
            hues = [0.00, 0.15, 0.62];
        case "cube"
            names = ["red", "green", "blue", "purple"];
            hues = [0.00, 0.33, 0.62, 0.78];
        otherwise
            names = strings(1,0);
            hues = zeros(1,0);
    end
end

function [points, targetBin] = map_color_to_scoring(clsName, label)
    points = NaN;
    targetBin = ";
    switch string(clsName)
        case "can"
            targetBin = "green";
            switch string(label)
                case "green"
                    points = 10;
                case "yellow"
                    points = 20;
                case "red"
                    points = 30;
            end
        case "bottle"
            targetBin = "blue";
            switch string(label)
                case "blue"
                    points = 10;
                case "yellow"
                    points = 20;
                case "red"
                    points = 30;
            end
        case "cube"
            points = 10;
            switch string(label)
                case {"green", "purple"}
                    targetBin = "green";
                case {"blue", "red"}
                    targetBin = "blue";
            end
    end
end

function hMean = circular_mean_hue(h, w)
    ang = 2 * pi * h(:);
    c = sum(w(:) .* cos(ang));
    s = sum(w(:) .* sin(ang));
    hMean = mod(atan2(s, c) / (2 * pi), 1);
end

function polyOut = shrink_polygon_to_center(polyIn, factor)
    polyOut = polyIn;
    if isempty(polyIn) || size(polyIn, 1) < 3
        return;
    end
    C = mean(polyIn, 1);
    polyOut = C + factor * (polyIn - C);
end

function suffix = format_color_suffix(obj)
    suffix = ";
    if isfield(obj, "color") && strlength(string(obj.color)) > 0
        suffix = " " + string(obj.color);
        if isfield(obj, "colorScore") && isfinite(obj.colorScore)
            suffix = suffix + sprintf("(%.2f)", obj.colorScore);
        end
    end
end

function show_image_results(rgb, imgRes, gripperMask)
    figName = sprintf("Results: %s", imgRes.name);
    figure('Name', figName);
    imshow(rgb); hold on;
    if nargin >= 3 && ~isempty(gripperMask)
        per = bwperim(gripperMask);
        [yy, xx] = find(per);
        plot(xx, yy, 'r.', 'MarkerSize', 1);
    end
    draw_class_results(imgRes.can, 'c', [0.2 0.8 1.0]);
    draw_class_results(imgRes.bottle, 'b', [1.0 0.6 0.1]);
    draw_rect_results(imgRes.spam, 's', [0.9 0.2 0.9]);
    draw_line_results(imgRes.marker, 'm', [0.1 1.0 0.1]);
    draw_square_results(imgRes.cube, 'p', [1.0 0.9 0.2]);
    title(figName);
    hold off;
end

function show_3d_results(imgRes)
    show_3d_class(imgRes.name, "can", imgRes.can);
    show_3d_class(imgRes.name, "bottle", imgRes.bottle);
    show_3d_class(imgRes.name, "spam", imgRes.spam);
    show_3d_class(imgRes.name, "marker", imgRes.marker);
    show_3d_class(imgRes.name, "cube", imgRes.cube);
end

function show_3d_class(imgName, clsName, objs)
    if isempty(objs)
        return;
    end
    if ~has_cloud_points(objs)
        return;
    end
    figName = sprintf("3D %s: %s", clsName, imgName);
    figure('Name', figName);
    hold on; grid on; axis equal;
    xlabel('X'); ylabel('Y'); zlabel('Z');
    colors = lines(max(1, numel(objs)));
    for k = 1:numel(objs)
        if ~isfield(objs(k), 'cloud') || isempty(objs(k).cloud)
            continue;
        end
        P = objs(k).cloud;
        c = colors(k,:);
        scatter3(P(:,1), P(:,2), P(:,3), 6, c, 'filled');
        if isfield(objs(k), 'center3D') && ~isempty(objs(k).center3D)
            C = objs(k).center3D;
            uv = objs(k).center2D;
            txt = sprintf('%s%d s=%.2f uv=(%.1f,%.1f)', clsName(1), k, objs(k).score, uv(1), uv(2));
            text(C(1), C(2), C(3), txt, 'Color', c, 'FontSize', 8, 'FontWeight', 'bold');
        end
        if isfield(objs(k), 'axisLine3D') && ~isempty(objs(k).axisLine3D)
            plot3(objs(k).axisLine3D(:,1), objs(k).axisLine3D(:,2), objs(k).axisLine3D(:,3), '-', 'Color', c, 'LineWidth', 2);
        end
        if isfield(objs(k), 'intersectLine3D') && ~isempty(objs(k).intersectLine3D)
            plot3(objs(k).intersectLine3D(:,1), objs(k).intersectLine3D(:,2), objs(k).intersectLine3D(:,3), '-', 'Color', [0 1 0], 'LineWidth', 2);
        end
        if isfield(objs(k), 'rect3D') && ~isempty(objs(k).rect3D)
            plot_poly3(objs(k).rect3D, c);
        end
        if isfield(objs(k), 'square3D') && ~isempty(objs(k).square3D)
            plot_poly3(objs(k).square3D, c);
        end
    end
    title(figName);
    hold off;
end

function tf = has_cloud_points(objs)
    tf = false;
    for k = 1:numel(objs)
        if isfield(objs(k), 'cloud') && ~isempty(objs(k).cloud) && size(objs(k).cloud,1) > 0
            tf = true;
            return;
        end
    end
end

function plot_poly3(P, color)
    if isempty(P) || size(P,1) < 3
        return;
    end
    plot3([P(:,1); P(1,1)], [P(:,2); P(1,2)], [P(:,3); P(1,3)], '-', 'Color', color, 'LineWidth', 2);
end

function draw_class_results(objs, label, color)
    if isempty(objs)
        return;
    end
    for k = 1:numel(objs)
        bb = objs(k).bbox;
        rect = [bb(1) bb(2) bb(3)-bb(1) bb(4)-bb(2)];
        isPartial = isfield(objs(k), 'partial') && objs(k).partial;
        lineStyle = '-';
        boxColor = color;
        if isPartial
            lineStyle = '--';
            boxColor = [1.0 0.2 0.2];
        end
        rectangle('Position', rect, 'EdgeColor', boxColor, 'LineWidth', 2, 'LineStyle', lineStyle);
        txt = string(sprintf("%s %.2f %s", label, objs(k).score, objs(k).ab)) + format_color_suffix(objs(k));
        if isPartial
            txt = txt + " partial";
        end
        text(bb(1), max(1, bb(2)-10), txt, 'Color', boxColor, 'FontSize', 10, 'FontWeight', 'bold');
        plot_pt(objs(k).center2D, color, 'o');
        if isfield(objs(k), 'axisLine2D') && ~isempty(objs(k).axisLine2D) && objs(k).ab == "B"
            plot_line(objs(k).axisLine2D, [0.2 0.9 1.0]);
        end
        if isfield(objs(k), 'intersectLine2D') && ~isempty(objs(k).intersectLine2D)
            plot_line(objs(k).intersectLine2D, [0.1 1.0 0.1]);
        end
    end
end

function draw_line_results(objs, label, color)
    if isempty(objs)
        return;
    end
    for k = 1:numel(objs)
        bb = objs(k).bbox;
        rect = [bb(1) bb(2) bb(3)-bb(1) bb(4)-bb(2)];
        isPartial = isfield(objs(k), 'partial') && objs(k).partial;
        lineStyle = '-';
        boxColor = color;
        if isPartial
            lineStyle = '--';
            boxColor = [1.0 0.2 0.2];
        end
        rectangle('Position', rect, 'EdgeColor', boxColor, 'LineWidth', 2, 'LineStyle', lineStyle);
        txt = string(sprintf("%s %.2f", label, objs(k).score)) + format_color_suffix(objs(k));
        if isPartial
            txt = txt + " partial";
        end
        text(bb(1), max(1, bb(2)-10), txt, 'Color', boxColor, 'FontSize', 10, 'FontWeight', 'bold');
        plot_pt(objs(k).center2D, color, 'o');
        plot_line(objs(k).axisLine2D, [0.2 0.9 1.0]);
        plot_line(objs(k).intersectLine2D, [0.1 1.0 0.1]);
    end
end

function draw_rect_results(objs, label, color)
    if isempty(objs)
        return;
    end
    for k = 1:numel(objs)
        bb = objs(k).bbox;
        rect = [bb(1) bb(2) bb(3)-bb(1) bb(4)-bb(2)];
        isPartial = isfield(objs(k), 'partial') && objs(k).partial;
        lineStyle = '-';
        boxColor = color;
        if isPartial
            lineStyle = '--';
            boxColor = [1.0 0.2 0.2];
        end
        rectangle('Position', rect, 'EdgeColor', boxColor, 'LineWidth', 2, 'LineStyle', lineStyle);
        txt = string(sprintf("%s %.2f", label, objs(k).score)) + format_color_suffix(objs(k));
        if isPartial
            txt = txt + " partial";
        end
        text(bb(1), max(1, bb(2)-10), txt, 'Color', boxColor, 'FontSize', 10, 'FontWeight', 'bold');
        plot_pt(objs(k).center2D, color, 'o');
        plot_poly(objs(k).rect2D, color);
    end
end

function draw_square_results(objs, label, color)
    if isempty(objs)
        return;
    end
    for k = 1:numel(objs)
        bb = objs(k).bbox;
        rect = [bb(1) bb(2) bb(3)-bb(1) bb(4)-bb(2)];
        isPartial = isfield(objs(k), 'partial') && objs(k).partial;
        lineStyle = '-';
        boxColor = color;
        if isPartial
            lineStyle = '--';
            boxColor = [1.0 0.2 0.2];
        end
        rectangle('Position', rect, 'EdgeColor', boxColor, 'LineWidth', 2, 'LineStyle', lineStyle);
        txt = string(sprintf("%s %.2f", label, objs(k).score)) + format_color_suffix(objs(k));
        if isPartial
            txt = txt + " partial";
        end
        text(bb(1), max(1, bb(2)-10), txt, 'Color', boxColor, 'FontSize', 10, 'FontWeight', 'bold');
        plot_pt(objs(k).center2D, color, 'o');
        plot_poly(objs(k).square2D, color);
    end
end

function plot_pt(p, color, marker)
    if isempty(p)
        return;
    end
    plot(p(1), p(2), marker, 'Color', color, 'MarkerSize', 8, 'LineWidth', 2);
end

function out = ternary(cond, a, b)
    if cond
        out = a;
    else
        out = b;
    end
end

function plot_line(p2, color)
    if isempty(p2) || size(p2,1) < 2
        return;
    end
    plot([p2(1,1) p2(2,1)], [p2(1,2) p2(2,2)], '-', 'Color', color, 'LineWidth', 2);
end

function plot_poly(p, color)
    if isempty(p) || size(p,1) < 3
        return;
    end
    plot([p(:,1); p(1,1)], [p(:,2); p(1,2)], '-', 'Color', color, 'LineWidth', 2);
end

function isPartial = is_bbox_partial(bbox, W, H, marginPx)
    if nargin < 4 || isempty(marginPx)
        marginPx = 0;
    end
    x1 = bbox(1); y1 = bbox(2); x2 = bbox(3); y2 = bbox(4);
    isPartial = (x1 <= 1 + marginPx) || (y1 <= 1 + marginPx) || ...
                (x2 >= W - marginPx) || (y2 >= H - marginPx);
end

function tf = is_bbox_overlapping_mask(bbox, mask)
    tf = false;
    if isempty(mask)
        return;
    end
    H = size(mask,1); W = size(mask,2);
    x1 = max(1, min(W, floor(bbox(1))));
    y1 = max(1, min(H, floor(bbox(2))));
    x2 = max(1, min(W, ceil(bbox(3))));
    y2 = max(1, min(H, ceil(bbox(4))));
    if x2 < x1 || y2 < y1
        return;
    end
    sub = mask(y1:y2, x1:x2);
    tf = any(sub(:));
end

function tf = is_mask_partial_soft(maskCoeff, proto, imgsz, bbox640, scale, pad, W, H, ...
    maskThresh, maskMinArea, maskUseBBox, bboxOrig, edgeMarginPx, gripperMask, ...
    maskMinAreaPx, maskMinCompAreaPx, edgeRatioThr, gripRatioThr)
    tf = false;
    if isempty(maskCoeff) || isempty(proto) || W <= 0 || H <= 0
        return;
    end

    if nargin < 9 || isempty(maskThresh)
        maskThresh = 0.50;
    end
    if nargin < 10 || isempty(maskMinArea)
        maskMinArea = 0;
    end
    if nargin < 11 || isempty(maskUseBBox)
        maskUseBBox = true;
    end
    if nargin < 13 || isempty(edgeMarginPx)
        edgeMarginPx = 2;
    end
    if nargin < 15 || isempty(maskMinAreaPx)
        maskMinAreaPx = 150;
    end
    if nargin < 16 || isempty(maskMinCompAreaPx)
        maskMinCompAreaPx = 40;
    end
    if nargin < 17 || isempty(edgeRatioThr)
        edgeRatioThr = 0.03;
    end
    if nargin < 18 || isempty(gripRatioThr)
        gripRatioThr = 0.05;
    end

    mask640 = buildMaskFromProto(maskCoeff, proto, imgsz);
    if maskUseBBox && ~isempty(bbox640)
        x1b = max(1, min(imgsz, round(bbox640(1))));
        x2b = max(1, min(imgsz, round(bbox640(3))));
        y1b = max(1, min(imgsz, round(bbox640(2))));
        y2b = max(1, min(imgsz, round(bbox640(4))));
        mask640(:,1:max(1,x1b-1)) = 0;
        mask640(:,min(imgsz,x2b+1):end) = 0;
        mask640(1:max(1,y1b-1),:) = 0;
        mask640(min(imgsz,y2b+1):end,:) = 0;
    end

    maskOrig = unletterboxMask(mask640, scale, pad, W, H);
    maskBin = maskOrig > maskThresh;
    if maskMinArea > 0
        maskBin = bwareaopen(maskBin, maskMinArea);
    end
    if ~isempty(bboxOrig)
        x1 = max(1, min(W, floor(bboxOrig(1))));
        x2 = max(1, min(W, ceil(bboxOrig(3))));
        y1 = max(1, min(H, floor(bboxOrig(2))));
        y2 = max(1, min(H, ceil(bboxOrig(4))));
        if x2 >= x1 && y2 >= y1
            maskRoi = false(H, W);
            maskRoi(y1:y2, x1:x2) = true;
            maskBin = maskBin & maskRoi;
        end
    end

    maskBin = keep_primary_mask_component(maskBin, bboxOrig, maskMinCompAreaPx);
    area = nnz(maskBin);
    if area < max(1, maskMinAreaPx)
        return;
    end

    m = max(1, round(edgeMarginPx));
    edgeBand = false(H, W);
    edgeBand(1:min(H,m), :) = true;
    edgeBand(max(1,H-m+1):H, :) = true;
    edgeBand(:, 1:min(W,m)) = true;
    edgeBand(:, max(1,W-m+1):W) = true;
    edgeFrac = nnz(maskBin & edgeBand) / area;

    gripFrac = 0;
    if ~isempty(gripperMask) && isequal(size(gripperMask,1), H) && isequal(size(gripperMask,2), W)
        gripFrac = nnz(maskBin & logical(gripperMask)) / area;
    end

    tf = (edgeFrac >= edgeRatioThr) || (gripFrac >= gripRatioThr);
end

function maskOut = keep_primary_mask_component(maskBin, bbox, minCompAreaPx)
    maskOut = logical(maskBin);
    if isempty(maskOut) || ~any(maskOut(:))
        return;
    end
    if nargin < 3 || isempty(minCompAreaPx)
        minCompAreaPx = 0;
    end
    if minCompAreaPx > 0
        maskOut = bwareaopen(maskOut, max(1, round(minCompAreaPx)));
        if ~any(maskOut(:))
            return;
        end
    end

    CC = bwconncomp(maskOut, 8);
    if CC.NumObjects <= 1
        return;
    end

    hasBBox = nargin >= 2 && ~isempty(bbox) && numel(bbox) >= 4;
    bboxMask = false(size(maskOut));
    if hasBBox
        H = size(maskOut,1);
        W = size(maskOut,2);
        x1 = max(1, min(W, floor(bbox(1))));
        x2 = max(1, min(W, ceil(bbox(3))));
        y1 = max(1, min(H, floor(bbox(2))));
        y2 = max(1, min(H, ceil(bbox(4))));
        if x2 >= x1 && y2 >= y1
            bboxMask(y1:y2, x1:x2) = true;
        else
            hasBBox = false;
        end
    end

    bestK = 1;
    bestScore = -inf;
    bestArea = -inf;
    for k = 1:CC.NumObjects
        idx = CC.PixelIdxList{k};
        area = numel(idx);
        ov = 0;
        if hasBBox
            ov = nnz(bboxMask(idx));
        end
        score = ov * 10 + area;
        if score > bestScore || (abs(score - bestScore) < 1e-9 && area > bestArea)
            bestScore = score;
            bestArea = area;
            bestK = k;
        end
    end

    keep = false(size(maskOut));
    keep(CC.PixelIdxList{bestK}) = true;
    maskOut = keep;
end










