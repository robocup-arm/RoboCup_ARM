function [cx, cy] = fitCircle2D(x, y)
    x = x(:); y = y(:);
    A = [x y ones(size(x))];
    b = -(x.^2 + y.^2);
    p = A \ b;
    cx = -0.5 * p(1);
    cy = -0.5 * p(2);
end
