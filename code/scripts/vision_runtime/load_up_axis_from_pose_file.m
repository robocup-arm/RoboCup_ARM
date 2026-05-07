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
