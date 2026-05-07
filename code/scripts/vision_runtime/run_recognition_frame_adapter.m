function imgRes = run_recognition_frame_adapter(rgb, depth, K)

if exist('run_recognition_frame', 'file') ~= 2
    error('run_recognition_frame.m not found on MATLAB path.');
end

imgRes = run_recognition_frame(rgb, depth, K);

end