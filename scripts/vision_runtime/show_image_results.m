function show_image_results(rgb, imgRes, gripperMask)
    figName = sprintf("Results: %s", imgRes.name);
    figure('Name', figName);
    imshow(rgb); hold on;
    if nargin >= 3 && ~isempty(gripperMask)
        per = bwperim(gripperMask);
        [yy, xx] = find(per);
        plot(xx, yy, 'r.', 'MarkerSize', 1);
    end
    draw_class_results(imgRes.can, 'c', [0.2 0.8 1.0]);
    draw_class_results(imgRes.bottle, 'b', [1.0 0.6 0.1]);
    draw_rect_results(imgRes.spam, 's', [0.9 0.2 0.9]);
    draw_line_results(imgRes.marker, 'm', [0.1 1.0 0.1]);
    draw_square_results(imgRes.cube, 'p', [1.0 0.9 0.2]);
    title(figName);
    hold off;
end
