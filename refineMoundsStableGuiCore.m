function varargout = refineMoundsStableGuiCore(action, varargin)
% refineMoundsStableGuiCore
% GUI-oriented step runner for the stable mound-refinement workflow.
%
% This intentionally leaves refineMoundsStable.m intact. The app calls this
% file one step at a time so review figures and user choices can live inside
% SOLFAnalysisApp instead of blocking on command-window input.

switch lower(string(action))
    case "init"
        varargout{1} = initState(varargin{:});
    case "runinitial"
        [varargout{1}, varargout{2}] = runInitial(varargin{:});
    case "feedback"
        [varargout{1}, varargout{2}] = runFeedback(varargin{:});
    case "accept"
        [varargout{1}, varargout{2}] = acceptResult(varargin{:});
    otherwise
        error('refineMoundsStableGuiCore:UnknownAction', ...
            'Unknown action: %s', char(action));
end
end

function state = initState(imagePath, fillDeepPits, fillThreshold, ...
    dilateRadius, minObjectArea, outputDir, maxInitialEvals, logFcn)

if nargin >= 7 && isa(maxInitialEvals, 'function_handle')
    logFcn = maxInitialEvals;
    maxInitialEvals = 60;
end
if nargin < 7 || isempty(maxInitialEvals)
    maxInitialEvals = 60;
end
if nargin < 8 || isempty(logFcn)
    logFcn = @(msg) fprintf('%s\n', msg);
end
maxInitialEvals = max(1, round(double(maxInitialEvals)));

constants = struct( ...
    'CLIP_LIMIT', 0.02, ...
    'BASE_GAUSS_FRACTION', 0.08, ...
    'BASE_OPEN_FRACTION', 0.05, ...
    'REFINE_EVALS', 30, ...
    'INITIAL_EVALS', maxInitialEvals, ...
    'TIER2_COUNT_WEIGHT', 1.25, ...
    'TIER3_COUNT_WEIGHT', 2.0, ...
    'MAX_NUDGES', 6, ...
    'NUDGE_FACTOR', 1.3, ...
    'COUNT_BAND_MARGIN', 0.10, ...
    'rngSeed', 1);

logFcn('Loading image for GUI mound detection...');
[I, imgH, imgW] = loadDetectionImage(imagePath);

[d_est0, n_p90, n_p95, n_p99, n_geom, n_weighted_p95_p99, seedDiag, scaleDiag] = ...
    estimateCountSetup(I, imgH, imgW, fillDeepPits, fillThreshold);
seedOverGeom = seedDiag.nAfterSpacing / max(n_geom, eps);
seedBandCandidates = [];
if seedOverGeom <= 1.5
    seedBandCandidates = seedDiag.nAfterSpacing;
end
countBand = buildPlausibleCountBand(n_p99, n_weighted_p95_p99, n_geom, ...
    seedBandCandidates, constants.COUNT_BAND_MARGIN);
scaleBounds = estimateAdaptiveScaleBounds(scaleDiag, seedDiag, n_geom, imgH, imgW);

logFcn('refineMoundsStable GUI count setup:');
logFcn(sprintf('  distance targets: p90=%.0f  p95=%.0f  p99=%.0f  geometric=%.0f', ...
    n_p90, n_p95, n_p99, n_geom));
logFcn(sprintf('  seed diagnostic: h=%.3f  spaced=%d  seed/geometric=%.2f', ...
    seedDiag.hSeed, seedDiag.nAfterSpacing, seedOverGeom));
logFcn(sprintf('  initial scoring band: [%d, %d] mounds', countBand(1), countBand(2)));
logFcn(sprintf('  scale confidence: %s  spacing spread=%.2f  seed spacing ratio=%.2f', ...
    char(scaleBounds.confidence), scaleBounds.spacingSpread, scaleBounds.seedSpacingRatio));
logFcn(sprintf('  adaptive morphScale bounds: [%.2f, %.2f]', ...
    scaleBounds.morphScaleBounds(1), scaleBounds.morphScaleBounds(2)));
logFcn(sprintf('  derived sigma range: [%.2f, %.2f] px  openRadius range: [%d, %d] px', ...
    scaleBounds.gaussSigmaRange(1), scaleBounds.gaussSigmaRange(2), ...
    scaleBounds.openRadiusRange(1), scaleBounds.openRadiusRange(2)));

