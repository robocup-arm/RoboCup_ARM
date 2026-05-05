function draw_square_results(objs, label, color)
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
        txt = string(sprintf("%s %.2f", label, objs(k).score)) + format_color_suffix(objs(k));
        if isPartial
            txt = txt + " partial";
        end
        text(bb(1), max(1, bb(2)-10), txt, 'Color', boxColor, 'FontSize', 10, 'FontWeight', 'bold');
        plot_pt(objs(k).center2D, color, 'o');
        plot_poly(objs(k).square2D, color);
    end
end
