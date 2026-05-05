function arr = attach_cls_name(arr, clsName)
for i = 1:numel(arr)
    arr(i).cls = clsName;
end
end