state = struct();
state.imagePath = imagePath;
state.outputDir = outputDir;
state.fillDeepPits = logical(fillDeepPits);
state.fillThreshold = fillThreshold;
state.dilateRadius = dilateRadius;
state.minObjectArea = minObjectArea;
state.logFcn = logFcn;
state.constants = constants;
state.I = I;
state.imgH = imgH;
state.imgW = imgW;
state.d_est0 = d_est0;
state.scaleDiag = scaleDiag;
state.scaleBounds = scaleBounds;
state.morphScaleBounds = scaleBounds.morphScaleBounds;
state.n_mid = n_geom;
state.countBand = countBand;
state.n_min = 3;
state.n_max = imgH * imgW / 10^2;
state.n_lo = 0;
state.n_hi = Inf;
state.nudge_count = 0;
state.bestParams = [];
state.lastResult = [];
state.lastSelectedCentroids = [];
state.lastSelectedSpacingDistances = [];
state.lastSelectedSpacingCv = NaN;
state.resultSerial = 0;
end

function [state, result] = runInitial(state)
c = state.constants;
state.logFcn(sprintf('========== Tier 1: Stable automatic tuning (%d evaluations) ==========', ...
    c.INITIAL_EVALS));
state.logFcn(sprintf('Using fixed optimizer RNG seed: %d', c.rngSeed));

auto_n_min = max(3, floor(state.n_mid * 0.1));
auto_n_max = ceil(state.n_mid * 15);
seed_morphScale = 1.0;
seedParams = deriveScaleLockedParams( ...
    table(seed_morphScale, categorical({'histeq'}), ...
    'VariableNames', {'morphScale','contrastMethod'}), ...
    state.d_est0, c.CLIP_LIMIT, c.BASE_GAUSS_FRACTION, c.BASE_OPEN_FRACTION);
seedPoint = seedParams(:, {'morphScale','contrastMethod'});

evalCache = containers.Map('KeyType', 'char', 'ValueType', 'any');
autoObj = @(p) cachedScoreParams(evalCache, state.I, p, auto_n_min, auto_n_max, state.n_mid, ...
    state.countBand, state.d_est0, c.CLIP_LIMIT, state.fillDeepPits, ...
    state.fillThreshold, state.dilateRadius, state.minObjectArea, 0.5, false);

seedScore = autoObj(seedPoint);
state.logFcn(sprintf('Image-derived seed: morphScale=%.2f  sigma=%.2f  contrast=histeq  openR=%d', ...
    seedParams.morphScale, seedParams.gaussSigma, seedParams.openRadius));
if seedScore >= 0.6
    state.logFcn(sprintf('Seed score: %.4f (poor - broad exploration)', seedScore));
    seedPoint = [];
else
    state.logFcn(sprintf('Seed score: %.4f (good - seeding optimizer)', seedScore));
end

vars = buildOptimizableVariables(state.morphScaleBounds);
bayesOpts = { ...
    'MaxObjectiveEvaluations', c.INITIAL_EVALS, ...
    'AcquisitionFunctionName', 'expected-improvement-plus', ...
    'IsObjectiveDeterministic', true, ...
    'Verbose', 1, ...
    'PlotFcn', []};
if ~isempty(seedPoint)
    bayesOpts = [bayesOpts, {'InitialX', seedPoint}];
end

previousRngState = rng;
rng(c.rngSeed, 'twister');
cleanupRng = onCleanup(@() rng(previousRngState));
results = bayesopt(autoObj, vars, bayesOpts{:});
clear cleanupRng

[state.bestParams, selectedEntry] = selectStableBestParams(results, evalCache, state.I, auto_n_min, auto_n_max, ...
    state.n_mid, state.countBand, state.d_est0, c.CLIP_LIMIT, state.fillDeepPits, ...
    state.fillThreshold, state.dilateRadius, state.minObjectArea, ...
    c.BASE_GAUSS_FRACTION, c.BASE_OPEN_FRACTION, 0.5, false, false);
state = rememberSelectedEntry(state, selectedEntry);
logSelectionDiagnostics(state, results, evalCache, auto_n_min, auto_n_max, state.n_mid, ...
    state.countBand, 0.5, false, 'Tier 1');

result = buildReviewResult(state, 'Tier 1');
state.lastResult = result;
state.logFcn(sprintf('Tier 1 complete. Current detection: %d mounds.', result.nCurrent));
state.logFcn(sprintf('Current params: morphScale=%.2f  sigma=%.2f  contrast=%s  openR=%d', ...
    state.bestParams.morphScale, state.bestParams.gaussSigma, ...
    char(state.bestParams.contrastMethod), state.bestParams.openRadius));
end

function [state, result] = runFeedback(state, feedbackAction, manualCount)
c = state.constants;
if isempty(state.bestParams)
    error('refineMoundsStableGuiCore:MissingInitialRun', ...
        'Run Tier 1 before applying mound-detection feedback.');
end

