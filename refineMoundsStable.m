function bestParams = refineMoundsStable(imagePath, fillDeepPits, fillThreshold, ...
                                    dilateRadius, minObjectArea, initParams, n_mid_init, rngSeed)
% =========================================================================
%  refineMounds  —  Tiered guided refinement of mound detection parameters
%
%  Runs stable automatic mound tuning first when no initial parameter table
%  is provided, then shows the initial centroid and spacing review figure.
%
%  Tier 1 (automatic):  Stable scale-locked automatic tuning.
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
%    % Recommended interactive workflow:
%    bestParams = refineMoundsStable('img.vk4', false, 0.3, 3, 20)
%
%    % Legacy refinement-only workflow:
%    bestParams = refineMoundsStable('img.vk4', false, 0.3, 3, 20, initParams, n_mid)
%    % Accepts .vk4 or image (.bmp/.tif/.png) — same file as autoTuneMounds.
%
%  INPUTS:
%    imagePath     - path to .vk4 file OR grayscale/RGB image (.bmp/.tif/.png)
%    fillDeepPits  - boolean (same as autoTuneMoundsStable)
%    fillThreshold - pit fill threshold (same as autoTuneMoundsStable)
%    dilateRadius  - fixed dilation radius (same as autoTuneMoundsStable)
%    minObjectArea - minimum blob area (same as autoTuneMoundsStable)
%    initParams    - optional bestParams table from autoTuneMoundsStable
%    n_mid_init    - optional geometric mean count target
%    rngSeed       - optional fixed random seed for repeatable bayesopt passes
%
%  OUTPUT:
%    bestParams    - refined parameter table, same format as autoTuneMoundsStable,
%                    saved as bestParams.mat beside the input image
%
%  FIXED: clipLimit = 0.02
%  OPTIMIZED: morphScale, contrastMethod
%  DERIVED: gaussSigma, openRadius from estimated mound spacing
% =========================================================================

CLIP_LIMIT  = 0.02;
BASE_GAUSS_FRACTION = 0.08;
BASE_OPEN_FRACTION = 0.05;
REFINE_EVALS = 30;       % bayesopt evaluations per refinement pass
INITIAL_EVALS = 60;      % bayesopt evaluations for standalone auto-tune
TIER2_COUNT_WEIGHT = 1.25;
TIER3_COUNT_WEIGHT = 2.0;
MAX_NUDGES   = 3;        % max Tier 2 nudge attempts before escalating to Tier 3
NUDGE_FACTOR = 1.3;      % multiplier when only one bracket bound is known
COUNT_BAND_MARGIN = 0.10;
if nargin < 6, initParams = []; end
if nargin < 7, n_mid_init = []; end
if nargin < 8 || isempty(rngSeed), rngSeed = 1; end
if isnumeric(initParams) && isscalar(initParams) && isempty(n_mid_init)
    INITIAL_EVALS = initParams;
    initParams = [];
end

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

% Estimate the same scale anchor and plausible count band used by
% autoTuneMoundsStable.
I_blur0  = imgaussfilt(I, 2.0);
BW0      = imbinarize(I_blur0, graythresh(I_blur0));
BW0      = imclearborder(BW0);
D0       = double(bwdist(~BW0));
fg_vals  = D0(BW0 > 0);

r_p90 = prctile(fg_vals, 90); d_p90 = 2 * r_p90;
r_p95 = prctile(fg_vals, 95); d_p95 = 2 * r_p95;
r_p99 = prctile(fg_vals, 99); d_p99 = 2 * r_p99;

n_p90 = imgH * imgW * 0.5 / d_p90^2;
n_p95 = imgH * imgW * 0.5 / d_p95^2;
n_p99 = imgH * imgW * 0.5 / d_p99^2;

d_est0 = d_p95;
n_geom = (n_p90 * n_p95 * n_p99)^(1/3);
n_weighted_p95_p99 = (n_p95 * n_p99^2)^(1/3);

