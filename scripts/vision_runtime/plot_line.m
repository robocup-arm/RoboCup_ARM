function plot_line(p2, color)
    if isempty(p2) || size(p2,1) < 2
        return;
    end
    plot([p2(1,1) p2(2,1)], [p2(1,2) p2(2,2)], '-', 'Color', color, 'LineWidth', 2);
end