switch lower(string(feedbackAction))
    case "toofew"
        [state, result] = runDirectionalNudge(state, "tooFew");
    case "toomany"
        [state, result] = runDirectionalNudge(state, "tooMany");
    case "manual"
        if isempty(manualCount) || ~isfinite(manualCount) || manualCount < 1
            error('refineMoundsStableGuiCore:InvalidManualCount', ...
                'Manual count must be a positive number.');
        end
        state.n_mid = double(round(manualCount));
        state.countBand = buildTargetCountBand(state.n_mid, c.COUNT_BAND_MARGIN);
        state.logFcn(sprintf('========== Tier 3: Manual count target %d ==========', round(state.n_mid)));
        state.logFcn(sprintf('Re-running optimization (%d evaluations)...', c.REFINE_EVALS));
        [bestParams, state] = runRefinementOptimization(state, ...
            c.TIER3_COUNT_WEIGHT, true, c.rngSeed + 100 + round(state.n_mid));
        state.bestParams = bestParams;
        result = buildReviewResult(state, 'Tier 3');
        state.lastResult = result;
        state.logFcn(sprintf('Tier 3 complete. Current detection: %d mounds.', result.nCurrent));
    otherwise
        error('refineMoundsStableGuiCore:UnknownFeedback', ...
            'Unknown feedback action: %s', char(feedbackAction));
end
end

function [state, result] = runDirectionalNudge(state, feedbackAction)
c = state.constants;
currentCount = state.lastResult.nCurrent;
if state.nudge_count >= c.MAX_NUDGES
    error('refineMoundsStableGuiCore:ManualCountRequired', ...
        'Maximum directional nudges reached. Use Manual Count for the next refinement.');
end

if feedbackAction == "tooFew"
    state.n_lo = max(state.n_lo, currentCount);
    state.logFcn(sprintf('Noted: %d is too few. Lower bound updated to %.0f.', ...
        currentCount, state.n_lo));
elseif feedbackAction == "tooMany"
    state.n_hi = min(state.n_hi, currentCount);
    state.logFcn(sprintf('Noted: %d is too many. Upper bound updated to %.0f.', ...
        currentCount, state.n_hi));
end

if state.n_lo > 0 && ~isinf(state.n_hi)
    state.n_mid = (state.n_lo + state.n_hi) / 2;
    state.logFcn(sprintf('Both bounds known [%.0f, %.0f] - bisecting to n_mid = %.0f', ...
        state.n_lo, state.n_hi, state.n_mid));
elseif state.n_lo > 0
    state.n_mid = state.n_lo * c.NUDGE_FACTOR;
    state.logFcn(sprintf('Only lower bound known - nudging up to n_mid = %.0f', state.n_mid));
else
    state.n_mid = state.n_hi / c.NUDGE_FACTOR;
    state.logFcn(sprintf('Only upper bound known - nudging down to n_mid = %.0f', state.n_mid));
end

state.countBand = buildTargetCountBand(state.n_mid, c.COUNT_BAND_MARGIN);
state.nudge_count = state.nudge_count + 1;
state.logFcn(sprintf('========== Tier 2 nudge #%d ==========', state.nudge_count));
state.logFcn(sprintf('Re-running optimization (%d evaluations)...', c.REFINE_EVALS));

[bestParams, state] = runRefinementOptimization(state, ...
    c.TIER2_COUNT_WEIGHT, false, c.rngSeed + state.nudge_count);
state.bestParams = bestParams;
result = buildReviewResult(state, sprintf('Tier 2.%d', state.nudge_count));
state.lastResult = result;
state.logFcn(sprintf('Tier 2 complete. Current detection: %d mounds.', result.nCurrent));
end

function [bestParams, state] = runRefinementOptimization(state, countWeight, linearPenalty, rngSeed)
c = state.constants;
seedRow = table(state.bestParams.morphScale, ...
    categorical({char(state.bestParams.contrastMethod)}), ...
    'VariableNames', {'morphScale','contrastMethod'});
evalCache = containers.Map('KeyType', 'char', 'ValueType', 'any');
obj = @(p) cachedScoreParams(evalCache, state.I, p, state.n_min, state.n_max, state.n_mid, ...
    state.countBand, state.d_est0, c.CLIP_LIMIT, state.fillDeepPits, ...
    state.fillThreshold, state.dilateRadius, state.minObjectArea, ...
    countWeight, linearPenalty);

previousRngState = rng;
rng(rngSeed, 'twister');
cleanupRng = onCleanup(@() rng(previousRngState));
results = bayesopt(obj, buildOptimizableVariables(state.morphScaleBounds), ...
    'MaxObjectiveEvaluations', c.REFINE_EVALS, ...
    'InitialX', seedRow, ...
    'AcquisitionFunctionName', 'expected-improvement-plus', ...
    'IsObjectiveDeterministic', true, ...
    'Verbose', 0, ...
    'PlotFcn', []);
