function [names, hues] = get_color_candidates(clsName)
    switch string(clsName)
        case "can"
            names = ["red", "yellow", "green"];
            hues = [0.00, 0.15, 0.33];
        case "bottle"
            names = ["red", "yellow", "blue"];
            hues = [0.00, 0.15, 0.62];
        case "cube"
            names = ["red", "green", "blue", "purple"];
            % Tuned for current sim textures (blue/purple both near 0.6~0.7 hue).
            hues = [0.00, 0.33, 0.60, 0.67];
        otherwise
            names = strings(1,0);
            hues = zeros(1,0);
    end
end
