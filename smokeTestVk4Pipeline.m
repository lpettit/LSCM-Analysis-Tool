function smokeTestVk4Pipeline(vk4FileName)
% smokeTestVk4Pipeline
% Non-interactive smoke test for one VK4 input file.

repoRoot = fileparts(mfilename('fullpath'));
addpath(genpath(fullfile(repoRoot, 'vk4mat-main')));

testDir = fullfile(repoRoot, 'Test vk4 Files');
outBase = fullfile(repoRoot, 'tmp_smoke_all');
if ~exist(outBase, 'dir')
    mkdir(outBase);
end

if nargin < 1 || isempty(vk4FileName)
    vk4FileName = 'Left-50x-pp-F3.5-PC800.vk4';
end

fillDeepPits = false;
fillThreshold = 0.3;
if strcmpi(vk4FileName, 'Left-50x-pp-F3.5-PC800.vk4')
    fillDeepPits = true;
    fillThreshold = 0.49;
end

targetPath = fullfile(testDir, vk4FileName);
if ~exist(targetPath, 'file')
    error('smokeTestVk4Pipeline:MissingFile', 'Requested test file not found: %s', targetPath);
end

figVisState = get(groot, 'DefaultFigureVisible');
cleanupObj = onCleanup(@() set(groot, 'DefaultFigureVisible', figVisState));
set(groot, 'DefaultFigureVisible', 'off');

fprintf('VK4 PIPELINE SMOKE TEST: %s\n', vk4FileName);

results = struct('name', {}, 'status', {}, 'mounds', {}, 'cavities', {}, ...
                 'shape_n', {}, 'message', {});

outDir = fullfile(outBase, erase(vk4FileName, '.vk4'));
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

try
    [~, xy, zrange, H, W] = readVK4(targetPath);
    fprintf('readVK4 PASS: size=%dx%d xy=%.6f zrange=%.4f\n', H, W, xy, zrange);

    bestParams = autoTuneMounds(targetPath, fillDeepPits, fillThreshold, 3, 20, 4, false);
    m1 = analyzeMounds(targetPath, bestParams, fillDeepPits, fillThreshold, 3, 20, [], [], outDir);
    c2 = analyzeCavities(m1, 2.0, fillDeepPits, fillThreshold, [], outDir);
    m3 = analyzeMoundShape(m1, outDir);
    assert(isfield(m3, 'Rz_per_mound'));
    assert(isfield(m3, 'preferred_Rz_per_mound'));
    assert(isfield(m3, 'feret_max_um'));
    assert(isfield(m3, 'feret_min_um'));
    assert(isfield(m3, 'circularity'));
    assert(all(isfinite(m3.preferred_Rz_per_mound(m3.preferred_valid_flag))));
    assert(all(isfinite(m3.feret_max_um(m3.preferred_valid_flag))));

    results(end+1) = struct( ... %#ok<AGROW>
        'name', vk4FileName, ...
        'status', 'PASS', ...
        'mounds', m1.n_mounds, ...
        'cavities', c2.n_cavities, ...
        'shape_n', m3.n_mounds, ...
        'message', '');

    fprintf('PIPELINE PASS: mounds=%d cavities=%d shape_n=%d\n', ...
            m1.n_mounds, c2.n_cavities, m3.n_mounds);
catch ME
    results(end+1) = struct( ... %#ok<AGROW>
        'name', vk4FileName, ...
        'status', 'FAIL', ...
        'mounds', NaN, ...
        'cavities', NaN, ...
        'shape_n', NaN, ...
        'message', ME.getReport());

    fprintf(2, 'PIPELINE FAIL: %s\n', ME.message);
end

close all force;

fprintf('\nFINAL SUMMARY\n');
for k = 1:numel(results)
    fprintf('%s | %s | mounds=%g cavities=%g shape_n=%g\n', ...
            results(k).name, results(k).status, ...
            results(k).mounds, results(k).cavities, results(k).shape_n);
    if ~isempty(results(k).message)
        fprintf('  message: %s\n', results(k).message);
    end
end

if any(strcmp({results.status}, 'FAIL'))
    error('smokeTestVk4Pipeline:Failed', 'One or more VK4 smoke tests failed.');
end

fprintf('\nALL VK4 PIPELINE SMOKE TESTS PASSED\n');
end
