function [axisLine3D] = axis_line_from_cloud(P, axisVec, center3D)
    axisVec = axisVec(:)' / max(norm(axisVec), 1e-9);
    t = (P - center3D) * axisVec';
    tLo = prctile(t, 5);
    tHi = prctile(t, 95);
    axisLine3D = [center3D + tLo * axisVec; center3D + tHi * axisVec];
end
