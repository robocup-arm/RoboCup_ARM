function [Pc, ok] = pixels_to_cloud_fast(uu, vv, depth, K, zMin, zMax, minPts)
    if nargin < 7 || isempty(minPts)
        minPts = 50;
    end

    Pc = zeros(0,3);
    ok = false;
    if isempty(uu) || isempty(vv)
        return;
    end

    ind = sub2ind(size(depth), vv, uu);
    Z = depth(ind);
    valid = isfinite(Z) & (Z > zMin) & (Z < zMax);
    if ~any(valid)
        return;
    end

    uu = double(uu(valid));
    vv = double(vv(valid));
    Z  = double(Z(valid));
    if numel(Z) < minPts
        return;
    end

    fx  = double(K(1,1)); fy  = double(K(2,2));
    cx0 = double(K(1,3)); cy0 = double(K(2,3));

    if should_use_gpu_math(numel(Z))
        try
            uuG = gpuArray(uu);
            vvG = gpuArray(vv);
            ZG  = gpuArray(Z);
            XcG = (uuG - cx0) .* ZG / fx;
            YcG = (vvG - cy0) .* ZG / fy;
            Pc = gather([XcG(:), YcG(:), ZG(:)]);
            ok = true;
            return;
        catch
            % fall through to CPU path
        end
    end

    Xc = (uu - cx0) .* Z / fx;
    Yc = (vv - cy0) .* Z / fy;
    Pc = [Xc(:), Yc(:), Z(:)];
    ok = true;
end

function tf = should_use_gpu_math(nPts)
    persistent inited gpuAvailable minPts enabled
    if isempty(inited)
        inited = true;
        gpuAvailable = false;
        minPts = 40000;
        enabled = true;

        envEnable = lower(strtrim(getenv("VISION_GPU_MATH")));
        if ~isempty(envEnable) && any(strcmp(envEnable, {"0","false","off","no"}))
            enabled = false;
        end

        envMin = strtrim(getenv("VISION_GPU_MATH_MINPTS"));
        if ~isempty(envMin)
            v = str2double(envMin);
            if isfinite(v) && v > 0
                minPts = v;
            end
        end

        if enabled
            try
                if exist('gpuDeviceCount', 'file') == 2 && gpuDeviceCount > 0
                    gpuAvailable = true;
                end
            catch
                gpuAvailable = false;
            end
        end
    end

    tf = enabled && gpuAvailable && (nPts >= minPts);
end
