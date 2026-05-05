function out = process_marker(dets, proto, depth, K, fx, fy, cx0, cy0, zMin, zMax, maskThresh, maskMinArea, maskUseBBox, imgsz, saveCloud, tiltTf, debugSegView, imgName)
    out = struct([]);
    if isempty(dets)
        return;
    end
    if nargin < 16
        tiltTf = build_tilt_tf([0 0 -1]);
    end
    if nargin < 17
        debugSegView = default_seg_debug();
    end
    if nargin < 18
        imgName = "";
    end
    optsB = struct("midBand", 0.008, "wallTol", 0.006, "tableMaxDist", 0.006, ...
                   "tableAng", 10, "thickPct", 70, "thickTol", 0.005, "minCand", 50, ...
                   "axisMode", "proj", "debugB", false);

    for i = 1:numel(dets)
        [Pm, okMask] = seg_det_to_cloud(dets(i), proto, depth, K, zMin, zMax, maskThresh, maskMinArea, maskUseBBox, imgsz);
        if ~okMask
            continue;
        end
        PmWork = apply_tilt_points(Pm, tiltTf);
        pcMarker = pointCloud(PmWork);
        [PcBox, ok] = bbox_to_cloud(dets(i).bbox, depth, K, zMin, zMax);
        if ~ok
            continue;
        end
        PcBoxWork = apply_tilt_points(PcBox, tiltTf);
        pcBox = pointCloud(PcBoxWork);

        [~, midPtWork, axisVecWork, infoB] = fit_caseB_target_point_bottle(pcMarker, pcBox, optsB);
        if should_show_seg_debug(debugSegView, "m", imgName, i)
            Pafter = pcMarker.Location;
            if isfield(infoB, "candPts") && ~isempty(infoB.candPts)
                Pafter = infoB.candPts;
            end
            show_segmentation_debug_cloud(sprintf("SegDebug MARKER %s det#%d", imgName, i), ...
                Pm, PmWork, Pafter, tiltTf, get_debug_show_tilt(debugSegView));
        end
        axisLine3DWork = axis_line_from_cloud(pcMarker.Location, axisVecWork, midPtWork);
        if isfield(infoB, "linePts") && ~isempty(infoB.linePts) && size(infoB.linePts,2) == 3
            line3DWork = infoB.linePts;
        else
            % Fallback: if case-B fitting returns no explicit linePts, use axis line.
            line3DWork = axisLine3DWork;
        end
        midPt = undo_tilt_points(midPtWork, tiltTf);
        axisVec = undo_tilt_dir(axisVecWork, tiltTf);
        axisLine3D = undo_tilt_points(axisLine3DWork, tiltTf);
        line3D = undo_tilt_points(line3DWork, tiltTf);
        center2D = project_points(midPt, fx, fy, cx0, cy0);
        axisLine2D = project_points(axisLine3D, fx, fy, cx0, cy0);
        line2D = project_points(line3D, fx, fy, cx0, cy0);

        obj = struct("bbox", dets(i).bbox, "score", dets(i).score, ...
            "center3D", midPt, "center2D", center2D, ...
            "axis3D", axisVec, "axisLine3D", axisLine3D, "axisLine2D", axisLine2D, ...
            "intersectLine3D", line3D, "intersectLine2D", line2D, "partial", dets(i).partial);
        if saveCloud
            obj.cloud = sample_cloud(undo_tilt_points(pcMarker.Location, tiltTf), 5000);
        end
        out = [out; obj]; %#ok<AGROW>
    end
end
