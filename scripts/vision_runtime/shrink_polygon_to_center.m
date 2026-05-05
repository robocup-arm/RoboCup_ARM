function polyOut = shrink_polygon_to_center(polyIn, factor)
    polyOut = polyIn;
    if isempty(polyIn) || size(polyIn, 1) < 3
        return;
    end
    C = mean(polyIn, 1);
    polyOut = C + factor * (polyIn - C);
end
