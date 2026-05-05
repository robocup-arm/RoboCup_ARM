function preview_block(Image, bboxList, classIdList, scoreList, centerList, numDet)
%#codegen
coder.extrinsic('vision_preview');

MAXDET = 20;
yawList = zeros(2, MAXDET);
for i = 1:MAXDET
    yawList(:,i) = [0; pi/2];
end

vision_preview(Image, bboxList, classIdList, scoreList, centerList, yawList, numDet);
end
