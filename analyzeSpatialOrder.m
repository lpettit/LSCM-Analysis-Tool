function spatialOrderResults = analyzeSpatialOrder(m1, outputDir)
% =========================================================================
%  analyzeSpatialOrder  -  Module 4: Spatial order, pair distribution,
%                          and lightweight local disorder diagnostics
%
%  Uses Module 1 centroid geometry to quantify sixfold bond-orientational
%  order via planar psi6, spacing periodicity via an approximate 2D pair
%  distribution, and interpretation-oriented local order tiers.
%
%  USAGE:
%    spatialOrderResults = analyzeSpatialOrder(m1)
%    spatialOrderResults = analyzeSpatialOrder(m1, 'output_folder')
%
%  INPUTS:
%    m1           - results struct from analyzeMounds (Module 1)
%    outputDir    - folder to save outputs; default = same folder as image
%
%  OUTPUT HIGHLIGHTS:
%    coordination_number - Delaunay neighbor count for each mound
%    local_psi6          - per-mound sixfold local order magnitude [0, 1]
%    psi6_phase          - per-mound local order phase in radians
%    global_psi6         - coherent field-level sixfold order magnitude
%    voronoi_area_um2    - finite Voronoi cell area per mound
%    local_density_um2_inv - local density from inverse finite Voronoi area
%    nn1_um, nn2_um, nn3_um - first/second/third-neighbor distances
%    pair_r_um           - radial bin centers for approximate g(r)
%    pair_g_r            - approximate 2D pair distribution
%    bond_angle_bins_deg - bond-orientation bin centers in degrees
%    bond_angle_counts   - bond counts per orientation bin
%    disorder_flag       - softened interior-focused disorder flag
%    acf2d               - provisional 2D surface-height autocorrelation
%    acf_anisotropy_ratio - provisional directional elongation summary
%    acf_dominant_orientation_deg - provisional preferred orientation
%
%  SAVES:
%    <n>_spatial_order_psi6.png
%    <n>_spatial_order_defects.png
%    <n>_voronoi_density.png
%    <n>_voronoi_cells.png
%    <n>_voronoi_area_hist.png
%    <n>_neighbor_shells.png
%    <n>_pair_distribution.png
%    <n>_bond_angles.png
%    <n>_acf2d.png
%    <n>_acf_radial.png
%    <n>_acf_directional_cuts.png
%    <n>_acf_vs_gr.png
%    <n>_spatial_order.xlsx
%    <n>_spatial_order.mat
%
%  REQUIRES: Image Processing Toolbox
% =========================================================================

[imageFolder, imageName, ~] = fileparts(m1.imagePath);
if nargin < 2 || isempty(outputDir)
    outputDir = imageFolder;
end
if isempty(outputDir), outputDir = pwd; end
if ~exist(outputDir, 'dir'), mkdir(outputDir); end

fprintf('analyzeSpatialOrder: %s\n', imageName);

% Centralized interpretation thresholds for local tiers and comparison labels.
PSI6_HIGH_THRESHOLD = 0.75;
PSI6_MODERATE_THRESHOLD = 0.45;
LEGACY_HARD_PSI6_THRESHOLD = 0.70;
BOUNDARY_MARGIN_NN_SCALE = 0.75;
BOUNDARY_MARGIN_MIN_PX = 5;
RADIAL_ORDER_STRONG_THRESHOLD = 0.25;
RADIAL_ORDER_MODERATE_THRESHOLD = 0.12;
ORIENT_GLOBAL_STRONG_THRESHOLD = 0.18;
ORIENT_GLOBAL_MODERATE_THRESHOLD = 0.06;
ORIENT_LOCAL_STRONG_THRESHOLD = 0.60;
ORIENT_LOCAL_MODERATE_THRESHOLD = 0.40;
SECOND_NEIGHBOR_LABEL = 'Second-neighbor';
THIRD_NEIGHBOR_LABEL = 'Third-neighbor';

centroids = double(m1.centroids);
trimmed_edges = double(m1.trimmed_edges);
xy = double(m1.xy_um_per_px);
n_mounds = size(centroids, 1);
nn_mean_px = double(m1.nn_mean_px);
nn_mean_um = double(m1.nn_mean_um);
I_rgb = repmat(m1.I_raw, [1 1 3]);
if ~isfield(m1, 'Z') || isempty(m1.Z)
    error('analyzeSpatialOrder:MissingHeightMap', ...
        'Module 4 autocorrelation testing requires m1.Z to be present.');
end
Z_um = double(m1.Z);

if n_mounds < 4
    error('analyzeSpatialOrder:TooFewMounds', ...
        'Module 4 requires at least 4 mounds; got %d.', n_mounds);
end
if isempty(trimmed_edges)
    error('analyzeSpatialOrder:MissingEdges', ...
        'Module 4 requires Module 1 trimmed_edges to be present.');
end

edge_vec = centroids(trimmed_edges(:,2), :) - centroids(trimmed_edges(:,1), :);
edge_len_px = hypot(edge_vec(:,1), edge_vec(:,2));
edge_len_um = edge_len_px * xy;
edge_angle_rad = atan2(edge_vec(:,2), edge_vec(:,1));
edge_angle_deg = mod(rad2deg(edge_angle_rad), 180);

adjacency = buildAdjacency(trimmed_edges, n_mounds);
[coordination_number, psi6_complex, local_psi6, psi6_phase] = ...
    computePsi6Metrics(centroids, adjacency);

valid_local = isfinite(local_psi6);
if ~any(valid_local)
    error('analyzeSpatialOrder:InvalidPsi6', ...
        'Could not compute any finite local psi6 values.');
end

global_psi6 = abs(mean(psi6_complex(valid_local)));
mean_local_psi6 = mean(local_psi6(valid_local), 'omitnan');
std_local_psi6 = std(local_psi6(valid_local), 'omitnan');
median_local_psi6 = median(local_psi6(valid_local), 'omitnan');
p25_local_psi6 = prctile(local_psi6(valid_local), 25);
psi6_high_threshold = PSI6_HIGH_THRESHOLD;
psi6_moderate_threshold = PSI6_MODERATE_THRESHOLD;
psi6_low_threshold = psi6_moderate_threshold;

boundary_margin_px = max(BOUNDARY_MARGIN_MIN_PX, BOUNDARY_MARGIN_NN_SCALE * nn_mean_px);
boundary_flag = identifyBoundaryMounds(centroids, boundary_margin_px);
interior_flag = ~boundary_flag;
valid_interior = valid_local & interior_flag;
if any(valid_interior)
    global_psi6_interior = abs(mean(psi6_complex(valid_interior)));
    mean_local_psi6_interior = mean(local_psi6(valid_interior), 'omitnan');
else
    global_psi6_interior = NaN;
    mean_local_psi6_interior = NaN;
end

non_sixfold_flag = coordination_number ~= 6;
interior_non_sixfold_flag = interior_flag & non_sixfold_flag;
low_psi6_flag = local_psi6 < psi6_moderate_threshold;
moderate_psi6_flag = local_psi6 >= psi6_moderate_threshold & local_psi6 < psi6_high_threshold;
high_psi6_flag = local_psi6 >= psi6_high_threshold;
soft_coordination_flag = interior_flag & (coordination_number < 5 | coordination_number > 7);
disorder_flag = interior_flag & (low_psi6_flag | soft_coordination_flag);
legacy_hard_disorder_flag = non_sixfold_flag | (local_psi6 < LEGACY_HARD_PSI6_THRESHOLD);
[local_order_class, local_order_score] = classifyLocalOrder(boundary_flag, local_psi6, ...
    psi6_moderate_threshold, psi6_high_threshold);

fprintf('  Global psi6 magnitude      : %.3f\n', global_psi6);
fprintf('  Mean local psi6 magnitude  : %.3f +/- %.3f\n', mean_local_psi6, std_local_psi6);
if any(valid_interior)
    fprintf('  Interior global psi6       : %.3f\n', global_psi6_interior);
end
fprintf('  Fraction boundary mounds   : %.3f\n', mean(boundary_flag));
fprintf('  Interior non-6 fraction    : %.3f\n', safeMean(interior_non_sixfold_flag(interior_flag)));
fprintf('  Interior disorder fraction : %.3f\n', safeMean(disorder_flag(interior_flag)));

[pair_r_um, pair_counts, pair_g_r, pair_bin_edges_um, pair_bin_width_um, ...
    pair_density_um2] = computePairDistribution(centroids, xy, nn_mean_um);
[first_peak_r_um, first_peak_g_r] = estimateFirstPairPeak(pair_r_um, pair_g_r, nn_mean_um);
radial_order_score = first_peak_g_r - 1.0;
[acf2d, acf_lag_x_um, acf_lag_y_um, acf_r_um, acf_r, ~, ...
    ~, ~, ~, ...
    acf_anisotropy_ratio, acf_dominant_orientation_deg, acf_x_cut, acf_y_cut, ...
    ~, ~] = computeSurfaceAutocorrelation(Z_um, xy, nn_mean_um);
