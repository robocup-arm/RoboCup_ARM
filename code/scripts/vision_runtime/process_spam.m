function out = process_spam(dets, depth, K, fx, fy, cx0, cy0, zMin, zMax, saveCloud, tiltTf, debugSegView, imgName, ...
    protoSeg, imgsz, maskThresh, maskMinArea, maskUseBBox, rectUseAll, rectPadFrac)
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
    if nargin < 14
        protoSeg = [];
    end
    if nargin < 15
        imgsz = 640;
    end
    if nargin < 16
        maskThresh = 0.50;
    end
    if nargin < 17
        maskMinArea = 0;
    end
    if nargin < 18
        maskUseBBox = true;
    end
    if nargin < 19
        rectUseAll = false;
    end
    if nargin < 20
        rectPadFrac = 0.005;
    end
    optsS = struct("bottomPct", 40, "planeMaxDist", 0.002, "zExpand", 0.006, ...
                   "zBin", 0.003, "minPts", 150, ...
                   "planeRef", [0 0 1], "planeAng", 12, ...
                   "rectThetaStep", 0.5, "rectPad", 0.002, "rectPadFrac", 0.01, ...
                   "rectPct", 1, "rectUseAll", rectUseAll, "rectUseHull", true);
    optsS.rectPadFrac = rectPadFrac;
    H = size(depth,1); W = size(depth,2);
    scaleLB = imgsz / max(H, W);
    nh = round(H * scaleLB);
    nw = round(W * scaleLB);
    padLB = [floor((imgsz - nw)/2) floor((imgsz - nh)/2)];

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
        if should_show_seg_debug(debugSegView, "s", imgName, i)
            show_segmentation_debug_cloud(sprintf("SegDebug SPAM %s det#%d", imgName, i), ...
                Pc, PcWork, pcObj.Location, tiltTf, get_debug_show_tilt(debugSegView));
        end
        try
            [center3DWork, rect3DWork, ~, len, wid, ~] = fit_bottom_face_center_rect_spam(pcObj, optsS);
        catch
            continue;
        end
        center3D = undo_tilt_points(center3DWork, tiltTf);
        rect3D = undo_tilt_points(rect3DWork, tiltTf);
        center2D = project_points(center3D, fx, fy, cx0, cy0);
        rect2D = project_points(rect3D, fx, fy, cx0, cy0);
        bboxDraw = dets(i).bbox;
        if isfield(dets(i), "maskBBox640") && ~isempty(dets(i).maskBBox640)
            bMask = undoLetterbox_xyxy(dets(i).maskBBox640, scaleLB, padLB);
            bMask(1) = max(1, min(W, bMask(1)));
            bMask(3) = max(1, min(W, bMask(3)));
            bMask(2) = max(1, min(H, bMask(2)));
            bMask(4) = max(1, min(H, bMask(4)));
            bMask = [min(bMask(1),bMask(3)), min(bMask(2),bMask(4)), ...
                     max(bMask(1),bMask(3)), max(bMask(2),bMask(4))];
            if (bMask(3) - bMask(1)) >= 3 && (bMask(4) - bMask(2)) >= 3
                bboxDraw = bMask;
            end
        end
        obj = struct("bbox", bboxDraw, "score", dets(i).score, ...
            "center3D", center3D, "center2D", center2D, ...
            "rect3D", rect3D, "rect2D", rect2D, ...
            "len", len, "wid", wid, "partial", dets(i).partial);
        if saveCloud
            obj.cloud = sample_cloud(undo_tilt_points(pcObj.Location, tiltTf), 5000);
        end
        out = [out; obj]; %#ok<AGROW>
    end
end
