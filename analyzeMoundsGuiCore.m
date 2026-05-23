function results = analyzeMoundsGuiCore(imagePath, bestParams, fillDeepPits, fillThreshold, ...
                                  dilateRadius, minObjectArea, xy_um_per_px, ...
                                  total_height_um, outputDir)
% =========================================================================
%  analyzeMoundsGuiCore  —  Module 1: Spacing, density, and Delaunay analysis
%
%  Accepts either a Keyence VK4 file (full 32-bit precision, calibration
%  read automatically from the file) or a standard grayscale/RGB image
%  (BMP, TIFF, PNG) with manually supplied calibration constants.
%
%  USAGE — VK4 input (recommended):
%    results = analyzeMounds('Left-50x.vk4', bestParams, false, 0.3, 3, 20)
%    results = analyzeMounds('Left-50x.vk4', bestParams, false, 0.3, 3, 20, ...
%                             [], [], 'output_folder')
%
%  USAGE — BMP/image input (legacy):
%    results = analyzeMounds('Left-50x.bmp', bestParams, false, 0.3, 3, 20, ...
%                             0.14174, 80.58)
%    results = analyzeMounds('Left-50x.bmp', bestParams, false, 0.3, 3, 20, ...
%                             0.14174, 80.58, 'output_folder')
%
%  INPUTS:
%    imagePath      - path to .vk4 file  OR  grayscale/RGB image file
%    bestParams     - table from autoTuneMounds (gaussSigma, contrastMethod,
%                     clipLimit, openRadius)
%    fillDeepPits   - boolean (same as used in autoTuneMounds)
%    fillThreshold  - pit fill threshold (same as used in autoTuneMounds)
%    dilateRadius   - blob dilation radius (same as used in autoTuneMounds)
%    minObjectArea  - minimum blob area (same as used in autoTuneMounds)
%    xy_um_per_px   - lateral calibration in µm/pixel.
%                     REQUIRED for image input; ignored ([] ok) for VK4.
%    total_height_um- total z-range of scan in µm.
%                     REQUIRED for image input; ignored ([] ok) for VK4.
%    outputDir      - (optional) folder to save outputs; default = image folder
%
%  VK4 vs IMAGE INPUT:
%    VK4:   calibration (xy_um_per_px, total_height_um) is read directly
%           from the file binary — no manual entry needed or used.
%           Requires readVK4.m and the vk4mat library on the MATLAB path.
%           Height map has 32-bit precision (~0.001 µm/count vs ~0.316 µm
%           for 8-bit BMP), which matters for Module 3 refPlane accuracy.
%    Image: calibration must be supplied as arguments (legacy behaviour,
%           unchanged from previous versions).
%
%  OUTPUTS (struct fields):
%    centroids      - Nx2 array of mound centroid [x,y] in pixels
%    n_mounds       - total mound count (border-excluded)
%    density_mm2    - mound density in mounds/mm²
%    nn_dist_px     - trimmed Delaunay NN distances in pixels
%    nn_dist_um     - trimmed Delaunay NN distances in µm
%    nn_mean_px     - mean NN spacing in pixels
%    nn_mean_um     - mean NN spacing in µm
%    nn_std_px      - std NN spacing in pixels
%    nn_std_um      - std NN spacing in µm
%    nn_cv          - coefficient of variation of NN spacing
%    dt             - delaunayTriangulation object
%    trimmed_edges  - Mx2 edge index pairs after trimming long boundary edges
%    Z              - calibrated height map in µm (double, same size as image)
%    I_raw          - uint8 grayscale display image (for downstream figures
%                     and pit detection); from imread for BMP, derived from
%                     Z for VK4.  Stored here so downstream modules do not
%                     need to re-read from disk.
%    xy_um_per_px   - lateral scale in µm/pixel (from file or argument)
%    total_height_um- z-range in µm  (from file or argument)
%    imageName      - image filename without extension (for labelling)
%    imagePath      - original input path (for provenance)
%
%  SAVES:
%    <name>_delaunay.png    - original image with Delaunay web overlay
%    <name>_spacing.png     - NN spacing histogram (px and µm)
%    <name>_results.xlsx    - per-edge spacing table + summary statistics
%    <name>_results.mat     - full results struct for downstream modules
%
%  REQUIRES: Image Processing Toolbox
%            readVK4.m + vk4mat library (VK4 input only)
% =========================================================================

% --- Handle optional args -------------------------------------------------
if nargin < 7, xy_um_per_px    = []; end
if nargin < 8, total_height_um = []; end

