function out = process_can(dets, depth, K, fx, fy, cx0, cy0, zMin, zMax, saveCloud, debugCan, debugCanMax, tiltTf, debugSegView, imgName, tallZSpanAbsThr, tallZtoRFactor, forceTallMinCos, edgeCleanupEnable, edgeCleanupDebug, protoSeg, imgsz, maskThresh, maskMinArea, maskUseBBox, rgb, scaleLB, padLB, enableColorRecognition, colorCfg)
    out = struct([]);
    if isempty(dets)
        return;
    end
    if nargin < 11
        debugCan = false;
    end
    if nargin < 12
        debugCanMax = 3;
    end
    if nargin < 13
        tiltTf = build_tilt_tf([0 0 -1]);
    end
    if nargin < 14
        debugSegView = default_seg_debug();
    end
    if nargin < 15
        imgName = "";
    end
    if nargin < 16
        tallZSpanAbsThr = 0.085;
    end
    if nargin < 17
        tallZtoRFactor = 1.8;
    end
    if nargin < 18
        forceTallMinCos = 0.55;
    end
    if nargin < 19
        edgeCleanupEnable = true;
    end
    if nargin < 20
        edgeCleanupDebug = false;
    end
    if nargin < 21
        protoSeg = [];
    end
    if nargin < 22
        imgsz = 640;
    end
    if nargin < 23
        maskThresh = 0.50;
    end
    if nargin < 24
        maskMinArea = 0;
    end
    if nargin < 25
        maskUseBBox = true;
    end
    if nargin < 26
        rgb = [];
    end
    if nargin < 27
        scaleLB = 1;
    end
    if nargin < 28
        padLB = [0 0];
    end
    if nargin < 29
        enableColorRecognition = false;
    end
    if nargin < 30 || isempty(colorCfg)
        colorCfg = default_color_config();
    end
    optsA = struct("topPct", 85, "planeMaxDist", 0.08, "planeAng", 15, ...
                   "minTopPts", 100, "band", 0.006, "tol", 0.006);
    optsB = struct("midBand", 0.004, "wallTol", 0.004, "tableMaxDist", 0.006, "tableAng", 10);
    abCosThr = 0.60;
    thinZSpanThr = 0.03; % if segmented cloud is too thin, force A
    tableTopPct = 80;
    tableMaxDist = 0.006;
    tableAng = 15;

    for i = 1:numel(dets)
        [Pc, ok] = det_to_cloud(dets(i), protoSeg, depth, K, zMin, zMax, maskThresh, maskMinArea, maskUseBBox, imgsz);
        if ~ok
            continue;
        end
        PcWork = apply_tilt_points(Pc, tiltTf);
        pcBox = pointCloud(PcWork);
        if debugCan && i <= debugCanMax
            fprintf("Can[%d] raw cloud points: %d\n", i, pcBox.Count);
            zAll = pcBox.Location(:,3);
            fprintf("Can[%d] raw Z range: %.4f ~ %.4f (span=%.4f)\n", i, min(zAll), max(zAll), max(zAll)-min(zAll));
        end
        pcObj = segment_largest_cluster(pcBox, debugCan && i <= debugCanMax, i);
        if pcObj.Count < 50
            continue;
        end
        if debugCan && i <= debugCanMax
            zSeg = pcObj.Location(:,3);
            fprintf("Can[%d] seg points: %d\n", i, pcObj.Count);
            fprintf("Can[%d] seg Z range: %.4f ~ %.4f (span=%.4f)\n", i, min(zSeg), max(zSeg), max(zSeg)-min(zSeg));
            figure('Name', sprintf('Can segmented cloud [%d]', i));
            pcshow(pcObj); xlabel('X'); ylabel('Y'); zlabel('Z');
            title(sprintf('Can segmented cloud [%d]', i));
        end
        % merge possible bottom-cap points that were split into a small cluster
        pcObj = merge_bottom_cap(pcObj, pcBox);
        pcObjAB = pcObj;  % keep AB judgement on pre-clean cloud to avoid over-clean side effects
        pcObjFit = pcObj;
        if edgeCleanupEnable
            pcObjFit = cleanup_cylinder_attachment(pcObjFit, edgeCleanupDebug || (debugCan && i <= debugCanMax), sprintf("Can[%d]", i));
        end
        segDbgEnable = should_show_seg_debug(debugSegView, "c", imgName, i);
        segDbgShowTilt = get_debug_show_tilt(debugSegView);
        zSpan = max(pcObjAB.Location(:,3)) - min(pcObjAB.Location(:,3));
        CxyObj = mean(pcObjAB.Location(:,1:2), 1);
        rObj = sqrt(sum((pcObjAB.Location(:,1:2) - CxyObj).^2, 2));
        rXY90 = prctile(rObj, 90);
        [abLabel, abInfo] = classifyAB_table(pcObjAB, pcBox, abCosThr, tableTopPct, tableMaxDist, tableAng);
        forceAThin = zSpan < thinZSpanThr;
        % Guard force-tall override: only allow when geometric AB score is already near A
        forceATall = abInfo.tableFound && (abInfo.cosAxis >= forceTallMinCos) && ...
            (zSpan > max(tallZSpanAbsThr, tallZtoRFactor * rXY90));
        if forceAThin || forceATall
            abLabel = 1; % force A when cloud is nearly planar
        end
        if debugCan && i <= debugCanMax
            if isfield(abInfo, "axisSource")
                fprintf("Can[%d] AB: cosAxis=%.3f tableFound=%d cosTable=%.3f zTable=%.3f zSpan=%.4f rXY90=%.4f forceThin=%d forceTall=%d axis=%s sc=%.3f(pca=%.3f wall=%.3f) -> %s\n", ...
                    i, abInfo.cosAxis, abInfo.tableFound, abInfo.cosTable, abInfo.zTable, zSpan, ...
                    rXY90, forceAThin, forceATall, string(abInfo.axisSource), abInfo.axisScore, ...
                    abInfo.axisScorePCA, abInfo.axisScoreWall, ternary(abLabel==1,"A","B"));
            else
                fprintf("Can[%d] AB: cosAxis=%.3f tableFound=%d cosTable=%.3f zTable=%.3f zSpan=%.4f rXY90=%.4f forceThin=%d forceTall=%d -> %s\n", ...
                    i, abInfo.cosAxis, abInfo.tableFound, abInfo.cosTable, abInfo.zTable, zSpan, rXY90, ...
                    forceAThin, forceATall, ternary(abLabel==1,"A","B"));
            end
        end
        if abLabel == 1
            [center3DWork, axisVecWork, ~] = fit_cap_center_axis_A(pcObjFit, optsA);
            axisLine3DWork = axis_line_from_cloud(pcObjFit.Location, axisVecWork, center3DWork);
            if segDbgEnable
                dbgOverlay = struct("centerWork", center3DWork, "axisLineWork", axisLine3DWork, "intersectLineWork", []);
                show_segmentation_debug_cloud(sprintf("SegDebug CAN %s det#%d", imgName, i), ...
                    Pc, PcWork, pcObjFit.Location, tiltTf, segDbgShowTilt, dbgOverlay);
            end
            center3D = undo_tilt_points(center3DWork, tiltTf);
            axisVec = undo_tilt_dir(axisVecWork, tiltTf);
            axisLine3D = undo_tilt_points(axisLine3DWork, tiltTf);
            center2D = project_points(center3D, fx, fy, cx0, cy0);
            axisLine2D = project_points(axisLine3D, fx, fy, cx0, cy0);
            colorInfo = default_color_info();
            if enableColorRecognition
                colorInfo = estimate_cylinder_color_info(rgb, dets(i), protoSeg, imgsz, maskThresh, maskMinArea, ...
                    maskUseBBox, scaleLB, padLB, "can", "A", colorCfg);
            end
            obj = struct("bbox", dets(i).bbox, "score", dets(i).score, "ab", "A", ...
                "center3D", center3D, "center2D", center2D, ...
                "axis3D", axisVec, "axisLine3D", axisLine3D, "axisLine2D", axisLine2D, ...
                "intersectLine3D", [], "intersectLine2D", [], "partial", dets(i).partial, ...
                "color", colorInfo.label, "colorScore", colorInfo.score, "colorSource", colorInfo.source, ...
                "colorHSV", colorInfo.meanHSV, "colorRGB", colorInfo.meanRGB, "colorPixelCount", colorInfo.pixelCount, ...
                "points", colorInfo.points, "targetBin", colorInfo.targetBin);
            if saveCloud
                obj.cloud = sample_cloud(undo_tilt_points(pcObjFit.Location, tiltTf), 5000);
            end
        else
            [~, midPtWork, axisVecWork, infoB] = fit_caseB_target_point(pcObjFit, pcBox, optsB);
            line3DWork = infoB.linePts;
            centerAxisWork = center_from_axis_line_closest(midPtWork, axisVecWork, line3DWork);
            center3DWork = center_from_xy_min_z(pcObjFit.Location, centerAxisWork);
            axisLine3DWork = axis_line_from_cloud(pcObjFit.Location, axisVecWork, centerAxisWork);
            if segDbgEnable
                dbgOverlay = struct("centerWork", center3DWork, "axisLineWork", axisLine3DWork, "intersectLineWork", line3DWork);
                show_segmentation_debug_cloud(sprintf("SegDebug CAN %s det#%d", imgName, i), ...
                    Pc, PcWork, pcObjFit.Location, tiltTf, segDbgShowTilt, dbgOverlay);
            end
            center3D = undo_tilt_points(center3DWork, tiltTf);
            axisVec = undo_tilt_dir(axisVecWork, tiltTf);
            axisLine3D = undo_tilt_points(axisLine3DWork, tiltTf);
            line3D = undo_tilt_points(line3DWork, tiltTf);
            center2D = project_points(center3D, fx, fy, cx0, cy0);
            axisLine2D = project_points(axisLine3D, fx, fy, cx0, cy0);
            line2D = project_points(line3D, fx, fy, cx0, cy0);
            colorInfo = default_color_info();
            if enableColorRecognition
                colorInfo = estimate_cylinder_color_info(rgb, dets(i), protoSeg, imgsz, maskThresh, maskMinArea, ...
                    maskUseBBox, scaleLB, padLB, "can", "B", colorCfg);
            end
            obj = struct("bbox", dets(i).bbox, "score", dets(i).score, "ab", "B", ...
                "center3D", center3D, "center2D", center2D, ...
                "axis3D", axisVec, "axisLine3D", axisLine3D, "axisLine2D", axisLine2D, ...
                "intersectLine3D", line3D, "intersectLine2D", line2D, "partial", dets(i).partial, ...
                "color", colorInfo.label, "colorScore", colorInfo.score, "colorSource", colorInfo.source, ...
                "colorHSV", colorInfo.meanHSV, "colorRGB", colorInfo.meanRGB, "colorPixelCount", colorInfo.pixelCount, ...
                "points", colorInfo.points, "targetBin", colorInfo.targetBin);
            if saveCloud
                obj.cloud = sample_cloud(undo_tilt_points(pcObjFit.Location, tiltTf), 5000);
            end
        end
        out = [out; obj]; %#ok<AGROW>
    end
end
