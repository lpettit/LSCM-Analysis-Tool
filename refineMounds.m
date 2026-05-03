function bestParams = refineMounds(imagePath, fillDeepPits, fillThreshold, ...
                                    dilateRadius, minObjectArea, initParams, n_mid_init)
% =========================================================================
%  refineMounds  —  Tiered guided refinement of mound detection parameters
%
%  Run this after autoTuneMounds if the automatic result is unsatisfactory.
%  Implements three tiers of increasing user involvement:
%
%  Tier 1 (automatic):  Already done by autoTuneMounds. refineMounds starts
%                       at Tier 2.
%
%  Tier 2 (directional nudge):  Shows detection overlay. User says
%                                "too few", "about right", or "too many".
%                                Updates n_mid using binary search logic
%                                and re-runs 30 bayesopt evaluations.
%                                Repeats up to MAX_NUDGES times.
%
%  Tier 3 (manual count):  User enters approximate expected count directly.
%                           Re-runs 30 evaluations with that as n_mid.
%                           Repeats until user is satisfied.
%
%  USAGE:
%    % After autoTuneMounds returns unsatisfactory result:
%    bestParams = autoTuneMounds('img.vk4', false, 0.3, 3, 20);
%    bestParams = refineMounds('img.vk4', false, 0.3, 3, 20, bestParams, n_mid)
%
%    % n_mid comes from autoTuneMounds console output (geometric mean target)
%    % Accepts .vk4 or image (.bmp/.tif/.png) — same file as autoTuneMounds.
%
%  INPUTS:
%    imagePath     - path to .vk4 file OR grayscale/RGB image (.bmp/.tif/.png)
%    fillDeepPits  - boolean (same as autoTuneMounds)
%    fillThreshold - pit fill threshold (same as autoTuneMounds)
%    dilateRadius  - fixed dilation radius (same as autoTuneMounds)
%    minObjectArea - minimum blob area (same as autoTuneMounds)
%    initParams    - bestParams table from autoTuneMounds (seed for refinement)
%    n_mid_init    - geometric mean count target from autoTuneMounds output
%
%  OUTPUT:
%    bestParams    - refined parameter table, same format as autoTuneMounds
%
%  FIXED: clipLimit = 0.02
%  OPTIMIZED: gaussSigma, contrastMethod, openRadius
% =========================================================================

CLIP_LIMIT  = 0.02;
REFINE_EVALS = 30;       % bayesopt evaluations per refinement pass
MAX_NUDGES   = 3;        % max Tier 2 nudge attempts before escalating to Tier 3
NUDGE_FACTOR = 1.3;      % multiplier when only one bracket bound is known

% --- Load image -----------------------------------------------------------
% VK4 or image: detection pipeline only needs normalised [0,1] intensities.
[~, ~, imageExt] = fileparts(imagePath);
if strcmpi(imageExt, '.vk4')
    if ~exist('readVK4', 'file')
        error(['refineMounds: readVK4.m not found on MATLAB path.\n' ...
               'Required for .vk4 input. Add readVK4.m and the vk4mat\n' ...
               'library (https://github.com/matt-black/vk4mat) to path.']);
    end
    [Z_load, ~, total_h, imgH, imgW] = readVK4(imagePath);
    I_raw = uint8(round(Z_load / total_h * 255));
    clear Z_load total_h;
else
    I_raw = imread(imagePath);
    if size(I_raw, 3) == 3, I_raw = rgb2gray(I_raw); end
    [imgH, imgW] = size(I_raw);
end
I = double(I_raw) / 255;

% Ensure clipLimit is in initParams
initParams.clipLimit = CLIP_LIMIT;

% Hard guardrail (wide — only blocks catastrophic failures)
n_min = 3;
n_max = imgH * imgW / 10^2;   % max 1 mound per 10x10 px patch