[nn1_um, nn2_um, nn3_um, neighbor_distance_matrix_um] = computeNeighborShellDistances(centroids, xy);
[voronoi_area_um2, local_density_um2_inv, voronoi_valid_flag, voronoi_polygons_px, ...
    voronoi_clipped_flag, voronoi_augmented_flag, voronoi_added_seed_count] = ...
    computeVoronoiMetrics(m1, centroids, xy);
voronoi_area_mean_um2 = mean(voronoi_area_um2(voronoi_valid_flag), 'omitnan');
voronoi_area_std_um2 = std(voronoi_area_um2(voronoi_valid_flag), 'omitnan');
local_density_mean_um2_inv = mean(local_density_um2_inv(voronoi_valid_flag), 'omitnan');
local_density_std_um2_inv = std(local_density_um2_inv(voronoi_valid_flag), 'omitnan');
nn1_mean_um = mean(nn1_um, 'omitnan');
nn1_std_um = std(nn1_um, 'omitnan');
nn1_cv = nn1_std_um / max(nn1_mean_um, eps);
nn2_mean_um = mean(nn2_um, 'omitnan');
nn2_std_um = std(nn2_um, 'omitnan');
nn2_cv = nn2_std_um / max(nn2_mean_um, eps);
nn3_mean_um = mean(nn3_um, 'omitnan');
nn3_std_um = std(nn3_um, 'omitnan');
nn3_cv = nn3_std_um / max(nn3_mean_um, eps);
orientational_order_label = classifyOrientationalOrder(global_psi6_interior, mean_local_psi6_interior, ...
    ORIENT_GLOBAL_STRONG_THRESHOLD, ORIENT_GLOBAL_MODERATE_THRESHOLD, ...
    ORIENT_LOCAL_STRONG_THRESHOLD, ORIENT_LOCAL_MODERATE_THRESHOLD);
radial_order_label = classifyRadialOrder(radial_order_score, ...
    RADIAL_ORDER_STRONG_THRESHOLD, RADIAL_ORDER_MODERATE_THRESHOLD);
comparison_summary_line = buildComparisonSummaryLine(imageName, radial_order_label, ...
    orientational_order_label, first_peak_r_um, first_peak_g_r, ...
    safeMean(high_psi6_flag(interior_flag)), safeMean(moderate_psi6_flag(interior_flag)), ...
    safeMean(low_psi6_flag(interior_flag)), mean(boundary_flag));

bond_bin_edges_deg = 0:5:180;
bond_angle_counts = histcounts(edge_angle_deg, bond_bin_edges_deg);
bond_angle_bins_deg = bond_bin_edges_deg(1:end-1) + diff(bond_bin_edges_deg) / 2;

psi6_map_path = fullfile(outputDir, [imageName '_spatial_order_psi6.png']);
defect_map_path = fullfile(outputDir, [imageName '_spatial_order_defects.png']);
voronoi_density_path = fullfile(outputDir, [imageName '_voronoi_density.png']);
voronoi_cells_path = fullfile(outputDir, [imageName '_voronoi_cells.png']);
voronoi_area_hist_path = fullfile(outputDir, [imageName '_voronoi_area_hist.png']);
neighbor_shells_path = fullfile(outputDir, [imageName '_neighbor_shells.png']);
pair_plot_path = fullfile(outputDir, [imageName '_pair_distribution.png']);
bond_plot_path = fullfile(outputDir, [imageName '_bond_angles.png']);
acf2d_path = fullfile(outputDir, [imageName '_acf2d.png']);
acf_radial_path = fullfile(outputDir, [imageName '_acf_radial.png']);
acf_directional_path = fullfile(outputDir, [imageName '_acf_directional_cuts.png']);
acf_vs_gr_path = fullfile(outputDir, [imageName '_acf_vs_gr.png']);
xlsx_path = fullfile(outputDir, [imageName '_spatial_order.xlsx']);
mat_path = fullfile(outputDir, [imageName '_spatial_order.mat']);
tabbed_fig = createSpatialOrderTabbedFigure(imageName);

fprintf('  Generating local psi6 map...\n');
ax_psi6 = axes('Parent', tabbed_fig.tabs.psi6);
showDiagnosticImage(ax_psi6, I_rgb); hold(ax_psi6, 'on');
drawEdges(ax_psi6, centroids, trimmed_edges, [0.8 0.8 0.8], 0.35);
scatter(ax_psi6, centroids(:,1), centroids(:,2), 42, local_psi6, 'filled', ...
    'MarkerEdgeColor', [0.15 0.15 0.15], 'LineWidth', 0.35);
cb = colorbar(ax_psi6);
cb.Label.String = 'Local |\psi_6|';
clim(ax_psi6, [0 1]);
title(ax_psi6, sprintf('%s  |  spatial order map  |  global |\\psi_6| = %.3f', ...
    imageName, global_psi6), 'Interpreter', 'none');
hold(ax_psi6, 'off');
exportgraphics(ax_psi6, psi6_map_path, 'Resolution', 150);
fprintf('  Saved: %s\n', psi6_map_path);

fprintf('  Generating disorder map...\n');
t = tiledlayout(tabbed_fig.tabs.order, 1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile(t, 1);
showDiagnosticImage(gca, I_rgb); hold(gca, 'on');
drawEdges(gca, centroids, trimmed_edges, [0.78 0.78 0.78], 0.35);
scatter(gca, centroids(:,1), centroids(:,2), 42, coordination_number, 'filled', ...
    'MarkerEdgeColor', [0.15 0.15 0.15], 'LineWidth', 0.35);
cb = colorbar(gca);
cb.Label.String = 'Coordination number';
title(gca, 'Coordination number');
hold(gca, 'off');

nexttile(t, 2);
showDiagnosticImage(gca, I_rgb); hold(gca, 'on');
drawEdges(gca, centroids, trimmed_edges, [0.82 0.82 0.82], 0.30);
idx_boundary = strcmp(local_order_class, 'boundary');
idx_low = strcmp(local_order_class, 'low');
idx_moderate = strcmp(local_order_class, 'moderate');
idx_high = strcmp(local_order_class, 'high');
h_boundary = plot(gca, centroids(idx_boundary,1), centroids(idx_boundary,2), 'o', ...
    'MarkerSize', 5, 'MarkerFaceColor', [0.60 0.60 0.60], ...
    'MarkerEdgeColor', [0.35 0.35 0.35]);
h_low = plot(gca, centroids(idx_low,1), centroids(idx_low,2), 'o', ...
    'MarkerSize', 6, 'MarkerFaceColor', [0.86 0.24 0.18], ...
    'MarkerEdgeColor', [0.45 0.10 0.08]);
h_moderate = plot(gca, centroids(idx_moderate,1), centroids(idx_moderate,2), 'o', ...
    'MarkerSize', 5, 'MarkerFaceColor', [0.93 0.76 0.22], ...
    'MarkerEdgeColor', [0.55 0.41 0.07]);
h_high = plot(gca, centroids(idx_high,1), centroids(idx_high,2), 'o', ...
    'MarkerSize', 5, 'MarkerFaceColor', [0.18 0.65 0.28], ...
    'MarkerEdgeColor', [0.10 0.32 0.10]);
title(gca, sprintf('Local order tiers  |  boundary margin = %.1f px', boundary_margin_px));
legend(gca, [h_boundary, h_low, h_moderate, h_high], {'Boundary', 'Low', 'Moderate', 'High'}, ...
    'Location', 'southoutside', 'Orientation', 'horizontal');
hold(gca, 'off');

exportgraphics(t, defect_map_path, 'Resolution', 150);
fprintf('  Saved: %s\n', defect_map_path);

fprintf('  Generating Voronoi density diagnostics...\n');
t = tiledlayout(tabbed_fig.tabs.voronoi, 1, 3, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile(t, 1);
showDiagnosticImage(gca, I_rgb); hold(gca, 'on');
drawVoronoiCells(gca, voronoi_polygons_px, voronoi_valid_flag, voronoi_area_um2);
plot(gca, centroids(voronoi_valid_flag,1), centroids(voronoi_valid_flag,2), '.', ...
    'Color', [1 1 1], 'MarkerSize', 4);
if any(~voronoi_valid_flag)
    plot(gca, centroids(~voronoi_valid_flag,1), centroids(~voronoi_valid_flag,2), 'x', ...
        'Color', [0.55 0.55 0.55], 'MarkerSize', 5, 'LineWidth', 0.8);
end
cb = colorbar(gca);
cb.Label.String = 'Finite Voronoi cell area (um^2)';
title(gca, 'Voronoi cells colored by area');
hold(gca, 'off');

nexttile(t, 2);
showDiagnosticImage(gca, I_rgb); hold(gca, 'on');
drawEdges(gca, centroids, trimmed_edges, [0.84 0.84 0.84], 0.25);
valid_density_idx = voronoi_valid_flag & isfinite(local_density_um2_inv);
invalid_density_idx = ~valid_density_idx;
if any(valid_density_idx)
    scatter(gca, centroids(valid_density_idx,1), centroids(valid_density_idx,2), 42, ...
        local_density_um2_inv(valid_density_idx), 'filled', ...
        'MarkerEdgeColor', [0.15 0.15 0.15], 'LineWidth', 0.35);
    cb = colorbar(gca);
    cb.Label.String = 'Local density (1 / Voronoi area, um^{-2})';
end
if any(invalid_density_idx)
    plot(gca, centroids(invalid_density_idx,1), centroids(invalid_density_idx,2), 'x', ...
        'Color', [0.55 0.55 0.55], 'MarkerSize', 5, 'LineWidth', 0.8);
end
title(gca, sprintf('Local density map  |  finite Voronoi cells = %d / %d', ...
    sum(valid_density_idx), n_mounds));
hold(gca, 'off');

nexttile(t, 3);
valid_area = voronoi_area_um2(voronoi_valid_flag);
ax_voronoi_hist = gca;
if isempty(valid_area)
    axis(ax_voronoi_hist, 'off');
    text(ax_voronoi_hist, 0.5, 0.5, 'No finite Voronoi cells available', 'HorizontalAlignment', 'center');
else
    histogram(ax_voronoi_hist, valid_area, 30, 'FaceColor', [0.25 0.55 0.85], ...
        'EdgeColor', 'none', 'FaceAlpha', 0.9);
    hold(ax_voronoi_hist, 'on');
    xline(ax_voronoi_hist, voronoi_area_mean_um2, 'r-', 'LineWidth', 1.6, ...
        'Label', sprintf('mean = %.1f um^2', voronoi_area_mean_um2), ...
        'LabelVerticalAlignment', 'bottom');
    xline(ax_voronoi_hist, voronoi_area_mean_um2 - voronoi_area_std_um2, 'r--', 'LineWidth', 1.0);
    xline(ax_voronoi_hist, voronoi_area_mean_um2 + voronoi_area_std_um2, 'r--', 'LineWidth', 1.0);
    xlabel(ax_voronoi_hist, 'Finite Voronoi cell area (um^2)');
    ylabel(ax_voronoi_hist, 'Count');
    title(ax_voronoi_hist, 'Voronoi cell area distribution');
    grid(ax_voronoi_hist, 'on');
    hold(ax_voronoi_hist, 'off');
end

exportgraphics(t, voronoi_density_path, 'Resolution', 150);
fprintf('  Saved: %s\n', voronoi_density_path);
fig_cells = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 900 820]);
ax_cells = axes(fig_cells);
showDiagnosticImage(ax_cells, I_rgb); hold(ax_cells, 'on');
drawVoronoiCells(ax_cells, voronoi_polygons_px, voronoi_valid_flag, voronoi_area_um2);
plot(ax_cells, centroids(voronoi_valid_flag,1), centroids(voronoi_valid_flag,2), '.', ...
    'Color', [1 1 1], 'MarkerSize', 4);
