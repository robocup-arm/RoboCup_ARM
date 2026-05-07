function Pout = apply_tilt_points(Pin, tf)
    if isempty(Pin)
        Pout = zeros(0,3);
        return;
    end
    if ~tf.enabled
        Pout = Pin;
        return;
    end
    if isvector(Pin) && numel(Pin) == 3
        Pin = reshape(Pin, [1 3]);
    end
    Pout = (tf.R * Pin')';
end
