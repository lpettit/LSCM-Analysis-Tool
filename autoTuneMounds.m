function bestParams = autoTuneMounds(imagePath, fillDeepPits, fillThreshold, dilateRadius, minObjectArea, maxEvals, showPlots)
% =========================================================================
%  autoTuneMounds  —  Bayesian optimization of mound detection parameters
%
%  Accepts either a Keyence VK4 file or a standard grayscale/RGB image
%  (BMP, TIFF, PNG).  The detection pipeline is purely morphological and
%  uses only normalised [0,1] pixel intensities, so VK4 and BMP input
%  produce identical results — no calibration constants are needed here.
%
%  USAGE:
%    bestParams = autoTuneMounds('Left-50x.vk4', false, 0.3, 3, 20)
%    bestParams = autoTuneMounds('Left-50x.bmp', false, 0.3, 3, 20)
%    bestParams = autoTuneMounds('Left-50x.vk4', true,  0.3, 3, 20, 80)
%    bestParams = autoTuneMounds('Left-50x.vk4', false, 0.3, 3, 20, 20, false)
%
%  INPUTS:
%    imagePath     - path to .vk4 file OR grayscale/RGB image (.bmp/.tif/.png)
%    fillDeepPits  - boolean; set true if reflection pits are a problem
%    fillThreshold - fixed intensity threshold for pit filling (e.g. 0.3)
%    dilateRadius  - fixed dilation radius for fgm4 blobs (visualization only)
%    minObjectArea - fixed minimum blob area to keep (noise filter)
%    maxEvals      - (optional) number of Bayesian evaluations, default 60
%    showPlots     - (optional) true to show bayesopt and result figures,
%                    false for quieter scripted smoke tests. Default: true
%
%  OPTIMIZED:  gaussSigma, contrastMethod, openRadius
%  FIXED:      clipLimit (0.02), fillDeepPits, fillThreshold, dilateRadius, minObjectArea
%
%  OUTPUT:
%    bestParams   - table of optimal parameters, ready to pass to analyzeMounds
%
%  REQUIRES: Image Processing Toolbox, Statistics and ML Toolbox (bayesopt)
%            readVK4.m + vk4mat library (VK4 input only)
% =========================================================================

if nargin < 6 || isempty(maxEvals),  maxEvals = 60;   end
if nargin < 7 || isempty(showPlots), showPlots = true; end

% --- Load image ----------------------------------------------------------
% VK4: derive uint8 display image from calibrated Z (identical in content
%      to the companion BMP but without 8-bit quantisation loss in Z).
%      The detection pipeline only needs normalised [0,1] intensities —
%      no calibration constants are used here.
% Image (BMP/TIFF/PNG): imread as before.
[~, ~, imageExt] = fileparts(imagePath);
if strcmpi(imageExt, '.vk4')
    if ~exist('readVK4', 'file')
        error(['autoTuneMounds: readVK4.m not found on MATLAB path.\n' ...
               'Required for .vk4 input. Add readVK4.m and the vk4mat\n' ...
               'library (https://github.com/matt-black/vk4mat) to path.']);
    end
    [Z_load, ~, total_h, imgH, imgW] = readVK4(imagePath);
    I_raw = uint8(round(Z_load / total_h * 255));
    clear Z_load total_h;
else
    I_raw = imread(imagePath);
    if size(I_raw, 3) == 3
        I_raw = rgb2gray(I_raw);
    end
    [imgH, imgW] = size(I_raw);
end
I = double(I_raw) / 255;  % normalised [0,1] double for pipeline

% --- Compute density guardrail and count band from distance transform ---

% --- Estimate plausible mound count range from raw image ----------------
% Instead of a single n_expected (which is sensitive to the exact percentile
% chosen), we compute the distance transform estimate at three percentiles
% and derive a soft band [n_lo, n_hi]. The count penalty is zero anywhere
% inside this band, and grows only outside it. This makes the optimizer
% insensitive to the exact percentile value while still preventing
% catastrophic over/under-detection.
I_blur0  = imgaussfilt(I, 2.0);
BW0      = imbinarize(I_blur0, graythresh(I_blur0));
BW0      = imclearborder(BW0);
D0       = double(bwdist(~BW0));
fg_vals  = D0(BW0 > 0);

