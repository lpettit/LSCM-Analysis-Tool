function app = launchSOLFAnalysisApp()
% launchSOLFAnalysisApp
% Convenience launcher for the single-file SOLF analysis app.
ensureVk4matOnPath();
app = SOLFAnalysisApp();
end

function ensureVk4matOnPath()
repoRoot = fileparts(mfilename('fullpath'));
vk4matRoot = fullfile(repoRoot, 'vk4mat-main');

if exist('vk4_readVk4Binary', 'file') && exist('vk4_computeVk4Offsets', 'file')
    return;
end

if exist(vk4matRoot, 'dir')
    addpath(genpath(vk4matRoot));
end
end
