function [pickTraj, placeTraj] = planner_core(targetPos, yawCandidates, valid)

persistent UR5e ik ikWeights qHome placeTool0Blue_M placeTool0Green_M verbose qMin qMax tableZ

if isempty(UR5e)
    % 机械臂模�?
    UR5e = loadrobot('universalUR5e', 'DataFormat', 'struct');

    % 如果你之前改过固定变换，这里先保持关�?
    % T = UR5e.Bodies{3}.Joint.JointToParentTransform;
    % UR5e.Bodies{3}.Joint.setFixedTransform(T * eul2tform([ pi/2, 0, 0], 'ZYX'));
    %
    % T = UR5e.Bodies{4}.Joint.JointToParentTransform;
    % UR5e.Bodies{4}.Joint.setFixedTransform(T * eul2tform([-pi/2, 0, 0], 'ZYX'));
    %
    % T = UR5e.Bodies{7}.Joint.JointToParentTransform;
    % UR5e.Bodies{7}.Joint.setFixedTransform(T * eul2tform([-pi/2, 0, 0], 'ZYX'));

    ik = inverseKinematics("RigidBodyTree", UR5e);
    ikWeights = [0.25 0.25 0.25 0.1 0.1 0.1];

    % 你当前定义的 home / 姿态偏�?
    % 这组姿态会作为"偏好姿�?参与打分，鼓�?elbow-up
    qHome = [-0.4582; -2.2360; 2.3159; -1.7055; -1.5777; 1.1303];


    % 关节限位（这里先保守�?±2pi�?
    qMin = [-2*pi; -2*pi; -2*pi; -2*pi; -2*pi; -2*pi];
    qMax = [ 2*pi;  2*pi;  2*pi;  2*pi;  2*pi;  2*pi];

    % 固定放置�?
    placeTool0Pos_M = [-0.4; -0.45; 0.3];

    % 桌面高度（base_link 坐标系下�?
    % !!! 如果你的桌面不是 z=0，请改这�?!!!
    tableZ = -0.15;

    verbose = get_env_bool_local("PLANNER_VERBOSE", false);
end

% Allow runtime update of home/view pose from base workspace.
try
    useSecondHome = false;
    if evalin('base', 'exist(''USER_CUBE_USE_SECOND_HOME'',''var'')') ~= 0
        useSecondHome = logical(evalin('base', 'USER_CUBE_USE_SECOND_HOME'));
    end

    if useSecondHome && evalin('base', 'exist(''USER_CUBE_SECOND_HOME'',''var'')') ~= 0
        qh = evalin('base', 'USER_CUBE_SECOND_HOME');
    elseif evalin('base', 'exist(''USER_QHOME_CURRENT'',''var'')') ~= 0
        qh = evalin('base', 'USER_QHOME_CURRENT');
    else
        qh = qHome;
    end

    if isnumeric(qh) && numel(qh) == 6 && all(isfinite(qh(:)))
        qHome = qh(:);
    end
catch
end
% 默认输出：静止，不动
pickTraj  = repmat(qHome(:), 1, 251);
placeTraj = repmat(qHome(:), 1, 351);

% 没确认目标，就保持静�?
if ~valid
    if verbose
        fprintf('[planner_core] no confirmed target, hold still.\n');
    end
    return;
end

objPos = targetPos(:);
if ~all(isfinite(objPos))
    if verbose
        fprintf('[planner_core] invalid targetPos, hold still.\n');
    end
    return;
end

if verbose
    fprintf('[planner_core] targetPos = [%.4f, %.4f, %.4f]\n', objPos(1), objPos(2), objPos(3));
end

% Cube weighing flow:
%   mode 1: place the cube on the scale
%   mode 2: place the cube into its normal classification bin
[placeTool0Pos_M, ~] = choose_place_target_pos_local(objPos, placeTool0Blue_M, placeTool0Green_M, verbose);

