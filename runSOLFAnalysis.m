function runResults = runSOLFAnalysis(config)
% runSOLFAnalysis
% Single-file orchestration entry point for the SOLF VK4 analysis workflow.

arguments
    config struct
end

config = applyDefaults(config);

if ~exist(config.inputPath, 'file')
    error('runSOLFAnalysis:MissingInput', 'Input file not found: %s', config.inputPath);
end
if ~exist(config.outputDir, 'dir')
    mkdir(config.outputDir);
end

runResults = struct('config', config, 'bestParams', [], 'm1', [], ...
    'cavResults', [], 'moundResults', [], 'spatialOrderResults', []);

fprintf('runSOLFAnalysis: %s\n', config.inputPath);

if config.fillDeepPits && isempty(config.fillThreshold)
    config.fillThreshold = pickFillThreshold(config.inputPath);
end
if config.fillDeepPits && config.runModule2 && isempty(config.reflThreshold)
    config.reflThreshold = pickReflectionThreshold(config.inputPath, config.fillThreshold);
end
runResults.config = config;

needM1 = config.runModule1 || config.runModule2 || config.runModule3 || config.runModule4;
if ~needM1
    warning('runSOLFAnalysis:NoModules', 'No analysis modules selected.');
    return;
end

fprintf('  Tuning mound detection...\n');
bestParams = autoTuneMounds(config.inputPath, config.fillDeepPits, config.fillThreshold, ...
    config.dilateRadius, config.minObjectArea, config.autoTuneMaxEvals, config.showAutoTunePlots);

if config.useRefineMounds
    fprintf('  Launching refineMounds for additional user control...\n');
    n_mid_hint = estimateMoundTarget(config.inputPath);
    bestParams = refineMounds(config.inputPath, config.fillDeepPits, config.fillThreshold, ...
        config.dilateRadius, config.minObjectArea, bestParams, n_mid_hint);
end

runResults.bestParams = bestParams;

fprintf('  Running Module 1...\n');
m1 = analyzeMounds(config.inputPath, bestParams, config.fillDeepPits, config.fillThreshold, ...
    config.dilateRadius, config.minObjectArea, [], [], config.outputDir);
runResults.m1 = m1;

if config.runModule2
    fprintf('  Running Module 2...\n');
    runResults.cavResults = analyzeCavities(m1, config.minDepthUm, config.fillDeepPits, ...
        config.fillThreshold, config.reflThreshold, config.outputDir);
end

if config.runModule3
    fprintf('  Running Module 3...\n');
    runResults.moundResults = analyzeMoundShape(m1, config.outputDir);
end

if config.runModule4
    fprintf('  Running Module 4...\n');
    runResults.spatialOrderResults = analyzeSpatialOrder(m1, config.outputDir);
end
end

function config = applyDefaults(config)
defaults = struct( ...
    'runModule1', true, ...
    'runModule2', false, ...
    'runModule3', true, ...
    'runModule4', false, ...
    'fillDeepPits', false, ...
    'fillThreshold', [], ...
    'reflThreshold', [], ...
    'dilateRadius', 3, ...
    'minObjectArea', 20, ...
    'autoTuneMaxEvals', 60, ...
    'showAutoTunePlots', true, ...
    'useRefineMounds', false, ...
    'minDepthUm', 2.0);

fields = fieldnames(defaults);
for i = 1:numel(fields)
    if ~isfield(config, fields{i}) || isempty(config.(fields{i}))
        config.(fields{i}) = defaults.(fields{i});
    end
end

required = {'inputPath', 'outputDir'};
for i = 1:numel(required)
    if ~isfield(config, required{i}) || isempty(config.(required{i}))
        error('runSOLFAnalysis:MissingConfig', 'Missing required config field: %s', required{i});
    end
end
end

function n_mid = estimateMoundTarget(imagePath)
[~, ~, imageExt] = fileparts(imagePath);
if strcmpi(imageExt, '.vk4')
    [Z_load, ~, total_h] = readVK4(imagePath);
    I_raw = uint8(round(Z_load / total_h * 255));
    clear Z_load total_h;
else
    I_raw = imread(imagePath);
    if size(I_raw, 3) == 3
        I_raw = rgb2gray(I_raw);
    end
end

I = double(I_raw) / 255;
I_blur0 = imgaussfilt(I, 2.0);
BW0 = imbinarize(I_blur0, graythresh(I_blur0));
BW0 = imclearborder(BW0);
D0 = double(bwdist(~BW0));
fg_vals = D0(BW0 > 0);

if isempty(fg_vals)
    n_mid = 100;
    return;
end

d_p90 = 2 * prctile(fg_vals, 90);
d_p95 = 2 * prctile(fg_vals, 95);
d_p99 = 2 * prctile(fg_vals, 99);
[imgH, imgW] = size(I_raw);
n_p90 = imgH * imgW * 0.5 / d_p90^2;
n_p95 = imgH * imgW * 0.5 / d_p95^2;
n_p99 = imgH * imgW * 0.5 / d_p99^2;
n_mid = max(3, round((n_p90 * n_p95 * n_p99)^(1/3)));
end
