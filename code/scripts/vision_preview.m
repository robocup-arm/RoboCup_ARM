function vision_preview(Image, bboxList, classIdList, scoreList, centerList, yawList, numDet)

persistent hFig hAx hImg hRects hTexts hPts hDirs ...
    previewEnabled previewStride previewFrame verbose

MAXDET = 20;

if isempty(previewEnabled)
    previewEnabled = get_env_bool_local("VISION_PREVIEW_ENABLE", true);
    previewStride = get_env_int_local("VISION_PREVIEW_STRIDE", 3);
    if previewStride < 1
        previewStride = 1;
    end
    previewFrame = uint64(0);
    verbose = get_env_bool_local("VISION_PREVIEW_VERBOSE", false);
end

if ~previewEnabled
    return;
end

previewFrame = previewFrame + 1;
if previewStride > 1
    if mod(double(previewFrame) - 1, previewStride) ~= 0
        return;
    end
end

if isempty(hFig) || ~isvalid(hFig)
    disp('[vision_preview] about to create Vision Preview figure');
    assignin('base', 'USER_SELECTED_ID', 0);
    assignin('base', 'USER_PROCEED', false);
    assignin('base', 'USER_ABORT', false);

    hFig = figure( ...
        'Name','Vision Preview', ...
        'NumberTitle','off', ...
        'MenuBar','none', ...
        'ToolBar','none', ...
        'WindowKeyPressFcn', @onKeyPress, ...
        'WindowButtonDownFcn', @onMouseClick);
    fprintf('[vision_preview] Press SPACE to START auto loop, X to STOP.\n');

    hAx = axes('Parent', hFig);
    hImg = imshow(Image, 'Parent', hAx);
    hold(hAx, 'on');

    set(hImg, 'ButtonDownFcn', @onMouseClick, 'HitTest', 'on', 'PickableParts', 'all');
    set(hAx,  'ButtonDownFcn', @onMouseClick, 'HitTest', 'on', 'PickableParts', 'all');

    hRects = gobjects(MAXDET,1);
    hTexts = gobjects(MAXDET,1);
    hPts   = gobjects(MAXDET,1);
    hDirs  = gobjects(MAXDET,1);

    for i = 1:MAXDET
        hRects(i) = rectangle(hAx, ...
            'Position',[1 1 1 1], ...
            'EdgeColor','g', ...
            'LineWidth', 1.5, ...
            'Visible','off', ...
            'HitTest','off');

        hTexts(i) = text(hAx, 1,1,'', ...
            'Color','y', ...
            'FontSize',10, ...
            'FontWeight','bold', ...
            'Visible','off', ...
            'HitTest','off');

        hPts(i) = plot(hAx, 1,1,'y+', ...
            'MarkerSize',12, ...
            'LineWidth',2.0, ...
            'Visible','off', ...
            'HitTest','off');

        hDirs(i) = plot(hAx, [1 1], [1 1], '-', ...
            'Color','c', ...
            'LineWidth',1.8, ...
            'Visible','off', ...
            'HitTest','off');
    end
end

setappdata(hFig, 'bboxList', double(bboxList));
setappdata(hFig, 'classIdList', double(classIdList));
setappdata(hFig, 'scoreList', double(scoreList));
setappdata(hFig, 'centerList', double(centerList));
setappdata(hFig, 'yawList', double(yawList));
setappdata(hFig, 'numDet', double(numDet));

set(hImg, 'CData', Image);

selectedId = evalin('base', 'USER_SELECTED_ID');
colorIdListRt = zeros(1, MAXDET);
try
    ctmp = double(evalin('base', 'VISION_LAST_COLORID'));
    if isnumeric(ctmp) && ~isempty(ctmp)
        nC = min(numel(ctmp), MAXDET);
        colorIdListRt(1:nC) = reshape(ctmp(1:nC), 1, []);
    end
catch
end

if verbose
    fprintf('[vision_preview] numDet = %d\n', numDet);
    for i = 1:double(numDet)
        x1 = bboxList(1,i); y1 = bboxList(2,i);
        x2 = bboxList(3,i); y2 = bboxList(4,i);
        cx = centerList(1,i); cy = centerList(2,i);
        fprintf('[vision_preview] target %d: grasp center = (%.1f, %.1f), bbox = [%.1f %.1f %.1f %.1f]\n', ...
            i, cx, cy, x1, y1, x2, y2);
    end
end

for i = 1:MAXDET
    if i <= double(numDet)
        x1 = bboxList(1,i); y1 = bboxList(2,i);
        x2 = bboxList(3,i); y2 = bboxList(4,i);
        cx = centerList(1,i); cy = centerList(2,i);
        yaw = yawList(1,i);

        if i == selectedId
            edgeColor = 'r';
            ptColor = 'r';
            dirColor = [1 0.3 0.3];
        else
            edgeColor = 'g';
            ptColor = 'y';
            dirColor = 'c';
        end

        set(hRects(i), ...
            'Position', [x1 y1 x2-x1 y2-y1], ...
            'EdgeColor', edgeColor, ...
            'Visible','on');

        label = sprintf('ID=%d class=%d score=%.2f', ...
            i, classIdList(i), scoreList(i));
        if round(double(classIdList(i))) == 4
            cId = round(double(colorIdListRt(i)));
            cName = color_id_to_name_local(cId);
            label = sprintf('%s cubeColor=%s', label, cName);
        end

        set(hTexts(i), ...
            'Position', [x1 max(1,y1-10)], ...
            'String', label, ...
            'Color', edgeColor, ...
            'Visible','on');

        set(hPts(i), ...
            'XData', cx, ...
            'YData', cy, ...
            'Color', ptColor, ...
            'Visible','on');

        L = 40;
        x2d = cx + L*cos(yaw);
        y2d = cy + L*sin(yaw);

        set(hDirs(i), ...
            'XData', [cx x2d], ...
            'YData', [cy y2d], ...
            'Color', dirColor, ...
            'Visible','on');
    else
        set(hRects(i), 'Visible','off');
        set(hTexts(i), 'Visible','off');
        set(hPts(i),   'Visible','off');
        set(hDirs(i),  'Visible','off');
    end