% ---------- yaw candidates ----------
% In the synthetic second cube pass, keep the yaw used when the cube was
% first picked/placed on the scale. This prevents wrist rotation while
% moving straight down from the scale release pose to the scale pick pose.
yawCandidatesForPlan = yawCandidates;
placeModeForYaw = get_runtime_scalar_local('USER_CUBE_PLACE_MODE', 0);
if round(placeModeForYaw) == 2
    scalePickPos = [0.799; 0.4; -0.052];
    if norm(objPos - scalePickPos) < 0.10
        cachedYaw = get_runtime_vec2_local('USER_CUBE_LATCHED_YAW', yawCandidatesForPlan(:));
        yawCandidatesForPlan = cachedYaw(:).';
        if verbose
            fprintf('[planner_core] cube second pass reuse cached yaw=[%.4f %.4f]\n', ...
                yawCandidatesForPlan(1), yawCandidatesForPlan(2));
        end
    elseif verbose
        fprintf('[planner_core] mode=2 but target is not scale pick, keep live yaw candidates.\n');
    end
end

yawList = [];
for i = 1:numel(yawCandidatesForPlan)
    if isfinite(yawCandidatesForPlan(i))
        yawList(end+1) = yawCandidatesForPlan(i); %#ok<AGROW>
    end
end
if isempty(yawList)
    yawList = 0;
end