% --- Search space (same as autoTuneMounds, clipLimit fixed) ---------------
vars = [
    optimizableVariable('gaussSigma',    [0.5, 15],   'Type', 'real')
    optimizableVariable('contrastMethod', {'none','histeq','adapthisteq'}, ...
                                          'Type', 'categorical')
    optimizableVariable('openRadius',    [1,  25],     'Type', 'integer')
];

% --- State for binary search bracket ------------------------------------
% n_lo: highest count user said was "too few"   (lower bound on true count)
% n_hi: lowest count user said was "too many"   (upper bound on true count)
n_lo      = 0;      % unknown lower bound initially
n_hi      = Inf;    % unknown upper bound initially
n_mid     = n_mid_init;
bestParams = initParams;
nudge_count = 0;

fprintf('\n========== refineMounds ==========\n');
fprintf('Starting from n_mid = %.0f\n', n_mid);
fprintf('Initial params: sigma=%.2f  contrast=%s  openR=%d\n\n', ...
        initParams.gaussSigma, char(initParams.contrastMethod), initParams.openRadius);

% =========================================================================
%  TIER 2 — DIRECTIONAL NUDGE LOOP
% =========================================================================
while nudge_count <= MAX_NUDGES

    % --- Run detection with current bestParams and show overlay -----------
    [~, centroids] = runPipeline(I, bestParams, fillDeepPits, fillThreshold, ...
                                  dilateRadius, minObjectArea);
    n_current = size(centroids, 1);

    showOverlay(I, centroids, bestParams, n_current, n_mid, nudge_count);

    % --- Ask user for feedback --------------------------------------------
    if nudge_count < MAX_NUDGES
        fprintf('Current detection: %d mounds  |  n_mid target: %.0f\n', ...
                n_current, n_mid);
        fprintf('Does this look correct?\n');
        fprintf('  [1] About right — done\n');
        fprintf('  [2] Too few mounds detected\n');
        fprintf('  [3] Too many mounds detected\n');
        fprintf('  [4] Skip to manual count entry (Tier 3)\n');
        response = getValidInput('Enter choice (1/2/3/4): ', [1 2 3 4]);
    else
        % Max nudges reached — force Tier 3
        fprintf('Maximum nudge attempts reached. Proceeding to manual count entry.\n');
        response = 4;
    end

    if response == 1
        % User is satisfied — done
        fprintf('\nRefinement complete. Final count: %d mounds\n', n_current);
        fprintf('Final params: sigma=%.2f  contrast=%s  openR=%d\n', ...
                bestParams.gaussSigma, char(bestParams.contrastMethod), bestParams.openRadius);
        return;

    elseif response == 4
        % Escalate to Tier 3
        break;

    else
        % --- Update bracket and compute new n_mid -------------------------
        if response == 2
            % Too few: current count is a lower bound
            n_lo = max(n_lo, n_current);
            fprintf('  Noted: %d is too few. Lower bound updated to %.0f.\n', ...
                    n_current, n_lo);
        elseif response == 3
            % Too many: current count is an upper bound
            n_hi = min(n_hi, n_current);
            fprintf('  Noted: %d is too many. Upper bound updated to %.0f.\n', ...
                    n_current, n_hi);
        end

        % Compute next n_mid using bracket
        if n_lo > 0 && ~isinf(n_hi)
            % Both bounds known — bisect
            n_mid_new = (n_lo + n_hi) / 2;
            fprintf('  Both bounds known [%.0f, %.0f] — bisecting to n_mid = %.0f\n', ...
                    n_lo, n_hi, n_mid_new);
        elseif n_lo > 0
            % Only lower bound — nudge up
            n_mid_new = n_lo * NUDGE_FACTOR;
            fprintf('  Only lower bound known — nudging up to n_mid = %.0f\n', n_mid_new);
        else
            % Only upper bound — nudge down
            n_mid_new = n_hi / NUDGE_FACTOR;
            fprintf('  Only upper bound known — nudging down to n_mid = %.0f\n', n_mid_new);
        end

        n_mid     = n_mid_new;
        nudge_count = nudge_count + 1;

        % --- Re-run optimization with updated n_mid ----------------------
        fprintf('\n  Re-running optimization (%d evals, seeded from current best)...\n', ...
                REFINE_EVALS);

        seedRow = table(bestParams.gaussSigma, ...
                        categorical({char(bestParams.contrastMethod)}), ...
                        bestParams.openRadius, ...
                        'VariableNames', {'gaussSigma','contrastMethod','openRadius'});

        % Tier 2: soft quadratic penalty, weight 0.5 (n_mid is an estimate)
        obj = @(p) scoreParams(I, p, n_min, n_max, n_mid, CLIP_LIMIT, ...
                               fillDeepPits, fillThreshold, dilateRadius, minObjectArea, ...
                               0.5, false);

        results = bayesopt(obj, vars, ...
            'MaxObjectiveEvaluations',   REFINE_EVALS, ...
            'InitialX',                  seedRow, ...
            'AcquisitionFunctionName',   'expected-improvement-plus', ...
            'IsObjectiveDeterministic',  true, ...
            'Verbose',                   0, ...
            'PlotFcn',                   []);   % suppress plots during refinement

        bestParams_new      = bestPoint(results);
        bestParams_new.clipLimit = CLIP_LIMIT;
        bestParams          = bestParams_new;

        fprintf('  Done. New params: sigma=%.2f  contrast=%s  openR=%d\n', ...
                bestParams.gaussSigma, char(bestParams.contrastMethod), bestParams.openRadius);
    end
