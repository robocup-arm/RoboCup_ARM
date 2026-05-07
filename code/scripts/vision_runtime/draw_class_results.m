function draw_class_results(objs, label, color)
    if isempty(objs)
        return;
    end
    for k = 1:numel(objs)
        bb = objs(k).bbox;
        rect = [bb(1) bb(2) bb(3)-bb(1) bb(4)-bb(2)];
        isPartial = isfield(objs(k), 'partial') && objs(k).partial;
        lineStyle = '-';
        boxColor = color;
        if isPartial
            lineStyle = '--';
            boxColor = [1.0 0.2 0.2];
        end
        rectangle('Position', rect, 'EdgeColor', boxColor, 'LineWidth', 2, 'LineStyle', lineStyle);
        txt = string(sprintf("%s %.2f %s", label, objs(k).score, objs(k).ab)) + format_color_suffix(objs(k));
        if isPartial
            txt = txt + " partial";
        end
        text(bb(1), max(1, bb(2)-10), txt, 'Color', boxColor, 'FontSize', 10, 'FontWeight', 'bold');
        plot_pt(objs(k).center2D, color, 'o');
        if isfield(objs(k), 'axisLine2D') && ~isempty(objs(k).axisLine2D) && objs(k).ab == "B"
            plot_line(objs(k).axisLine2D, [0.2 0.9 1.0]);
        end
        if isfield(objs(k), 'intersectLine2D') && ~isempty(objs(k).intersectLine2D)
            plot_line(objs(k).intersectLine2D, [0.1 1.0 0.1]);
        end
    end
end