[imageFolder, imageName, imageExt] = fileparts(imagePath);
is_vk4 = strcmpi(imageExt, '.vk4');

if nargin < 9 || isempty(outputDir)
    outputDir = imageFolder;
end
if isempty(outputDir), outputDir = pwd; end
if ~exist(outputDir, 'dir'), mkdir(outputDir); end

fprintf('analyzeMoundsGuiCore: %s\n', imageName);

% =========================================================================
%  LOAD IMAGE AND BUILD HEIGHT MAP
%  Two paths depending on file type:
%    VK4  — readVK4 returns calibrated Z (µm), xy, total_height_um
%    Image — imread + user-supplied calibration constants
% =========================================================================
if is_vk4
    % --- VK4 path: full 32-bit precision, calibration from file ----------
    if ~exist('readVK4', 'file')
        error(['analyzeMoundsGuiCore: readVK4.m not found on MATLAB path.\n' ...
               'Required for .vk4 input. Add readVK4.m and the vk4mat\n' ...
               'library (https://github.com/matt-black/vk4mat) to path.']);
    end
    fprintf('  Loading VK4 (32-bit height map)...\n');
    [Z, xy_um_per_px, total_height_um, imgH, imgW] = readVK4(imagePath);

    % Derive uint8 display image from calibrated Z — identical in
    % information content to what imread returns from the companion BMP,
    % but without 8-bit quantisation loss in the height map itself.
    I_raw = uint8(round(Z / total_height_um * 255));
    I     = double(I_raw) / 255;

else
    % --- Image path (BMP, TIFF, PNG, ...): legacy behaviour --------------
    if isempty(xy_um_per_px) || isempty(total_height_um)
        error(['analyzeMoundsGuiCore: xy_um_per_px and total_height_um are required ' ...
               'for image input (BMP/TIFF/PNG).\n' ...
               'Supply them as arguments 7 and 8, or use a .vk4 file instead.']);
    end
    I_raw = imread(imagePath);
    if size(I_raw, 3) == 3
        I_raw = rgb2gray(I_raw);
    end
    I     = double(im2double(I_raw));
    [imgH, imgW] = size(I);

    % Calibrated height map: z = intensity/255 * total_height_um
    % Note: ~0.316 µm quantisation per count; use VK4 input for higher
    % precision (matters for Module 3 refPlane calculation).
    Z = double(I_raw) / 255 * total_height_um;
end

fprintf('  Image size     : %d × %d px\n',   imgH, imgW);
fprintf('  xy calibration : %.6f µm/px\n',   xy_um_per_px);
fprintf('  Z range        : %.4f µm\n',       total_height_um);

% --- Run detection pipeline with best parameters -------------------------
fprintf('  Running detection pipeline...\n');
[~, centroids] = runPipeline(I, bestParams, fillDeepPits, fillThreshold, ...
                              dilateRadius, minObjectArea);
n_mounds = size(centroids, 1);
fprintf('  Detected %d mounds\n', n_mounds);

if n_mounds < 4
    error('analyzeMoundsGuiCore: fewer than 4 mounds detected — check parameters.');
end

% --- Delaunay triangulation ----------------------------------------------
dt = delaunayTriangulation(centroids(:,1), centroids(:,2));

% Use alpha shape to remove long outer boundary edges that would not
% exist if the field of view were wider. The alpha parameter is found
% by iterating to a self-consistent solution where alpha equals the
% median edge length of the resulting shape.
% Initial alpha: median of all Delaunay edges — robust starting point.
all_edges_full = dt.edges();
d1_all = centroids(all_edges_full(:,1), :);
d2_all = centroids(all_edges_full(:,2), :);
init_alpha = median(sqrt(sum((d1_all - d2_all).^2, 2)));

[S_alpha, alpha_final] = computeAlphaShape(centroids, init_alpha);
fprintf('  Alpha shape converged: alpha = %.1f px\n', alpha_final);

% Extract edges from alpha shape triangulation
tris          = S_alpha.alphaTriangulation;
raw_edges     = unique(sort([tris(:,[1 2]); tris(:,[2 3]); tris(:,[3 1])], 2), 'rows');
d1            = centroids(raw_edges(:,1), :);
d2            = centroids(raw_edges(:,2), :);
all_dists_px  = sqrt(sum((d1 - d2).^2, 2));
trimmed_edges = raw_edges;
nn_dist_px    = all_dists_px;
nn_dist_um    = nn_dist_px * xy_um_per_px;

