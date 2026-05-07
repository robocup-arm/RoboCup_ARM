function record_grasp_failure_runtime()
targetPos = [NaN; NaN; NaN];

if evalin('base', 'exist(''USER_ACTIVE_TARGET_POS'',''var'')') ~= 0
    p = evalin('base', 'double(USER_ACTIVE_TARGET_POS)');
    if isnumeric(p) && numel(p) == 3 && all(isfinite(p(:)))
        targetPos = p(:);
    end
end

if ~all(isfinite(targetPos))
    fprintf('[grasp_fail] no valid USER_ACTIVE_TARGET_POS\n');
    return;
end

maxFail = 3;
if evalin('base', 'exist(''USER_GRASP_MAX_FAILS'',''var'')') ~= 0
    t = evalin('base', 'double(USER_GRASP_MAX_FAILS)');
    if isfinite(t) && t >= 1
        maxFail = round(t);
    end
end

matchThr = 0.04;
if evalin('base', 'exist(''USER_IGNORE_MATCH_THR'',''var'')') ~= 0
    t = evalin('base', 'double(USER_IGNORE_MATCH_THR)');
    if isfinite(t) && t > 0
        matchThr = t;
    end
end

failPos = zeros(3,20);
failCounts = zeros(1,20);

if evalin('base', 'exist(''USER_GRASP_FAIL_POSITIONS'',''var'')') ~= 0
    p = evalin('base', 'double(USER_GRASP_FAIL_POSITIONS)');
    if isnumeric(p) && size(p,1) == 3
        cols = min(20, size(p,2));
        failPos(:,1:cols) = p(:,1:cols);
    end
end

if evalin('base', 'exist(''USER_GRASP_FAIL_COUNTS'',''var'')') ~= 0
    c = evalin('base', 'double(USER_GRASP_FAIL_COUNTS)');
    if isnumeric(c)
        cols = min(20, numel(c));
        failCounts(1:cols) = c(1:cols);
    end
end

idx = 0;
bestD = inf;

for k = 1:20
    if failCounts(k) > 0 && any(failPos(:,k) ~= 0)
        d = norm(targetPos - failPos(:,k));
        if d < bestD
            bestD = d;
            idx = k;
        end
    end
end

if idx == 0 || bestD > matchThr
    for k = 1:20
        if failCounts(k) <= 0
            idx = k;
            failPos(:,k) = targetPos;
            failCounts(k) = 0;
            break;
        end
    end
end

if idx == 0
    idx = 1;
    failPos(:,1) = targetPos;
    failCounts(1) = 0;
end

failCounts(idx) = failCounts(idx) + 1;
failPos(:,idx) = targetPos;

assignin('base', 'USER_GRASP_FAIL_POSITIONS', failPos);
assignin('base', 'USER_GRASP_FAIL_COUNTS', failCounts);

fprintf('[grasp_fail] target failure %.0f/%.0f pos=[%.4f %.4f %.4f]\n', ...
    failCounts(idx), maxFail, targetPos(1), targetPos(2), targetPos(3));

if failCounts(idx) >= maxFail
    ignorePos = zeros(3,20);

    if evalin('base', 'exist(''USER_IGNORE_TARGETS'',''var'')') ~= 0
        p = evalin('base', 'double(USER_IGNORE_TARGETS)');
        if isnumeric(p) && size(p,1) == 3
            cols = min(20, size(p,2));
            ignorePos(:,1:cols) = p(:,1:cols);
        end
    end

    alreadyIgnored = false;
    emptyIdx = 0;

    for k = 1:20
        if all(ignorePos(:,k) == 0)
            if emptyIdx == 0
                emptyIdx = k;
            end
        else
            d = norm(targetPos - ignorePos(:,k));
            if d <= matchThr
                alreadyIgnored = true;
            end
        end
    end

    if ~alreadyIgnored
        if emptyIdx == 0
            emptyIdx = 1;
        end
        ignorePos(:,emptyIdx) = targetPos;
        assignin('base', 'USER_IGNORE_TARGETS', ignorePos);
    end

    assignin('base', 'USER_IGNORE_TOKEN', now);

    fprintf('[grasp_fail] target ignored after %.0f failures pos=[%.4f %.4f %.4f]\n', ...
        failCounts(idx), targetPos(1), targetPos(2), targetPos(3));
end
end
