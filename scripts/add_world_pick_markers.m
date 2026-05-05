function add_world_pick_markers(modelPath)
%ADD_WORLD_PICK_MARKERS Add two debug grasp markers in Simulation 3D world.
% This script only edits top-level blocks and does not modify Robot Subsystem.

if nargin < 1 || strlength(string(modelPath)) == 0
    thisDir = fileparts(mfilename('fullpath'));
    modelPath = fullfile(thisDir, '..', 'RoboCup_ARM.slx');
end

modelPath = char(modelPath);
if exist(modelPath, 'file') ~= 2
    error('Model file not found: %s', modelPath);
end

[modelDir, modelName] = fileparts(modelPath);
if ~bdIsLoaded(modelName)
    load_system(modelPath);
end
mdl = modelName;

% Keep current working folder stable for relative project assets.
if ~strcmpi(pwd, modelDir)
    cd(modelDir);
end

srcActorBlk = [mdl '/camera subsystem/Simulation 3D Actor'];
if ~local_block_exists(srcActorBlk)
    error('Template block not found: %s', srcActorBlk);
end

poseBlk = [mdl '/Debug Marker Pose'];
m1Blk = [mdl '/Debug Grasp Marker 1'];
m2Blk = [mdl '/Debug Grasp Marker 2'];

if ~local_block_exists(poseBlk)
    add_block('simulink/User-Defined Functions/MATLAB Function', poseBlk, ...
        'Position', [970 500 1160 620]);
end

local_set_mf_script(poseBlk, local_pose_script_text());

if ~local_block_exists(m1Blk)
    add_block(srcActorBlk, m1Blk, ...
        'MakeNameUnique', 'off', ...
        'Position', [1210 470 1450 590]);
end

if ~local_block_exists(m2Blk)
    add_block(srcActorBlk, m2Blk, ...
        'MakeNameUnique', 'off', ...
        'Position', [1210 620 1450 740]);
end

local_config_marker_actor(m1Blk, 'debugPick1', [1.0 0.2 0.2]);
local_config_marker_actor(m2Blk, 'debugPick2', [0.2 1.0 1.0]);

% Branch from existing Generate Robot Config2 outputs.
local_add_line_if_missing(mdl, 'Generate Robot Config2/1', 'Debug Marker Pose/1');
local_add_line_if_missing(mdl, 'Generate Robot Config2/7', 'Debug Marker Pose/2');

% Pose outputs to marker actors.
local_add_line_if_missing(mdl, 'Debug Marker Pose/1', 'Debug Grasp Marker 1/1');
local_add_line_if_missing(mdl, 'Debug Marker Pose/2', 'Debug Grasp Marker 2/1');
local_add_line_if_missing(mdl, 'Debug Marker Pose/3', 'Debug Grasp Marker 1/2');
local_add_line_if_missing(mdl, 'Debug Marker Pose/3', 'Debug Grasp Marker 2/2');

set_param(mdl, 'Dirty', 'on');
save_system(mdl);

fprintf('[add_world_pick_markers] Added/updated marker blocks in model: %s\n', mdl);
fprintf('  - Red sphere  : Debug Grasp Marker 1 (targetPosList(:,1))\n');
fprintf('  - Cyan sphere : Debug Grasp Marker 2 (targetPosList(:,2))\n');
end

function tf = local_block_exists(path)
h = getSimulinkBlockHandle(path);
tf = h ~= -1;
end

function txt = local_pose_script_text()
txt = [ ...
"function [p1, p2, r] = fcn(targetPosList, numDet)" newline ...
"% targetPosList: 3x20, numDet: scalar" newline ...
"% p1/p2 are marker translations in Robo1(base) frame." newline ...
"p1 = [0 0 -2];" newline ...
"p2 = [0 0 -2];" newline ...
"r  = [0 0 0];" newline ...
"" newline ...
"n = int32(numDet);" newline ...
"if n >= 1" newline ...
"    v1 = double(targetPosList(:,1));" newline ...
"    p1 = reshape(v1, 1, 3);" newline ...
"end" newline ...
"if n >= 2" newline ...
"    v2 = double(targetPosList(:,2));" newline ...
"    p2 = reshape(v2, 1, 3);" newline ...
"end" newline ...
"end" ...
];
txt = char(txt);
end

function local_config_marker_actor(blk, actorName, colorRGB)
inputsText = sprintf('%s.Translation\n%s.Rotation', actorName, actorName);
outputsText = inputsText;

initScript = sprintf([ ...
    'Actor.createShape(''sphere'', [0.018]);\n' ...
    'Actor.Mobility = sim3d.utils.MobilityTypes.Movable;\n' ...
    'Actor.Color = [%.4f %.4f %.4f];\n' ...
    'Actor.Translation = [0 0 -2];\n' ...
    'Actor.Rotation = [0 0 0];\n' ...
    'Actor.ConstantAttributes = false;\n' ...
    'Actor.Physics = false;\n' ...
    'Actor.Collisions = false;\n' ...
    'Actor.Gravity = false;\n' ...
    'Actor.Transparency = 0.15;\n' ...
    'Actor.Shininess = 0.2;'], colorRGB(1), colorRGB(2), colorRGB(3));

set_param(blk, ...
    'ActorName', actorName, ...
    'ParentName', 'Robo1', ...
    'Operation', 'Create at setup', ...
    'SourceFile', '', ...
    'SampleTime', '-1', ...
    'Translation', '[0 0 -2]', ...
    'Rotation', '[0 0 0]', ...
    'Scale', '[1 1 1]', ...
    'InputsText', inputsText, ...
    'OutputsText', outputsText, ...
    'EventsText', '', ...
    'InitScriptText', initScript);
end

function local_add_line_if_missing(sys, src, dst)
existing = get_param(sys, 'Lines');
for i = 1:numel(existing)
    ln = existing(i);
    try
        srcBlk = getfullname(ln.SrcBlockHandle);
    catch
        srcBlk = '';
    end
    if isempty(srcBlk)
        continue;
    end
    try
        dstBlks = getfullname(ln.DstBlockHandle);
    catch
        dstBlks = {};
    end
    if ischar(dstBlks) || isstring(dstBlks)
        dstBlks = {char(dstBlks)};
    end
    if isempty(dstBlks)
        continue;
    end

    srcParts = split(src, '/');
    dstParts = split(dst, '/');
    srcBlkName = char(srcParts(1));
    dstBlkName = char(dstParts(1));
    srcPort = str2double(srcParts(2));
    dstPort = str2double(dstParts(2));

    srcFull = [sys '/' srcBlkName];
    dstFull = [sys '/' dstBlkName];

    if strcmp(srcBlk, srcFull) && ln.SrcPort == (srcPort-1)
        for k = 1:numel(dstBlks)
            if strcmp(dstBlks{k}, dstFull) && ln.DstPort(k) == (dstPort-1)
                return;
            end
        end
    end
end

add_line(sys, src, dst, 'autorouting', 'on');
end

function local_set_mf_script(mfBlk, scriptText)
rt = sfroot;
charts = rt.find('-isa', 'Stateflow.EMChart', 'Path', mfBlk);
if isempty(charts)
    error('Could not find MATLAB Function chart at path: %s', mfBlk);
end
charts(1).Script = scriptText;
end