end

drawnow limitrate;

end

function onMouseClick(src, ~)
fig = ancestor(src, 'figure');
ax = findobj(fig, 'Type', 'axes');

cp = get(ax, 'CurrentPoint');
x = cp(1,1);
y = cp(1,2);

bboxList   = getappdata(fig, 'bboxList');
centerList = getappdata(fig, 'centerList');
numDet     = getappdata(fig, 'numDet');

if is_preview_verbose_local()
    fprintf('[vision_preview] click at (%.1f, %.1f)\n', x, y);
    fprintf('[vision_preview] callback sees numDet = %d\n', numDet);
end

% 先按"点在 bbox 内"判定
for k = 1:numDet
    x1 = bboxList(1,k); y1 = bboxList(2,k);
    x2 = bboxList(3,k); y2 = bboxList(4,k);
    cx = centerList(1,k); cy = centerList(2,k);

    if is_preview_verbose_local()
        fprintf('[vision_preview] target %d grasp center = (%.1f, %.1f), bbox = [%.1f %.1f %.1f %.1f]\n', ...
            k, cx, cy, x1, y1, x2, y2);
    end

    if x >= x1 && x <= x2 && y >= y1 && y <= y2
        assignin('base', 'USER_SELECTED_ID', k);
        if is_preview_verbose_local()
            fprintf('[vision_preview] selected ID = %d (inside bbox)\n', k);
        end
        return;
    end
end

% 如果没点进框，再按最近"真实抓取点"选
bestId = 0;
bestDist = inf;
for k = 1:numDet
    cx = centerList(1,k);
    cy = centerList(2,k);
    d = hypot(x-cx, y-cy);
    if is_preview_verbose_local()
        fprintf('[vision_preview] distance to target %d grasp center = %.2f\n', k, d);
    end
    if d < bestDist
        bestDist = d;
        bestId = k;
    end
end

if bestId > 0
    assignin('base', 'USER_SELECTED_ID', bestId);
    if is_preview_verbose_local()
        fprintf('[vision_preview] selected ID = %d (nearest grasp center, dist = %.2f)\n', bestId, bestDist);
    end
else
    if is_preview_verbose_local()
        fprintf('[vision_preview] no valid target selected.\n');
    end
end
end

function onKeyPress(~, evt)
persistent lastKeySec
nowSec = now * 86400;
if isempty(lastKeySec)
    lastKeySec = -1e9;
end

% Debounce to avoid repeated key events from one key press.
if (nowSec - lastKeySec) < 0.25
    return;
end
lastKeySec = nowSec;

switch lower(char(evt.Key))
    case 'return'
        assignin('base', 'USER_PROCEED', true);
        if is_preview_verbose_local()
            fprintf('[vision_preview] ENTER pressed.\n');
        end
    case {'space','s'}
        % Space only arms auto mode (no toggle).
        resetToken = evalin('base', 'double(USER_RESET_TOKEN)');
        assignin('base', 'USER_RESET_TOKEN', resetToken + 1);
        assignin('base', 'USER_AUTO_RUN', true);
        assignin('base', 'USER_AUTO_NEED_RESET', false);
        assignin('base', 'USER_PROCEED', false);
        assignin('base', 'USER_ABORT', false);
        fprintf('[vision_preview] AUTO LOOP ARMED.\n');
    case 'x'
        assignin('base', 'USER_AUTO_RUN', false);
        assignin('base', 'USER_AUTO_NEED_RESET', false);
        assignin('base', 'USER_PROCEED', false);
        assignin('base', 'USER_ABORT', false);
        fprintf('[vision_preview] AUTO LOOP DISARMED.\n');

    case 'escape'
        assignin('base', 'USER_ABORT', true);
        if is_preview_verbose_local()
            fprintf('[vision_preview] ESC pressed.\n');
        end
end
end

function v = get_env_int_local(name, defaultVal)
v = defaultVal;
s = strtrim(getenv(name));
if isempty(s)
    return;
end
t = str2double(s);
if isfinite(t)
    v = round(t);
end
end

function tf = get_env_bool_local(name, defaultVal)
tf = defaultVal;
s = lower(strtrim(getenv(name)));
if isempty(s)
    return;
end
if any(strcmp(s, {'1','true','on','yes'}))
    tf = true;
elseif any(strcmp(s, {'0','false','off','no'}))
    tf = false;
end
end

function tf = is_preview_verbose_local()
persistent verboseCached inited
if isempty(inited)
    inited = true;
    verboseCached = get_env_bool_local("VISION_PREVIEW_VERBOSE", false);
end
tf = verboseCached;
end

function name = color_id_to_name_local(cid)
switch round(double(cid))
    case 1
        name = 'red';
    case 2
        name = 'yellow';
    case 3
        name = 'green';
    case 4
        name = 'blue';
    case 5
        name = 'purple';
    otherwise
        name = 'unknown';
end
end
