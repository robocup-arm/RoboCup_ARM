function [detBProc, detCProc, detSProc, detPProc, detM, proto, scale, pad] = ...
    detect_all_objects_single_frame(rgb)

persistent inited sessSeg ort np imgsz confTh nmsIou ...
    maskThresh maskMinArea maskUseBBox ...
    markPartial edgeMarginPx ...
    partialUseMaskEvidence partialMaskEdgeMarginPx ...
    partialMaskMinAreaPx partialMaskMinCompAreaPx ...
    partialMaskEdgeRatioThr partialMaskGripRatioThr ...
    detVerbose

if isempty(inited)
    ort = py.importlib.import_module('onnxruntime');
    np  = py.importlib.import_module('numpy');

    thisDir = fileparts(mfilename('fullpath'));
    onnxPathSeg = string(fullfile(thisDir, '..', 'model', 'best10_seg_v3.onnx'));
    if exist(onnxPathSeg, 'file') ~= 2
        error('Seg model not found: %s', onnxPathSeg);
    end

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
    try
        sessSeg = ort.InferenceSession(char(onnxPathSeg), pyargs('providers', providersPref));
    catch ME
        warning('[detect_all_objects_single_frame] Preferred GPU providers init failed, fallback to default: %s', ME.message);
        sessSeg = ort.InferenceSession(char(onnxPathSeg));
    end

    try
        provStr = char(string(py.builtins.repr(sessSeg.get_providers())));
        fprintf('[detect_all_objects_single_frame] ORT providers = %s\n', provStr);
    catch
        fprintf('[detect_all_objects_single_frame] ORT providers query failed.\n');
    end

    imgsz   = get_env_int_local("VISION_IMGSZ", 640);
    confTh  = get_env_double_local("VISION_CONF_TH", 0.70);
    nmsIou  = get_env_double_local("VISION_NMS_IOU", 0.50);

    maskThresh  = get_env_double_local("VISION_MASK_THRESH", 0.50);
    maskMinArea = get_env_int_local("VISION_MASK_MIN_AREA", 0);
    maskUseBBox = get_env_bool_local("VISION_MASK_USE_BBOX", true);

    markPartial = get_env_bool_local("VISION_MARK_PARTIAL", true);
    edgeMarginPx = max(0, get_env_int_local("VISION_EDGE_MARGIN_PX", 4));

    partialUseMaskEvidence   = get_env_bool_local("VISION_PARTIAL_MASK_EVIDENCE", true);
    partialMaskEdgeMarginPx  = max(0, get_env_int_local("VISION_PARTIAL_MASK_EDGE_MARGIN_PX", 2));
    partialMaskMinAreaPx     = max(1, get_env_int_local("VISION_PARTIAL_MASK_MIN_AREA_PX", 150));
    partialMaskMinCompAreaPx = max(1, get_env_int_local("VISION_PARTIAL_MASK_MIN_COMP_AREA_PX", 40));
    partialMaskEdgeRatioThr  = get_env_double_local("VISION_PARTIAL_MASK_EDGE_RATIO_THR", 0.03);
    partialMaskGripRatioThr  = get_env_double_local("VISION_PARTIAL_MASK_GRIP_RATIO_THR", 0.05);
    detVerbose = get_env_bool_local("VISION_DET_VERBOSE", false);

    if detVerbose
        fprintf('[detect_all_objects_single_frame] cfg: conf=%.2f nms=%.2f maskThr=%.2f maskUseBBox=%d markPartial=%d maskEvidence=%d\n', ...
            confTh, nmsIou, maskThresh, int32(maskUseBBox), int32(markPartial), int32(partialUseMaskEvidence));
    end

    inited = true;
end

H = size(rgb,1);
W = size(rgb,2);
gripperMask = [];

[I640, scale, pad] = letterbox(rgb, imgsz);
X = im2single(I640);
X = permute(X,[3 1 2]);
X = reshape(X,[1 3 size(I640,1) size(I640,2)]);
Xnp = np.array(X);

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

detBProc = collectSegDetectionsByClass({'bottle','b'}, xywhS, scoreS, cidS, maskCoeffS, classNamesSeg, ...
    confTh, nmsIou, scale, pad, W, H, markPartial, edgeMarginPx, gripperMask, ...
    proto, imgsz, maskThresh, maskMinArea, maskUseBBox, ...
    partialUseMaskEvidence, partialMaskEdgeMarginPx, partialMaskMinAreaPx, partialMaskMinCompAreaPx, ...
    partialMaskEdgeRatioThr, partialMaskGripRatioThr);

detCProc = collectSegDetectionsByClass({'can','c'}, xywhS, scoreS, cidS, maskCoeffS, classNamesSeg, ...
    confTh, nmsIou, scale, pad, W, H, markPartial, edgeMarginPx, gripperMask, ...
    proto, imgsz, maskThresh, maskMinArea, maskUseBBox, ...
    partialUseMaskEvidence, partialMaskEdgeMarginPx, partialMaskMinAreaPx, partialMaskMinCompAreaPx, ...
    partialMaskEdgeRatioThr, partialMaskGripRatioThr);

detSProc = collectSegDetectionsByClass({'spam','s'}, xywhS, scoreS, cidS, maskCoeffS, classNamesSeg, ...
    confTh, nmsIou, scale, pad, W, H, markPartial, edgeMarginPx, gripperMask, ...
    proto, imgsz, maskThresh, maskMinArea, maskUseBBox, ...
    partialUseMaskEvidence, partialMaskEdgeMarginPx, partialMaskMinAreaPx, partialMaskMinCompAreaPx, ...
    partialMaskEdgeRatioThr, partialMaskGripRatioThr);

detM = collectSegDetectionsByClass({'marker','m'}, xywhS, scoreS, cidS, maskCoeffS, classNamesSeg, ...
    confTh, nmsIou, scale, pad, W, H, markPartial, edgeMarginPx, gripperMask, ...
    proto, imgsz, maskThresh, maskMinArea, maskUseBBox, ...
    partialUseMaskEvidence, partialMaskEdgeMarginPx, partialMaskMinAreaPx, partialMaskMinCompAreaPx, ...
    partialMaskEdgeRatioThr, partialMaskGripRatioThr);

detPProc = collectSegDetectionsByClass({'cube','p'}, xywhS, scoreS, cidS, maskCoeffS, classNamesSeg, ...
    confTh, nmsIou, scale, pad, W, H, markPartial, edgeMarginPx, gripperMask, ...
    proto, imgsz, maskThresh, maskMinArea, maskUseBBox, ...
    partialUseMaskEvidence, partialMaskEdgeMarginPx, partialMaskMinAreaPx, partialMaskMinCompAreaPx, ...
    partialMaskEdgeRatioThr, partialMaskGripRatioThr);

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


