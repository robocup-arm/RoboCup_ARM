function [targetPosList, yawList, bboxList, classIdList, scoreList, centerList, numDet] = ...
    vision(Image, Depth, CameraTform)
%#codegen
coder.extrinsic('vision_core_multi');
coder.extrinsic('assignin');

targetPosList = zeros(3,20);
yawList       = zeros(2,20);
bboxList      = zeros(4,20);
classIdList   = zeros(1,20);
scoreList     = zeros(1,20);
centerList    = zeros(2,20);
numDet        = 0;

[targetPosList, yawList, bboxList, classIdList, scoreList, centerList, numDet] = ...
    vision_core_multi(Image, Depth, CameraTform);

% Publish latest detection count for UserCommand auto-loop gate.
assignin('base', 'VISION_LAST_NUMDET', double(numDet));
assignin('base', 'VISION_LAST_TARGETPOS', double(targetPosList));
assignin('base', 'VISION_LAST_YAW', double(yawList));
assignin('base', 'VISION_LAST_BBOX', double(bboxList));
assignin('base', 'VISION_LAST_CLASSID', double(classIdList));
assignin('base', 'VISION_LAST_SCORE', double(scoreList));
assignin('base', 'VISION_LAST_CENTER2D', double(centerList));
end
