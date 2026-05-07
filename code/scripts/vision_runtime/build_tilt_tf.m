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