seedDiag = estimateSeedCountDiagnostic(I, d_est0, fillDeepPits, fillThreshold);
seedOverGeom = seedDiag.nAfterSpacing / max(n_geom, eps);
seedBandCandidates = [];
if seedOverGeom <= 1.5
    seedBandCandidates = seedDiag.nAfterSpacing;
end

if isempty(n_mid_init)
    n_mid_init = n_geom;
end
countBand = buildPlausibleCountBand(n_p99, n_weighted_p95_p99, n_geom, ...
    seedBandCandidates, COUNT_BAND_MARGIN);

fprintf('refineMoundsStable count setup:\n');
fprintf('  distance targets: p90=%.0f  p95=%.0f  p99=%.0f  geometric=%.0f\n', ...
        n_p90, n_p95, n_p99, n_geom);
fprintf('  seed diagnostic: h=%.3f  spaced=%d  seed/geometric=%.2f\n', ...
        seedDiag.hSeed, seedDiag.nAfterSpacing, seedOverGeom);
fprintf('  initial scoring band: [%d, %d] mounds\n', countBand(1), countBand(2));

% Ensure initParams has stable scale-locked fields.
if ~isempty(initParams)
    initParams = ensureScaleLockedParams(initParams, d_est0, CLIP_LIMIT, ...
        BASE_GAUSS_FRACTION, BASE_OPEN_FRACTION);
end

% Hard guardrail (wide — only blocks catastrophic failures)
n_min = 3;
n_max = imgH * imgW / 10^2;   % max 1 mound per 10x10 px patch

% --- Search space (same as autoTuneMoundsStable, clipLimit fixed) ---------
vars = [
    optimizableVariable('morphScale',    [0.5, 3.0],  'Type', 'real')
    optimizableVariable('contrastMethod', {'none','histeq','adapthisteq'}, ...
                                          'Type', 'categorical')
];

% --- Tier 1: standalone stable auto-tune when no seed params were passed --
if isempty(initParams)
    fprintf('\n========== Tier 1: Stable automatic tuning ==========\n');
    fprintf('No initParams supplied. Running internal stable auto-tune (%d evaluations).\n', ...
            INITIAL_EVALS);
    fprintf('Using fixed optimizer RNG seed: %d\n', rngSeed);

    auto_n_min = max(3, floor(n_mid_init * 0.1));
    auto_n_max = ceil(n_mid_init * 15);

    seed_morphScale = 1.0;
    seedParams = deriveScaleLockedParams( ...
        table(seed_morphScale, categorical({'histeq'}), ...
        'VariableNames', {'morphScale','contrastMethod'}), ...
        d_est0, CLIP_LIMIT, BASE_GAUSS_FRACTION, BASE_OPEN_FRACTION);
    seedPoint = seedParams(:, {'morphScale','contrastMethod'});

    autoObj = @(p) scoreParams(I, p, auto_n_min, auto_n_max, n_mid_init, countBand, ...
                               d_est0, CLIP_LIMIT, fillDeepPits, fillThreshold, ...
                               dilateRadius, minObjectArea, 0.5, false);

    seedScore = autoObj(seedPoint);
    fprintf('Image-derived seed: morphScale=%.2f  sigma=%.2f  contrast=histeq  openR=%d\n', ...
            seedParams.morphScale, seedParams.gaussSigma, seedParams.openRadius);
    fprintf('Seed score: %.4f', seedScore);
    if seedScore >= 0.6
        fprintf(' (poor - falling back to broad exploration)\n');
        seedPoint = [];
    else
        fprintf(' (good - seeding optimizer)\n');
    end

    bayesOpts = { ...
        'MaxObjectiveEvaluations',   INITIAL_EVALS, ...
        'AcquisitionFunctionName',   'expected-improvement-plus', ...
        'IsObjectiveDeterministic',  true, ...
        'Verbose',                   1, ...
        'PlotFcn',                   []};
    if ~isempty(seedPoint)
        bayesOpts = [bayesOpts, {'InitialX', seedPoint}];
    end

    previousRngState = rng;
    rng(rngSeed, 'twister');
    cleanupRng = onCleanup(@() rng(previousRngState));
    results = bayesopt(autoObj, vars, bayesOpts{:});
    clear cleanupRng

    initParams = selectStableBestParams(results, I, auto_n_min, auto_n_max, n_mid_init, countBand, ...
        d_est0, CLIP_LIMIT, fillDeepPits, fillThreshold, dilateRadius, minObjectArea, ...
        BASE_GAUSS_FRACTION, BASE_OPEN_FRACTION, 0.5, false);