clear cleanupRng

[bestParams, selectedEntry] = selectStableBestParams(results, evalCache, state.I, state.n_min, state.n_max, ...
    state.n_mid, state.countBand, state.d_est0, c.CLIP_LIMIT, state.fillDeepPits, ...
    state.fillThreshold, state.dilateRadius, state.minObjectArea, ...
    c.BASE_GAUSS_FRACTION, c.BASE_OPEN_FRACTION, countWeight, linearPenalty, true);
state = rememberSelectedEntry(state, selectedEntry);
logSelectionDiagnostics(state, results, evalCache, state.n_min, state.n_max, state.n_mid, ...
    state.countBand, countWeight, linearPenalty, 'Refinement');

state.logFcn(sprintf('Done. New params: morphScale=%.2f  sigma=%.2f  contrast=%s  openR=%d', ...
    bestParams.morphScale, bestParams.gaussSigma, ...
    char(bestParams.contrastMethod), bestParams.openRadius));
state.logFcn(sprintf('Selected refinement candidate count: %d mounds (target %.0f).', ...
    selectedEntry.metrics.n, state.n_mid));
end

function state = rememberSelectedEntry(state, selectedEntry)
state.lastSelectedCentroids = selectedEntry.centroids;
state.lastSelectedSpacingDistances = selectedEntry.spacingDistances;
state.lastSelectedSpacingCv = selectedEntry.metrics.cv;
end

function logSelectionDiagnostics(state, results, evalCache, n_min, n_max, n_mid, countBand, ...
    countWeight, linearPenalty, label)
c = state.constants;
candidateParams = results.XTrace;
nCandidates = height(candidateParams);
nDetected = NaN(nCandidates, 1);
scores = NaN(nCandidates, 1);
countPenalties = NaN(nCandidates, 1);

for k = 1:nCandidates
    entry = getCachedOrScore(evalCache, state.I, candidateParams(k, :), n_min, n_max, ...
        n_mid, countBand, state.d_est0, c.CLIP_LIMIT, state.fillDeepPits, ...
        state.fillThreshold, state.dilateRadius, state.minObjectArea, countWeight, linearPenalty);
    scores(k) = entry.score;
    metrics = entry.metrics;
    nDetected(k) = metrics.n;
    countPenalties(k) = metrics.countPenalty;
end

finiteMask = isfinite(scores) & isfinite(nDetected);
if ~any(finiteMask)
    state.logFcn(sprintf('%s optimizer diagnostics: no finite scored candidates.', label));
    return;
end

finiteCounts = nDetected(finiteMask);
finiteScores = scores(finiteMask);
finitePenalties = countPenalties(finiteMask);
[bestScore, bestLocalIdx] = min(finiteScores);
bestCount = finiteCounts(bestLocalIdx);
[~, nearestLocalIdx] = min(abs(finiteCounts - n_mid));
nearestCount = finiteCounts(nearestLocalIdx);
nearestScore = finiteScores(nearestLocalIdx);
nearestPenalty = finitePenalties(nearestLocalIdx);

state.logFcn(sprintf('%s optimizer diagnostics:', label));
state.logFcn(sprintf('  target n_mid=%.0f, count band=[%d, %d], count weight=%.2f, linear penalty=%d', ...
    n_mid, countBand(1), countBand(2), countWeight, logical(linearPenalty)));
state.logFcn(sprintf('  evaluated count range=[%d, %d] across %d candidates', ...
    round(min(finiteCounts)), round(max(finiteCounts)), nnz(finiteMask)));
state.logFcn(sprintf('  best scored candidate: n=%d, score=%.4f', ...
    round(bestCount), bestScore));
state.logFcn(sprintf('  nearest-count candidate: n=%d, score=%.4f, count penalty=%.4f', ...
    round(nearestCount), nearestScore, nearestPenalty));
end

function [state, savePath] = acceptResult(state)
if isempty(state.bestParams)
    error('refineMoundsStableGuiCore:NoBestParams', ...
        'No mound-detection parameters are available to save.');
end
if ~exist(state.outputDir, 'dir')
    mkdir(state.outputDir);
end
bestParams = state.bestParams;
savePath = fullfile(state.outputDir, 'bestParams.mat');
save(savePath, 'bestParams');
state.logFcn(sprintf('Saved bestParams to %s', savePath));
end

function result = buildReviewResult(state, tierLabel)
if isfield(state, 'lastSelectedCentroids') && ~isempty(state.lastSelectedCentroids)
    centroids = state.lastSelectedCentroids;