end

% =========================================================================
%  TIER 3 — MANUAL COUNT ENTRY
% =========================================================================
fprintf('\n========== Tier 3: Manual count entry ==========\n');
fprintf('Enter your approximate expected mound count.\n');
fprintf('This becomes the optimization target directly.\n');
fprintf('Type 0 at any point to accept the current result.\n\n');

while true
    [~, centroids] = runPipeline(I, bestParams, fillDeepPits, fillThreshold, ...
                                  dilateRadius, minObjectArea);
    n_current = size(centroids, 1);

    showOverlay(I, centroids, bestParams, n_current, n_mid, -1);

    fprintf('Current detection: %d mounds\n', n_current);
    user_count = input('Enter expected count (or 0 to accept current result): ');

    if isempty(user_count) || user_count == 0
        fprintf('\nAccepted. Final count: %d mounds\n', n_current);
        fprintf('Final params: sigma=%.2f  contrast=%s  openR=%d\n', ...
                bestParams.gaussSigma, char(bestParams.contrastMethod), bestParams.openRadius);
        return;
    end

    n_mid = double(user_count);
    fprintf('  Target set to %d. Re-running optimization (%d evals)...\n', ...
            user_count, REFINE_EVALS);

    seedRow = table(bestParams.gaussSigma, ...
                    categorical({char(bestParams.contrastMethod)}), ...
                    bestParams.openRadius, ...
                    'VariableNames', {'gaussSigma','contrastMethod','openRadius'});

    % Tier 3: linear penalty, weight 2.0 — user count is trusted as ground truth.
    % |log(n/n_mid)| with weight 2.0 means a 20% count deviation adds 0.36
    % to the score, comfortably overriding any CV advantage from merging.
    obj = @(p) scoreParams(I, p, n_min, n_max, n_mid, CLIP_LIMIT, ...
                           fillDeepPits, fillThreshold, dilateRadius, minObjectArea, ...
                           2.0, true);

    results = bayesopt(obj, vars, ...
        'MaxObjectiveEvaluations',   REFINE_EVALS, ...
        'InitialX',                  seedRow, ...
        'AcquisitionFunctionName',   'expected-improvement-plus', ...
        'IsObjectiveDeterministic',  true, ...
        'Verbose',                   0, ...
        'PlotFcn',                   []);

    bestParams_new           = bestPoint(results);
    bestParams_new.clipLimit = CLIP_LIMIT;
    bestParams               = bestParams_new;

    fprintf('  Done. New params: sigma=%.2f  contrast=%s  openR=%d\n', ...
            bestParams.gaussSigma, char(bestParams.contrastMethod), bestParams.openRadius);