end

% --- State for binary search bracket ------------------------------------
% n_lo: highest count user said was "too few"   (lower bound on true count)
% n_hi: lowest count user said was "too many"   (upper bound on true count)
n_lo      = 0;      % unknown lower bound initially
n_hi      = Inf;    % unknown upper bound initially
n_mid     = n_mid_init;
bestParams = initParams;
nudge_count = 0;
skipTier3InitialOverlay = false;

fprintf('\n========== refineMoundsStable ==========\n');
fprintf('Starting from n_mid = %.0f\n', n_mid);
fprintf('Initial params: morphScale=%.2f  sigma=%.2f  contrast=%s  openR=%d\n\n', ...
        initParams.morphScale, initParams.gaussSigma, char(initParams.contrastMethod), initParams.openRadius);

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
        fprintf('Final params: morphScale=%.2f  sigma=%.2f  contrast=%s  openR=%d\n', ...
                bestParams.morphScale, bestParams.gaussSigma, char(bestParams.contrastMethod), bestParams.openRadius);
        saveBestParams(imagePath, bestParams);
        return;

    elseif response == 4
        % Escalate to Tier 3
        skipTier3InitialOverlay = true;
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
        countBand = buildTargetCountBand(n_mid, COUNT_BAND_MARGIN);
        nudge_count = nudge_count + 1;

        % --- Re-run optimization with updated n_mid ----------------------
        fprintf('\n  Re-running optimization (%d evals, seeded from current best)...\n', ...
                REFINE_EVALS);

        seedRow = table(bestParams.morphScale, ...
                        categorical({char(bestParams.contrastMethod)}), ...
                        'VariableNames', {'morphScale','contrastMethod'});

        % Tier 2: broad plausible-count band, matching autoTuneMoundsStable.
        obj = @(p) scoreParams(I, p, n_min, n_max, n_mid, countBand, d_est0, CLIP_LIMIT, ...
                               fillDeepPits, fillThreshold, dilateRadius, minObjectArea, ...
                               TIER2_COUNT_WEIGHT, false);

        previousRngState = rng;
        rng(rngSeed + nudge_count, 'twister');
        cleanupRng = onCleanup(@() rng(previousRngState));
        results = bayesopt(obj, vars, ...
            'MaxObjectiveEvaluations',   REFINE_EVALS, ...
            'InitialX',                  seedRow, ...
            'AcquisitionFunctionName',   'expected-improvement-plus', ...
            'IsObjectiveDeterministic',  true, ...
            'Verbose',                   0, ...
            'PlotFcn',                   []);   % suppress plots during refinement
        clear cleanupRng

        bestParams_new      = selectStableBestParams(results, I, n_min, n_max, n_mid, countBand, d_est0, ...
            CLIP_LIMIT, fillDeepPits, fillThreshold, dilateRadius, minObjectArea, ...
            BASE_GAUSS_FRACTION, BASE_OPEN_FRACTION, TIER2_COUNT_WEIGHT, false);
        bestParams          = bestParams_new;

        fprintf('  Done. New params: morphScale=%.2f  sigma=%.2f  contrast=%s  openR=%d\n', ...
                bestParams.morphScale, bestParams.gaussSigma, char(bestParams.contrastMethod), bestParams.openRadius);
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
    if skipTier3InitialOverlay
        skipTier3InitialOverlay = false;
    else
        [~, centroids] = runPipeline(I, bestParams, fillDeepPits, fillThreshold, ...
                                      dilateRadius, minObjectArea);
        n_current = size(centroids, 1);

        showOverlay(I, centroids, bestParams, n_current, n_mid, -1);
    end

    fprintf('Current detection: %d mounds\n', n_current);
    user_count = input('Enter expected count (or 0 to accept current result): ');

    if isempty(user_count) || user_count == 0
        fprintf('\nAccepted. Final count: %d mounds\n', n_current);
        fprintf('Final params: morphScale=%.2f  sigma=%.2f  contrast=%s  openR=%d\n', ...
                bestParams.morphScale, bestParams.gaussSigma, char(bestParams.contrastMethod), bestParams.openRadius);
        saveBestParams(imagePath, bestParams);
        return;
    end

    n_mid = double(user_count);
    manualCountBand = buildTargetCountBand(n_mid, COUNT_BAND_MARGIN);
    fprintf('  Target set to %d. Re-running optimization (%d evals)...\n', ...
            user_count, REFINE_EVALS);

    seedRow = table(bestParams.morphScale, ...
                    categorical({char(bestParams.contrastMethod)}), ...
                    'VariableNames', {'morphScale','contrastMethod'});

    % Tier 3: linear penalty, weight 2.0 — user count is trusted as ground truth.
    % |log(n/n_mid)| with weight 2.0 means a 20% count deviation adds 0.36
    % to the score, comfortably overriding any CV advantage from merging.
    obj = @(p) scoreParams(I, p, n_min, n_max, n_mid, manualCountBand, d_est0, CLIP_LIMIT, ...
                           fillDeepPits, fillThreshold, dilateRadius, minObjectArea, ...
                           TIER3_COUNT_WEIGHT, true);

    previousRngState = rng;
    rng(rngSeed + 100 + round(n_mid), 'twister');
    cleanupRng = onCleanup(@() rng(previousRngState));
    results = bayesopt(obj, vars, ...
        'MaxObjectiveEvaluations',   REFINE_EVALS, ...
        'InitialX',                  seedRow, ...
        'AcquisitionFunctionName',   'expected-improvement-plus', ...
        'IsObjectiveDeterministic',  true, ...
        'Verbose',                   0, ...
        'PlotFcn',                   []);
    clear cleanupRng

    bestParams_new           = selectStableBestParams(results, I, n_min, n_max, n_mid, manualCountBand, d_est0, ...
        CLIP_LIMIT, fillDeepPits, fillThreshold, dilateRadius, minObjectArea, ...
        BASE_GAUSS_FRACTION, BASE_OPEN_FRACTION, TIER3_COUNT_WEIGHT, true);
    bestParams               = bestParams_new;

    fprintf('  Done. New params: morphScale=%.2f  sigma=%.2f  contrast=%s  openR=%d\n', ...
            bestParams.morphScale, bestParams.gaussSigma, char(bestParams.contrastMethod), bestParams.openRadius);