else
    [~, centroids] = runPipeline(state.I, state.bestParams, state.fillDeepPits, ...
        state.fillThreshold, state.dilateRadius, state.minObjectArea);
end
[spacingDistances, spacingCv] = computeSpacingDiagnostics(centroids);

state.resultSerial = state.resultSerial + 1;
result = struct( ...
    'serial', state.resultSerial, ...
    'tierLabel', tierLabel, ...
    'I', state.I, ...
    'centroids', centroids, ...
    'nCurrent', size(centroids, 1), ...
    'nMid', state.n_mid, ...
    'bestParams', state.bestParams, ...
    'spacingDistances', spacingDistances, ...
    'spacingCv', spacingCv);
end

function [I, imgH, imgW] = loadDetectionImage(imagePath)
[~, ~, imageExt] = fileparts(imagePath);
if strcmpi(imageExt, '.vk4')
    if ~exist('readVK4', 'file')
        error(['refineMoundsStableGuiCore: readVK4.m not found on MATLAB path.\n' ...
            'Required for .vk4 input. Add readVK4.m and the vk4mat library to path.']);
    end
    [Z_load, ~, total_h, imgH, imgW] = readVK4(imagePath);
    I_raw = uint8(round(Z_load / total_h * 255));
else
    I_raw = imread(imagePath);
    if size(I_raw, 3) == 3
        I_raw = rgb2gray(I_raw);
    end
    [imgH, imgW] = size(I_raw);
end
I = double(I_raw) / 255;
end

function [d_est0, n_p90, n_p95, n_p99, n_geom, n_weighted_p95_p99, seedDiag, scaleDiag] = ...
    estimateCountSetup(I, imgH, imgW, fillDeepPits, fillThreshold)
I_blur0 = imgaussfilt(I, 2.0);
BW0 = imbinarize(I_blur0, graythresh(I_blur0));
BW0 = imclearborder(BW0);
D0 = double(bwdist(~BW0));
fg_vals = D0(BW0 > 0);

if isempty(fg_vals)
    fg_vals = max(1, min(imgH, imgW) / 20);
end

r_p90 = prctile(fg_vals, 90); d_p90 = 2 * r_p90;
r_p95 = prctile(fg_vals, 95); d_p95 = 2 * r_p95;
r_p99 = prctile(fg_vals, 99); d_p99 = 2 * r_p99;

n_p90 = imgH * imgW * 0.5 / max(d_p90^2, eps);
n_p95 = imgH * imgW * 0.5 / max(d_p95^2, eps);
n_p99 = imgH * imgW * 0.5 / max(d_p99^2, eps);
d_est0 = d_p95;
n_geom = (n_p90 * n_p95 * n_p99)^(1/3);
n_weighted_p95_p99 = (n_p95 * n_p99^2)^(1/3);
seedDiag = estimateSeedCountDiagnostic(I, d_est0, fillDeepPits, fillThreshold);
scaleDiag = struct('d_p90', d_p90, 'd_p95', d_p95, 'd_p99', d_p99);
end

function scaleBounds = estimateAdaptiveScaleBounds(scaleDiag, seedDiag, n_geom, imgH, imgW)
seedSpacing = NaN;
if isfield(seedDiag, 'nAfterSpacing') && seedDiag.nAfterSpacing > 0
    seedSpacing = sqrt(imgH * imgW * 0.5 / seedDiag.nAfterSpacing);
end

dValues = [scaleDiag.d_p90, scaleDiag.d_p95, scaleDiag.d_p99];
dValues = dValues(isfinite(dValues) & dValues > 0);
spacingSpread = max(dValues) / max(min(dValues), eps);
seedSpacingRatio = seedSpacing / max(scaleDiag.d_p95, eps);
seedOverGeom = seedDiag.nAfterSpacing / max(n_geom, eps);

if spacingSpread <= 1.35 && seedSpacingRatio >= 0.75 && seedSpacingRatio <= 1.35 && seedOverGeom <= 1.5
    confidence = "high";
    morphScaleBounds = [0.75, 1.60];
elseif spacingSpread <= 1.80 && seedSpacingRatio >= 0.55 && seedSpacingRatio <= 1.80 && seedOverGeom <= 2.25
    confidence = "moderate";
    morphScaleBounds = [0.60, 2.20];
else
    confidence = "low";
    morphScaleBounds = [0.50, 3.00];
end

baseGaussFraction = 0.08;
baseOpenFraction = 0.05;
gaussSigmaRange = max(0.5, min(15, scaleDiag.d_p95 * baseGaussFraction .* morphScaleBounds));
openRadiusRange = max(1, min(25, round(scaleDiag.d_p95 * baseOpenFraction .* morphScaleBounds)));