if any(~voronoi_valid_flag)
    plot(ax_cells, centroids(~voronoi_valid_flag,1), centroids(~voronoi_valid_flag,2), 'x', ...
        'Color', [0.55 0.55 0.55], 'MarkerSize', 5, 'LineWidth', 0.8);
end
cb = colorbar(ax_cells);
cb.Label.String = 'Finite Voronoi cell area (um^2)';
title(ax_cells, sprintf('%s | Voronoi cells colored by area', imageName), 'Interpreter', 'none');
hold(ax_cells, 'off');
exportgraphics(fig_cells, voronoi_cells_path, 'Resolution', 150);
close(fig_cells);
fprintf('  Saved: %s\n', voronoi_cells_path);
if isempty(valid_area)
    fig_hist = figure('Visible', 'off');
    ax_hist = axes(fig_hist);
    axis(ax_hist, 'off');
    text(ax_hist, 0.5, 0.5, 'No finite Voronoi cells available', 'HorizontalAlignment', 'center');
    exportgraphics(fig_hist, voronoi_area_hist_path, 'Resolution', 150);
    close(fig_hist);
else
    exportgraphics(ax_voronoi_hist, voronoi_area_hist_path, 'Resolution', 150);
end
fprintf('  Saved: %s\n', voronoi_area_hist_path);