% --- Summary statistics --------------------------------------------------
nn_mean_px = mean(nn_dist_px);
nn_std_px  = std(nn_dist_px);
nn_mean_um = mean(nn_dist_um);
nn_std_um  = std(nn_dist_um);
nn_cv      = nn_std_px / nn_mean_px;

% --- Mound density -------------------------------------------------------
% Effective area: centroid bounding box rather than full image area.
% The nearest centroid to each edge defines the effective image boundary,
% naturally accounting for whatever border margin imclearborder imposed
% without needing a fixed pixel offset. The "shaved" widths are reported
% so the cropping is transparent.
x_min_px = min(centroids(:,1));   % nearest centroid to left edge
x_max_px = max(centroids(:,1));   % nearest centroid to right edge
y_min_px = min(centroids(:,2));   % nearest centroid to top edge
y_max_px = max(centroids(:,2));   % nearest centroid to bottom edge

eff_width_px  = x_max_px - x_min_px;
eff_height_px = y_max_px - y_min_px;

fprintf('  Effective area crop (px): left=%.0f  right=%.0f  top=%.0f  bottom=%.0f\n', ...
        x_min_px, imgW - x_max_px, y_min_px, imgH - y_max_px);

image_area_um2 = eff_width_px * eff_height_px * xy_um_per_px^2;
image_area_mm2 = image_area_um2 / 1e6;
density_mm2    = n_mounds / image_area_mm2;

fprintf('  Mean NN spacing : %.1f px  |  %.2f µm\n', nn_mean_px, nn_mean_um);
fprintf('  Std  NN spacing : %.1f px  |  %.2f µm\n', nn_std_px,  nn_std_um);
fprintf('  CV              : %.3f\n', nn_cv);
fprintf('  Mound density   : %.1f mounds/mm²\n', density_mm2);

fprintf('  GUI mode: skipping standalone mound-spacing figures.\n');
createStandaloneFigures = strcmp(getenv('SOLF_GUI_WRITE_FIGURES'), '1');
if createStandaloneFigures
% --- Figure 1: Delaunay overlay on original image ------------------------
fprintf('  Generating Delaunay overlay figure...\n');
fig1 = figure('Name', 'Delaunay spacing web', ...
              'Position', [50 50 1100 850], 'Color', 'w');

% Convert to uint8 RGB so colormap changes don't affect the image display
I_rgb = repmat(I_raw, [1 1 3]);
imshow(I_rgb); hold on;

% Draw trimmed Delaunay edges, coloured by edge length
edge_lengths_um = nn_dist_um;
cmap = parula(256);
clim_lo = prctile(edge_lengths_um, 5);
clim_hi = prctile(edge_lengths_um, 95);

for k = 1:size(trimmed_edges, 1)
    i1 = trimmed_edges(k, 1);
    i2 = trimmed_edges(k, 2);
    x  = [centroids(i1,1), centroids(i2,1)];
    y  = [centroids(i1,2), centroids(i2,2)];

    % Map edge length to colour
    t    = (edge_lengths_um(k) - clim_lo) / max(clim_hi - clim_lo, eps);
    t    = max(0, min(1, t));
    cidx = max(1, round(t * 255) + 1);
    col  = cmap(cidx, :);

    line(x, y, 'Color', col, 'LineWidth', 0.8);
end

% Overlay centroids
plot(centroids(:,1), centroids(:,2), 'r.', 'MarkerSize', 8);

% Colourbar
cb = colorbar;
colormap(gca, parula);
clim([clim_lo, clim_hi]);
cb.Label.String = 'NN spacing (µm)';

title(sprintf('%s  |  n=%d  |  %.1f ± %.1f µm  |  %.0f mounds/mm²', ...
      imageName, n_mounds, nn_mean_um, nn_std_um, density_mm2), ...
      'Interpreter', 'none', 'FontSize', 10);

hold off;

delaunay_path = fullfile(outputDir, [imageName '_delaunay.png']);
exportgraphics(fig1, delaunay_path, 'Resolution', 150);
fprintf('  Saved: %s\n', delaunay_path);

% --- Figure 2: NN spacing histogram --------------------------------------
fig2 = figure('Name', 'NN spacing distribution', ...
              'Position', [200 200 800 500], 'Color', 'w');

histogram(nn_dist_um, 40, ...
          'FaceColor', [0.25 0.55 0.85], ...
          'EdgeColor', 'none', 'FaceAlpha', 0.85);
