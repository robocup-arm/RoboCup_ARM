% ===== Fixed runtime hyper-parameters (always applied) =====
ENV_CFG = {
    "VISION_VERBOSE", "0";
    "PLANNER_VERBOSE", "0";
    "VISION_PREVIEW_VERBOSE", "0";
    "VISION_SORT_VERBOSE", "0";
    "VISION_RECOG_STRIDE", "1";
    "VISION_PREVIEW_STRIDE", "1";
    "VISION_PREVIEW_ENABLE", "1";
    "VISION_GPU_MATH", "0";
    "VISION_DROP_PARTIAL", "1";
    "VISION_ASYNC_ENABLE", "0";
    "VISION_ASYNC_PERIOD_SEC", "0.08";
    "VISION_ASYNC_TIMEOUT_SEC", "1.50";
    "VISION_EDGE_MARGIN_PX", "4";
    "VISION_CAM_FRAME_FIX", "swap_xy_negx";
};
for i = 1:size(ENV_CFG, 1)
    setenv(ENV_CFG{i,1}, ENV_CFG{i,2});
end

DEFAULT_QHOME = [-0.4582; -2.2360; 2.3159; -1.7055; -1.5777; 1.1303];

BASE_CFG = {
    "USER_SELECTED_ID",            0;
    "USER_PROCEED",                false;
    "USER_ABORT",                  false;
    "USER_AUTO_RUN",               false;
    "USER_AUTO_NEED_RESET",        false;
    "USER_AUTO_COOLDOWN_FRAMES",   120;
    "USER_GRAB_TIMEOUT_FRAMES",    180;
    "USER_AUTO_SETTLE_FRAMES",     30;
    "USER_AUTO_STABLE_FRAMES",     3;
    "USER_AUTO_STABLE_POS_THR",    0.015;
    "USER_RESET_TOKEN",            0;
    "USER_CAN_PICK",               false;
    "USER_LAST_CYCLE_RESULT",      int32(0);
    "USER_VIEW_SWITCH_ENABLED",    true;
    "USER_VIEW_EMPTY_FRAMES",      80;
    "USER_VIEW_IDX",               2;
    "USER_VIEW_COUNT",             1;
    "USER_QHOME_CURRENT",          DEFAULT_QHOME;
    % Bin place targets in base frame (tool0). Green bin is mirrored Y.
    "USER_BIN_BLUE_POS",           [-0.50;  0.30; 0.3];
    "USER_BIN_GREEN_POS",          [-0.40; -0.45; 0.3];
    "USER_SCALE_PLACE_POS",        [0.799; 0.4; 0.3];
    "USER_CUBE_SCALE_PICK_Z",      -0.052;
    "USER_CUBE_ACTIVE",            false;
    "USER_CUBE_SECOND_PICK_PENDING", false;
    "USER_CUBE_PLACE_MODE",        0;
    "USER_CUBE_WAIT_FRESH_VISION", false;
    "USER_CUBE_EDGE_GUARD_DEBUG", false;
    "USER_CUBE_EDGE_GUARD_DEBUG_FAIL", false;
    "USER_CUBE_EDGE_MARGIN_TOL",  0.005;
    "USER_CUBE_USE_SECOND_HOME",   false;
    "USER_CUBE_SECOND_HOME",       DEFAULT_QHOME;
    "USER_CUBE_LATCHED_CLASSID",   0;
    "USER_CUBE_LATCHED_COLORID",   0;
    "VISION_LAST_NUMDET",          0;
};
for i = 1:size(BASE_CFG, 1)
    assignin("base", BASE_CFG{i,1}, BASE_CFG{i,2});
end

clear vision_core_multi;
clear vision_async_worker;

thisDir = fileparts(mfilename("fullpath"));
projectDir = fileparts(thisDir);

if ~strcmpi(pwd, projectDir)
    cd(projectDir);
end
addpath(projectDir);
addpath(fullfile(projectDir, "scripts"));
addpath(fullfile(projectDir, "scripts", "vision_runtime"));
addpath(fullfile(projectDir, "modelData"));
addpath(fullfile(projectDir, "Objects"));

try
    pyenv;
catch
end

load(fullfile(projectDir, "modelData", "arm_data.mat"));
load(fullfile(projectDir, "modelData", "ur5e_gripper.mat"));

modelName = "RoboCup_ARM";
if bdIsLoaded(modelName)
    close_system(modelName, 0);
end

modelPath = fullfile(projectDir, "RoboCup_ARM.slx");
if usejava("desktop")
    open_system(modelPath);
else
    load_system(modelPath);
end

% Always use in-project pose file for reproducible behavior.
poseRecordsFile = fullfile(projectDir, "modelData", "pose_records.xlsx");
init_view_pose_records(poseRecordsFile);
tune_model_startup(modelName);

function tune_model_startup(modelName)
if bdIsLoaded(modelName) == 0
    load_system(modelName);
end

% Ensure Sim3D project executable follows current MATLAB install root.
blk = modelName + "/Simulation 3D Scene Configuration";
sim3dExe = fullfile(matlabroot, "toolbox", "shared", "sim3d_projects", ...
    "automotive_project_windows", "UE", "WindowsNoEditor", "VehicleSimulation.exe");

