function [targetPos, yawCandidates, valid] = vision_core(Image, Depth, CameraTform)

persistent inited lockedTarget lockedYaw lockedValid
if isempty(inited)
    thisFile = mfilename('fullpath');
    thisDir = fileparts(thisFile);

    addpath(thisDir);
    geomDir = fullfile(thisDir, 'vision_geom');
    modelDir = fullfile(thisDir, 'model');
    if isfolder(geomDir)
        addpath(geomDir);
    end
    if isfolder(modelDir)
        addpath(modelDir);
    end

    inited = true;
    lockedTarget = zeros(3,1);
    lockedYaw = [0, pi/2];
    lockedValid = false;
end

targetPos = zeros(3,1);
yawCandidates = zeros(1,2);
valid = false;

if isempty(Image) || isempty(Depth) || isempty(CameraTform)
    fprintf('[vision_core] empty input.\n');
    return;
end

rgb = Image;
if ~isa(rgb, 'uint8')
    rgb = uint8(rgb);
end

depth = double(Depth);
if isa(Depth,'uint16')
    depth = depth / 1000.0;
end

T = double(CameraTform);
if ~isequal(size(T), [4 4])
    fprintf('[vision_core] CameraTform size invalid: %s\n', mat2str(size(T)));
    return;
end

% -------------------------------------------------
% 如果已经锁定，就直接返回锁定目标，不再每帧重新选
% -------------------------------------------------
if lockedValid
    targetPos = lockedTarget;
    yawCandidates = lockedYaw;
    valid = true;
    fprintf('[vision_core] using locked cube target = [%.4f, %.4f, %.4f]\n', ...
        targetPos(1), targetPos(2), targetPos(3));
    return;
end

% -------------------------------------------------
% 还没锁定时，跑检测
% -------------------------------------------------
detAll = runCubeBboxOnnx(rgb);
fprintf('[vision_core] num dets total = %d\n', numel(detAll));

if isempty(detAll)
    fprintf('[vision_core] no detections.\n');
    return;
end

% -------------------------------------------------
% 只保留 cube 类别
% 这里先按你之前旧代码的设定：cubeClassId = 4
% 如果后面发现类别映射不对，再改这个数
% -------------------------------------------------
cubeClassId = 4;
keep = false(1, numel(detAll));
for i = 1:numel(detAll)
    keep(i) = (detAll(i).class_id == cubeClassId);
end
detCube = detAll(keep);

fprintf('[vision_core] num cube dets = %d\n', numel(detCube));

if isempty(detCube)
    fprintf('[vision_core] no cube detections.\n');
    return;
end

% 调试打印 cube 框
nShow = min(numel(detCube), 3);
for i = 1:nShow
    fprintf('[vision_core] cube det(%d): bbox=[%.1f %.1f %.1f %.1f], score=%.3f, partial=%d\n', ...
        i, ...
        detCube(i).bbox(1), detCube(i).bbox(2), detCube(i).bbox(3), detCube(i).bbox(4), ...
        detCube(i).score, detCube(i).partial);
end

% -------------------------------------------------
% 从 cube 里选分数最高的一个
% -------------------------------------------------
scores = [detCube.score];
[~, idx] = max(scores);
det = detCube(idx);

bbox = det.bbox;

H = size(depth,1);
W = size(depth,2);

x1 = max(1, min(W, round(bbox(1))));
y1 = max(1, min(H, round(bbox(2))));
x2 = max(1, min(W, round(bbox(3))));
y2 = max(1, min(H, round(bbox(4))));

if x2 <= x1 || y2 <= y1
    fprintf('[vision_core] invalid cube bbox after clamp.\n');
    return;
end

fprintf('[vision_core] selected cube bbox = [%d %d %d %d]\n', x1, y1, x2, y2);

% -------------------------------------------------
% 用 bbox 中心附近的稳健深度
% -------------------------------------------------
uc = round((x1 + x2) / 2);
vc = round((y1 + y2) / 2);

halfWin = 3;
uu1 = max(1, uc - halfWin);
uu2 = min(W, uc + halfWin);
vv1 = max(1, vc - halfWin);
vv2 = min(H, vc + halfWin);

patch = depth(vv1:vv2, uu1:uu2);
patchValid = patch(isfinite(patch) & patch > 0.05 & patch < 5.0);

if isempty(patchValid)
    patch2 = depth(y1:y2, x1:x2);
    patch2Valid = patch2(isfinite(patch2) & patch2 > 0.05 & patch2 < 5.0);

    if isempty(patch2Valid)
        fprintf('[vision_core] no valid depth in cube bbox.\n');
        return;
    end

    z = median(patch2Valid(:));
    fprintf('[vision_core] cube depth from bbox median = %.4f m\n', z);
else
    z = median(patchValid(:));
    fprintf('[vision_core] cube depth from center patch median = %.4f m\n', z);
end

% -------------------------------------------------
% 固定相机内参（后面可替换成真实 K）
% -------------------------------------------------
fx = 1109;
fy = 1109;
cx = 640;
cy = 360;

x_c = (uc - cx) * z / fx;
y_c = (vc - cy) * z / fy;
p_c = [x_c; y_c; z; 1];

fprintf('[vision_core] cube camera point = [%.4f, %.4f, %.4f]\n', ...
    p_c(1), p_c(2), p_c(3));

% -------------------------------------------------
% camera -> base/world
% 约定 CameraTform 是 base<-camera
% -------------------------------------------------
p_b = T * p_c;
targetPos = p_b(1:3);

fprintf('[vision_core] locked cube targetPos = [%.4f, %.4f, %.4f]\n', ...
    targetPos(1), targetPos(2), targetPos(3));

% 先给固定 yaw 候选
yawCandidates = [0, pi/2];

valid = true;

% -------------------------------------------------
% 一旦识别到一个 cube，就锁定
% -------------------------------------------------
lockedTarget = targetPos;
lockedYaw = yawCandidates;
lockedValid = true;

fprintf('[vision_core] cube target locked.\n');

end
