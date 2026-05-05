function mask640 = buildMaskFromProto(maskCoeff, proto, outSize)
    nm = size(proto,1);
    hp = size(proto,2);
    wp = size(proto,3);
    proto2 = reshape(proto, [nm, hp*wp]);
    m = (maskCoeff(:)' * proto2);
    m = 1 ./ (1 + exp(-m));
    maskSmall = reshape(m, [hp, wp]);
    mask640 = imresize(maskSmall, [outSize outSize], 'bilinear');
end
