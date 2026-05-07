function [points, targetBin] = map_color_to_scoring(clsName, label)
    points = NaN;
    targetBin = "";
    switch string(clsName)
        case "can"
            targetBin = "green";
            switch string(label)
                case "green"
                    points = 10;
                case "yellow"
                    points = 20;
                case "red"
                    points = 30;
            end
        case "bottle"
            targetBin = "blue";
            switch string(label)
                case "blue"
                    points = 10;
                case "yellow"
                    points = 20;
                case "red"
                    points = 30;
            end
        case "cube"
            points = 10;
            switch string(label)
                case {"green", "purple"}
                    targetBin = "green";
                case {"blue", "red"}
                    targetBin = "blue";
            end
    end
end
