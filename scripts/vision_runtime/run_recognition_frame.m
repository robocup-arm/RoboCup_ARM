function imgRes = run_recognition_frame(rgb, depth, K)

fx = K(1,1); fy = K(2,2);
cx0 = K(1,3); cy0 = K(2,3);

zMin = 0.05; 
zMax = 2.50;

imgsz = 640;
maskThresh = 0.50;
maskMinArea = 0;
maskUseBBox = true;
saveCloud = false;

colorCfg = default_color_config();
tiltTf = build_tilt_tf([0 0 -1]);
debugSegView = default_seg_debug();

[detBProc, detCProc, detSProc, detPProc, detM, proto, scaleLB, padLB] = ...
    detect_all_objects_single_frame(rgb);

canObjs = process_can(detCProc, depth, K, fx, fy, cx0, cy0, zMin, zMax, saveCloud, ...
    false, 0, tiltTf, debugSegView, "", ...
    0.085, 1.8, 0.55, true, false, ...
    proto, imgsz, maskThresh, maskMinArea, maskUseBBox, ...
    rgb, scaleLB, padLB, false, colorCfg);

bottleObjs = process_bottle(detBProc, depth, K, fx, fy, cx0, cy0, zMin, zMax, saveCloud, ...
    false, 0, tiltTf, debugSegView, "", ...
    false, true, 0.35, true, false, ...
    proto, imgsz, maskThresh, maskMinArea, maskUseBBox, ...
    rgb, scaleLB, padLB, false, colorCfg);

spamObjs = process_spam(detSProc, depth, K, fx, fy, cx0, cy0, zMin, zMax, saveCloud, ...
    tiltTf, debugSegView, "", ...
    proto, imgsz, maskThresh, maskMinArea, maskUseBBox, false, 0.005);

cubeObjs = process_cube(detPProc, depth, K, fx, fy, cx0, cy0, zMin, zMax, saveCloud, ...
    tiltTf, debugSegView, "", ...
    proto, imgsz, maskThresh, maskMinArea, maskUseBBox, rgb, true, colorCfg);

markerObjs = process_marker(detM, proto, depth, K, fx, fy, cx0, cy0, ...
    zMin, zMax, maskThresh, maskMinArea, maskUseBBox, imgsz, saveCloud, tiltTf, debugSegView, "");

imgRes = struct();
imgRes.can    = attach_cls_name(canObjs,    'can');
imgRes.bottle = attach_cls_name(bottleObjs, 'bottle');
imgRes.spam   = attach_cls_name(spamObjs,   'spam');
imgRes.cube   = attach_cls_name(cubeObjs,   'cube');
imgRes.marker = attach_cls_name(markerObjs, 'marker');

end
