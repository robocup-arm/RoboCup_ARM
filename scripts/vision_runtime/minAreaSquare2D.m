function [theta, xmid, ymid, side] = minAreaSquare2D(u, v, stepDeg, pct)
    P = [u(:) v(:)];
    P = P(all(isfinite(P),2),:);
    if size(P,1) < 5
        theta = 0;
        xmin = min(u); xmax = max(u);
        ymin = min(v); ymax = max(v);
        xmid = 0.5 * (xmin + xmax);
        ymid = 0.5 * (ymin + ymax);
        side = max(xmax - xmin, ymax - ymin);
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
    theta = 0; xmid = 0; ymid = 0; side = 0;
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
        w = xmax_t - xmin_t;
        h = ymax_t - ymin_t;
        s = max(w, h);
        area = s * s;
        if area < bestArea
            bestArea = area;
            theta = t;
            xmid = 0.5 * (xmin_t + xmax_t);
            ymid = 0.5 * (ymin_t + ymax_t);
            side = s;
        end
    end
end
