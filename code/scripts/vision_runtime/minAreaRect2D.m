function [theta, xmin, xmax, ymin, ymax] = minAreaRect2D(u, v, stepDeg, pct)
    P = [u(:) v(:)];
    P = P(all(isfinite(P),2),:);
    if size(P,1) < 5
        theta = 0;
        xmin = min(u); xmax = max(u);
        ymin = min(v); ymax = max(v);
        return;
    end
    if nargin < 3 || isempty(stepDeg) || stepDeg <= 0
        stepDeg = 1;
    end
    if nargin < 4 || isempty(pct)
        pct = 0;
    end
    thetaList = 0:deg2rad(stepDeg):pi/2;
    bestArea = inf;
    theta = 0; xmin = 0; xmax = 0; ymin = 0; ymax = 0;
    for t = thetaList
        R = [cos(t) -sin(t); sin(t) cos(t)];
        Pr = P * R;
        if pct > 0
            xmin_t = prctile(Pr(:,1), pct);
            xmax_t = prctile(Pr(:,1), 100 - pct);
            ymin_t = prctile(Pr(:,2), pct);
            ymax_t = prctile(Pr(:,2), 100 - pct);
        else
            xmin_t = min(Pr(:,1));
            xmax_t = max(Pr(:,1));
            ymin_t = min(Pr(:,2));
            ymax_t = max(Pr(:,2));
        end
        area = (xmax_t - xmin_t) * (ymax_t - ymin_t);
        if area < bestArea
            bestArea = area;
            theta = t;
            xmin = xmin_t; xmax = xmax_t;
            ymin = ymin_t; ymax = ymax_t;
        end
    end
end
