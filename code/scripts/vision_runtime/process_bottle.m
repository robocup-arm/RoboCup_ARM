function out = process_bottle(dets, depth, K, fx, fy, cx0, cy0, zMin, zMax, saveCloud, debugBottle, debugBottleMax, ...
    tiltTf, debugSegView, imgName, forceBUseMainCluster, bottleBAutoSelect, bottleBMinAcceptScore, edgeCleanupEnable, edgeCleanupDebug, ...
    protoSeg, imgsz, maskThresh, maskMinArea, maskUseBBox, rgb, scaleLB, padLB, enableColorRecognition, colorCfg)
    out = struct([]);
    if isempty(dets)
        return;
    end
    if nargin < 11
        debugBottle = false;
    end
    if nargin < 12
        debugBottleMax = 3;
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
        forceBUseMainCluster = false;
    end
    if nargin < 17
        bottleBAutoSelect = true;
    end
    if nargin < 18
        bottleBMinAcceptScore = 0.35;
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
    optsA = struct("bottomPct", 40, "planeMaxDist", 0.004, "zBand", 0.004, ...
                   "zExpand", 0.006, "zBin", 0.003, "minPts", 120);
    optsB = struct("midBand", 0.008, "wallTol", 0.006, "tableMaxDist", 0.006, ...
                   "tableAng", 10, "thickPct", 70, "thickTol", 0.005, "minCand", 50, ...
                   "axisMode", "wall", "debugB", false);
    abCosThr = 0.60;
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
        if debugBottle && i <= debugBottleMax
            fprintf("Bottle[%d] raw cloud points: %d\n", i, pcBox.Count);
            zAll = pcBox.Location(:,3);
            fprintf("Bottle[%d] raw Z range: %.4f ~ %.4f (span=%.4f)\n", i, min(zAll), max(zAll), max(zAll)-min(zAll));
        end
        pcObj = segment_largest_cluster(pcBox, debugBottle && i <= debugBottleMax, i);
        if pcObj.Count < 50
            continue;
        end
        % merge possible bottom-cap points that were split into a small cluster
        pcObj = merge_bottom_cap(pcObj, pcBox);
        pcObjAB = pcObj;
        pcObjMainFit = pcObj;
        if edgeCleanupEnable
            pcObjMainFit = cleanup_cylinder_attachment(pcObjMainFit, edgeCleanupDebug || (debugBottle && i <= debugBottleMax), sprintf("Bottle[%d]-main", i));
        end
        if debugBottle && i <= debugBottleMax
            zSeg = pcObjMainFit.Location(:,3);
            fprintf("Bottle[%d] seg points: %d\n", i, pcObjMainFit.Count);
            fprintf("Bottle[%d] seg Z range: %.4f ~ %.4f (span=%.4f)\n", i, min(zSeg), max(zSeg), max(zSeg)-min(zSeg));
            figure('Name', sprintf('Bottle segmented cloud [%d]', i));
            pcshow(pcObjMainFit); xlabel('X'); ylabel('Y'); zlabel('Z');
            title(sprintf('Bottle segmented cloud [%d]', i));
        end
        segDbgEnable = should_show_seg_debug(debugSegView, "b", imgName, i);
        segDbgShowTilt = get_debug_show_tilt(debugSegView);
        [abLabel, ~] = classifyAB_table(pcObjAB, pcBox, abCosThr, tableTopPct, tableMaxDist, tableAng);
        if abLabel == 1
            [center3DWork, axisVecWork, ~] = fit_bottom_cap_center_axis_A_bottle(pcObjMainFit, optsA);
            axisLine3DWork = axis_line_from_cloud(pcObjMainFit.Location, axisVecWork, center3DWork);
            if segDbgEnable
                dbgOverlay = struct("centerWork", center3DWork, "axisLineWork", axisLine3DWork, "intersectLineWork", []);
                show_segmentation_debug_cloud(sprintf("SegDebug BOTTLE %s det#%d", imgName, i), ...
                    Pc, PcWork, pcObjMainFit.Location, tiltTf, segDbgShowTilt, dbgOverlay);
            end
            center3D = undo_tilt_points(center3DWork, tiltTf);
            axisVec = undo_tilt_dir(axisVecWork, tiltTf);
            axisLine3D = undo_tilt_points(axisLine3DWork, tiltTf);
            center2D = project_points(center3D, fx, fy, cx0, cy0);
            axisLine2D = project_points(axisLine3D, fx, fy, cx0, cy0);
            colorInfo = default_color_info();
            if enableColorRecognition
                colorInfo = estimate_cylinder_color_info(rgb, dets(i), protoSeg, imgsz, maskThresh, maskMinArea, ...
                    maskUseBBox, scaleLB, padLB, "bottle", "A", colorCfg);
            end
            obj = struct("bbox", dets(i).bbox, "score", dets(i).score, "ab", "A", ...
                "center3D", center3D, "center2D", center2D, ...
                "axis3D", axisVec, "axisLine3D", axisLine3D, "axisLine2D", axisLine2D, ...
                "intersectLine3D", [], "intersectLine2D", [], ...
                "clusterSource", "A", "clusterScore", NaN, "clusterLowConf", false, ...
                "partial", dets(i).partial, ...
                "color", colorInfo.label, "colorScore", colorInfo.score, "colorSource", colorInfo.source, ...
                "colorHSV", colorInfo.meanHSV, "colorRGB", colorInfo.meanRGB, "colorPixelCount", colorInfo.pixelCount, ...
                "points", colorInfo.points, "targetBin", colorInfo.targetBin);
            if saveCloud
                obj.cloud = sample_cloud(undo_tilt_points(pcObjMainFit.Location, tiltTf), 5000);
            end
        else
            % B-class: use a separate segmentation method (only for bottle B)
            sel = struct("source","main","bestScore",NaN,"lowConf",false);
            if forceBUseMainCluster
                pcUse = pcObjMainFit;
                [~, midPtWork, axisVecWork, infoB] = fit_caseB_target_point_bottle(pcUse, pcBox, optsB);
                sel.source = "main_forced";
                [sel.bestScore, ~] = score_bottle_B_candidate(infoB, pcUse.Count);
            else
                pcObjB = segment_bottle_B(pcBox, debugBottle && i <= debugBottleMax, i);
                if edgeCleanupEnable
                    pcObjB = cleanup_cylinder_attachment(pcObjB, edgeCleanupDebug || (debugBottle && i <= debugBottleMax), sprintf("Bottle[%d]-spec", i));
                end
                if bottleBAutoSelect
                    [pcUse, midPtWork, axisVecWork, infoB, sel] = choose_bottle_B_cluster( ...
                        pcObjMainFit, pcObjB, pcBox, optsB, bottleBMinAcceptScore, debugBottle && i <= debugBottleMax, i);
                else
                    if pcObjB.Count >= 50
                        pcUse = pcObjB;
                        sel.source = "special_direct";
                    else
                        pcUse = pcObjMainFit;
                        sel.source = "main_direct";
                    end
                    [~, midPtWork, axisVecWork, infoB] = fit_caseB_target_point_bottle(pcUse, pcBox, optsB);
                    [sel.bestScore, ~] = score_bottle_B_candidate(infoB, pcUse.Count);
                end
            end
            if isfield(infoB, "linePts") && ~isempty(infoB.linePts) && size(infoB.linePts,2) == 3
                line3DWork = infoB.linePts;
            else
                % Fallback: some fits may return only mid/axis without linePts.
                line3DWork = axis_line_from_cloud(pcUse.Location, axisVecWork, midPtWork);
            end
            centerAxisWork = center_from_axis_line_closest(midPtWork, axisVecWork, line3DWork);
            center3DWork = center_from_xy_min_z(pcUse.Location, centerAxisWork);
            axisLine3DWork = axis_line_from_cloud(pcUse.Location, axisVecWork, centerAxisWork);
            if segDbgEnable
                dbgOverlay = struct("centerWork", center3DWork, "axisLineWork", axisLine3DWork, "intersectLineWork", line3DWork);
                show_segmentation_debug_cloud(sprintf("SegDebug BOTTLE %s det#%d", imgName, i), ...
                    Pc, PcWork, pcUse.Location, tiltTf, segDbgShowTilt, dbgOverlay);
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
                    maskUseBBox, scaleLB, padLB, "bottle", "B", colorCfg);
            end
            obj = struct("bbox", dets(i).bbox, "score", dets(i).score, "ab", "B", ...
                "center3D", center3D, "center2D", center2D, ...
                "axis3D", axisVec, "axisLine3D", axisLine3D, "axisLine2D", axisLine2D, ...
                "intersectLine3D", line3D, "intersectLine2D", line2D, ...
                "clusterSource", sel.source, "clusterScore", sel.bestScore, "clusterLowConf", sel.lowConf, ...
                "partial", dets(i).partial, ...
                "color", colorInfo.label, "colorScore", colorInfo.score, "colorSource", colorInfo.source, ...
                "colorHSV", colorInfo.meanHSV, "colorRGB", colorInfo.meanRGB, "colorPixelCount", colorInfo.pixelCount, ...
                "points", colorInfo.points, "targetBin", colorInfo.targetBin);
            if saveCloud
                obj.cloud = sample_cloud(undo_tilt_points(pcUse.Location, tiltTf), 5000);
            end
        end
        out = [out; obj]; %#ok<AGROW>
    end
end