hold on;

% Mean and ±1 std lines
xline(nn_mean_um,             'r-',  'LineWidth', 1.8, ...
      'Label', sprintf('mean = %.1f µm', nn_mean_um), ...
      'LabelVerticalAlignment', 'bottom');
xline(nn_mean_um - nn_std_um, 'r--', 'LineWidth', 1.0);
xline(nn_mean_um + nn_std_um, 'r--', 'LineWidth', 1.0, ...
      'Label', sprintf('±1σ = %.1f µm', nn_std_um), ...
      'LabelVerticalAlignment', 'bottom');

xlabel('NN spacing (µm)');
ylabel('Edge count');
title(sprintf('NN spacing distribution  |  CV = %.3f  |  n = %d mounds', ...
      nn_cv, n_mounds));
grid on;

% Secondary x-axis: pixel values as a manual tick overlay on top spine.
% linkaxes cannot be used here because it syncs display limits, not values.
% Instead we compute pixel tick positions from the µm axis limits and draw
% them on a transparent overlaid axes.
ax1 = gca;
drawnow;                              % ensure ax1 limits are finalised
xlim_um = ax1.XLim;

% Choose ~5 round pixel tick values that fall within the µm range
px_lo    = ceil(xlim_um(1)  / xy_um_per_px / 50) * 50;   % round to 50 px
px_hi    = floor(xlim_um(2) / xy_um_per_px / 50) * 50;
px_ticks = px_lo : 50 : px_hi;
um_ticks = px_ticks * xy_um_per_px;  % positions in µm (bottom axis units)

ax2 = axes('Position', ax1.Position, ...
           'XAxisLocation', 'top', 'YAxisLocation', 'right', ...
           'Color', 'none', 'YTick', []);
ax2.XLim  = xlim_um;                 % same µm limits as ax1
ax2.XTick = um_ticks;                % placed at µm positions of round px values
ax2.XTickLabel = arrayfun(@(v) sprintf('%d', v), px_ticks, ...
                           'UniformOutput', false);
ax2.XLabel.String = 'NN spacing (px)';
ax2.YTick = [];

axes(ax1);                           % return focus to main axes

spacing_path = fullfile(outputDir, [imageName '_spacing.png']);
exportgraphics(fig2, spacing_path, 'Resolution', 150);
fprintf('  Saved: %s\n', spacing_path);

end

% --- Excel output --------------------------------------------------------
fprintf('  Writing Excel output...\n');
xlsx_path = fullfile(outputDir, [imageName '_results.xlsx']);

% Sheet 1: per-edge spacing data
edge_table = table(...
    (1:numel(nn_dist_px))', ...
    nn_dist_px, ...
    nn_dist_um, ...
    'VariableNames', {'EdgeIndex', 'Spacing_px', 'Spacing_um'});
writetable(edge_table, xlsx_path, 'Sheet', 'Spacing_edges');

% Sheet 2: per-mound centroids
centroid_table = table(...
    (1:n_mounds)', ...
    centroids(:,1), ...
    centroids(:,2), ...
    centroids(:,1) * xy_um_per_px, ...
    centroids(:,2) * xy_um_per_px, ...
    'VariableNames', {'MoundIndex','X_px','Y_px','X_um','Y_um'});
writetable(centroid_table, xlsx_path, 'Sheet', 'Centroids');

% Sheet 3: summary statistics
summary = table(...
    {imageName}, ...
    n_mounds, ...
    density_mm2, ...
    image_area_mm2, ...
    nn_mean_px, nn_std_px, ...
    nn_mean_um, nn_std_um, ...
    nn_cv, ...
    xy_um_per_px, ...
    total_height_um, ...
    'VariableNames', { ...
        'ImageName', ...
        'N_mounds', ...
        'Density_mounds_per_mm2', ...
        'Image_area_mm2', ...
        'Mean_spacing_px', 'Std_spacing_px', ...
        'Mean_spacing_um', 'Std_spacing_um', ...
        'CV_spacing', ...
        'xy_um_per_px', ...
        'total_height_um'});
writetable(summary, xlsx_path, 'Sheet', 'Summary');
fprintf('  Saved: %s\n', xlsx_path);

