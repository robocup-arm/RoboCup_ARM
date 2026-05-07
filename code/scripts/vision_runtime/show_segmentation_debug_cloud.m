function show_segmentation_debug_cloud(figTitle, PbeforeCam, PbeforeWork, PafterWork, tiltTf, showTiltFrame, overlay)
    if nargin < 6
        showTiltFrame = true;
    end
    if nargin < 7 || isempty(overlay)
        overlay = struct();
    end
    PbCam = sample_cloud(PbeforeCam, 12000);
    Pw = sample_cloud(PbeforeWork, 12000);
    PaW = sample_cloud(PafterWork, 12000);
    PaCam = undo_tilt_points(PaW, tiltTf);
    [centerW, axisW, interW] = get_seg_overlay_work(overlay);
    centerCam = undo_tilt_points(centerW, tiltTf);
    axisCam = undo_tilt_points(axisW, tiltTf);
    interCam = undo_tilt_points(interW, tiltTf);
    overlayWorkAll = [centerW; axisW; interW];
    overlayCamAll = [centerCam; axisCam; interCam];

    hFig = figure('Name', figTitle);
    rotate3d(hFig, 'on');
    if showTiltFrame
        t = tiledlayout(1,3, "Padding","compact", "TileSpacing","compact");
        title(t, figTitle);

        nexttile;
        hold on; grid on; axis equal;
        if ~isempty(PbCam)
            scatter3(PbCam(:,1), PbCam(:,2), PbCam(:,3), 4, [0.5 0.5 0.5], 'filled');
        end
        plot_seg_overlay3d(centerCam, axisCam, interCam);
        xlabel('X'); ylabel('Y'); zlabel('Z');
        setup_seg_axes3d([PbCam; overlayCamAll]);
        title('Before (camera)');
        hold off;

        nexttile;
        hold on; grid on; axis equal;
        if ~isempty(Pw)
            scatter3(Pw(:,1), Pw(:,2), Pw(:,3), 4, [0.5 0.5 0.5], 'filled');
        end
        if ~isempty(PaW)
            scatter3(PaW(:,1), PaW(:,2), PaW(:,3), 6, [0.0 0.7 0.2], 'filled');
        end
        plot_seg_overlay3d(centerW, axisW, interW);
        xlabel('X'); ylabel('Y'); zlabel('Z');
        setup_seg_axes3d([Pw; PaW; overlayWorkAll]);
        title('Work Frame (gray=before, green=after)');
        hold off;

        nexttile;
        hold on; grid on; axis equal;
        if ~isempty(PbCam)
            scatter3(PbCam(:,1), PbCam(:,2), PbCam(:,3), 4, [0.5 0.5 0.5], 'filled');
        end
        if ~isempty(PaCam)
            scatter3(PaCam(:,1), PaCam(:,2), PaCam(:,3), 6, [0.0 0.7 0.2], 'filled');
        end
        plot_seg_overlay3d(centerCam, axisCam, interCam);
        xlabel('X'); ylabel('Y'); zlabel('Z');
        setup_seg_axes3d([PbCam; PaCam; overlayCamAll]);
        title('Camera Frame (gray=before, green=after)');
        hold off;
    else
        t = tiledlayout(1,2, "Padding","compact", "TileSpacing","compact");
        title(t, figTitle);

        nexttile;
        hold on; grid on; axis equal;
        if ~isempty(PbCam)
            scatter3(PbCam(:,1), PbCam(:,2), PbCam(:,3), 4, [0.5 0.5 0.5], 'filled');
        end
        plot_seg_overlay3d(centerCam, axisCam, interCam);
        xlabel('X'); ylabel('Y'); zlabel('Z');
        setup_seg_axes3d([PbCam; overlayCamAll]);
        title('Before (camera)');
        hold off;

        nexttile;
        hold on; grid on; axis equal;
        if ~isempty(PbCam)
            scatter3(PbCam(:,1), PbCam(:,2), PbCam(:,3), 4, [0.5 0.5 0.5], 'filled');
        end
        if ~isempty(PaCam)
            scatter3(PaCam(:,1), PaCam(:,2), PaCam(:,3), 6, [0.0 0.7 0.2], 'filled');
        end
        plot_seg_overlay3d(centerCam, axisCam, interCam);
        xlabel('X'); ylabel('Y'); zlabel('Z');
        setup_seg_axes3d([PbCam; PaCam; overlayCamAll]);
        title('After Segmentation (camera)');
        hold off;
    end
end