% Deduplicate yaw candidates.
yawList = unique(round(yawList(:)' * 1e6) / 1e6);

if verbose
    fprintf('[planner_core] number of yaw candidates = %d\n', numel(yawList));
end

% ---------- key positions ----------
tool0HoverZ    = 0.30;
tool0ApproachZ = 0.14;

bestPlanCost  = inf;
bestPickTraj  = pickTraj;
bestPlaceTraj = placeTraj;

% 尝试所�?yaw
for iy = 1:numel(yawList)
    yaw = yawList(iy);

    if verbose
        fprintf('[planner_core] try yaw = %.4f rad (%.2f deg)\n', yaw, yaw*180/pi);
    end

    % tool0 蓝轴朝下
    x_tool_in_base = [cos(yaw); sin(yaw); 0];
    z_tool_in_base = [0; 0; -1];
    y_tool_in_base = cross(z_tool_in_base, x_tool_in_base);

    if norm(y_tool_in_base) < 1e-9
        continue;
    end
    y_tool_in_base = y_tool_in_base / norm(y_tool_in_base);

    Trot = eye(4);
    Trot(1:3,1:3) = [x_tool_in_base, y_tool_in_base, z_tool_in_base];

    alignTool0Pos    = objPos + [0;0;tool0HoverZ];
    approachTool0Pos = objPos + [0;0;tool0ApproachZ];

    Talign = Trot;
    Talign(1:3,4) = alignTool0Pos;

    Tapproach = Trot;
    Tapproach(1:3,4) = approachTool0Pos;

    Tplace = Trot;
    Tplace(1:3,4) = placeTool0Pos_M;

    try
        qAlign = solveBestIK(UR5e, ik, 'tool0', Talign, ...
            ikWeights, qHome, qHome, qMin, qMax, tableZ, verbose);

        qApproach = solveBestIK(UR5e, ik, 'tool0', Tapproach, ...
            ikWeights, qAlign, qHome, qMin, qMax, tableZ, verbose);

        qLift = solveBestIK(UR5e, ik, 'tool0', Talign, ...
            ikWeights, qApproach, qHome, qMin, qMax, tableZ, verbose);

        qPlace = solveBestIK(UR5e, ik, 'tool0', Tplace, ...
            ikWeights, qLift, qHome, qMin, qMax, tableZ, verbose);

    catch ME
        if verbose
            fprintf('[planner_core] yaw %.4f failed in IK: %s\n', yaw, ME.message);
        end
        continue;
    end

    % 检查关键段插值过程是否安�?
    ok1 = segmentSafe(UR5e, qHome,     qAlign,    tableZ);
    ok2 = segmentSafe(UR5e, qAlign,    qApproach, tableZ);
    ok3 = segmentSafe(UR5e, qApproach, qLift,     tableZ);
    ok4 = segmentSafe(UR5e, qLift,     qPlace,    tableZ);

    if ~(ok1 && ok2 && ok3 && ok4)
        if verbose
            fprintf('[planner_core] yaw %.4f rejected: unsafe interpolated segment.\n', yaw);
        end
        continue;
    end

    pickCand = [ ...
        interpCols(qHome,   qAlign,    120), ...
        interpCols(qAlign,  qApproach, 131) ...
    ];

    placeCand = [ ...
        interpCols(qApproach, qLift,  170), ...
        interpCols(qLift,     qPlace, 181) ...
    ];

    planCost = planScore(UR5e, qHome, qAlign, qApproach, qLift, qPlace, tableZ);

    if verbose
        fprintf('[planner_core] yaw %.4f planCost = %.6f\n', yaw, planCost);
    end

    if planCost < bestPlanCost
        bestPlanCost  = planCost;
        bestPickTraj  = pickCand;
        bestPlaceTraj = placeCand;
    end
end

if isfinite(bestPlanCost)
    pickTraj  = bestPickTraj;
    placeTraj = bestPlaceTraj;

    if verbose
        fprintf('[planner_core] selected best plan, cost = %.6f\n', bestPlanCost);
    end
else
    if verbose
        fprintf('[planner_core] no valid plan found, hold still.\n');
    end
end

end

% ========================= 核心：多候�?IK =========================
function qBest = solveBestIK(robot, ik, eeName, tform, ikWeights, qPrev, qBias, qMin, qMax, tableZ, verbose)

seedSet = generateSeedSet(qPrev, qBias);

bestCost = inf;
qBest = [];

for k = 1:size(seedSet,2)
    qSeed = seedSet(:,k);
    cfgSeed = vec2cfg(homeConfiguration(robot), qSeed.');

    try
        [cfgRaw, solInfo] = ik(eeName, tform, ikWeights, cfgSeed);
    catch
        continue;
    end

    q = cfg2vec(cfgRaw).';
    q = wrapToNearest2Pi(q, qPrev(:).');
    q = q(:);

    % 限位检�?
    if any(q < qMin) || any(q > qMax)
        continue;
    end

    cfgQ = vec2cfg(homeConfiguration(robot), q.');
    Tfk = getTransform(robot, cfgQ, eeName);
    posErr = norm(Tfk(1:3,4) - tform(1:3,4));
    rotErr = norm(Tfk(1:3,1:3) - tform(1:3,1:3), 'fro');

    % 姿态自身安全�?
    [isSafe, clearanceCost] = postureSafety(robot, q, tableZ);
    if ~isSafe
        continue;
    end

    % 关节偏好代价
    prefCost = jointPreferenceCost(q);

    % 连续�?/ 靠近偏好姿�?
    motionCost = norm(q - qPrev(:));
    biasCost   = norm(q - qBias(:));

    % 末端误差 + 姿态偏�?+ 安全距离
    c = 20.0*posErr ...
      + 2.0*rotErr ...
      + 1.5*motionCost ...
      + 0.8*biasCost ...
      + 1.0*prefCost ...
      + 4.0*clearanceCost;

    if isstruct(solInfo) && isfield(solInfo, 'PoseErrorNorm')
        c = c + 10.0 * solInfo.PoseErrorNorm;
    end

    if c < bestCost
        bestCost = c;
        qBest = q;
    end
end

if isempty(qBest)
    if verbose
        fprintf('[solveBestIK] no valid solution found.\n');
    end
    error('solveBestIK:NoValidSolution', 'No valid IK solution found.');
end

end

% ========================= seed 集合 =========================
function seedSet = generateSeedSet(qPrev, qBias)

qPrev = qPrev(:);
qBias = qBias(:);

seedSet = [ ...
    qPrev, ...
    qBias, ...
    qPrev + [0;  0.25; -0.35; 0; 0; 0], ...
    qPrev + [0; -0.25;  0.35; 0; 0; 0], ...
    qBias + [0;  0.35; -0.50; 0; 0; 0], ...
    qBias + [0; -0.35;  0.50; 0; 0; 0], ...
    qPrev + [0;  0.60; -0.80; 0; 0; 0], ...
    qPrev + [0; -0.60;  0.80; 0; 0; 0], ...
    qPrev + [0;  0.15; -0.20; 0; 0;  pi], ...
    qPrev + [0; -0.15;  0.20; 0; 0; -pi] ...
];

end

% ========================= 单个姿态安全�?=========================
function [isSafe, cost] = postureSafety(robot, q, tableZ)

cfg = vec2cfg(homeConfiguration(robot), q.');

% 关键 link
Telbow = getTransform(robot, cfg, 'forearm_link');
Tw1    = getTransform(robot, cfg, 'wrist_1_link');
Tw2    = getTransform(robot, cfg, 'wrist_2_link');
Tw3    = getTransform(robot, cfg, 'wrist_3_link');
Ttool  = getTransform(robot, cfg, 'tool0');

zElbow = Telbow(3,4);
zW1    = Tw1(3,4);
zW2    = Tw2(3,4);
zW3    = Tw3(3,4);
zTool  = Ttool(3,4);

% 安全高度阈�?
minElbow = tableZ + 0.18;
minW1    = tableZ + 0.12;
minW2    = tableZ + 0.10;
minW3    = tableZ + 0.08;
minTool  = tableZ + 0.03;

isSafe = (zElbow > minElbow) && ...
         (zW1    > minW1)    && ...
         (zW2    > minW2)    && ...
         (zW3    > minW3)    && ...
         (zTool  > minTool);

cost = 0;
cost = cost + 2.0 * max(0, minElbow - zElbow)^2;
cost = cost + 1.5 * max(0, minW1    - zW1)^2;
cost = cost + 1.2 * max(0, minW2    - zW2)^2;
cost = cost + 1.0 * max(0, minW3    - zW3)^2;
cost = cost + 0.5 * max(0, minTool  - zTool)^2;

end

% ========================= 关节姿态偏�?=========================
function c = jointPreferenceCost(q)

q2 = q(2);
q3 = q(3);
q4 = q(4);

c = 0;

% 惩罚�?关节过度"向下�?
if q3 < 0.30
    c = c + 6.0 * (0.30 - q3)^2;
end

% 惩罚 q2+q3 让肘整体过低
if (q2 + q3) < -0.80
    c = c + 5.0 * (-0.80 - (q2 + q3))^2;
end

% wrist_1 过度折叠惩罚
if abs(q4) > 2.80
    c = c + 2.0 * (abs(q4) - 2.80)^2;
end

end

% ========================= 轨迹段中间检�?=========================
function ok = segmentSafe(robot, qA, qB, tableZ)

ok = true;
N = 31;

for i = 1:N
    s = (i-1)/(N-1);
    q = (1-s)*qA(:) + s*qB(:);

    [isSafe, ~] = postureSafety(robot, q, tableZ);
    if ~isSafe
        ok = false;
        return;
    end
end

end

% ========================= 整条规划打分 =========================
function c = planScore(robot, qHome, qAlign, qApproach, qLift, qPlace, tableZ)

c = 0;

% 关节运动平滑 / 连续
c = c + 1.0 * norm(qAlign    - qHome);
c = c + 1.0 * norm(qApproach - qAlign);
c = c + 0.8 * norm(qLift     - qApproach);
c = c + 0.8 * norm(qPlace    - qLift);

% 姿态偏�?
c = c + 1.0 * jointPreferenceCost(qAlign);
c = c + 1.2 * jointPreferenceCost(qApproach);
c = c + 0.8 * jointPreferenceCost(qLift);
c = c + 0.4 * jointPreferenceCost(qPlace);

% 安全裕量
[~, c1] = postureSafety(robot, qAlign,    tableZ);
[~, c2] = postureSafety(robot, qApproach, tableZ);
[~, c3] = postureSafety(robot, qLift,     tableZ);
[~, c4] = postureSafety(robot, qPlace,    tableZ);

c = c + 6.0*(c1 + c2 + c3 + c4);

end

% ========================= 线性插�?=========================
function traj = interpCols(qA, qB, n)
qA = qA(:);
qB = qB(:);

traj = zeros(length(qA), n);
for i = 1:n
    alpha = (i-1)/(n-1);
    traj(:,i) = (1-alpha)*qA + alpha*qB;
end
end

% ========================= cfg -> vec =========================
function q = cfg2vec(cfg)
q = zeros(1, numel(cfg));
for i = 1:numel(cfg)
    q(i) = cfg(i).JointPosition;
end
end

% ========================= vec -> cfg =========================
function cfg = vec2cfg(templateCfg, q)
cfg = templateCfg;
for i = 1:numel(cfg)
    cfg(i).JointPosition = q(i);
end
end

% ========================= wrap 到最�?2pi 分支 =========================
function qAdj = wrapToNearest2Pi(q, qRef)
qAdj = q;
for i = 1:numel(q)
    k = round((qRef(i) - q(i)) / (2*pi));
    qAdj(i) = q(i) + 2*pi*k;
end
end

% ========================= 环境变量读取 =========================


function [pPlace, targetName] = choose_place_target_pos_local(objPos, pBlueDefault, pGreenDefault, verbose)
placeMode = get_runtime_scalar_local('USER_CUBE_PLACE_MODE', 0);
[clsId0, colorId0, ~] = infer_target_meta_local(objPos);
if clsId0 == 4 && round(placeMode) ~= 2
    assignin('base', 'USER_CUBE_ACTIVE', true);
    assignin('base', 'USER_CUBE_PLACE_MODE', 1);
    assignin('base', 'USER_CUBE_LATCHED_CLASSID', double(clsId0));
    assignin('base', 'USER_CUBE_LATCHED_COLORID', double(colorId0));
    placeMode = 1;
end
if round(placeMode) == 1
    pPlace = get_runtime_vec3_local('USER_SCALE_PLACE_POS', [0.799; 0.4; 0.3]);
    targetName = 'scale';

    if verbose
        fprintf('[planner_core] place target=%s pos=[%.4f %.4f %.4f]\\n', ...
            targetName, pPlace(1), pPlace(2), pPlace(3));
    end
    return;
end

[pPlace, targetName] = choose_place_bin_pos_local(objPos, pBlueDefault, pGreenDefault, verbose);
end

function [pPlace, binName] = choose_place_bin_pos_local(objPos, pBlueDefault, pGreenDefault, verbose)
% Allow runtime override from base workspace if needed.
pBlue = get_runtime_vec3_local('USER_BIN_BLUE_POS', pBlueDefault(:));
pGreen = get_runtime_vec3_local('USER_BIN_GREEN_POS', pGreenDefault(:));

[clsId, colorId, matchDist] = infer_target_meta_local(objPos);
binName = decide_bin_name_local(clsId, colorId);

if strcmp(binName, 'green')
    pPlace = pGreen;
else
    pPlace = pBlue;
    binName = 'blue';
end

if verbose
    fprintf('[planner_core] place bin=%s (cls=%d color=%d matchDist=%.4f) pos=[%.4f %.4f %.4f]\n', ...
        binName, int32(clsId), int32(colorId), matchDist, pPlace(1), pPlace(2), pPlace(3));
end
end

function [clsId, colorId, bestDist] = infer_target_meta_local(objPos)
clsId = 0;
colorId = 0;
bestDist = inf;

% During the second cube pass the pick position is the scale, so it may not
% match the original vision detection. Reuse the cached cube metadata.
try
    placeMode = double(evalin('base', 'USER_CUBE_PLACE_MODE'));
    if round(placeMode) == 2
        cachedCls = double(evalin('base', 'USER_CUBE_LATCHED_CLASSID'));
        cachedColor = double(evalin('base', 'USER_CUBE_LATCHED_COLORID'));
        if isfinite(cachedCls) && cachedCls > 0
            clsId = round(cachedCls);
            if isfinite(cachedColor)
                colorId = round(cachedColor);
            end
            bestDist = 0;
            return;
        end
    end
catch
end

try
    numDet = double(evalin('base', 'VISION_LAST_NUMDET'));
    targetPosList = double(evalin('base', 'VISION_LAST_TARGETPOS'));
    classIdList = double(evalin('base', 'VISION_LAST_CLASSID'));
    colorIdList = double(evalin('base', 'VISION_LAST_COLORID'));

    if isfinite(numDet) && numDet >= 1 && isnumeric(targetPosList) && size(targetPosList,1) >= 3
        N = min([int32(round(numDet)), int32(size(targetPosList,2)), int32(numel(classIdList)), int32(numel(colorIdList))]);
        for i = 1:N
            p = targetPosList(:, i);
            if ~all(isfinite(p))
                continue;
            end
            d = norm(p(:) - objPos(:));
            if d < bestDist
                bestDist = d;
                clsId = round(classIdList(i));
                colorId = round(colorIdList(i));
            end
        end
    end
catch
end

% fallback: use selected index
if clsId <= 0
    try
        sid = round(double(evalin('base', 'USER_SELECTED_ID')));
        classIdList = double(evalin('base', 'VISION_LAST_CLASSID'));
        colorIdList = double(evalin('base', 'VISION_LAST_COLORID'));
        if sid >= 1 && sid <= numel(classIdList)
            clsId = round(classIdList(sid));
        end
        if sid >= 1 && sid <= numel(colorIdList)
            colorId = round(colorIdList(sid));
        end
    catch
    end
end
end

function binName = decide_bin_name_local(clsId, colorId)
% class id mapping used in this project:
% 1 bottle, 2 can, 3 marker, 4 cube, 5 spam
switch clsId
    case 2 % can
        binName = 'green';
    case 5 % spam
        binName = 'green';
    case 1 % bottle
        binName = 'blue';
    case 3 % marker
        binName = 'blue';
    case 4 % cube
        % color id mapping: 1 red, 2 yellow, 3 green, 4 blue, 5 purple
        if any(colorId == [3, 5])
            binName = 'green';
        elseif any(colorId == [4, 1])
            binName = 'blue';
        else
            % unknown cube color defaults to blue
            binName = 'blue';
        end
    otherwise
        % unknown class defaults to blue
        binName = 'blue';
end
end
function v = get_runtime_vec3_local(varName, defaultVal)
v = double(defaultVal(:));
try
    t = evalin('base', varName);
    t = double(reshape(t, [], 1));
    if numel(t) == 3 && all(isfinite(t))
        v = t;
    end
catch
end
end

function v = get_runtime_vec2_local(varName, defaultVal)
v = double(defaultVal(:));
if numel(v) < 2
    v = [0; 0];
else
    v = v(1:2);
end
try
    t = evalin('base', varName);
    t = double(reshape(t, [], 1));
    if numel(t) >= 2 && all(isfinite(t(1:2)))
        v = t(1:2);
    end
catch
end
end
function v = get_runtime_scalar_local(varName, defaultVal)
v = double(defaultVal);
try
    t = double(evalin('base', varName));
    if isfinite(t)
        v = t;
    end
catch
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