fprintf('  Generating neighbor-shell diagnostics...\n');
t = tiledlayout(tabbed_fig.tabs.neighbors, 2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile(t, 1);
showDiagnosticImage(gca, I_rgb); hold(gca, 'on');
scatter(gca, centroids(:,1), centroids(:,2), 42, nn1_um, 'filled', ...
    'MarkerEdgeColor', [0.15 0.15 0.15], 'LineWidth', 0.35);
cb = colorbar(gca);
cb.Label.String = '1st-neighbor spacing (um)';
title(gca, sprintf('Nearest-neighbor spacing map | mean = %.2f um, CV = %.3f', nn1_mean_um, nn1_cv));
hold(gca, 'off');

nexttile(t, 2);
showDiagnosticImage(gca, I_rgb); hold(gca, 'on');
scatter(gca, centroids(:,1), centroids(:,2), 42, nn2_um, 'filled', ...
    'MarkerEdgeColor', [0.15 0.15 0.15], 'LineWidth', 0.35);
cb = colorbar(gca);
cb.Label.String = '2nd-neighbor spacing (um)';
title(gca, sprintf('%s spacing map | mean = %.2f um, CV = %.3f', SECOND_NEIGHBOR_LABEL, nn2_mean_um, nn2_cv));
hold(gca, 'off');

nexttile(t, 3);
showDiagnosticImage(gca, I_rgb); hold(gca, 'on');
scatter(gca, centroids(:,1), centroids(:,2), 42, nn3_um, 'filled', ...
    'MarkerEdgeColor', [0.15 0.15 0.15], 'LineWidth', 0.35);
cb = colorbar(gca);
cb.Label.String = '3rd-neighbor spacing (um)';
title(gca, sprintf('%s spacing map | mean = %.2f um, CV = %.3f', THIRD_NEIGHBOR_LABEL, nn3_mean_um, nn3_cv));
hold(gca, 'off');

nexttile(t, 4);
all_neighbor_shells = [nn1_um(:); nn2_um(:); nn3_um(:)];
all_neighbor_shells = all_neighbor_shells(isfinite(all_neighbor_shells));
if isempty(all_neighbor_shells)
    axis(gca, 'off');
    text(gca, 0.5, 0.5, 'No neighbor-shell spacing data available', 'HorizontalAlignment', 'center');
else
    edges = linspace(min(all_neighbor_shells), max(all_neighbor_shells), 35);
    if numel(edges) < 2 || max(all_neighbor_shells) <= min(all_neighbor_shells)
        edges = linspace(min(all_neighbor_shells) - 0.1, max(all_neighbor_shells) + 0.1, 10);
    end
    histogram(gca, nn1_um, edges, 'FaceColor', [0.15 0.55 0.90], 'EdgeColor', 'none', 'FaceAlpha', 0.55);
    hold(gca, 'on');
    histogram(gca, nn2_um, edges, 'FaceColor', [0.90 0.55 0.15], 'EdgeColor', 'none', 'FaceAlpha', 0.45);
    histogram(gca, nn3_um, edges, 'FaceColor', [0.25 0.70 0.35], 'EdgeColor', 'none', 'FaceAlpha', 0.40);
    xlabel(gca, 'Neighbor-shell spacing (um)');
    ylabel(gca, 'Count');
    title(gca, '1st/2nd/3rd-neighbor spacing distributions');
    h_nn1_proxy = makePatchLegendProxy(gca, [0.15 0.55 0.90], 0.55);
    h_nn2_proxy = makePatchLegendProxy(gca, [0.90 0.55 0.15], 0.45);
    h_nn3_proxy = makePatchLegendProxy(gca, [0.25 0.70 0.35], 0.40);
    legend(gca, [h_nn1_proxy, h_nn2_proxy, h_nn3_proxy], ...
        {sprintf('NN1 (CV %.3f)', nn1_cv), sprintf('NN2 (CV %.3f)', nn2_cv), sprintf('NN3 (CV %.3f)', nn3_cv)}, ...
        'Location', 'northeast');
    grid(gca, 'on');
    hold(gca, 'off');
end

exportgraphics(t, neighbor_shells_path, 'Resolution', 150);
fprintf('  Saved: %s\n', neighbor_shells_path);

fprintf('  Generating pair-distribution plot...\n');
ax_pair = axes('Parent', tabbed_fig.tabs.pair);
plot(ax_pair, pair_r_um, pair_g_r, 'LineWidth', 2.0, 'Color', [0.10 0.36 0.68]);
hold(ax_pair, 'on');
yline(ax_pair, 1.0, '--', 'Color', [0.50 0.50 0.50], 'LineWidth', 1.0, ...
    'Label', 'random baseline', 'LabelVerticalAlignment', 'bottom');
if isfinite(first_peak_r_um)
    plot(ax_pair, first_peak_r_um, first_peak_g_r, 'o', 'MarkerSize', 8, ...
        'MarkerFaceColor', [0.86 0.24 0.18], 'MarkerEdgeColor', 'none');
    text(ax_pair, first_peak_r_um, first_peak_g_r, ...
        sprintf('  first peak: %.2f um, g(r)=%.2f', first_peak_r_um, first_peak_g_r), ...
        'VerticalAlignment', 'bottom', 'Color', [0.30 0.12 0.10]);
end
xlabel(ax_pair, 'r (um)');
ylabel(ax_pair, 'Approximate g(r)');
title(ax_pair, sprintf('%s  |  pair distribution  |  bin width = %.3f um', ...
    imageName, pair_bin_width_um), 'Interpreter', 'none');
grid(ax_pair, 'on');
hold(ax_pair, 'off');
exportgraphics(ax_pair, pair_plot_path, 'Resolution', 150);
fprintf('  Saved: %s\n', pair_plot_path);

fprintf('  Generating bond-angle plot...\n');
t = tiledlayout(tabbed_fig.tabs.bond, 1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile(t, 1);
histogram(gca, edge_angle_deg, bond_bin_edges_deg, ...
    'FaceColor', [0.25 0.55 0.85], 'EdgeColor', 'none', 'FaceAlpha', 0.9);
xlabel(gca, 'Bond orientation (deg, modulo 180)');
ylabel(gca, 'Bond count');
title(gca, 'Bond-angle histogram');
grid(gca, 'on');

nexttile(t, 2);
polarhistogram(deg2rad(edge_angle_deg * 2), deg2rad(bond_bin_edges_deg * 2), ...
    'FaceColor', [0.15 0.60 0.55], 'EdgeColor', 'none', 'FaceAlpha', 0.85);
ax = gca;
ax.ThetaZeroLocation = 'right';
ax.ThetaDir = 'counterclockwise';
ax.ThetaTickLabel = compose('%d', mod(ax.ThetaTick / 2, 180));
title('Rose-style view (doubled to show 180 deg symmetry)');

exportgraphics(t, bond_plot_path, 'Resolution', 150);
fprintf('  Saved: %s\n', bond_plot_path);

fprintf('  Generating autocorrelation diagnostics...\n');
ax_acf2d = axes('Parent', tabbed_fig.tabs.acf2d);
imagesc(ax_acf2d, acf_lag_x_um, acf_lag_y_um, acf2d);
axis(ax_acf2d, 'image');
set(ax_acf2d, 'YDir', 'normal');
colormap(ax_acf2d, parula(256));
cb = colorbar(ax_acf2d);
cb.Label.String = 'Normalized ACF';
xlabel(ax_acf2d, '\Deltax (um)');
ylabel(ax_acf2d, '\Deltay (um)');
title(ax_acf2d, sprintf('%s  |  2D surface-height ACF diagnostic', imageName), ...
    'Interpreter', 'none');
exportgraphics(ax_acf2d, acf2d_path, 'Resolution', 150);
fprintf('  Saved: %s\n', acf2d_path);

ax_acf_radial = axes('Parent', tabbed_fig.tabs.acfRadial);
plot(ax_acf_radial, acf_r_um, acf_r, 'LineWidth', 2.0, 'Color', [0.15 0.45 0.78]);
hold(ax_acf_radial, 'on');
yline(ax_acf_radial, 0.0, '--', 'Color', [0.60 0.60 0.60], 'LineWidth', 1.0);
xlabel(ax_acf_radial, 'r (um)');
ylabel(ax_acf_radial, 'Radial ACF');
title(ax_acf_radial, sprintf('%s  |  radial ACF diagnostic', imageName), 'Interpreter', 'none');
grid(ax_acf_radial, 'on');
hold(ax_acf_radial, 'off');
exportgraphics(ax_acf_radial, acf_radial_path, 'Resolution', 150);
fprintf('  Saved: %s\n', acf_radial_path);

t = tiledlayout(tabbed_fig.tabs.acfCuts, 1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile(t, 1);
plot(gca, acf_lag_x_um, acf_x_cut, 'LineWidth', 2.0, 'Color', [0.85 0.33 0.10]);
xlabel(gca, '\Deltax (um)');
ylabel(gca, 'ACF');
title(gca, 'Horizontal cut (\Deltay = 0)');
grid(gca, 'on');

nexttile(t, 2);
plot(gca, acf_lag_y_um, acf_y_cut, 'LineWidth', 2.0, 'Color', [0.10 0.55 0.42]);
xlabel(gca, '\Deltay (um)');
ylabel(gca, 'ACF');
title(gca, sprintf('Vertical cut (\\Deltax = 0) | anisotropy %.2f | %.1f deg', ...
    acf_anisotropy_ratio, acf_dominant_orientation_deg));
grid(gca, 'on');

exportgraphics(t, acf_directional_path, 'Resolution', 150);
fprintf('  Saved: %s\n', acf_directional_path);

ax_acf_compare = axes('Parent', tabbed_fig.tabs.acfCompare);
yyaxis(ax_acf_compare, 'left');
plot(ax_acf_compare, acf_r_um, acf_r, 'LineWidth', 2.0, 'Color', [0.15 0.45 0.78]);
ylabel(ax_acf_compare, 'Radial ACF');
yyaxis(ax_acf_compare, 'right');
plot(ax_acf_compare, pair_r_um, pair_g_r, 'LineWidth', 1.8, 'Color', [0.85 0.33 0.10]);
ylabel(ax_acf_compare, 'Approximate g(r)');
xlabel(ax_acf_compare, 'r (um)');
title(ax_acf_compare, sprintf('%s  |  radial ACF vs g(r)', imageName), 'Interpreter', 'none');
grid(ax_acf_compare, 'on');
exportgraphics(ax_acf_compare, acf_vs_gr_path, 'Resolution', 150);
fprintf('  Saved: %s\n', acf_vs_gr_path);

fprintf('  Writing Excel output...\n');
per_mound_table = table( ...
    (1:n_mounds)', ...
    centroids(:,1), ...
    centroids(:,2), ...
    centroids(:,1) * xy, ...
    centroids(:,2) * xy, ...
    coordination_number, ...
    local_psi6, ...
    psi6_phase, ...
    rad2deg(psi6_phase), ...
    boundary_flag, ...
    interior_flag, ...
    local_order_score, ...
    string(local_order_class), ...
    voronoi_valid_flag, ...
    voronoi_clipped_flag, ...
    voronoi_augmented_flag, ...
    voronoi_area_um2, ...
    local_density_um2_inv, ...
    nn1_um, ...
    nn2_um, ...
    nn3_um, ...
    non_sixfold_flag, ...
    interior_non_sixfold_flag, ...
    low_psi6_flag, ...
    moderate_psi6_flag, ...
    high_psi6_flag, ...
    soft_coordination_flag, ...
    disorder_flag, ...
    legacy_hard_disorder_flag, ...
    'VariableNames', {'MoundIndex', 'X_px', 'Y_px', 'X_um', 'Y_um', ...
    'CoordinationNumber', 'LocalPsi6', 'Psi6Phase_rad', 'Psi6Phase_deg', ...
    'BoundaryFlag', 'InteriorFlag', 'LocalOrderScore', 'LocalOrderClass', ...
    'VoronoiValidFlag', 'VoronoiClippedFlag', 'VoronoiAugmentedFlag', ...
    'VoronoiArea_um2', 'LocalDensity_um2_inv', ...
    'NN1_um', 'NN2_um', 'NN3_um', ...
    'NonSixfoldFlag', 'InteriorNonSixfoldFlag', 'LowPsi6Flag', ...
    'ModeratePsi6Flag', 'HighPsi6Flag', 'SoftCoordinationFlag', ...
    'DisorderFlag', 'LegacyHardDisorderFlag'});
writetable(per_mound_table, xlsx_path, 'Sheet', 'PerMound');

pair_table = table( ...
    pair_r_um(:), ...
    pair_counts(:), ...
    pair_g_r(:), ...
    pair_bin_edges_um(1:end-1)', ...
    pair_bin_edges_um(2:end)', ...
    'VariableNames', {'r_um', 'PairCount', 'g_r', 'BinStart_um', 'BinEnd_um'});
writetable(pair_table, xlsx_path, 'Sheet', 'PairDistribution');

bond_table = table( ...
    bond_angle_bins_deg(:), ...
    bond_angle_counts(:), ...
    bond_bin_edges_deg(1:end-1)', ...
    bond_bin_edges_deg(2:end)', ...
    'VariableNames', {'AngleCenter_deg', 'Count', 'BinStart_deg', 'BinEnd_deg'});
writetable(bond_table, xlsx_path, 'Sheet', 'BondAngles');

voronoi_table = table( ...
    (1:n_mounds)', ...
    voronoi_valid_flag, ...
    voronoi_clipped_flag, ...
    voronoi_augmented_flag, ...
    voronoi_area_um2, ...
    local_density_um2_inv, ...
    'VariableNames', {'MoundIndex', 'VoronoiValidFlag', 'VoronoiClippedFlag', ...
    'VoronoiAugmentedFlag', 'VoronoiArea_um2', 'LocalDensity_um2_inv'});
writetable(voronoi_table, xlsx_path, 'Sheet', 'Voronoi');

neighbor_shell_table = table( ...
    (1:n_mounds)', ...
    nn1_um, ...
    nn2_um, ...
    nn3_um, ...
    'VariableNames', {'MoundIndex', 'NN1_um', 'NN2_um', 'NN3_um'});
writetable(neighbor_shell_table, xlsx_path, 'Sheet', 'NeighborShells');

comparison_table = table( ...
    {imageName}, ...
    {radial_order_label}, ...
    {orientational_order_label}, ...
    {comparison_summary_line}, ...
    first_peak_r_um, ...
    first_peak_g_r, ...
    radial_order_score, ...
    global_psi6_interior, ...
    mean_local_psi6_interior, ...
    safeMean(high_psi6_flag(interior_flag)), ...
    safeMean(moderate_psi6_flag(interior_flag)), ...
    safeMean(low_psi6_flag(interior_flag)), ...
    nn1_cv, ...
    nn2_mean_um, ...
    nn2_cv, ...
    nn3_mean_um, ...
    nn3_cv, ...
    acf_anisotropy_ratio, ...
    acf_dominant_orientation_deg, ...
    voronoi_area_mean_um2, ...
    local_density_mean_um2_inv, ...
    mean(voronoi_clipped_flag(voronoi_valid_flag)), ...
    voronoi_added_seed_count, ...
    mean(boundary_flag), ...
    'VariableNames', {'ImageName', 'RadialOrderLabel', 'OrientationalOrderLabel', ...
    'ComparisonSummary', 'FirstPeak_r_um', 'FirstPeak_g_r', 'RadialOrderScore', ...
    'InteriorGlobalPsi6', 'InteriorMeanLocalPsi6', 'InteriorFractionHighPsi6', ...
    'InteriorFractionModeratePsi6', 'InteriorFractionLowPsi6', ...
    'NN1_CV', 'NN2_Mean_um', 'NN2_CV', 'NN3_Mean_um', 'NN3_CV', ...
    'ACFAnisotropyRatio', ...
    'ACFDominantOrientation_deg', ...
    'VoronoiAreaMean_um2', 'LocalDensityMean_um2_inv', ...
    'FractionClippedVoronoi', 'VoronoiAddedSeedCount', 'FractionBoundary'});
writetable(comparison_table, xlsx_path, 'Sheet', 'Comparison');

summary_table = table( ...
    {imageName}, ...
    n_mounds, ...
    global_psi6, ...
    mean_local_psi6, ...
    std_local_psi6, ...
    median_local_psi6, ...
    p25_local_psi6, ...
    global_psi6_interior, ...
    mean_local_psi6_interior, ...
    mean(boundary_flag), ...
    psi6_low_threshold, ...
    psi6_high_threshold, ...
    safeMean(interior_non_sixfold_flag(interior_flag)), ...
    safeMean(low_psi6_flag(interior_flag)), ...
    safeMean(moderate_psi6_flag(interior_flag)), ...
    safeMean(high_psi6_flag(interior_flag)), ...
    safeMean(soft_coordination_flag(interior_flag)), ...
    safeMean(disorder_flag(interior_flag)), ...
    mean(legacy_hard_disorder_flag), ...
    mean(coordination_number), ...
    mean(edge_len_um), ...
    std(edge_len_um), ...
    nn1_mean_um, ...
    nn1_std_um, ...
    nn1_cv, ...
    nn2_mean_um, ...
    nn2_std_um, ...
    nn2_cv, ...
    nn3_mean_um, ...
    nn3_std_um, ...
    nn3_cv, ...
    voronoi_area_mean_um2, ...
    voronoi_area_std_um2, ...
    local_density_mean_um2_inv, ...
    local_density_std_um2_inv, ...
    mean(voronoi_valid_flag), ...
    mean(voronoi_clipped_flag(voronoi_valid_flag)), ...
    voronoi_added_seed_count, ...
    pair_density_um2, ...
    pair_bin_width_um, ...
    first_peak_r_um, ...
    first_peak_g_r, ...
    radial_order_score, ...
    acf_anisotropy_ratio, ...
    acf_dominant_orientation_deg, ...
    {radial_order_label}, ...
    {orientational_order_label}, ...
    {comparison_summary_line}, ...
    'VariableNames', {'ImageName', 'N_mounds', 'GlobalPsi6', ...
    'MeanLocalPsi6', 'StdLocalPsi6', 'MedianLocalPsi6', 'P25LocalPsi6', ...
    'InteriorGlobalPsi6', 'InteriorMeanLocalPsi6', 'FractionBoundary', ...
    'LowPsi6Threshold', 'HighPsi6Threshold', 'InteriorFractionNonSixfold', ...
    'InteriorFractionLowPsi6', 'InteriorFractionModeratePsi6', ...
    'InteriorFractionHighPsi6', 'InteriorFractionSoftCoordinationFlag', ...
    'InteriorFractionDisorderFlagged', 'LegacyHardFractionDisorderFlagged', ...
    'MeanCoordinationNumber', ...
    'MeanBondLength_um', 'StdBondLength_um', ...
    'NN1_Mean_um', 'NN1_Std_um', 'NN1_CV', ...
    'NN2_Mean_um', 'NN2_Std_um', 'NN2_CV', ...
    'NN3_Mean_um', 'NN3_Std_um', 'NN3_CV', ...
    'VoronoiAreaMean_um2', 'VoronoiAreaStd_um2', ...
    'LocalDensityMean_um2_inv', 'LocalDensityStd_um2_inv', ...
    'FractionFiniteVoronoi', 'FractionClippedVoronoi', ...
    'VoronoiAddedSeedCount', 'NumberDensity_per_um2', ...
    'PairBinWidth_um', 'FirstPeak_r_um', 'FirstPeak_g_r', 'RadialOrderScore', ...
    'ACFAnisotropyRatio', 'ACFDominantOrientation_deg', ...
    'RadialOrderLabel', 'OrientationalOrderLabel', 'ComparisonSummary'});
writetable(summary_table, xlsx_path, 'Sheet', 'Summary');
fprintf('  Saved: %s\n', xlsx_path);

spatialOrderResults.n_mounds = n_mounds;
spatialOrderResults.centroid_px = centroids;
spatialOrderResults.coordination_number = coordination_number;
spatialOrderResults.local_psi6 = local_psi6;
spatialOrderResults.psi6_phase = psi6_phase;
spatialOrderResults.psi6_phase_deg = rad2deg(psi6_phase);
spatialOrderResults.psi6_complex = psi6_complex;
spatialOrderResults.global_psi6 = global_psi6;
spatialOrderResults.mean_local_psi6 = mean_local_psi6;
spatialOrderResults.std_local_psi6 = std_local_psi6;
spatialOrderResults.median_local_psi6 = median_local_psi6;
spatialOrderResults.p25_local_psi6 = p25_local_psi6;
spatialOrderResults.global_psi6_interior = global_psi6_interior;
spatialOrderResults.mean_local_psi6_interior = mean_local_psi6_interior;
spatialOrderResults.boundary_margin_px = boundary_margin_px;
spatialOrderResults.boundary_flag = boundary_flag;
spatialOrderResults.interior_flag = interior_flag;
spatialOrderResults.local_order_class = local_order_class;
spatialOrderResults.local_order_score = local_order_score;
spatialOrderResults.voronoi_valid_flag = voronoi_valid_flag;
spatialOrderResults.voronoi_clipped_flag = voronoi_clipped_flag;
spatialOrderResults.voronoi_augmented_flag = voronoi_augmented_flag;
spatialOrderResults.voronoi_area_um2 = voronoi_area_um2;
spatialOrderResults.local_density_um2_inv = local_density_um2_inv;
spatialOrderResults.voronoi_added_seed_count = voronoi_added_seed_count;
spatialOrderResults.voronoi_polygons_px = voronoi_polygons_px;
spatialOrderResults.psi6_moderate_threshold = psi6_moderate_threshold;
spatialOrderResults.psi6_high_threshold = psi6_high_threshold;
spatialOrderResults.low_psi6_threshold = psi6_low_threshold;
spatialOrderResults.non_sixfold_flag = non_sixfold_flag;
spatialOrderResults.interior_non_sixfold_flag = interior_non_sixfold_flag;
spatialOrderResults.low_psi6_flag = low_psi6_flag;
spatialOrderResults.moderate_psi6_flag = moderate_psi6_flag;
spatialOrderResults.high_psi6_flag = high_psi6_flag;
spatialOrderResults.soft_coordination_flag = soft_coordination_flag;
spatialOrderResults.disorder_flag = disorder_flag;
spatialOrderResults.legacy_hard_disorder_flag = legacy_hard_disorder_flag;
spatialOrderResults.edge_length_px = edge_len_px;
spatialOrderResults.edge_length_um = edge_len_um;
spatialOrderResults.nn1_um = nn1_um;
spatialOrderResults.nn2_um = nn2_um;
spatialOrderResults.nn3_um = nn3_um;
spatialOrderResults.neighbor_distance_matrix_um = neighbor_distance_matrix_um;
spatialOrderResults.nn1_mean_um = nn1_mean_um;
spatialOrderResults.nn1_std_um = nn1_std_um;
spatialOrderResults.nn1_cv = nn1_cv;
spatialOrderResults.nn2_mean_um = nn2_mean_um;
spatialOrderResults.nn2_std_um = nn2_std_um;
spatialOrderResults.nn2_cv = nn2_cv;
spatialOrderResults.nn3_mean_um = nn3_mean_um;
spatialOrderResults.nn3_std_um = nn3_std_um;
spatialOrderResults.nn3_cv = nn3_cv;
spatialOrderResults.voronoi_area_mean_um2 = voronoi_area_mean_um2;
spatialOrderResults.voronoi_area_std_um2 = voronoi_area_std_um2;
spatialOrderResults.local_density_mean_um2_inv = local_density_mean_um2_inv;
spatialOrderResults.local_density_std_um2_inv = local_density_std_um2_inv;
spatialOrderResults.edge_angle_deg = edge_angle_deg;
spatialOrderResults.bond_angle_bins_deg = bond_angle_bins_deg;
spatialOrderResults.bond_angle_counts = bond_angle_counts;
spatialOrderResults.bond_angle_bin_edges_deg = bond_bin_edges_deg;
spatialOrderResults.pair_r_um = pair_r_um;
spatialOrderResults.pair_counts = pair_counts;
spatialOrderResults.pair_g_r = pair_g_r;
spatialOrderResults.pair_bin_edges_um = pair_bin_edges_um;
spatialOrderResults.pair_bin_width_um = pair_bin_width_um;
spatialOrderResults.pair_density_per_um2 = pair_density_um2;
spatialOrderResults.first_peak_r_um = first_peak_r_um;
spatialOrderResults.first_peak_g_r = first_peak_g_r;
spatialOrderResults.radial_order_score = radial_order_score;
spatialOrderResults.acf_anisotropy_ratio = acf_anisotropy_ratio;
spatialOrderResults.acf_dominant_orientation_deg = acf_dominant_orientation_deg;
spatialOrderResults.radial_order_label = radial_order_label;
spatialOrderResults.orientational_order_label = orientational_order_label;
spatialOrderResults.comparison_summary_line = comparison_summary_line;
spatialOrderResults.neighbor_definition = 'trimmed_delaunay';
spatialOrderResults.order_metric = 'psi6';
spatialOrderResults.order_level_note = [ ...
    'Order tiers are heuristic interpretation bins: boundary, low ' ...
    '(local psi6 < 0.45), moderate (0.45-0.75), and high (>= 0.75).'];
spatialOrderResults.pair_distribution_note = [ ...
    'Approximate 2D g(r) using centroid bounding-box density and no ' ...
    'heavy edge correction in v1.'];
spatialOrderResults.acf_note = [ ...
    'Testing-stage 2D surface-height autocorrelation is retained mainly ' ...
    'as a diagnostic workflow; anisotropy ratio and dominant orientation ' ...
    'are the only comparison-facing ACF outputs currently kept.'];
spatialOrderResults.imageName = imageName;
spatialOrderResults.imagePath = m1.imagePath;
spatialOrderResults.m1 = m1;
spatialOrderResults.psi6_map_path = psi6_map_path;
spatialOrderResults.defect_map_path = defect_map_path;
spatialOrderResults.voronoi_density_path = voronoi_density_path;
spatialOrderResults.voronoi_cells_path = voronoi_cells_path;
spatialOrderResults.voronoi_area_hist_path = voronoi_area_hist_path;
spatialOrderResults.neighbor_shells_path = neighbor_shells_path;
spatialOrderResults.pair_plot_path = pair_plot_path;
spatialOrderResults.bond_plot_path = bond_plot_path;
spatialOrderResults.acf2d_path = acf2d_path;
spatialOrderResults.acf_radial_path = acf_radial_path;
spatialOrderResults.acf_directional_path = acf_directional_path;
spatialOrderResults.acf_vs_gr_path = acf_vs_gr_path;
spatialOrderResults.xlsx_path = xlsx_path;
spatialOrderResults.tabbed_figure_handle = tabbed_fig.figure;

tabbed_figure_handle = spatialOrderResults.tabbed_figure_handle;
spatialOrderResults = rmfield(spatialOrderResults, 'tabbed_figure_handle');
save(mat_path, 'spatialOrderResults');
spatialOrderResults.tabbed_figure_handle = tabbed_figure_handle;
fprintf('  Saved: %s\n', mat_path);
fprintf('analyzeSpatialOrder complete.\n\n');

end

function adjacency = buildAdjacency(edges, n_nodes)
adjacency = cell(n_nodes, 1);
for k = 1:size(edges, 1)
    i = edges(k, 1);
    j = edges(k, 2);
    adjacency{i}(end+1) = j;
    adjacency{j}(end+1) = i;
end
for k = 1:n_nodes
    adjacency{k} = unique(adjacency{k}, 'stable');
end
end

function [coordination_number, psi6_complex, local_psi6, psi6_phase] = ...
    computePsi6Metrics(centroids, adjacency)
n_nodes = size(centroids, 1);
coordination_number = zeros(n_nodes, 1);
psi6_complex = nan(n_nodes, 1);
local_psi6 = nan(n_nodes, 1);
psi6_phase = nan(n_nodes, 1);

for k = 1:n_nodes
    nbr = adjacency{k};
    coordination_number(k) = numel(nbr);
    if isempty(nbr)
        continue;
    end

    dxy = centroids(nbr, :) - centroids(k, :);
    theta = atan2(dxy(:,2), dxy(:,1));
    order_k = mean(exp(1i * 6 * theta));
    psi6_complex(k) = order_k;
    local_psi6(k) = abs(order_k);
    psi6_phase(k) = angle(order_k) / 6;
end
end

function [pair_r_um, pair_counts, pair_g_r, pair_bin_edges_um, pair_bin_width_um, ...
    rho_um2] = computePairDistribution(centroids_px, xy_um_per_px, nn_mean_um)
centroids_um = centroids_px * xy_um_per_px;
x = centroids_um(:,1);
y = centroids_um(:,2);
n = size(centroids_um, 1);

dx = x - x.';
dy = y - y.';
D = hypot(dx, dy);
pair_dists = D(triu(true(n), 1));
pair_dists = pair_dists(isfinite(pair_dists) & pair_dists > 0);

x_span_um = max(x) - min(x);
y_span_um = max(y) - min(y);
eff_area_um2 = max(x_span_um * y_span_um, eps);
rho_um2 = n / eff_area_um2;

pair_bin_width_um = max([xy_um_per_px, nn_mean_um / 20, 0.05]);
r_max_um = min(max(pair_dists), max(2.5 * nn_mean_um, 0.45 * min(x_span_um, y_span_um)));
r_max_um = max(r_max_um, 2 * pair_bin_width_um);
pair_bin_edges_um = 0:pair_bin_width_um:(r_max_um + pair_bin_width_um);
if pair_bin_edges_um(end) < r_max_um
    pair_bin_edges_um(end+1) = r_max_um;
end

pair_counts = histcounts(pair_dists, pair_bin_edges_um);
pair_r_um = pair_bin_edges_um(1:end-1) + diff(pair_bin_edges_um) / 2;
shell_area_um2 = pi * (pair_bin_edges_um(2:end).^2 - pair_bin_edges_um(1:end-1).^2);
expected_unique_counts = 0.5 * n * rho_um2 .* shell_area_um2;
pair_g_r = pair_counts ./ max(expected_unique_counts, eps);
end

function [first_peak_r_um, first_peak_g_r] = estimateFirstPairPeak(pair_r_um, pair_g_r, nn_mean_um)
search_mask = pair_r_um >= (0.5 * nn_mean_um) & pair_r_um <= (1.5 * nn_mean_um);
if ~any(search_mask)
    search_mask = isfinite(pair_g_r);
end

candidate_idx = find(search_mask & isfinite(pair_g_r));
if isempty(candidate_idx)
    first_peak_r_um = NaN;
    first_peak_g_r = NaN;
    return;
end

[first_peak_g_r, idx_local] = max(pair_g_r(candidate_idx));
first_peak_r_um = pair_r_um(candidate_idx(idx_local));
end

function [acf2d, lag_x_um, lag_y_um, acf_r_um, acf_r, overlap_fraction, ...
    correlation_length_um, first_ring_radius_um, first_ring_value, ...
    anisotropy_ratio, dominant_orientation_deg, x_cut, y_cut, ...
    detrend_plane, mean_center_value_um] = computeSurfaceAutocorrelation(Z_um, xy_um_per_px, nn_mean_um)
valid_mask = isfinite(Z_um);
if nnz(valid_mask) < 9
    error('analyzeSpatialOrder:InsufficientHeightData', ...
        'Autocorrelation requires at least 9 finite height pixels.');
end

[img_h, img_w] = size(Z_um);
[x_grid, y_grid] = meshgrid(1:img_w, 1:img_h);
A = [x_grid(valid_mask), y_grid(valid_mask), ones(nnz(valid_mask), 1)];
detrend_plane = A \ Z_um(valid_mask);
plane_fit = detrend_plane(1) * x_grid + detrend_plane(2) * y_grid + detrend_plane(3);
Z_detrended = Z_um - plane_fit;
mean_center_value_um = mean(Z_detrended(valid_mask), 'omitnan');
Z_centered = Z_detrended - mean_center_value_um;
Z_centered(~valid_mask) = 0;

mask_numeric = double(valid_mask);
fft_surface = fft2(Z_centered);
fft_mask = fft2(mask_numeric);
raw_acf = fftshift(real(ifft2(abs(fft_surface).^2)));
overlap_counts = fftshift(real(ifft2(abs(fft_mask).^2)));
variance_um2 = sum(Z_centered(valid_mask).^2) / max(nnz(valid_mask), 1);
max_overlap_count = max(overlap_counts(:));

acf2d = raw_acf ./ max(overlap_counts, 1);
acf2d = acf2d / max(variance_um2, eps);
overlap_fraction_2d = overlap_counts ./ max(max_overlap_count, 1);
acf2d(overlap_fraction_2d < 0.05) = NaN;

lag_x_px = (-floor(img_w / 2)):(ceil(img_w / 2) - 1);
lag_y_px = (-floor(img_h / 2)):(ceil(img_h / 2) - 1);
lag_x_um = lag_x_px * xy_um_per_px;
lag_y_um = lag_y_px * xy_um_per_px;

[acf_r_um, acf_r, overlap_fraction] = radialAverageAutocorrelation(acf2d, overlap_fraction_2d, xy_um_per_px);
correlation_length_um = estimateCorrelationLength(acf_r_um, acf_r);
[first_ring_radius_um, first_ring_value] = estimateAutocorrelationRing(acf_r_um, acf_r, nn_mean_um);
[anisotropy_ratio, dominant_orientation_deg] = estimateAutocorrelationAnisotropy( ...
    acf2d, lag_x_um, lag_y_um);

row_center = floor(img_h / 2) + 1;
col_center = floor(img_w / 2) + 1;
x_cut = acf2d(row_center, :).';
y_cut = acf2d(:, col_center);
end

function [r_um, acf_r, overlap_fraction] = radialAverageAutocorrelation(acf2d, overlap_fraction_2d, xy_um_per_px)
[img_h, img_w] = size(acf2d);
[x_grid, y_grid] = meshgrid(1:img_w, 1:img_h);
x0 = floor(img_w / 2) + 1;
y0 = floor(img_h / 2) + 1;
r_px = hypot(x_grid - x0, y_grid - y0);
r_max_px = floor(max(r_px(:)));
r_edges_px = 0:1:(r_max_px + 1);
r_um = ((r_edges_px(1:end-1) + r_edges_px(2:end)) / 2) * xy_um_per_px;
r_um = r_um(:);
acf_r = nan(numel(r_um), 1);
overlap_fraction = nan(numel(r_um), 1);

for k = 1:numel(r_um)
    ring_mask = r_px >= r_edges_px(k) & r_px < r_edges_px(k + 1);
    values = acf2d(ring_mask);
    overlap_vals = overlap_fraction_2d(ring_mask);
    valid = isfinite(values);
    if any(valid)
        acf_r(k) = mean(values(valid), 'omitnan');
        overlap_fraction(k) = mean(overlap_vals(valid), 'omitnan');
    end
end
end

function correlation_length_um = estimateCorrelationLength(acf_r_um, acf_r)
acf_r_um = acf_r_um(:);
acf_r = acf_r(:);
target = exp(-1);
valid = isfinite(acf_r_um) & isfinite(acf_r);
acf_r_um = acf_r_um(valid);
acf_r = acf_r(valid);
idx = find(acf_r_um > 0 & acf_r <= target, 1, 'first');
if isempty(idx)
    correlation_length_um = NaN;
else
    correlation_length_um = acf_r_um(idx);
end
end

function [first_ring_radius_um, first_ring_value] = estimateAutocorrelationRing(acf_r_um, acf_r, nn_mean_um)
acf_r_um = acf_r_um(:);
acf_r = acf_r(:);
valid = isfinite(acf_r_um) & isfinite(acf_r);
if ~any(valid)
    first_ring_radius_um = NaN;
    first_ring_value = NaN;
    return;
end
search_mask = valid & acf_r_um >= max(nn_mean_um * 0.5, min(acf_r_um(valid))) & ...
    acf_r_um <= max(nn_mean_um * 2.0, nn_mean_um);
candidate_idx = find(search_mask);
if isempty(candidate_idx)
    first_ring_radius_um = NaN;
    first_ring_value = NaN;
    return;
end

[first_ring_value, idx_local] = max(acf_r(candidate_idx));
first_ring_radius_um = acf_r_um(candidate_idx(idx_local));
end

function [anisotropy_ratio, dominant_orientation_deg] = estimateAutocorrelationAnisotropy(acf2d, lag_x_um, lag_y_um)
[img_h, img_w] = size(acf2d);
row_center = floor(img_h / 2) + 1;
col_center = floor(img_w / 2) + 1;
[x_grid_um, y_grid_um] = meshgrid(lag_x_um, lag_y_um);

peak_mask = isfinite(acf2d) & acf2d >= 0.5;
peak_mask = peak_mask & hypot(x_grid_um, y_grid_um) > 0;
if ~peak_mask(row_center, col_center)
    peak_mask(row_center, col_center) = true;
end

weights = acf2d(peak_mask) - 0.5;
weights = max(weights, eps);
x_vals = x_grid_um(peak_mask);
y_vals = y_grid_um(peak_mask);
if numel(weights) < 3
    anisotropy_ratio = NaN;
    dominant_orientation_deg = NaN;
    return;
end

w_sum = sum(weights);
x_mean = sum(weights .* x_vals) / w_sum;
y_mean = sum(weights .* y_vals) / w_sum;
x_centered = x_vals - x_mean;
y_centered = y_vals - y_mean;
cov_xx = sum(weights .* x_centered.^2) / w_sum;
cov_xy = sum(weights .* x_centered .* y_centered) / w_sum;
cov_yy = sum(weights .* y_centered.^2) / w_sum;
C = [cov_xx, cov_xy; cov_xy, cov_yy];
[V, D] = eig(C);
eigvals = diag(D);
if any(~isfinite(eigvals)) || min(eigvals) <= 0
    anisotropy_ratio = NaN;
    dominant_orientation_deg = NaN;
    return;
end
[major_val, idx_major] = max(eigvals);
minor_val = min(eigvals);
major_vec = V(:, idx_major);
anisotropy_ratio = sqrt(major_val / minor_val);
dominant_orientation_deg = mod(rad2deg(atan2(major_vec(2), major_vec(1))), 180);
end

function [nn1_um, nn2_um, nn3_um, neighbor_distance_matrix_um] = computeNeighborShellDistances(centroids_px, xy_um_per_px)
n = size(centroids_px, 1);
dx = centroids_px(:,1) - centroids_px(:,1).';
dy = centroids_px(:,2) - centroids_px(:,2).';
D_px = hypot(dx, dy);
D_px(1:n+1:end) = Inf;
neighbor_distance_matrix_um = sort(D_px, 2, 'ascend') * xy_um_per_px;
nn1_um = neighbor_distance_matrix_um(:, 1);
if size(neighbor_distance_matrix_um, 2) >= 2
    nn2_um = neighbor_distance_matrix_um(:, 2);
else
    nn2_um = nan(n, 1);
end
if size(neighbor_distance_matrix_um, 2) >= 3
    nn3_um = neighbor_distance_matrix_um(:, 3);
else
    nn3_um = nan(n, 1);
end
end

function [voronoi_area_um2, local_density_um2_inv, voronoi_valid_flag, voronoi_polygons_px, ...
    voronoi_clipped_flag, voronoi_augmented_flag, added_seed_count] = computeVoronoiMetrics(m1, centroids_px, xy_um_per_px)
n = size(centroids_px, 1);
voronoi_area_um2 = nan(n, 1);
local_density_um2_inv = nan(n, 1);
voronoi_valid_flag = false(n, 1);
voronoi_polygons_px = cell(n, 1);
voronoi_clipped_flag = false(n, 1);
voronoi_augmented_flag = false(n, 1);
added_seed_count = 0;

[imgH, imgW] = size(m1.I_raw);
clip_rect = polyshape([1 imgW imgW 1], [1 1 imgH imgH], 'Simplify', true);

all_centroids = centroids_px;
[centroids_all, ok, ~] = detectBorderInclusiveCentroidsForVoronoi(m1);
if ok && ~isempty(centroids_all) && ~isempty(centroids_px)
    idx_near = knnsearch(centroids_px, centroids_all);
    d_near = sqrt(sum((centroids_all - centroids_px(idx_near,:)).^2, 2));
    added_mask = d_near > 1.5;
    added_centroids = centroids_all(added_mask, :);
    if ~isempty(added_centroids)
        all_centroids = [centroids_px; added_centroids];
        added_seed_count = size(added_centroids, 1);
    end
end

dt = delaunayTriangulation(all_centroids(:,1), all_centroids(:,2));

try
    [V, R] = voronoiDiagram(dt);
catch
    return;
end

for k = 1:n
    region_idx = R{k};
    if isempty(region_idx) || numel(region_idx) < 3
        continue;
    end
    raw_infinite = any(region_idx == 1);
    if raw_infinite
        continue;
    end
    verts = V(region_idx, :);
    if any(~isfinite(verts(:)))
        continue;
    end
    raw_poly = polyshape(verts(:,1), verts(:,2), 'Simplify', true);
    if isempty(raw_poly.Vertices) || area(raw_poly) <= 0
        continue;
    end

    clipped_poly = intersect(raw_poly, clip_rect);
    if isempty(clipped_poly.Vertices) || area(clipped_poly) <= 0
        continue;
    end

    voronoi_polygons_px{k} = clipped_poly;
    area_px2 = area(clipped_poly);
    voronoi_area_um2(k) = area_px2 * xy_um_per_px^2;
    local_density_um2_inv(k) = 1 / voronoi_area_um2(k);
    voronoi_valid_flag(k) = true;
    voronoi_clipped_flag(k) = abs(area(raw_poly) - area(clipped_poly)) > max(1e-6, 1e-6 * area(raw_poly));
    voronoi_augmented_flag(k) = added_seed_count > 0;
end
end

function [centroids_all, ok, reason] = detectBorderInclusiveCentroidsForVoronoi(m1)
ok = false;
reason = '';
centroids_all = zeros(0, 2);

required = {'bestParams', 'fillDeepPits', 'fillThreshold', 'dilateRadius', 'minObjectArea', 'I_raw'};
for i = 1:numel(required)
    if ~isfield(m1, required{i})
        reason = sprintf('missing m1.%s', required{i});
        return;
    end
end

I = double(m1.I_raw) / 255;
p = m1.bestParams;
fillDeepPits = logical(m1.fillDeepPits);
fillThreshold = double(m1.fillThreshold);
dilateRadius = double(m1.dilateRadius);
minObjectArea = double(m1.minObjectArea);

Iblur = imgaussfilt(double(I), double(p.gaussSigma));
mask = double(applyDetectionContrastVoronoi(Iblur, char(p.contrastMethod), double(p.clipLimit)));
Iobrcbr = preprocessDetectionImageVoronoi(mask, double(p.openRadius));
fgm4 = extractDetectionRegionalMaximaVoronoi(Iobrcbr, dilateRadius, minObjectArea, ...
    fillDeepPits, Iblur, fillThreshold);

stats = regionprops(logical(fgm4), 'Centroid');
if isempty(stats)
    centroids_all = zeros(0, 2);
else
    centroids_all = double(cat(1, stats.Centroid));
end
ok = true;
end

function mask = applyDetectionContrastVoronoi(I, method, clipLimit)
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

function Iobrcbr = preprocessDetectionImageVoronoi(mask, radius)
se = strel('disk', radius);
Ie = imerode(mask, se);
Iobr = imreconstruct(Ie, mask);
Iobrd = imdilate(Iobr, se);
Iobrcbr = imreconstruct(imcomplement(Iobrd), imcomplement(Iobr));
Iobrcbr = imcomplement(Iobrcbr);
end

function fgm4 = extractDetectionRegionalMaximaVoronoi(Iobrcbr, dilateRadius, minArea, ...
    fillDeepPits, Iblur, fillThreshold)
fgm = imregionalmax(Iobrcbr);
se = strel('disk', dilateRadius);
fgm2 = imclose(fgm, se);
fgm3 = imdilate(fgm2, se);
fgm4 = bwareaopen(fgm3, minArea);
if fillDeepPits
    filled = imcomplement(imfill(imcomplement(imbinarize(Iblur, fillThreshold)), 'holes'));
    fgm4 = and(filled, fgm4);
end
end

function tabbed_fig = createSpatialOrderTabbedFigure(imageName)
fig = figure('Name', ['Spatial Order Diagnostics - ' imageName], ...
    'Position', [70 70 1450 900], 'Color', 'w');
tg = uitabgroup(fig, 'Position', [0 0 1 1], 'Units', 'normalized');
tabbed_fig.figure = fig;
tabbed_fig.tabgroup = tg;
tabbed_fig.tabs.psi6 = uitab(tg, 'Title', 'Psi6 Map');
tabbed_fig.tabs.order = uitab(tg, 'Title', 'Order Tiers');
tabbed_fig.tabs.voronoi = uitab(tg, 'Title', 'Voronoi Density');
tabbed_fig.tabs.neighbors = uitab(tg, 'Title', 'Neighbor Shells');
tabbed_fig.tabs.pair = uitab(tg, 'Title', 'Pair Distribution');
tabbed_fig.tabs.bond = uitab(tg, 'Title', 'Bond Angles');
tabbed_fig.tabs.acf2d = uitab(tg, 'Title', 'ACF 2D');
tabbed_fig.tabs.acfRadial = uitab(tg, 'Title', 'ACF Radial');
tabbed_fig.tabs.acfCuts = uitab(tg, 'Title', 'ACF Cuts');
tabbed_fig.tabs.acfCompare = uitab(tg, 'Title', 'ACF vs g(r)');
end

function drawVoronoiCells(ax, voronoi_polygons_px, valid_flag, area_values)
if isempty(voronoi_polygons_px)
    return;
end
valid_area = area_values(valid_flag & isfinite(area_values));
if isempty(valid_area)
    return;
end
clim_lo = prctile(valid_area, 5);
clim_hi = prctile(valid_area, 95);
if clim_hi <= clim_lo
    clim_hi = clim_lo + eps;
end
cmap = turbo(256);
for k = 1:min(numel(voronoi_polygons_px), numel(valid_flag))
    if ~valid_flag(k)
        continue;
    end
    poly_k = voronoi_polygons_px{k};
    if isempty(poly_k)
        continue;
    end
    [xb, yb] = boundary(poly_k);
    verts = [xb(:), yb(:)];
    if any(~isfinite(verts(:)))
        continue;
    end
    t = (area_values(k) - clim_lo) / max(clim_hi - clim_lo, eps);
    t = max(0, min(1, t));
    cidx = max(1, min(256, round(t * 255) + 1));
    patch(ax, verts(:,1), verts(:,2), cmap(cidx, :), ...
        'FaceAlpha', 0.32, 'EdgeColor', cmap(cidx, :), 'LineWidth', 0.8);
end
colormap(ax, turbo(256));
clim(ax, [clim_lo, clim_hi]);
end

function boundary_flag = identifyBoundaryMounds(centroids, margin_px)
x = centroids(:, 1);
y = centroids(:, 2);
dist_to_bbox = min([x - min(x), max(x) - x, y - min(y), max(y) - y], [], 2);
boundary_flag = dist_to_bbox <= margin_px;
end

function [local_order_class, local_order_score] = classifyLocalOrder(boundary_flag, local_psi6, ...
    moderate_threshold, high_threshold)
n = numel(local_psi6);
local_order_class = repmat("low", n, 1);
local_order_score = zeros(n, 1);

local_order_class(boundary_flag) = "boundary";
local_order_score(boundary_flag) = NaN;

moderate_mask = ~boundary_flag & local_psi6 >= moderate_threshold & local_psi6 < high_threshold;
high_mask = ~boundary_flag & local_psi6 >= high_threshold;
low_mask = ~boundary_flag & local_psi6 < moderate_threshold;

local_order_class(low_mask) = "low";
local_order_class(moderate_mask) = "moderate";
local_order_class(high_mask) = "high";
local_order_score(~boundary_flag) = local_psi6(~boundary_flag);
end

function value = safeMean(x)
if isempty(x)
    value = NaN;
else
    value = mean(x);
end
end

function label = classifyRadialOrder(radial_order_score, strong_threshold, moderate_threshold)
if ~isfinite(radial_order_score)
    label = 'unknown';
elseif radial_order_score >= strong_threshold
    label = 'strong';
elseif radial_order_score >= moderate_threshold
    label = 'moderate';
else
    label = 'weak';
end
end

function label = classifyOrientationalOrder(global_psi6_interior, mean_local_psi6_interior, ...
    global_strong_threshold, global_moderate_threshold, local_strong_threshold, local_moderate_threshold)
if ~isfinite(global_psi6_interior) || ~isfinite(mean_local_psi6_interior)
    label = 'unknown';
elseif global_psi6_interior >= global_strong_threshold || mean_local_psi6_interior >= local_strong_threshold
    label = 'strong';
elseif global_psi6_interior >= global_moderate_threshold || mean_local_psi6_interior >= local_moderate_threshold
    label = 'moderate';
else
    label = 'weak';
end
end

function summary_line = buildComparisonSummaryLine(imageName, radial_label, orient_label, ...
    first_peak_r_um, first_peak_g_r, frac_high, frac_moderate, frac_low, frac_boundary)
summary_line = sprintf([ ...
    '%s: radial order %s (first g(r) peak %.2f um, %.2f); ' ...
    'orientational order %s (interior high/moderate/low psi6 fractions %.2f/%.2f/%.2f; boundary %.2f).'], ...
    imageName, radial_label, first_peak_r_um, first_peak_g_r, orient_label, ...
    frac_high, frac_moderate, frac_low, frac_boundary);
end

function h = makePatchLegendProxy(ax, face_color, face_alpha)
h = patch(ax, nan, nan, face_color, 'FaceAlpha', face_alpha, ...
    'EdgeColor', 'none', 'Visible', 'on');
end

function h = showDiagnosticImage(ax, img)
if isa(ax, 'matlab.graphics.axis.PolarAxes')
    error('showDiagnosticImage:InvalidAxes', 'Cannot show raster image on polar axes.');
end
if size(img, 3) == 1
    h = imagesc(ax, img);
    colormap(ax, gray(256));
else
    h = image(ax, img);
end
axis(ax, 'image');
axis(ax, 'off');
set(ax, 'YDir', 'reverse');
end

function drawEdges(ax, centroids, edges, colorVal, lineWidth)
for k = 1:size(edges, 1)
    pts = centroids(edges(k, :), :);
    line(ax, pts(:,1), pts(:,2), 'Color', colorVal, 'LineWidth', lineWidth);
end
end