end

end % refineMounds


% =========================================================================
%  OVERLAY VISUALIZATION
% =========================================================================
function showOverlay(I, centroids, bestParams, n_current, n_mid, tier)
    fig = figure('Name', sprintf('refineMounds — %d mounds', n_current), ...
                 'Position', [100 100 1000 450], 'Color', [0.15 0.15 0.15]);

    % --- Panel 1: detection overlay --------------------------------------
    subplot(1, 2, 1);
    imshow(I, []); hold on;
    if ~isempty(centroids)
        plot(centroids(:,1), centroids(:,2), 'r+', ...
             'MarkerSize', 6, 'LineWidth', 1.0);
    end
    if tier >= 0
        title(sprintf('Tier 2 nudge #%d  |  %d mounds detected  |  target ~%.0f', ...
              tier+1, n_current, n_mid), 'Color', 'w', 'FontSize', 9);
    else
        title(sprintf('Tier 3  |  %d mounds detected  |  target %.0f', ...
              n_current, n_mid), 'Color', 'w', 'FontSize', 9);
    end
    set(gca, 'Color', 'k');
    hold off;

    % --- Panel 2: NN spacing histogram via alpha shape -------------------
    subplot(1, 2, 2);
    n = size(centroids, 1);
    if n > 3
        dt      = delaunayTriangulation(centroids(:,1), centroids(:,2));
        all_edg = dt.edges();
        d1a     = centroids(all_edg(:,1), :);
        d2a     = centroids(all_edg(:,2), :);
        init_a  = median(sqrt(sum((d1a-d2a).^2, 2)));
        try
            [S_a, ~] = computeAlphaShape(centroids, init_a);
            tris = S_a.alphaTriangulation;
            if ~isempty(tris)
                edg   = unique(sort([tris(:,[1 2]);tris(:,[2 3]);tris(:,[3 1])],2),'rows');
                d1    = centroids(edg(:,1),:);
                d2    = centroids(edg(:,2),:);
                dists = sqrt(sum((d1-d2).^2,2));
            else
                dists_all = sqrt(sum((d1a-d2a).^2,2));
                dists = dists_all(dists_all < 2.5*median(dists_all));
            end
        catch
            dists_all = sqrt(sum((d1a-d2a).^2,2));
            dists = dists_all(dists_all < 2.5*median(dists_all));
        end
        histogram(dists, 35, 'FaceColor',[0.3 0.6 0.9], ...
                  'EdgeColor','none','FaceAlpha',0.85);
        xline(mean(dists), 'r-', 'LineWidth',1.5, ...
              'Label', sprintf('mean=%.1f px', mean(dists)));
        xlabel('NN distance (px)'); ylabel('Edge count');
        t = title(sprintf('NN spacing  |  CV=%.3f', std(dists)/mean(dists)));
        t.Color = 'w';
        grid on;
    else
        text(0.5,0.5,'Too few mounds','HorizontalAlignment','center','Color','w');
        axis off;
    end
    set(gca,'Color',[0.1 0.1 0.1],'GridColor',[0.3 0.3 0.3],...
            'XColor','w','YColor','w');

    sgtitle(sprintf('sigma=%.2f  contrast=%s  openR=%d', ...
            bestParams.gaussSigma, char(bestParams.contrastMethod), ...
            bestParams.openRadius), 'Color','w','FontSize',9);

    drawnow;
end


% =========================================================================
%  SAFE INPUT VALIDATION
% =========================================================================
function val = getValidInput(prompt, valid_vals)
    val = [];
    while isempty(val) || ~ismember(val, valid_vals)
        raw = input(prompt);
        if isnumeric(raw) && ismember(raw, valid_vals)
            val = raw;
        else
            fprintf('  Please enter one of: %s\n', num2str(valid_vals));
        end
    end
end


