function vOut = undo_tilt_dir(vIn, tf)
    if isempty(vIn)
        vOut = zeros(1,3);
        return;
    end
    v = reshape(vIn, [3 1]);
    if tf.enabled
        v = tf.Rt * v;
    end
    n = norm(v);
    if n > 1e-12
        v = v / n;
    end
    vOut = v(:)';
end
