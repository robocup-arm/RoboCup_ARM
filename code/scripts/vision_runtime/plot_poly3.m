function plot_poly3(P, color)
    if isempty(P) || size(P,1) < 3
        return;
    end
    plot3([P(:,1); P(1,1)], [P(:,2); P(1,2)], [P(:,3); P(1,3)], '-', 'Color', color, 'LineWidth', 2);
end