scaleBounds = struct( ...
    'confidence', confidence, ...
    'spacingSpread', spacingSpread, ...
    'seedSpacing', seedSpacing, ...
    'seedSpacingRatio', seedSpacingRatio, ...
    'seedOverGeom', seedOverGeom, ...
    'morphScaleBounds', morphScaleBounds, ...
    'gaussSigmaRange', gaussSigmaRange, ...
    'openRadiusRange', openRadiusRange);
end

function vars = buildOptimizableVariables(morphScaleBounds)
if nargin < 1 || isempty(morphScaleBounds)
    morphScaleBounds = [0.5, 3.0];
end
vars = [
    optimizableVariable('morphScale', morphScaleBounds, 'Type', 'real')
    optimizableVariable('contrastMethod', {'none','histeq','adapthisteq'}, ...
    'Type', 'categorical')
    ];
end

function [spacingDistances, spacingCv] = computeSpacingDiagnostics(centroids)
spacingDistances = [];
spacingCv = NaN;
n = size(centroids, 1);
if n <= 3
    return;
end
dt = delaunayTriangulation(centroids(:,1), centroids(:,2));
all_edg = dt.edges();
d1a = centroids(all_edg(:,1), :);
d2a = centroids(all_edg(:,2), :);
init_a = median(sqrt(sum((d1a - d2a).^2, 2)));
try
    [S_a, ~] = computeAlphaShape(centroids, init_a);
    tris = S_a.alphaTriangulation;
    if ~isempty(tris)
        edg = unique(sort([tris(:,[1 2]); tris(:,[2 3]); tris(:,[3 1])], 2), 'rows');
        d1 = centroids(edg(:,1), :);
        d2 = centroids(edg(:,2), :);
        spacingDistances = sqrt(sum((d1 - d2).^2, 2));
    end
catch
    spacingDistances = [];
end
if isempty(spacingDistances)
    dists_all = sqrt(sum((d1a - d2a).^2, 2));
    spacingDistances = dists_all(dists_all < 2.5 * median(dists_all));
end
if ~isempty(spacingDistances)
    spacingCv = std(spacingDistances) / mean(spacingDistances);
end
end

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

if fillDeepPits && ~isempty(fillThreshold)
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
seedDiag = struct('hSeed', hSeed, 'nAfterSpacing', size(seedCentroids, 1));
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

function [bestParams, selectedEntry] = selectStableBestParams(results, evalCache, I, n_min, n_max, n_mid, countBand, d_est0, ...
    clipLimit, fillDeepPits, fillThreshold, dilateRadius, minObjectArea, ...
    baseGaussFraction, baseOpenFraction, countWeight, linearPenalty, prioritizeCount)

if nargin < 18
    prioritizeCount = false;
end

candidateParams = results.XTrace;
nCandidates = height(candidateParams);
scores = NaN(nCandidates, 1);
nDetected = NaN(nCandidates, 1);
cvs = NaN(nCandidates, 1);
countBandDeltas = NaN(nCandidates, 1);
countTargetDeltas = NaN(nCandidates, 1);
morphScales = NaN(nCandidates, 1);
gaussSigmas = NaN(nCandidates, 1);
openRadii = NaN(nCandidates, 1);

for k = 1:nCandidates
    entry = getCachedOrScore(evalCache, I, candidateParams(k, :), n_min, n_max, n_mid, ...
        countBand, d_est0, clipLimit, fillDeepPits, fillThreshold, dilateRadius, ...
        minObjectArea, countWeight, linearPenalty);
    p = entry.params;
    metrics = entry.metrics;
    scores(k) = entry.score;
    nDetected(k) = metrics.n;
    cvs(k) = metrics.cv;
    countBandDeltas(k) = max([countBand(1) - nDetected(k), 0, nDetected(k) - countBand(2)]);
    countTargetDeltas(k) = abs(nDetected(k) - n_mid);
    morphScales(k) = p.morphScale;
    gaussSigmas(k) = p.gaussSigma;
    openRadii(k) = p.openRadius;
end

finiteScores = scores(isfinite(scores));
if isempty(finiteScores)
    bestParams = deriveScaleLockedParams(results.XAtMinObjective, d_est0, clipLimit, ...
        baseGaussFraction, baseOpenFraction);
    selectedEntry = getCachedOrScore(evalCache, I, bestParams, n_min, n_max, n_mid, ...
        countBand, d_est0, clipLimit, fillDeepPits, fillThreshold, dilateRadius, ...
        minObjectArea, countWeight, linearPenalty);
    return;
end

minScore = min(finiteScores);
tieTolerance = max(1e-4, 0.01 * max(1, abs(minScore)));
if prioritizeCount
    nearTieIdx = find(isfinite(scores));
