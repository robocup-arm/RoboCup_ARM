function plot_poly(p, color)
    if isempty(p) || size(p,1) < 3
        return;
    end
    plot([p(:,1); p(1,1)], [p(:,2); p(1,2)], '-', 'Color', color, 'LineWidth', 2);
end
