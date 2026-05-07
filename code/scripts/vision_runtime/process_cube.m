function out = process_cube(dets, depth, K, fx, fy, cx0, cy0, zMin, zMax, saveCloud, tiltTf, debugSegView, imgName, ...
    protoSeg, imgsz, maskThresh, maskMinArea, maskUseBBox, rgb, enableColorRecognition, colorCfg)
    out = struct([]);
    if isempty(dets)
        return;
    end
    if nargin < 11
        tiltTf = build_tilt_tf([0 0 -1]);
    end
    if nargin < 12
        debugSegView = default_seg_debug();
    end
    if nargin < 13
        imgName = "";
    end
    if nargin < 19
        rgb = [];
    end
    if nargin < 20
        enableColorRecognition = false;
    end
    if nargin < 21 || isempty(colorCfg)
        colorCfg = default_color_config();
    end
    if nargin < 14
        protoSeg = [];
    end
    if nargin < 15 || isempty(imgsz)
        imgsz = 640;
    end
    if nargin < 16 || isempty(maskThresh)
        maskThresh = 0.50;
    end
    if nargin < 17 || isempty(maskMinArea)
        maskMinArea = 0;
    end
    if nargin < 18 || isempty(maskUseBBox)
        maskUseBBox = true;
    end
    optsC = struct("bottomPct", 40, "planeMaxDist", 0.002, "zExpand", 0.006, ...
                   "zBin", 0.003, "minPts", 150, ...
                   "planeRef", [0 0 1], "planeAng", 12, ...
                   "squareThetaStep", 0.5, "squarePad", 0.0, "squarePadFrac", 0.0, ...
                   "squarePct", 2, "squareUseAll", false, "squareUseHull", true);

    for i = 1:numel(dets)
        [Pc, ok] = det_to_cloud(dets(i), protoSeg, depth, K, zMin, zMax, maskThresh, maskMinArea, maskUseBBox, imgsz);
        if ~ok
            continue;
        end
        PcWork = apply_tilt_points(Pc, tiltTf);
        pcBox = pointCloud(PcWork);
        pcObj = segment_largest_cluster(pcBox);
        if pcObj.Count < 50
            continue;
        end
        if should_show_seg_debug(debugSegView, "p", imgName, i)
            show_segmentation_debug_cloud(sprintf("SegDebug CUBE %s det#%d", imgName, i), ...
                Pc, PcWork, pcObj.Location, tiltTf, get_debug_show_tilt(debugSegView));
        end
        try
            [center3DWork, square3DWork, ~, side, ~] = fit_bottom_face_center_square_cube(pcObj, optsC);
        catch
            continue;
        end
        center3D = undo_tilt_points(center3DWork, tiltTf);
        square3D = undo_tilt_points(square3DWork, tiltTf);
        center2D = project_points(center3D, fx, fy, cx0, cy0);
        square2D = project_points(square3D, fx, fy, cx0, cy0);
        colorInfo = default_color_info();
        if enableColorRecognition
            colorInfo = estimate_cube_color_info(rgb, square2D, colorCfg);
        end
        obj = struct("bbox", dets(i).bbox, "score", dets(i).score, ...
            "center3D", center3D, "center2D", center2D, ...
            "square3D", square3D, "square2D", square2D, "side", side, "partial", dets(i).partial, ...
            "color", colorInfo.label, "colorScore", colorInfo.score, "colorSource", colorInfo.source, ...
            "colorHSV", colorInfo.meanHSV, "colorRGB", colorInfo.meanRGB, "colorPixelCount", colorInfo.pixelCount, ...
            "points", colorInfo.points, "targetBin", colorInfo.targetBin);
        if saveCloud
            obj.cloud = sample_cloud(undo_tilt_points(pcObj.Location, tiltTf), 5000);
        end
        out = [out; obj]; %#ok<AGROW>
    end
end