% --- Assemble results struct ---------------------------------------------
results.centroids       = centroids;
results.n_mounds        = n_mounds;
results.density_mm2     = density_mm2;
results.image_area_mm2  = image_area_mm2;
results.nn_dist_px      = nn_dist_px;
results.nn_dist_um      = nn_dist_um;
results.nn_mean_px      = nn_mean_px;
results.nn_mean_um      = nn_mean_um;
results.nn_std_px       = nn_std_px;
results.nn_std_um       = nn_std_um;
results.nn_cv           = nn_cv;
results.dt              = dt;
results.trimmed_edges   = trimmed_edges;
results.Z               = Z;
results.I_raw           = I_raw;       % uint8 grayscale; used by downstream
                                       % modules for figures and pit detection
                                       % without re-reading from disk
results.xy_um_per_px    = xy_um_per_px;
results.total_height_um = total_height_um;
results.imageName       = imageName;
results.imagePath       = imagePath;
results.bestParams      = bestParams;
results.fillDeepPits    = fillDeepPits;
results.fillThreshold   = fillThreshold;
results.dilateRadius    = dilateRadius;
results.minObjectArea   = minObjectArea;

% Save MAT file for downstream modules
mat_path = fullfile(outputDir, [imageName '_results.mat']);
save(mat_path, 'results');
fprintf('  Saved: %s\n', mat_path);

fprintf('analyzeMoundsGuiCore complete.\n\n');

end % analyzeMounds


% =========================================================================
%  PIPELINE  (copy of autoTuneMounds version — kept local for portability)
% =========================================================================
function [fgm4, centroids] = runPipeline(I, p, fillDeepPits, fillThreshold, ...
                                          dilateRadius, minObjectArea)
    Iblur    = imgaussfilt(double(I), double(p.gaussSigma));
    mask     = double(applyContrast(Iblur, char(p.contrastMethod), double(p.clipLimit)));
    Iobrcbr  = preprocessImage(mask, double(p.openRadius));
    fgm4     = extractRegionalMaxima(Iobrcbr, dilateRadius, minObjectArea, ...
                                     fillDeepPits, Iblur, fillThreshold);
    BW       = imclearborder(fgm4);
    stats    = regionprops(BW, 'Centroid');
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
%  ALPHA SHAPE WITH ITERATIVE CONVERGENCE
% =========================================================================
function [S, alpha] = computeAlphaShape(points, initialAlpha)
% Iteratively find a self-consistent alpha where alpha equals the median
% edge length of the resulting alpha shape. Using median (not mean) makes
% convergence robust against outlier edges during early iterations.
%
% After convergence, checks for interior holes (which indicate alpha is
% too small) and nudges alpha upward until the shape is hole-free.
%
% INPUTS:
%   points       - Nx2 array of [x,y] centroid coordinates
%   initialAlpha - starting alpha value (median of all Delaunay edges works)
%
% OUTPUTS:
%   S     - converged alphaShape object
%   alpha - final alpha value

    MAX_ITER  = 50;
    TOL       = 0.1;        % convergence tolerance in pixels
    MAX_HOLES = 10;         % max hole-correction attempts
    HOLE_BUMP = 1.10;       % multiply alpha by this to fix holes

    prevAlpha = 0;
    currAlpha = initialAlpha;
    iter      = 0;

    while abs(prevAlpha - currAlpha) > TOL && iter < MAX_ITER
        prevAlpha = currAlpha;
        S         = alphaShape(points, prevAlpha);

        tris = S.alphaTriangulation;
        if isempty(tris)
            % Alpha too small — all triangles removed; double and retry
            currAlpha = prevAlpha * 2;
            continue;
        end

        edges   = unique(sort([tris(:,[1 2]); tris(:,[2 3]); tris(:,[3 1])], 2), 'rows');
        lengths = sqrt(sum((points(edges(:,1),:) - points(edges(:,2),:)).^2, 2));
        currAlpha = median(lengths);   % median for robust convergence
        iter = iter + 1;
    end

    if iter == MAX_ITER
        warning('computeAlphaShape: max iterations reached (alpha=%.1f)', currAlpha);
    end

    S = alphaShape(points, currAlpha);

    % --- Hole correction --------------------------------------------------
    hole_iter = 0;
    while (countBoundaryLoops(S) > 1 || numRegions(S) > 1) && hole_iter < MAX_HOLES
        currAlpha = currAlpha * HOLE_BUMP;
        S         = alphaShape(points, currAlpha);
        hole_iter = hole_iter + 1;
    end

    if hole_iter > 0
        fprintf('  Alpha shape: corrected %d iteration(s), final alpha=%.1f px\n', ...
                hole_iter, currAlpha);
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