else
    nearTieIdx = find(isfinite(scores) & scores <= minScore + tieTolerance);
end
contrastRank = getContrastRank(candidateParams.contrastMethod);

ranking = table( ...
    scores(nearTieIdx), ...
    countBandDeltas(nearTieIdx), ...
    countTargetDeltas(nearTieIdx), ...
    cvs(nearTieIdx), ...
    abs(morphScales(nearTieIdx) - 1), ...
    contrastRank(nearTieIdx), ...
    morphScales(nearTieIdx), ...
    gaussSigmas(nearTieIdx), ...
    openRadii(nearTieIdx), ...
    nearTieIdx, ...
    'VariableNames', {'Score','CountBandDelta','CountTargetDelta','CV','ScaleDelta','ContrastRank','MorphScale','GaussSigma','OpenRadius','OriginalIndex'});

if prioritizeCount
    ranking = sortrows(ranking, {'CountBandDelta','CountTargetDelta','Score','CV','ScaleDelta','ContrastRank','MorphScale','GaussSigma','OpenRadius','OriginalIndex'});
else
    ranking = sortrows(ranking, {'Score','CountBandDelta','CountTargetDelta','CV','ScaleDelta','ContrastRank','MorphScale','GaussSigma','OpenRadius','OriginalIndex'});
end
selectedIdx = ranking.OriginalIndex(1);
selectedEntry = getCachedOrScore(evalCache, I, candidateParams(selectedIdx, :), n_min, n_max, ...
    n_mid, countBand, d_est0, clipLimit, fillDeepPits, fillThreshold, ...
    dilateRadius, minObjectArea, countWeight, linearPenalty);
bestParams = selectedEntry.params;
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

function score = cachedScoreParams(evalCache, I, p, n_min, n_max, n_mid, countBand, d_est0, clipLimit, ...
    fillDeepPits, fillThreshold, dilateRadius, minObjectArea, count_weight, linear_penalty)
entry = getCachedOrScore(evalCache, I, p, n_min, n_max, n_mid, countBand, d_est0, clipLimit, ...
    fillDeepPits, fillThreshold, dilateRadius, minObjectArea, count_weight, linear_penalty);
score = entry.score;
end

function entry = getCachedOrScore(evalCache, I, p, n_min, n_max, n_mid, countBand, d_est0, clipLimit, ...
    fillDeepPits, fillThreshold, dilateRadius, minObjectArea, count_weight, linear_penalty)
p = deriveScaleLockedParams(p, d_est0, clipLimit, 0.08, 0.05);
key = paramsCacheKey(p);
if isKey(evalCache, key)
    entry = evalCache(key);
    return;
end
entry = scoreParamsWithDetails(I, p, n_min, n_max, n_mid, countBand, d_est0, clipLimit, ...
    fillDeepPits, fillThreshold, dilateRadius, minObjectArea, count_weight, linear_penalty);
evalCache(key) = entry; %#ok<NASGU>
end

function key = paramsCacheKey(p)
key = sprintf('%.12g|%s', double(p.morphScale), char(p.contrastMethod));
end

function entry = scoreParamsWithDetails(I, p, n_min, n_max, n_mid, countBand, d_est0, clipLimit, ...
    fillDeepPits, fillThreshold, dilateRadius, minObjectArea, count_weight, linear_penalty)
if nargin < 13, count_weight = 0.5; end
if nargin < 14, linear_penalty = false; end
metrics = struct('n', NaN, 'cv', NaN, 'countPenalty', NaN, 'score', NaN);
centroids = zeros(0, 2);
spacingDistances = [];
p = deriveScaleLockedParams(p, d_est0, clipLimit, 0.08, 0.05);
try
    [~, centroids] = runPipeline(I, p, fillDeepPits, fillThreshold, ...
        dilateRadius, minObjectArea);
    n = size(centroids, 1);
    metrics.n = n;

    if n < n_min || n > n_max
        score = 100;
        metrics.score = score;
        entry = buildScoreEntry(p, score, metrics, centroids, spacingDistances);
        return;
    end

    [spacingDistances, cv] = computeFastSpacingCv(centroids);

    if linear_penalty
        count_penalty = abs(log(n / n_mid));
    elseif n < countBand(1)
        count_penalty = log(n / countBand(1))^2;
    elseif n > countBand(2)
        count_penalty = log(n / countBand(2))^2;
    else
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
entry = buildScoreEntry(p, score, metrics, centroids, spacingDistances);
end

function entry = buildScoreEntry(p, score, metrics, centroids, spacingDistances)
entry = struct( ...
    'params', p, ...
    'score', score, ...
    'metrics', metrics, ...
    'centroids', centroids, ...
    'spacingDistances', spacingDistances);