% Three percentile estimates → three spacing estimates → three counts
r_p90    = prctile(fg_vals, 90);   d_p90 = 2 * r_p90;
r_p95    = prctile(fg_vals, 95);   d_p95 = 2 * r_p95;
r_p99    = prctile(fg_vals, 99);   d_p99 = 2 * r_p99;

n_p90    = imgH * imgW * 0.5 / d_p90^2;
n_p95    = imgH * imgW * 0.5 / d_p95^2;
n_p99    = imgH * imgW * 0.5 / d_p99^2;

% Seed spacing: use the middle estimate for seed point derivation
d_est0   = d_p95;

% Geometric mean of the three estimates as the count target.
% More robust than any single percentile: the geometric mean is pulled
% toward the center of the plausible range and is insensitive to whether
% the "right" percentile is 90, 95, or 99 for this particular surface.
n_mid = (n_p90 * n_p95 * n_p99)^(1/3);

fprintf('Count estimates from distance transform:\n');
fprintf('  p90: %.1f px spacing -> %.0f mounds\n', d_p90, n_p90);
fprintf('  p95: %.1f px spacing -> %.0f mounds\n', d_p95, n_p95);
fprintf('  p99: %.1f px spacing -> %.0f mounds\n', d_p99, n_p99);
fprintf('  Geometric mean target: %.0f mounds\n', n_mid);

% Hard guardrail: only reject truly catastrophic failures
n_min = max(3, floor(n_mid * 0.1));
n_max = ceil(n_mid * 15);
fprintf('  Hard guardrail: [%d, %d] mounds\n', n_min, n_max);

% --- Define parameter search space ---------------------------------------
% clipLimit is fixed at 0.02 — the default value that works well across
% LSCM images and is never changed in practice. Removing it from the
% search space reduces dimensionality and improves convergence.
CLIP_LIMIT = 0.02;

vars = [
    optimizableVariable('gaussSigma',    [0.5, 15],   'Type', 'real')
    optimizableVariable('contrastMethod', {'none','histeq','adapthisteq'}, ...
                                                       'Type', 'categorical')
    optimizableVariable('openRadius',    [1,  25],     'Type', 'integer')
];

% --- Objective function --------------------------------------------------
obj = @(p) scoreParams(I, p, n_min, n_max, n_mid, CLIP_LIMIT, fillDeepPits, fillThreshold, dilateRadius, minObjectArea);

% --- Derive image-based seed point ---------------------------------------
% openRadius: structuring element should be ~5% of mound spacing
% gaussSigma: blur should smooth at mound scale (~8% of spacing)
% contrastMethod: 'histeq' is a safe default for LSCM images
seed_openRadius = max(1, min(25, round(d_est0 * 0.05)));
seed_gaussSigma = max(0.5, min(15, d_est0 * 0.08));
seedPoint = table(seed_gaussSigma, categorical({'histeq'}), seed_openRadius, ...
    'VariableNames', {'gaussSigma','contrastMethod','openRadius'});
fprintf('Image-derived seed: gaussSigma=%.1f  contrastMethod=histeq  openRadius=%d\n', ...
        seed_gaussSigma, seed_openRadius);

% Evaluate seed quality before committing to it.
% If the seed scores poorly (>= 0.6), it means the image-derived estimate
% is unreliable — fall back to broad exploration without a fixed seed.
seedScore = obj(seedPoint);
fprintf('Seed score: %.4f  ', seedScore);
if seedScore >= 0.6
    fprintf('(poor — falling back to broad exploration)\n');
    seedPoint = [];
else
    fprintf('(good — seeding optimizer)\n');
end

% --- Run Bayesian optimization -------------------------------------------
fprintf('\nStarting Bayesian optimization (%d evaluations)...\n', maxEvals);
bayesOpts = { ...
    'MaxObjectiveEvaluations',    maxEvals, ...
    'AcquisitionFunctionName',    'expected-improvement-plus', ...
    'IsObjectiveDeterministic',   true, ...
    'Verbose',                    1};

if showPlots
    bayesOpts = [bayesOpts, {'PlotFcn', {@plotObjectiveModel, @plotMinObjective}}];
else
    bayesOpts = [bayesOpts, {'PlotFcn', {}}];
end

if ~isempty(seedPoint)
    bayesOpts = [bayesOpts, {'InitialX', seedPoint}];