pathChanged = false;
if exist(sim3dExe, "file") == 2
    try
        curExe = string(get_param(blk, "ProjectName"));
        if curExe ~= string(sim3dExe)
            set_param(blk, "ProjectName", sim3dExe);
            pathChanged = true;
        end
    catch ME
        warning(ME.identifier, "%s", "[arm_startup] Failed to update Sim3D path: " + string(ME.message));
    end
else
    warning("[arm_startup] Sim3D executable not found: %s", sim3dExe);
end

% Reduce memory/IO pressure by disabling default logging.
try
    set_param(modelName, "SimulationMode", "accelerator");
    set_param(modelName, "SignalLogging", "off");
    set_param(modelName, "SaveOutput", "off");
    set_param(modelName, "SaveTime", "off");
    set_param(modelName, "SaveState", "off");
catch ME
    warning(ME.identifier, "%s", "[arm_startup] Failed to set logging options: " + string(ME.message));
end

if pathChanged
    try
        save_system(modelName);
    catch ME
        warning(ME.identifier, "%s", "[arm_startup] Updated Sim3D path in memory but failed to save model: " + string(ME.message));
    end
end
end

function init_view_pose_records(poseFile)
disp('=== init_view_pose_records called ===');
disp(['poseFile = ', poseFile]);

defaultQ = [-0.4582; -2.2360; 2.3159; -1.7055; -1.5777; 1.1303];
poses = defaultQ;

disp('defaultQ = ');
disp(defaultQ);
disp('poses initialized to defaultQ');
disp(poses);

if exist(poseFile, "file") == 2
    try
        loaded = false;

        % Preferred format: columns named q1..q6
        T = readtable(poseFile, "VariableNamingRule", "preserve");
        names = string(T.Properties.VariableNames);

        disp('readtable variable names = ');
        disp(names);
        
        req = ["q1","q2","q3","q4","q5","q6"];
        disp('required columns = ');
        disp(req);
        disp('ismember result = ');
        disp(ismember(req, names));
        if all(ismember(req, names))
            disp('>>> q1..q6 header path matched');
            Q = [T.("q1"), T.("q2"), T.("q3"), T.("q4"), T.("q5"), T.("q6")];
            rowGood = all(isfinite(Q), 2);
            Q = Q(rowGood, :);
            disp('Q before transpose = ');
            disp(Q);
            disp('size(Q) = ');
            disp(size(Q));
            if ~isempty(Q)
                poses = Q.'; % 6xN
                loaded = true;
                disp('>>> poses overwritten from table Q''');
                disp('poses = ');
                disp(poses);
                disp('size(poses) = ');
                disp(size(poses));
            end
        end

        % Fallback for pure numeric sheets without headers.
        if ~loaded
            disp('>>> header path not loaded, entering numeric fallback');
            M = readmatrix(poseFile);
            disp('M = ');
            disp(M);
            disp('size(M) = ');
            disp(size(M));
            if isnumeric(M) && ~isempty(M)
                if size(M,2) >= 9
                    R = M(:,4:9);  % timestamp/tag/teleop + q1..q6
                    rowGood = all(isfinite(R), 2);
                    R = R(rowGood, :);
                
                    disp('R from numeric fallback = ');
                    disp(R);
                    disp('size(R) = ');
                    disp(size(R));
                
                    if ~isempty(R)
                        poses = R.'; % 6xN
                        loaded = true;
                        disp('>>> poses overwritten from numeric fallback R''');
                        disp('poses = ');
                        disp(poses);
                        disp('size(poses) = ');
                        disp(size(poses));
                    end
                end
            end
        end
    catch ME
        warning(ME.identifier, "%s", "[arm_startup] Failed to read pose_records.xlsx: " + string(ME.message));
    end
end

if isempty(poses) || size(poses,1) ~= 6
    poses = defaultQ;
end

n = size(poses,2);
if n < 1
    poses = defaultQ;
    n = 1;
end

idx = 1;
try
    idx0 = evalin("base", "double(USER_VIEW_IDX)");
    if isfinite(idx0)
        idx = round(idx0);
    end
catch
end
if idx < 1 || idx > n
    idx = 1;
end

disp('=== final result before assignin ===');
disp('poses = ');
disp(poses);
disp('size(poses) = ');
disp(size(poses));
disp('n = ');
disp(n);
disp('idx = ');
disp(idx);
disp('poses(:,idx) = ');
disp(poses(:,idx));

assignin("base", "USER_VIEW_POSES", poses);
assignin("base", "USER_VIEW_COUNT", double(n));
assignin("base", "USER_VIEW_IDX", double(idx));
assignin("base", "USER_QHOME_CURRENT", poses(:,idx));
assignin("base", "USER_VISION_ENABLE", true);
assignin("base", "USER_IGNORE_TARGETS", zeros(3,20));
assignin("base", "USER_IGNORE_TOKEN", 0);
assignin("base", "USER_GRASP_FAIL_POSITIONS", zeros(3,20));
assignin("base", "USER_GRASP_FAIL_COUNTS", zeros(1,20));
assignin("base", "USER_GRASP_MAX_FAILS", 1);
assignin("base", "USER_IGNORE_MATCH_THR", 0.04);


disp('=== init_view_pose_records finished ===');
end