end

function [dists, cv] = computeFastSpacingCv(centroids)
dt = delaunayTriangulation(centroids(:,1), centroids(:,2));
edg = dt.edges();
d1 = centroids(edg(:,1), :);
d2 = centroids(edg(:,2), :);
dists = sqrt(sum((d1 - d2).^2, 2));
med = median(dists);
dists = dists(dists < 2.5 * med);
cv = std(dists) / mean(dists);
end

function [fgm4, centroids] = runPipeline(I, p, fillDeepPits, fillThreshold, ...
    dilateRadius, minObjectArea)
Iblur = imgaussfilt(double(I), double(p.gaussSigma));
mask = double(applyContrast(Iblur, char(p.contrastMethod), double(p.clipLimit)));
Iobrcbr = preprocessImage(mask, double(p.openRadius));
fgm4 = extractRegionalMaxima(Iobrcbr, dilateRadius, minObjectArea, ...
    fillDeepPits, I, fillThreshold);
BW = imclearborder(fgm4);
stats = regionprops(BW, 'Centroid');
if isempty(stats)
    centroids = zeros(0, 2);
else
    centroids = double(cat(1, stats.Centroid));
end
end

function mask = applyContrast(I, method, clipLimit)
switch method
    case 'none'
        mask = I;
    case 'histeq'
        mask = histeq(I);
    case 'adapthisteq'
        mask = adapthisteq(I, 'clipLimit', clipLimit, 'Distribution', 'rayleigh');
    otherwise
        mask = I;
end
end

function Iobrcbr = preprocessImage(mask, radius)
se = strel('disk', radius);
Ie = imerode(mask, se);
Iobr = imreconstruct(Ie, mask);
Iobrd = imdilate(Iobr, se);
Iobrcbr = imreconstruct(imcomplement(Iobrd), imcomplement(Iobr));
Iobrcbr = imcomplement(Iobrcbr);
end

function fgm4 = extractRegionalMaxima(Iobrcbr, dilateRadius, minArea, ...
    fillDeepPits, fillSourceImage, fillThreshold)
fgm = imregionalmax(Iobrcbr);
se = strel('disk', dilateRadius);
fgm2 = imclose(fgm, se);
fgm3 = imdilate(fgm2, se);
fgm4 = bwareaopen(fgm3, minArea);
if fillDeepPits && ~isempty(fillThreshold)
    filled = imcomplement(imfill(imcomplement( ...
        imbinarize(fillSourceImage, fillThreshold)), 'holes'));
    fgm4 = and(filled, fgm4);
end
end

function [S, alpha] = computeAlphaShape(points, initialAlpha)
MAX_ITER = 50; TOL = 0.1; MAX_HOLES = 10; HOLE_BUMP = 1.10;
prevAlpha = 0; currAlpha = initialAlpha; iter = 0;
while abs(prevAlpha - currAlpha) > TOL && iter < MAX_ITER
    prevAlpha = currAlpha;
    S = alphaShape(points, prevAlpha);
    tris = S.alphaTriangulation;
    if isempty(tris), currAlpha = prevAlpha * 2; continue; end
    edg = unique(sort([tris(:,[1 2]); tris(:,[2 3]); tris(:,[3 1])], 2), 'rows');
    lens = sqrt(sum((points(edg(:,1), :) - points(edg(:,2), :)).^2, 2));
    currAlpha = median(lens);
    iter = iter + 1;
end
S = alphaShape(points, currAlpha);
hole_iter = 0;
while (countBoundaryLoops(S) > 1 || numRegions(S) > 1) && hole_iter < MAX_HOLES
    currAlpha = currAlpha * HOLE_BUMP;
    S = alphaShape(points, currAlpha);
    hole_iter = hole_iter + 1;
end
alpha = currAlpha;
end

function n = countBoundaryLoops(S)
try
    bf = boundaryFacets(S);
    if isempty(bf)
        n = 0; return;
    end
    nodes = unique(bf(:));
    n_nodes = numel(nodes);
    [~, ia] = ismember(bf, nodes);
    parent = 1:n_nodes;
    for k = 1:size(ia, 1)
        x = ia(k, 1);
        while parent(x) ~= x, x = parent(x); end
        ra = x;
        x = ia(k, 2);
        while parent(x) ~= x, x = parent(x); end
        rb = x;
        if ra ~= rb, parent(ra) = rb; end
    end
    roots = zeros(1, n_nodes);
    for i = 1:n_nodes
        x = i;
        while parent(x) ~= x, x = parent(x); end
        roots(i) = x;
    end
    n = numel(unique(roots));
catch
    n = 1;
end
end