end

results = bayesopt(obj, vars, bayesOpts{:});

% --- Extract and display best parameters ---------------------------------
bestParams = bestPoint(results);
fprintf('\n========== Best parameters ==========\n');
disp(bestParams);

% --- Run final pipeline with best params and visualize -------------------
% Re-inject fixed clipLimit since bestPoint() only returns optimized columns
bestParams.clipLimit = CLIP_LIMIT;
[~, centroids] = runPipeline(I, bestParams, fillDeepPits, fillThreshold, dilateRadius, minObjectArea);
if showPlots
    visualizeResult(I, centroids, bestParams, results);
end

end % autoTuneMounds


% =========================================================================
%  OBJECTIVE FUNCTION
% =========================================================================
function score = scoreParams(I, p, n_min, n_max, n_mid, clipLimit, fillDeepPits, fillThreshold, dilateRadius, minObjectArea)

    try
        % Inject fixed clipLimit into params table for pipeline
        p.clipLimit = clipLimit;
        [~, centroids] = runPipeline(I, p, fillDeepPits, fillThreshold, dilateRadius, minObjectArea);
        n = size(centroids, 1);

        % Hard guardrail: reject obviously absurd counts (total pipeline failure)
        if n < n_min || n > n_max
            score = 100; return;
        end

        % --- Delaunay NN distances (trimmed) ---------------------------------
        dt    = delaunayTriangulation(centroids(:,1), centroids(:,2));
        edg   = dt.edges();
        d1    = centroids(edg(:,1), :);
        d2    = centroids(edg(:,2), :);
        dists = sqrt(sum((d1 - d2).^2, 2));
        med   = median(dists);
        dists = dists(dists < 2.5 * med);

        % --- Metric 1: spacing regularity (CV) — primary signal -------------
        cv = std(dists) / mean(dists);

        % --- Metric 2: continuous log penalty toward geometric mean count ----
        % Uses log(n/n_mid)^2 — a symmetric, smooth penalty minimised at
        % n_mid and growing gently in both directions. Unlike a point target
        % it's robust to percentile choice (n_mid is a geometric mean of 3
        % estimates). Unlike a flat band it always provides a soft pull toward
        % the plausible count range, preventing CV-only local minima.
        % Weight 0.5: enough to prefer correct count over spuriously low CV
        % from over-merged detections, without overriding genuine CV signal.
        count_penalty = log(n / n_mid)^2;

        % --- Diagnostic --------------------------------------------------
        fprintf('n=%d  n_mid=%.0f  cv=%.3f  cp=%.3f  score=%.3f\n', ...
                n, n_mid, cv, count_penalty, cv + 0.5*count_penalty);

        % --- Combined score --------------------------------------------------
        score = cv + 0.5 * count_penalty;

    catch ME
        warning('scoreParams:pipelineError', '%s', ME.message);
        score = 100;
    end

end


% =========================================================================
%  PIPELINE  (mirrors your exact code)
% =========================================================================
function [fgm4, centroids] = runPipeline(I, p, fillDeepPits, fillThreshold, dilateRadius, minObjectArea)

    % 1. Gaussian blur
    % Cast to double here so all downstream functions (imreconstruct,
    % histeq, adapthisteq) receive consistent types regardless of MATLAB
    % version or image codec behaviour.
    Iblur = imgaussfilt(double(I), double(p.gaussSigma));

    % 2. Contrast enhancement
    mask = double(applyContrast(Iblur, char(p.contrastMethod), double(p.clipLimit)));

    % 3. Morphological open/close by reconstruction
    Iobrcbr = preprocessImage(mask, double(p.openRadius));

    % 4. Regional maxima extraction (dilateRadius and minObjectArea are fixed inputs)
    fgm4 = extractRegionalMaxima(Iobrcbr, dilateRadius, minObjectArea, ...
                                  fillDeepPits, Iblur, fillThreshold);

    % 5. Centroid extraction  (your exact chain)
    BW     = imclearborder(fgm4);
    stats  = regionprops(BW, 'Centroid');
    if isempty(stats)
        centroids = zeros(0, 2);
    else
        centroids = double(cat(1, stats.Centroid));  % ensure double for delaunayTriangulation
    end

end


