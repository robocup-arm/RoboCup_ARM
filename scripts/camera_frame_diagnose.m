function report = camera_frame_diagnose(Tcb, pCamList, pBaseRefList)
%CAMERA_FRAME_DIAGNOSE Diagnose camera-frame mismatch against known base points.
%
% Inputs:
%   Tcb          4x4 transform currently used as base <- camera_like_frame
%   pCamList     Nx3 points from vision center3D (camera frame used by vision)
%   pBaseRefList Nx3 manually verified base-frame points
%
% Output:
%   report struct with best candidate mappings and errors.
%
% This script enumerates all 48 signed-permutation mappings M:
%   pCamLike = M * pCam
% then evaluates:
%   pBaseEst = R * pCamLike + t
% against pBaseRef.
%
% It also computes an optional residual translation correction dT:
%   pBaseEst2 = pBaseEst + dT
% where dT is the mean residual over all samples.

validateattributes(Tcb, {'double', 'single'}, {'size', [4 4]}, mfilename, 'Tcb', 1);
validateattributes(pCamList, {'double', 'single'}, {'2d', 'ncols', 3}, mfilename, 'pCamList', 2);
validateattributes(pBaseRefList, {'double', 'single'}, {'2d', 'ncols', 3}, mfilename, 'pBaseRefList', 3);
assert(size(pCamList, 1) == size(pBaseRefList, 1), ...
    'pCamList and pBaseRefList must have the same row count.');

N = size(pCamList, 1);
if N < 1
    error('At least one sample is required.');
end

R = double(Tcb(1:3, 1:3));
t = double(Tcb(1:3, 4));

Ms = enumerate_signed_permutation_mats();
K = numel(Ms);

rows = repmat(struct( ...
    'M', eye(3), ...
    'detM', 1, ...
    'rmseRaw', inf, ...
    'rmseWithDt', inf, ...
    'dT', zeros(3, 1), ...
    'maxRaw', inf, ...
    'maxWithDt', inf, ...
    'meanErr', inf), K, 1);

for i = 1:K
    M = Ms{i};
    pBaseEst = zeros(N, 3);
    for j = 1:N
        pc = double(pCamList(j, :).');
        pBaseEst(j, :) = (R * (M * pc) + t).';
    end

    err = pBaseRefList - pBaseEst;
    errNorm = sqrt(sum(err.^2, 2));
    dT = mean(err, 1).';

    err2 = pBaseRefList - (pBaseEst + dT.');
    err2Norm = sqrt(sum(err2.^2, 2));

    rows(i).M = M;
    rows(i).detM = round(det(M));
    rows(i).rmseRaw = sqrt(mean(errNorm.^2));
    rows(i).rmseWithDt = sqrt(mean(err2Norm.^2));
    rows(i).dT = dT;
    rows(i).maxRaw = max(errNorm);
    rows(i).maxWithDt = max(err2Norm);
    rows(i).meanErr = mean(errNorm);
end

[~, idxRaw] = sort([rows.rmseRaw], 'ascend');
[~, idxDt] = sort([rows.rmseWithDt], 'ascend');

report = struct();
report.nSamples = N;
report.Tcb = Tcb;
report.bestRaw = rows(idxRaw(1));
report.bestWithDt = rows(idxDt(1));
report.topRaw = rows(idxRaw(1:min(8, K)));
report.topWithDt = rows(idxDt(1:min(8, K)));

fprintf('\n=== camera_frame_diagnose ===\n');
fprintf('Samples: %d\n', N);
fprintf('Current t (camera origin in base) = [%.6f %.6f %.6f]\n', t(1), t(2), t(3));

fprintf('\nTop candidates (raw, no extra translation):\n');
for k = 1:min(5, numel(report.topRaw))
    r = report.topRaw(k);
    fprintf('#%d rmse=%.6f max=%.6f det(M)=%d\n', k, r.rmseRaw, r.maxRaw, r.detM);
    disp(r.M);
end

fprintf('\nBest candidate with residual translation dT:\n');
r = report.bestWithDt;
fprintf('rmse=%.6f max=%.6f det(M)=%d dT=[%.6f %.6f %.6f]\n', ...
    r.rmseWithDt, r.maxWithDt, r.detM, r.dT(1), r.dT(2), r.dT(3));
disp(r.M);
fprintf('=============================\n\n');
end

function Ms = enumerate_signed_permutation_mats()
permList = perms(1:3);
Ms = cell(48, 1);
idx = 0;
sgn = [-1, 1];
for p = 1:size(permList, 1)
    P = zeros(3, 3);
    for r = 1:3
        P(r, permList(p, r)) = 1;
    end
    for sx = sgn
        for sy = sgn
            for sz = sgn
                S = diag([sx, sy, sz]);
                idx = idx + 1;
                Ms{idx} = S * P;
            end
        end
    end
end
end
