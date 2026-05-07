function plot_seg_overlay3d(center3D, axisLine3D, intersectLine3D)
    if nargin < 1
        center3D = zeros(0,3);
    end
    if nargin < 2
        axisLine3D = zeros(0,3);
    end
    if nargin < 3
        intersectLine3D = zeros(0,3);
    end
    if size(axisLine3D,1) >= 2
        plot3(axisLine3D(:,1), axisLine3D(:,2), axisLine3D(:,3), '-', ...
            'Color', [0.2 0.9 1.0], 'LineWidth', 2.2);
    end
    if size(intersectLine3D,1) >= 2
        plot3(intersectLine3D(:,1), intersectLine3D(:,2), intersectLine3D(:,3), '-', ...
            'Color', [0.1 1.0 0.1], 'LineWidth', 2.2);
    end
    if size(center3D,1) >= 1
        c = center3D(1,:);
        if all(isfinite(c))
            plot3(c(1), c(2), c(3), 'o', ...
                'MarkerSize', 9, 'MarkerFaceColor', [1.0 0.85 0.0], 'MarkerEdgeColor', 'k', 'LineWidth', 1.2);
        end
    end
end
