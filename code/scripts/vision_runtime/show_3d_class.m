function show_3d_class(imgName, clsName, objs)
    if isempty(objs)
        return;
    end
    if ~has_cloud_points(objs)
        return;
    end
    figName = sprintf("3D %s: %s", clsName, imgName);
    figure('Name', figName);
    hold on; grid on; axis equal;
    xlabel('X'); ylabel('Y'); zlabel('Z');
    colors = lines(max(1, numel(objs)));
    for k = 1:numel(objs)
        if ~isfield(objs(k), 'cloud') || isempty(objs(k).cloud)
            continue;
        end
        P = objs(k).cloud;
        c = colors(k,:);
        scatter3(P(:,1), P(:,2), P(:,3), 6, c, 'filled');
        if isfield(objs(k), 'center3D') && ~isempty(objs(k).center3D)
            C = objs(k).center3D;
            uv = objs(k).center2D;
            txt = sprintf('%s%d s=%.2f uv=(%.1f,%.1f)', clsName(1), k, objs(k).score, uv(1), uv(2));
            text(C(1), C(2), C(3), txt, 'Color', c, 'FontSize', 8, 'FontWeight', 'bold');
        end
        if isfield(objs(k), 'axisLine3D') && ~isempty(objs(k).axisLine3D)
            plot3(objs(k).axisLine3D(:,1), objs(k).axisLine3D(:,2), objs(k).axisLine3D(:,3), '-', 'Color', c, 'LineWidth', 2);
        end
        if isfield(objs(k), 'intersectLine3D') && ~isempty(objs(k).intersectLine3D)
            plot3(objs(k).intersectLine3D(:,1), objs(k).intersectLine3D(:,2), objs(k).intersectLine3D(:,3), '-', 'Color', [0 1 0], 'LineWidth', 2);
        end
        if isfield(objs(k), 'rect3D') && ~isempty(objs(k).rect3D)
            plot_poly3(objs(k).rect3D, c);
        end
        if isfield(objs(k), 'square3D') && ~isempty(objs(k).square3D)
            plot_poly3(objs(k).square3D, c);
        end
    end
    title(figName);
    hold off;
end