end

end % refineMoundsStable


% =========================================================================
%  OVERLAY VISUALIZATION
% =========================================================================
function showOverlay(I, centroids, bestParams, n_current, n_mid, tier)
    figure('Name', sprintf('refineMoundsStable -- %d mounds', n_current), ...
                 'Position', [100 100 1000 450], 'Color', [0.15 0.15 0.15]);

    % --- Panel 1: detection overlay --------------------------------------
    subplot(1, 2, 1);
    imshow(I, []); hold on;
    if ~isempty(centroids)
        plot(centroids(:,1), centroids(:,2), 'r+', ...
             'MarkerSize', 6, 'LineWidth', 1.0);
    end
    if tier == 0
        title(sprintf('Tier 1 automatic detection  |  %d mounds detected  |  target ~%.0f', ...
              n_current, n_mid), 'Color', 'w', 'FontSize', 9);
    elseif tier > 0
        title(sprintf('Tier 2 nudge #%d  |  %d mounds detected  |  target ~%.0f', ...
              tier, n_current, n_mid), 'Color', 'w', 'FontSize', 9);
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

    sgtitle(sprintf('scale=%.2f  sigma=%.2f  contrast=%s  openR=%d', ...
            bestParams.morphScale, bestParams.gaussSigma, ...
            char(bestParams.contrastMethod), bestParams.openRadius), ...
            'Color','w','FontSize',9);

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
%  SAVE FINAL PARAMETERS
% =========================================================================
function saveBestParams(imagePath, bestParams)
    imageFolder = fileparts(imagePath);
    savePath = fullfile(imageFolder, 'bestParams.mat');
    save(savePath, 'bestParams');
    fprintf('Saved bestParams to %s\n', savePath);