% =========================================================================
%  YOUR EXISTING SUB-FUNCTIONS (unchanged)
% =========================================================================
function mask = applyContrast(I, method, clipLimit)
    switch method
        case 'none',        mask = I;
        case 'histeq',      mask = histeq(I);
        case 'adapthisteq', mask = adapthisteq(I, 'clipLimit', clipLimit, ...
                                               'Distribution', 'rayleigh');
        otherwise,          mask = I;
    end
end

function Iobrcbr = preprocessImage(mask, radius)
    se       = strel('disk', radius);
    Ie       = imerode(mask, se);
    Iobr     = imreconstruct(Ie, mask);
    Iobrd    = imdilate(Iobr, se);
    Iobrcbr  = imreconstruct(imcomplement(Iobrd), imcomplement(Iobr));
    Iobrcbr  = imcomplement(Iobrcbr);
end

function fgm4 = extractRegionalMaxima(Iobrcbr, dilateRadius, minArea, ...
                                       fillDeepPits, Iblur, fillThreshold)
    fgm  = imregionalmax(Iobrcbr);
    se   = strel('disk', dilateRadius);
    fgm2 = imclose(fgm, se);
    fgm3 = imdilate(fgm2, se);
    fgm4 = bwareaopen(fgm3, minArea);
    if fillDeepPits
        filled = imcomplement(imfill(imcomplement( ...
                     imbinarize(Iblur, fillThreshold)), 'holes'));
        fgm4   = and(filled, fgm4);
    end
end





% =========================================================================
%  VISUALIZATION
% =========================================================================
function visualizeResult(I, centroids, bestParams, results)

    n = size(centroids, 1);

    figure('Name', 'autoTuneMounds — Result', ...
           'Position', [80 80 1500 500], ...
           'Color', [0.15 0.15 0.15]);

    % --- Panel 1: detected mounds overlaid on image ----------------------
    subplot(1, 3, 1);
    imshow(I, []); hold on;
    if n > 0
        plot(centroids(:,1), centroids(:,2), ...
             'r+', 'MarkerSize', 5, 'LineWidth', 0.8);
    end
    title(sprintf('%d mounds detected', n), 'Color', 'w');
    set(gca, 'Color', 'k');

    % --- Panel 2: optimization convergence curve -------------------------
    subplot(1, 3, 2);
    obj_trace = results.ObjectiveTrace;
    best_so_far = cummin(obj_trace);
    plot(obj_trace,     'o', 'Color', [0.5 0.7 1.0], ...
         'MarkerSize', 4, 'MarkerFaceColor', [0.5 0.7 1.0]); hold on;
    plot(best_so_far,   '-', 'Color', [1.0 0.6 0.2], 'LineWidth', 2);
    xlabel('Evaluation #');
    ylabel('Score (lower = better)');
    t2 = title('Bayesian optimization convergence'); t2.Color = 'w';
    legend({'All evals', 'Best so far'}, 'Location', 'northeast');
    grid on;
    set(gca, 'Color', [0.1 0.1 0.1], 'GridColor', [0.3 0.3 0.3], ...
             'XColor', 'w', 'YColor', 'w');

    % --- Panel 3: NN distance distribution via alpha shape Delaunay --------
    subplot(1, 3, 3);
    if n > 3
        dt       = delaunayTriangulation(centroids(:,1), centroids(:,2));
        all_edg  = dt.edges();
        d1all    = centroids(all_edg(:,1), :);
        d2all    = centroids(all_edg(:,2), :);
        init_alpha = median(sqrt(sum((d1all - d2all).^2, 2)));

        [S_alpha, ~] = computeAlphaShape(centroids, init_alpha);
        tris  = S_alpha.alphaTriangulation;
        if ~isempty(tris)
            edg   = unique(sort([tris(:,[1 2]); tris(:,[2 3]); tris(:,[3 1])], 2), 'rows');
            d1    = centroids(edg(:,1), :);
            d2    = centroids(edg(:,2), :);
            dists = sqrt(sum((d1 - d2).^2, 2));
        else
            % fallback to median trimming if alpha shape fails
            dists_all = sqrt(sum((d1all - d2all).^2, 2));
            dists     = dists_all(dists_all < 2.5 * median(dists_all));
        end

        histogram(dists, 40, 'FaceColor', [0.3 0.6 0.9], ...
                  'EdgeColor', 'none', 'FaceAlpha', 0.85);
        xline(mean(dists), 'r-', 'LineWidth', 1.5, 'Label', ...
              sprintf('mean=%.1f px', mean(dists)));
        xlabel('NN distance (px)');
        ylabel('Edge count');
        t3 = title(sprintf('NN spacing  |  CV = %.3f', std(dists)/mean(dists))); t3.Color = 'w';
        grid on;
        set(gca, 'Color', [0.1 0.1 0.1], 'GridColor', [0.3 0.3 0.3], ...
                 'XColor', 'w', 'YColor', 'w');
    else
        text(0.5, 0.5, 'Too few mounds for Delaunay', ...
             'HorizontalAlignment', 'center', 'Color', 'w');
        axis off;
    end

    sgtitle(sprintf('Best: sigma=%.2f  contrast=%s  openR=%d', ...
        bestParams.gaussSigma, char(bestParams.contrastMethod), ...
        bestParams.openRadius), ...
        'Color', 'w', 'FontSize', 10);