% =========================================================================
%  SCORING
% =========================================================================
function score = scoreParams(I, p, n_min, n_max, n_mid, clipLimit, ...
                              fillDeepPits, fillThreshold, dilateRadius, minObjectArea, ...
                              count_weight, linear_penalty)
% count_weight:   weight applied to count penalty (0.5 for Tier 2, 2.0 for Tier 3)
% linear_penalty: if true, use |log(n/n_mid)| (sharper); else log(n/n_mid)^2 (softer)
    if nargin < 11, count_weight   = 0.5;  end
    if nargin < 12, linear_penalty = false; end

    try
        p.clipLimit = clipLimit;
        [~, centroids] = runPipeline(I, p, fillDeepPits, fillThreshold, ...
                                      dilateRadius, minObjectArea);
        n = size(centroids, 1);

        if n < n_min || n > n_max
            score = 100; return;
        end

        dt    = delaunayTriangulation(centroids(:,1), centroids(:,2));
        edg   = dt.edges();
        d1    = centroids(edg(:,1), :);
        d2    = centroids(edg(:,2), :);
        dists = sqrt(sum((d1 - d2).^2, 2));
        med   = median(dists);
        dists = dists(dists < 2.5 * med);

        cv = std(dists) / mean(dists);

        if linear_penalty
            % Linear in log-space: grows faster, punishes deviations more aggressively.
            % Used in Tier 3 where user count is trusted as ground truth.
            count_penalty = abs(log(n / n_mid));
        else
            % Quadratic in log-space: flat near n_mid, grows gradually.
            % Used in Tiers 1/2 where n_mid is an estimate, not ground truth.
            count_penalty = log(n / n_mid)^2;
        end

        score = cv + count_weight * count_penalty;

    catch ME
        warning('scoreParams: pipeline error — %s', ME.message);
        score = 100;
    end
end


% =========================================================================
%  PIPELINE  (identical to autoTuneMounds)
% =========================================================================
function [fgm4, centroids] = runPipeline(I, p, fillDeepPits, fillThreshold, ...
                                          dilateRadius, minObjectArea)
    Iblur   = imgaussfilt(double(I), double(p.gaussSigma));
    mask    = double(applyContrast(Iblur, char(p.contrastMethod), double(p.clipLimit)));
    Iobrcbr = preprocessImage(mask, double(p.openRadius));
    fgm4    = extractRegionalMaxima(Iobrcbr, dilateRadius, minObjectArea, ...
                                    fillDeepPits, Iblur, fillThreshold);
    BW      = imclearborder(fgm4);
    stats   = regionprops(BW, 'Centroid');
    if isempty(stats)
        centroids = zeros(0, 2);
    else
        centroids = double(cat(1, stats.Centroid));
    end
end

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
    se      = strel('disk', radius);
    Ie      = imerode(mask, se);
    Iobr    = imreconstruct(Ie, mask);
    Iobrd   = imdilate(Iobr, se);
    Iobrcbr = imreconstruct(imcomplement(Iobrd), imcomplement(Iobr));
    Iobrcbr = imcomplement(Iobrcbr);
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
%  ALPHA SHAPE (identical to autoTuneMounds / analyzeMounds)
% =========================================================================
function [S, alpha] = computeAlphaShape(points, initialAlpha)
    MAX_ITER  = 50; TOL = 0.1; MAX_HOLES = 10; HOLE_BUMP = 1.10;
    prevAlpha = 0; currAlpha = initialAlpha; iter = 0;
    while abs(prevAlpha - currAlpha) > TOL && iter < MAX_ITER
        prevAlpha = currAlpha;
        S    = alphaShape(points, prevAlpha);
        tris = S.alphaTriangulation;
        if isempty(tris), currAlpha = prevAlpha * 2; continue; end
        edg   = unique(sort([tris(:,[1 2]);tris(:,[2 3]);tris(:,[3 1])],2),'rows');
        lens  = sqrt(sum((points(edg(:,1),:)-points(edg(:,2),:)).^2,2));
        currAlpha = median(lens);
        iter  = iter + 1;
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
        S = alphaShape(points, currAlpha);
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