end


% =========================================================================
%  COUNT-BAND HELPERS
% =========================================================================
function countBand = buildPlausibleCountBand(n_p99, n_weighted_p95_p99, n_geom, seedCandidate, margin)
    bandCore = [n_p99, n_weighted_p95_p99, n_geom, seedCandidate];
    bandCore = bandCore(isfinite(bandCore) & bandCore > 0);
    countBand = [floor(min(bandCore) * (1 - margin)), ...
                 ceil(max(bandCore) * (1 + margin))];
    countBand(1) = max(3, countBand(1));
end


function countBand = buildTargetCountBand(n_mid, margin)
    countBand = [max(3, floor(n_mid * (1 - margin))), ...
                 ceil(n_mid * (1 + margin))];
end


function seedDiag = estimateSeedCountDiagnostic(I, d_est0, fillDeepPits, fillThreshold)

    seedSigma = max(1, 0.04 * d_est0);
    backgroundRadius = max(3, round(0.20 * d_est0));
    defaultSpacingFactor = 0.45;
    minSeedDistance = max(1, defaultSpacingFactor * d_est0);

    Iseed = imgaussfilt(double(I), seedSigma);
    Ilocal = Iseed - imopen(Iseed, strel('disk', backgroundRadius));

    if fillDeepPits
        fillMask = imcomplement(imfill(imcomplement( ...
            imbinarize(I, fillThreshold)), 'holes'));
        Ilocal(~fillMask) = 0;
    end

    vals = Ilocal(Ilocal > 0);
    if isempty(vals)
        hSeed = 0.04;
    else
        hSeed = max(0.04, min(0.08, 0.5 * iqr(vals)));
    end

    [~, seedCentroids] = countSeedsForSettings(Ilocal, hSeed, minSeedDistance);

    seedDiag = struct( ...
        'hSeed', hSeed, ...
        'nAfterSpacing', size(seedCentroids, 1));
end


function [nRaw, seedCentroids] = countSeedsForSettings(Ilocal, hSeed, minSeedDistance)
    seedMask = imextendedmax(Ilocal, hSeed);
    seedMask = imclearborder(seedMask);
    seedMask = bwareaopen(seedMask, 1);

    stats = regionprops(seedMask, Ilocal, 'Centroid', 'MaxIntensity');
    nRaw = numel(stats);
    if nRaw == 0
        seedCentroids = zeros(0, 2);
    else
        centroids = double(cat(1, stats.Centroid));
        strengths = double(cat(1, stats.MaxIntensity));
        seedCentroids = enforceMinSeedDistance(centroids, strengths, minSeedDistance);
    end
end


function keptCentroids = enforceMinSeedDistance(centroids, strengths, minDistance)
    [~, order] = sort(strengths, 'descend');
    keptCentroids = zeros(0, 2);

    for kk = 1:numel(order)
        candidate = centroids(order(kk), :);
        if isempty(keptCentroids)
            keptCentroids = candidate;
            continue;
        end

        d = sqrt(sum((keptCentroids - candidate).^2, 2));
        if all(d >= minDistance)
            keptCentroids = [keptCentroids; candidate]; %#ok<AGROW>
        end
    end
