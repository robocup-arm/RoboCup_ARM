function R = align_vectors_rotm(a, b)
    a = a(:) / max(norm(a), 1e-12);
    b = b(:) / max(norm(b), 1e-12);
    v = cross(a, b);
    c = dot(a, b);
    s = norm(v);
    if s < 1e-12
        if c > 0
            R = eye(3);
            return;
        end
        % 180 deg: choose axis orthogonal to a
        if abs(a(1)) < 0.9
            u = [1;0;0];
        else
            u = [0;1;0];
        end
        v = cross(a, u);
        v = v / max(norm(v), 1e-12);
        K = [0 -v(3) v(2); v(3) 0 -v(1); -v(2) v(1) 0];
        R = eye(3) + 2 * (K * K);
        return;
    end
    K = [0 -v(3) v(2); v(3) 0 -v(1); -v(2) v(1) 0];
    R = eye(3) + K + K*K*((1-c)/(s^2));
end