end

% =========================================================================
%  ALPHA SHAPE WITH ITERATIVE CONVERGENCE  (shared with analyzeMounds)
% =========================================================================
function [S, alpha] = computeAlphaShape(points, initialAlpha)
    MAX_ITER  = 50;
    TOL       = 0.1;
    MAX_HOLES = 10;
    HOLE_BUMP = 1.10;

    prevAlpha = 0;
    currAlpha = initialAlpha;
    iter      = 0;

    while abs(prevAlpha - currAlpha) > TOL && iter < MAX_ITER
        prevAlpha = currAlpha;
        S         = alphaShape(points, prevAlpha);
        tris = S.alphaTriangulation;
        if isempty(tris)
            currAlpha = prevAlpha * 2;
            continue;
        end
        edges     = unique(sort([tris(:,[1 2]); tris(:,[2 3]); tris(:,[3 1])], 2), 'rows');
        lengths   = sqrt(sum((points(edges(:,1),:) - points(edges(:,2),:)).^2, 2));
        currAlpha = median(lengths);
        iter      = iter + 1;
    end

    S = alphaShape(points, currAlpha);

    hole_iter = 0;
    % Detect interior holes by checking boundary edge connectivity.
    % boundaryFacets returns Mx2 edge indices. If the boundary forms more
    % than one connected loop (outer + holes), the edge graph has multiple
    % connected components. We count those components to detect holes.
    % More than 1 region also catches fragmented outer shapes.
    while (countBoundaryLoops(S) > 1 || numRegions(S) > 1) && hole_iter < MAX_HOLES
        currAlpha = currAlpha * HOLE_BUMP;
        S         = alphaShape(points, currAlpha);
        hole_iter = hole_iter + 1;
    end
    alpha = currAlpha;
end

% =========================================================================
%  COUNT BOUNDARY LOOPS (hole detection via boundaryFacets)
% =========================================================================
function n = countBoundaryLoops(S)
% Returns the number of boundary loops in a 2D alpha shape.
% 1 = no holes (simply connected). >1 = interior holes present.
% Counts connected components of the boundary edge graph using union-find
% with inline path compression (no nested functions — MATLAB restriction).
    try
        bf = boundaryFacets(S);
        if isempty(bf)
            n = 0; return;
        end
        nodes   = unique(bf(:));
        n_nodes = numel(nodes);
        [~, ia] = ismember(bf, nodes);   % remap to 1..n_nodes
        parent  = 1:n_nodes;

        % Union-find: merge components for each edge
        for k = 1:size(ia, 1)
            % Find root of ia(k,1) with path compression
            x = ia(k,1);
            while parent(x) ~= x, x = parent(x); end
            ra = x;
            % Find root of ia(k,2) with path compression
            x = ia(k,2);
            while parent(x) ~= x, x = parent(x); end
            rb = x;
            if ra ~= rb, parent(ra) = rb; end
        end

        % Count unique roots
        roots = zeros(1, n_nodes);
        for i = 1:n_nodes
            x = i;
            while parent(x) ~= x, x = parent(x); end
            roots(i) = x;
        end
        n = numel(unique(roots));
    catch
        n = 1;   % assume no holes if boundaryFacets fails
    end
end