end


% =========================================================================
%  SCALE-LOCKED PARAMETER HELPERS
% =========================================================================
function p = ensureScaleLockedParams(p, d_est0, clipLimit, baseGaussFraction, baseOpenFraction)
    names = p.Properties.VariableNames;
    if ~ismember('morphScale', names)
        if ismember('gaussSigma', names)
            p.morphScale = max(0.5, min(3.0, double(p.gaussSigma) / (d_est0 * baseGaussFraction)));
        else
            p.morphScale = 1;
        end
    end
    p = deriveScaleLockedParams(p, d_est0, clipLimit, baseGaussFraction, baseOpenFraction);
end


function p = deriveScaleLockedParams(p, d_est0, clipLimit, baseGaussFraction, baseOpenFraction)
    names = p.Properties.VariableNames;
    if ismember('morphScale', names)
        morphScale = double(p.morphScale);
    else
        morphScale = 1;
        p.morphScale = morphScale;
    end
    p.gaussSigma = max(0.5, min(15, d_est0 * baseGaussFraction * morphScale));
    p.openRadius = max(1, min(25, round(d_est0 * baseOpenFraction * morphScale)));
    p.clipLimit = clipLimit;
end


function bestParams = selectStableBestParams(results, I, n_min, n_max, n_mid, countBand, d_est0, ...
    clipLimit, fillDeepPits, fillThreshold, dilateRadius, minObjectArea, ...
    baseGaussFraction, baseOpenFraction, countWeight, linearPenalty)

    candidateParams = results.XTrace;
    nCandidates = height(candidateParams);
    scores = NaN(nCandidates, 1);
    nDetected = NaN(nCandidates, 1);
    cvs = NaN(nCandidates, 1);
    countBandDeltas = NaN(nCandidates, 1);
    morphScales = NaN(nCandidates, 1);
    gaussSigmas = NaN(nCandidates, 1);
    openRadii = NaN(nCandidates, 1);

    for k = 1:nCandidates
        p = deriveScaleLockedParams(candidateParams(k, :), d_est0, clipLimit, ...
            baseGaussFraction, baseOpenFraction);
        [scores(k), metrics] = scoreParams(I, p, n_min, n_max, n_mid, countBand, d_est0, clipLimit, ...
            fillDeepPits, fillThreshold, dilateRadius, minObjectArea, countWeight, linearPenalty);
        nDetected(k) = metrics.n;
        cvs(k) = metrics.cv;
        countBandDeltas(k) = max([countBand(1) - nDetected(k), 0, nDetected(k) - countBand(2)]);
        morphScales(k) = p.morphScale;
        gaussSigmas(k) = p.gaussSigma;
        openRadii(k) = p.openRadius;
    end

    finiteScores = scores(isfinite(scores));
    if isempty(finiteScores)
        bestParams = bestPoint(results);
        bestParams = deriveScaleLockedParams(bestParams, d_est0, clipLimit, ...
            baseGaussFraction, baseOpenFraction);
        return;
    end

    minScore = min(finiteScores);
    tieTolerance = max(1e-4, 0.01 * max(1, abs(minScore)));
    nearTieIdx = find(isfinite(scores) & scores <= minScore + tieTolerance);
    contrastRank = getContrastRank(candidateParams.contrastMethod);

    ranking = table( ...
        scores(nearTieIdx), ...
        countBandDeltas(nearTieIdx), ...
        cvs(nearTieIdx), ...
        abs(morphScales(nearTieIdx) - 1), ...
        contrastRank(nearTieIdx), ...
        morphScales(nearTieIdx), ...
        gaussSigmas(nearTieIdx), ...
        openRadii(nearTieIdx), ...
        nearTieIdx, ...
        'VariableNames', {'Score','CountBandDelta','CV','ScaleDelta','ContrastRank','MorphScale','GaussSigma','OpenRadius','OriginalIndex'});

    ranking = sortrows(ranking, {'Score','CountBandDelta','CV','ScaleDelta','ContrastRank','MorphScale','GaussSigma','OpenRadius','OriginalIndex'});
    selectedIdx = ranking.OriginalIndex(1);
    bestParams = deriveScaleLockedParams(candidateParams(selectedIdx, :), d_est0, clipLimit, ...
        baseGaussFraction, baseOpenFraction);
