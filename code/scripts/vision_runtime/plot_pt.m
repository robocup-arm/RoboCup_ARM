function plot_pt(p, color, marker)
    if isempty(p)
        return;
    end
    plot(p(1), p(2), marker, 'Color', color, 'MarkerSize', 8, 'LineWidth', 2);
end