end


function ranks = getContrastRank(methods)
    methodNames = cellstr(methods);
    ranks = 99 * ones(numel(methodNames), 1);
    for k = 1:numel(methodNames)
        switch methodNames{k}
            case 'adapthisteq'
                ranks(k) = 1;
            case 'histeq'
                ranks(k) = 2;
            case 'none'
                ranks(k) = 3;
        end
    end
end


% =========================================================================
%  SCORING
% =========================================================================
function [score, metrics] = scoreParams(I, p, n_min, n_max, n_mid, countBand, d_est0, clipLimit, ...
                              fillDeepPits, fillThreshold, dilateRadius, minObjectArea, ...
                              count_weight, linear_penalty)
% count_weight:   weight applied to count penalty (0.5 for Tier 2, 2.0 for Tier 3)
% linear_penalty: if true, use |log(n/n_mid)| (sharper); else log(n/n_mid)^2 (softer)
    if nargin < 13, count_weight   = 0.5;  end
    if nargin < 14, linear_penalty = false; end
    metrics = struct('n', NaN, 'cv', NaN, 'countPenalty', NaN, 'score', NaN);

    try
        p = deriveScaleLockedParams(p, d_est0, clipLimit, 0.08, 0.05);
        [~, centroids] = runPipeline(I, p, fillDeepPits, fillThreshold, ...
                                      dilateRadius, minObjectArea);
        n = size(centroids, 1);
        metrics.n = n;

        if n < n_min || n > n_max
            score = 100;
            metrics.score = score;
            return;
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
        elseif n < countBand(1)
            count_penalty = log(n / countBand(1))^2;
        elseif n > countBand(2)
            count_penalty = log(n / countBand(2))^2;
        else
            % Tier 2 uses the same broad plausible-count band as
            % autoTuneMoundsStable: no count penalty inside the band.
            count_penalty = 0;
        end

        score = cv + count_weight * count_penalty;
        metrics.cv = cv;
        metrics.countPenalty = count_penalty;
        metrics.score = score;

    catch ME
        warning('scoreParams:pipelineError', '%s', ME.message);
        score = 100;
        metrics.score = score;
    end
end


% =========================================================================
%  PIPELINE  (scale-locked stable copy)
% =========================================================================
function [fgm4, centroids] = runPipeline(I, p, fillDeepPits, fillThreshold, ...
                                          dilateRadius, minObjectArea)
    Iblur   = imgaussfilt(double(I), double(p.gaussSigma));
    mask    = double(applyContrast(Iblur, char(p.contrastMethod), double(p.clipLimit)));
    Iobrcbr = preprocessImage(mask, double(p.openRadius));
    fgm4    = extractRegionalMaxima(Iobrcbr, dilateRadius, minObjectArea, ...
                                    fillDeepPits, I, fillThreshold);
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
                                       fillDeepPits, fillSourceImage, fillThreshold)
    fgm  = imregionalmax(Iobrcbr);
    se   = strel('disk', dilateRadius);
    fgm2 = imclose(fgm, se);
    fgm3 = imdilate(fgm2, se);
    fgm4 = bwareaopen(fgm3, minArea);
    if fillDeepPits
        filled = imcomplement(imfill(imcomplement( ...
                     imbinarize(fillSourceImage, fillThreshold)), 'holes'));
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
