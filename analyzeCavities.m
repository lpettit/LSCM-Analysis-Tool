function cavResults = analyzeCavities(m1, min_depth_um, fillDeepPits, fillThreshold, reflThreshold, outputDir)
% =========================================================================
%  analyzeCavities  -  Module 2: Inclusive inter-mound cavity geometry
%
%  This version targets boiling-oriented inter-mound cavities. Delaunay
%  triangles from the Module 1 mound centroids are used to propose local
%  inter-mound neighborhoods, then adjacent triangle candidates are merged
%  when they support the same physical depression.
%
%  USAGE:
%    cavResults = analyzeCavities(m1)
%    cavResults = analyzeCavities(m1, 2.0, false, 0.3)
%    cavResults = analyzeCavities(m1, 2.0, true, 0.52, 0.35)
%    cavResults = analyzeCavities(m1, 2.0, true, 0.52, 0.35, 'output_folder')
%
%  OUTPUTS (selected struct fields):
%    n_cavities                - number of accepted inter-mound cavities
%    n_shallow                 - number of provisional candidates rejected
%    depth_um                  - cavity depth from mouth to robust floor
%    mouth_area_um2            - true mouth cross-sectional area
%    mouth_equiv_radius_um     - equivalent mouth radius from true area
%    mouth_equiv_diameter_um   - equivalent mouth diameter from true area
%    mouth_inscribed_radius_um - conservative inscribed mouth radius
%    cone_half_angle_deg       - effective cone half-angle from depth/radius
%    persistence_um            - local significance / persistence-like span
%    n_supporting_triangles    - number of supporting Delaunay triangles
%    supporting_triangle_idx   - triangle indices supporting each cavity
%    bounding_mound_idx        - mound centroid indices supporting each cavity
%    cavity_support_type       - single/merged support classification
%    cavity_enclosure_type     - enclosed / semi_enclosed / open_trough_like
%    cavity_quality_flag       - diagnostic quality summary for each cavity
%    cavity_label              - label image for accepted cavities
%
%  Compatibility aliases retained:
%    r_mouth_um  -> mouth_equiv_radius_um
%    beta_deg    -> cone_half_angle_deg
%    basin_label -> cavity_label
% =========================================================================

if nargin < 2 || isempty(min_depth_um),   min_depth_um   = 2.0;   end
if nargin < 3 || isempty(fillDeepPits),   fillDeepPits   = false;  end
if nargin < 4 || isempty(fillThreshold),  fillThreshold  = 0.3;    end
if nargin < 5 || isempty(reflThreshold),  reflThreshold  = [];     end

min_depth_um  = double(min_depth_um);
fillDeepPits  = logical(fillDeepPits);
fillThreshold = double(fillThreshold);

[imageFolder, imageName, ~] = fileparts(m1.imagePath);
if nargin < 6 || isempty(outputDir)
    outputDir = imageFolder;
end
if isempty(outputDir), outputDir = pwd; end
if ~exist(outputDir, 'dir')
    try
        mkdir(outputDir);
    catch ME
        warning('analyzeCavities:OutputDirFallback', ...
            'Could not create outputDir "%s" (%s). Falling back to current folder.', ...
            outputDir, ME.message);
        outputDir = pwd;
        if ~exist(outputDir, 'dir')
            mkdir(outputDir);
        end
    end
end

fprintf('analyzeCavities: %s\n', imageName);

Z            = double(m1.Z);
centroids    = double(m1.centroids);
original_centroids = centroids;
xy           = double(m1.xy_um_per_px);
[imgH, imgW] = size(Z);
nn_mean_px   = double(m1.nn_mean_px);
spacing_px   = computeCavityRepresentativeSpacingPx(m1, nn_mean_px);

[tri_seed_centroids, seed_to_original_idx, added_edge_seed_centroids, tri_seed_mode] = ...
    buildAugmentedCavitySeedCentroids(m1, centroids);
if size(tri_seed_centroids, 1) >= 3
    dt = delaunayTriangulation(tri_seed_centroids(:,1), tri_seed_centroids(:,2));
else
    dt = delaunayTriangulation(centroids(:,1), centroids(:,2));
    tri_seed_centroids = centroids;
    seed_to_original_idx = (1:size(centroids,1))';
    added_edge_seed_centroids = zeros(0, 2);
    tri_seed_mode = 'original centroids fallback';
end
fprintf('  Triangle seed source: %s (%d added edge seeds)\n', tri_seed_mode, size(added_edge_seed_centroids, 1));

smooth_sigma = selectCavitySmoothingSigmaPx(spacing_px);
Z_smooth     = imgaussfilt(Z, smooth_sigma);
fprintf('  Height map smoothed (sigma=%.2f px | spacing=%.2f px | ratio=%.3f)\n', ...
    smooth_sigma, spacing_px, smooth_sigma / max(spacing_px, eps));

[hull_mask, hull_mode] = buildCentroidHullMask(centroids, imgH, imgW, nn_mean_px);
fprintf('  Analysis mask source: %s\n', hull_mode);

inpaint_mask = false(imgH, imgW);
if fillDeepPits
    fprintf('  Correcting reflection artifacts (fillThreshold=%.3f)...\n', fillThreshold);
    [Z_smooth, inpaint_mask] = correctReflectionArtifacts( ...
        Z_smooth, m1.I_raw, hull_mask, fillThreshold, reflThreshold, outputDir, imageName);
end

fprintf('  Building triangle candidates...\n');
candidate_opts = struct();
candidate_opts.expand_px       = max(1, round(0.08 * nn_mean_px));
candidate_opts.floor_radius_px = max(2, round(0.10 * nn_mean_px));
candidate_opts.sig_min_um      = max(1.00, 0.65 * min_depth_um);
candidate_opts.max_triangles   = size(dt.ConnectivityList, 1);

[tri_candidates, tri_support_label] = buildTriangleCandidates( ...
    Z, Z_smooth, hull_mask, tri_seed_centroids, seed_to_original_idx, dt, nn_mean_px, candidate_opts);

fprintf('  Candidate triangles with meaningful depressions: %d / %d\n', ...
    nnz([tri_candidates.is_valid]), numel(tri_candidates));

fprintf('  Merging adjacent triangle candidates...\n');
merge_opts = struct();
merge_opts.min_overlap_ratio = 0.20;
merge_opts.merge_dist_px     = max(2, 0.25 * nn_mean_px);
merge_opts.bridge_tol_um     = max(0.15, 0.15 * candidate_opts.sig_min_um);

groups = mergeTriangleCandidates(tri_candidates, Z_smooth, merge_opts);
fprintf('  Merged cavity groups: %d\n', numel(groups));

fprintf('  Computing final cavity geometry...\n');
cavity_opts = struct();
cavity_opts.floor_radius_px      = candidate_opts.floor_radius_px;
cavity_opts.search_levels        = 28;
cavity_opts.min_depth_um         = min_depth_um;
cavity_opts.contact_px_threshold = max(3, round(0.02 * nn_mean_px));

[cavities_all, ~] = finalizeCavityGroups( ...
    groups, tri_candidates, tri_support_label, Z, Z_smooth, inpaint_mask, ...
    original_centroids, dt, xy, nn_mean_px, cavity_opts);

if isempty(cavities_all)
    warning('analyzeCavities:noCavities', 'No inter-mound cavity candidates were accepted.');
end

depth_all = columnField(cavities_all, 'depth_um');
is_real   = depth_all >= min_depth_um & isfinite(depth_all);
n_real    = nnz(is_real);
n_shallow = numel(cavities_all) - n_real;
fprintf('  Cavities >= %.1f um depth: %d\n', min_depth_um, n_real);
fprintf('  Rejected / shallow cavity groups: %d\n', n_shallow);

real_cavities = cavities_all(is_real);
shallow_cavities = cavities_all(~is_real);

cavity_label = zeros(imgH, imgW, 'uint32');
for k = 1:numel(real_cavities)
    cavity_label(real_cavities(k).mask) = k;
end

fprintf('  Generating figures...\n');
makeTriangleDiagnosticFigure(m1.I_raw, imageName, outputDir, tri_seed_centroids, original_centroids, dt, tri_candidates, groups);
makeMergedOverlayFigure(m1.I_raw, imageName, outputDir, original_centroids, real_cavities, shallow_cavities, xy, added_edge_seed_centroids);
makeMethodOverlayFigure(m1.I_raw, imageName, outputDir, original_centroids, real_cavities, shallow_cavities, xy, ...
    added_edge_seed_centroids, 'highest_valid');
makeMethodOverlayFigure(m1.I_raw, imageName, outputDir, original_centroids, real_cavities, shallow_cavities, xy, ...
    added_edge_seed_centroids, 'plateau_top');
method_compare = summarizeMethodComparison(real_cavities);
makeMethodDifferenceFigure(m1.I_raw, imageName, outputDir, real_cavities, xy, method_compare);
make3DCavityFigure(Z_smooth, imageName, outputDir, real_cavities, xy);
makeHistogramFigure(imageName, outputDir, real_cavities, min_depth_um);

fprintf('  Writing outputs...\n');
xlsx_path = fullfile(outputDir, [imageName '_cavities.xlsx']);
writeCavityWorkbook(xlsx_path, imageName, real_cavities, shallow_cavities, min_depth_um);
fprintf('  Saved: %s\n', xlsx_path);

[cavResults, mat_path] = assembleOutputStruct( ...
    m1, imageName, min_depth_um, real_cavities, shallow_cavities, ...
    cavity_label, tri_support_label, Z_smooth, smooth_sigma, spacing_px, outputDir, method_compare);
save(mat_path, 'cavResults');
fprintf('  Saved: %s\n', mat_path);

fprintf('analyzeCavities complete.\n\n');
end


function [Z_smooth_out, inpaint_mask] = correctReflectionArtifacts( ...
    Z_smooth_in, I_raw_inp, hull_mask, fillThreshold, reflThreshold, outputDir, imageName)

Z_smooth_out = Z_smooth_in;
[imgH, imgW] = size(Z_smooth_in);
inpaint_mask = false(imgH, imgW);

I_double = double(I_raw_inp) / 255;
BW_high  = imbinarize(I_raw_inp, double(fillThreshold));
filled   = imcomplement(imfill(imcomplement(BW_high), 'holes'));
pit_mask = ~filled & hull_mask;

pit_cc = bwconncomp(pit_mask);
diag_data = struct('refl_mask',{}, 'ring_mask',{}, 'region_px',{}, 'replaced',{});
fprintf('  Total pit regions: %d\n', pit_cc.NumObjects);

for pi_idx = 1:pit_cc.NumObjects
    region_px = pit_cc.PixelIdxList{pi_idx};
    if numel(region_px) < 9
        continue;
    end

    pit_vals = I_double(region_px);
    if isempty(reflThreshold)
        T_refl = mean(pit_vals) + 0.5 * std(pit_vals);
        T_refl = max(0.01, min(0.99, T_refl));
    else
        T_refl = double(reflThreshold);
    end

    refl_local = pit_vals >= T_refl;
    if sum(refl_local) < 3 || sum(refl_local) >= numel(region_px) * 0.7
        continue;
    end

    refl_mask = false(imgH, imgW);
    refl_mask(region_px(refl_local)) = true;
    refl_mask = imdilate(refl_mask, strel('disk', 2)) & pit_mask;
    refl_px = find(refl_mask);
    if isempty(refl_px)
        continue;
    end

    ring_outer = imdilate(refl_mask, strel('disk', 8));
    ring_inner = imdilate(refl_mask, strel('disk', 1));
    ring_mask  = ring_outer & ~ring_inner & pit_mask & ~refl_mask;
    ring_px    = find(ring_mask);
    if numel(ring_px) < 4
        ring_px = setdiff(region_px, refl_px);
    end
    if numel(ring_px) < 4
        continue;
    end

    fill_z = median(Z_smooth_out(ring_px));
    replace = Z_smooth_out(refl_px) > fill_z;

    diag_data(end+1) = struct( ... %#ok<AGROW>
        'refl_mask', refl_mask, ...
        'ring_mask', ring_mask, ...
        'region_px', region_px, ...
        'replaced', any(replace));

    if any(replace)
        Z_smooth_out(refl_px(replace)) = fill_z;
        inpaint_mask(refl_px(replace)) = true;
    end
end

if isempty(diag_data)
    return;
end

n_show = min(numel(diag_data), 12);
n_cols = 4;
n_rows = ceil(n_show / n_cols);
fig = figure('Name','Reflection correction diagnostic', ...
             'Position',[50 50 1400 350*n_rows], 'Color','w');
pad_px = 40;

for k = 1:n_show
    dd = diag_data(k);
    [ry_r, rx_r] = ind2sub([imgH imgW], dd.region_px);
    r1 = max(1, min(ry_r)-pad_px);  r2 = min(imgH, max(ry_r)+pad_px);
    c1 = max(1, min(rx_r)-pad_px);  c2 = min(imgW, max(rx_r)+pad_px);

    I_crop    = I_double(r1:r2, c1:c2);
    refl_crop = dd.refl_mask(r1:r2, c1:c2);
    ring_crop = dd.ring_mask(r1:r2, c1:c2);
    inp_crop  = inpaint_mask(r1:r2, c1:c2);

    Ir = uint8(I_crop * 255);
    Ig = Ir;
    Ib = Ir;

    Ir = min(255, Ir + uint8(refl_crop) * 100);
    Ig = uint8(max(0, double(Ig) - double(uint8(refl_crop)) * 60));
    Ib = uint8(max(0, double(Ib) - double(uint8(refl_crop)) * 60));

    Ir = uint8(max(0, double(Ir) - double(uint8(ring_crop)) * 40));
    Ig = min(255, Ig + uint8(ring_crop) * 100);
    Ib = uint8(max(0, double(Ib) - double(uint8(ring_crop)) * 40));

    Ir = min(255, Ir + uint8(inp_crop) * 80);
    Ig = min(255, Ig + uint8(inp_crop) * 80);

    subplot(n_rows, n_cols, k);
    imshow(cat(3, Ir, Ig, Ib));
    title(sprintf('Pit %d (%s)', k, ternary(dd.replaced, 'corrected', 'skipped')), 'FontSize', 8);
end

sgtitle(sprintf('%s | red=reflection green=dark ring yellow=replaced', imageName), ...
    'Interpreter', 'none', 'FontSize', 9);
exportgraphics(fig, fullfile(outputDir, [imageName '_reflection_diag.png']), 'Resolution', 150);
end


function [candidates, tri_support_label] = buildTriangleCandidates( ...
    Z_raw, Z_smooth, hull_mask, seed_centroids, seed_to_original_idx, dt, ~, opts)

[imgH, imgW] = size(Z_raw);
tri = dt.ConnectivityList;
n_tri = size(tri, 1);
tri_support_label = zeros(imgH, imgW, 'uint16');

template = struct( ...
    'tri_idx', NaN, ...
    'mound_idx', zeros(1, 3), ...
    'support_mask', false(imgH, imgW), ...
    'is_valid', false, ...
    'min_x_px', NaN, ...
    'min_y_px', NaN, ...
    'floor_z_um', NaN, ...
    'merge_z_um', NaN, ...
    'significance_um', NaN, ...
    'depression_mask', false(imgH, imgW), ...
    'support_perimeter_mask', false(imgH, imgW), ...
    'boundary_z_p25_um', NaN, ...
    'peak_z_proxy_um', NaN);

candidates = repmat(template, n_tri, 1);
expand_se = strel('disk', opts.expand_px);

for t = 1:n_tri
    idx = tri(t, :);
    poly = seed_centroids(idx, :);
    tri_mask = poly2mask(poly(:,1), poly(:,2), imgH, imgW);
    if ~any(tri_mask(:))
        continue;
    end

    tri_core_mask = tri_mask & hull_mask;
    support_mask = imdilate(tri_core_mask, expand_se) & hull_mask;
    if nnz(support_mask) < 9
        continue;
    end

    tri_support_label(tri_mask) = uint16(t);
    support_perim = bwperim(support_mask);

    z_core = Z_smooth;
    z_core(~tri_core_mask) = inf;
    [~, idx_min] = min(z_core(:));
    if ~isfinite(z_core(idx_min))
        continue;
    end
    [min_r, min_c] = ind2sub([imgH imgW], idx_min);

    floor_mask = buildLocalDiskMask(imgH, imgW, min_r, min_c, opts.floor_radius_px) & support_mask;
    floor_vals = Z_raw(floor_mask);
    if isempty(floor_vals)
        floor_vals = Z_raw(idx_min);
    end
    floor_z = prctile(floor_vals, 20);

    boundary_vals = Z_smooth(support_perim);
    if numel(boundary_vals) < 5
        continue;
    end
    merge_z = prctile(boundary_vals, 25);
    significance = merge_z - floor_z;
    depression_mask = support_mask & (Z_smooth <= merge_z);

    peak_proxy = max(Z_raw(poly2mask(poly(:,1), poly(:,2), imgH, imgW)));
    if isempty(peak_proxy)
        peak_proxy = max(Z_raw(support_mask));
    end

    candidates(t) = template;
    candidates(t).tri_idx = t;
    candidates(t).mound_idx = unique(seed_to_original_idx(idx(seed_to_original_idx(idx) > 0)), 'stable')';
    candidates(t).support_mask = support_mask;
    candidates(t).support_perimeter_mask = support_perim;
    candidates(t).min_x_px = min_c;
    candidates(t).min_y_px = min_r;
    candidates(t).floor_z_um = floor_z;
    candidates(t).merge_z_um = merge_z;
    candidates(t).significance_um = significance;
    candidates(t).depression_mask = depression_mask;
    candidates(t).boundary_z_p25_um = merge_z;
    candidates(t).peak_z_proxy_um = peak_proxy;
    candidates(t).is_valid = significance >= opts.sig_min_um && nnz(depression_mask) >= 9;
end
end


function groups = mergeTriangleCandidates(candidates, Z_smooth, opts)
valid_idx = find([candidates.is_valid]);
if isempty(valid_idx)
    groups = struct('candidate_idx', {});
    return;
end

n = numel(candidates);
adj = false(n, n);
tri_list = reshape([candidates.tri_idx], [], 1);

for i = 1:numel(valid_idx)
    ci = valid_idx(i);
    for j = i+1:numel(valid_idx)
        cj = valid_idx(j);

        shared_mounds = intersect(candidates(ci).mound_idx, candidates(cj).mound_idx);
        if numel(shared_mounds) < 2
            continue;
        end

        if shouldMergeCandidates(candidates(ci), candidates(cj), Z_smooth, opts)
            adj(ci, cj) = true;
            adj(cj, ci) = true;
        end
    end
end

visited = false(n, 1);
groups = struct('candidate_idx', {});
g = 0;
for i = valid_idx(:)'
    if visited(i)
        continue;
    end
    queue = i;
    members = [];
    visited(i) = true;

    while ~isempty(queue)
        curr = queue(1);
        queue(1) = [];
        members(end+1) = curr; %#ok<AGROW>
        nbrs = find(adj(curr, :) & ~visited');
        if ~isempty(nbrs)
            visited(nbrs) = true;
            queue = [queue, nbrs];
        end
    end

    g = g + 1;
    groups(g).candidate_idx = sort(members);
    groups(g).triangle_idx = tri_list(groups(g).candidate_idx);
end
end


function tf = shouldMergeCandidates(c1, c2, Z_smooth, opts)
dist_px = hypot(c1.min_x_px - c2.min_x_px, c1.min_y_px - c2.min_y_px);
bridge_z = sampleBridgeMax(Z_smooth, [c1.min_x_px c1.min_y_px], [c2.min_x_px c2.min_y_px]);
bridge_limit = min(c1.merge_z_um, c2.merge_z_um) + opts.bridge_tol_um;
bridge_ok = bridge_z <= bridge_limit;
close_ok = dist_px <= opts.merge_dist_px;

% Only merge when adjacent triangles nominate essentially the same local pit.
% This avoids graph-chaining long valley corridors into one cavity object.
tf = bridge_ok && close_ok;
end


function [cavities, cavity_label] = finalizeCavityGroups( ...
    groups, candidates, ~, Z_raw, Z_smooth, inpaint_mask, ...
    ~, ~, xy, ~, opts)

[imgH, imgW] = size(Z_raw);
cavity_label = zeros(imgH, imgW, 'uint32');
template = struct( ...
    'depth_um', NaN, ...
    'floor_z_um', NaN, ...
    'mouth_z_um', NaN, ...
    'mouth_area_um2', NaN, ...
    'mouth_equiv_radius_um', NaN, ...
    'mouth_equiv_diameter_um', NaN, ...
    'mouth_inscribed_radius_um', NaN, ...
    'cone_half_angle_deg', NaN, ...
    'cone_fit_rmse_um', NaN, ...
    'persistence_um', NaN, ...
    'independent_relief_um', NaN, ...
    'n_supporting_triangles', NaN, ...
    'supporting_triangle_idx', [], ...
    'bounding_mound_idx', [], ...
    'cavity_support_type', "", ...
    'cavity_enclosure_type', "", ...
    'cavity_quality_flag', "", ...
    'centroid_px', [NaN NaN], ...
    'floor_px', [NaN NaN], ...
    'raw_minimum_px', [NaN NaN], ...
    'n_raw_minima', NaN, ...
    'n_surviving_minima_in_group', NaN, ...
    'swallowed_minimum_parent_idx', NaN, ...
    'minimum_saddle_um', NaN, ...
    'mouth_z_highest_valid_um', NaN, ...
    'mouth_area_highest_valid_um2', NaN, ...
    'mouth_equiv_radius_highest_valid_um', NaN, ...
    'mouth_equiv_diameter_highest_valid_um', NaN, ...
    'mouth_inscribed_radius_highest_valid_um', NaN, ...
    'depth_highest_valid_um', NaN, ...
    'cone_half_angle_highest_valid_deg', NaN, ...
    'highest_valid_pixel_idx', zeros(0, 1), ...
    'mouth_z_plateau_top_um', NaN, ...
    'mouth_area_plateau_top_um2', NaN, ...
    'mouth_equiv_radius_plateau_top_um', NaN, ...
    'mouth_equiv_diameter_plateau_top_um', NaN, ...
    'mouth_inscribed_radius_plateau_top_um', NaN, ...
    'depth_plateau_top_um', NaN, ...
    'cone_half_angle_plateau_top_deg', NaN, ...
    'plateau_top_pixel_idx', zeros(0, 1), ...
    'mask', false(imgH, imgW), ...
    'mouth_mask', false(imgH, imgW), ...
    'mouth_perimeter_mask', false(imgH, imgW), ...
    'support_mask', false(imgH, imgW), ...
    'is_inpainted', false, ...
    'support_contact_fraction', NaN, ...
    'contour_level_history_um', zeros(0, 1), ...
    'contour_area_history_px', zeros(0, 1), ...
    'contour_candidate_flag', false(0, 1), ...
    'contour_admissible_flag', false(0, 1));

cavities = repmat(template, 0, 1);

for g = 1:numel(groups)
    cand_idx = groups(g).candidate_idx;
    support_mask = false(imgH, imgW);
    depression_union = false(imgH, imgW);
    tri_idx = zeros(1, numel(cand_idx));
    mound_idx = [];
    persistence_group = nan(numel(cand_idx), 1);

    for k = 1:numel(cand_idx)
        ck = candidates(cand_idx(k));
        support_mask = support_mask | ck.support_mask;
        depression_union = depression_union | ck.depression_mask;
        tri_idx(k) = ck.tri_idx;
        mound_idx = [mound_idx, ck.mound_idx]; %#ok<AGROW>
        persistence_group(k) = ck.significance_um;
    end

    mound_idx = unique(mound_idx, 'stable');
    z_support = Z_smooth;
    z_support(~support_mask) = inf;
    [~, idx_min] = min(z_support(:));
    if ~isfinite(z_support(idx_min))
        continue;
    end
    [min_r, min_c] = ind2sub([imgH imgW], idx_min);

    floor_mask = buildLocalDiskMask(imgH, imgW, min_r, min_c, opts.floor_radius_px) & support_mask;
    if nnz(floor_mask) < 4
        floor_mask = buildLocalDiskMask(imgH, imgW, min_r, min_c, max(1, floor(opts.floor_radius_px / 2))) & support_mask;
    end
    floor_vals = Z_raw(floor_mask);
    if isempty(floor_vals)
        floor_vals = Z_raw(idx_min);
    end
    floor_z = prctile(floor_vals, 20);

    geom_support_mask = support_mask & imdilate(depression_union, strel('disk', max(1, opts.floor_radius_px)));
    if nnz(geom_support_mask) < nnz(floor_mask)
        geom_support_mask = support_mask;
    end

    raw_minima = detectRawMinimaInMask(Z_smooth, geom_support_mask);
    if isempty(raw_minima)
        raw_minima = struct('row', min_r, 'col', min_c, 'z_um', Z_smooth(min_r, min_c), ...
            'pixel_count', 1, 'parent_idx', NaN, 'saddle_um', NaN, 'independent_relief_um', NaN);
    end

    relief_threshold = max(opts.min_depth_um * 0.35, max(persistence_group) * 0.15);
    merge_dist_px = max(2, 2.2 * opts.floor_radius_px);
    consolidated = consolidateLocalMinima(raw_minima, Z_smooth, relief_threshold, merge_dist_px);
    surviving_idx = find([consolidated.is_surviving]);
    if isempty(surviving_idx)
        [~, best_idx] = min([consolidated.z_um]);
        surviving_idx = best_idx;
        consolidated(best_idx).is_surviving = true;
    end

    surviving_pts = [[consolidated(surviving_idx).row]' [consolidated(surviving_idx).col]'];
    support_type = classifySupportType(numel(tri_idx));

    for si = 1:numel(surviving_idx)
        ci = surviving_idx(si);
        curr = consolidated(ci);
        floor_r = curr.row;
        floor_c = curr.col;
        floor_mask_local = buildLocalDiskMask(imgH, imgW, floor_r, floor_c, opts.floor_radius_px) & geom_support_mask;
        if nnz(floor_mask_local) < 4
            floor_mask_local = buildLocalDiskMask(imgH, imgW, floor_r, floor_c, max(1, floor(opts.floor_radius_px / 2))) & geom_support_mask;
        end
        floor_vals_local = Z_raw(floor_mask_local);
        if isempty(floor_vals_local)
            floor_vals_local = Z_raw(floor_r, floor_c);
        end
        floor_z_local = prctile(floor_vals_local, 20);

        history = buildContourHistoryForMinimum( ...
            Z_raw, Z_smooth, geom_support_mask, floor_r, floor_c, floor_z_local, ...
            surviving_pts, [floor_r floor_c], opts, xy);

        idx_highest = chooseHighestAdmissibleContour(history);
        idx_plateau = choosePlateauContour(history);

        if isnan(idx_highest) && isnan(idx_plateau)
            history = buildFallbackContourHistory(history, floor_mask_local, floor_z_local, Z_raw, xy, floor_r, floor_c, geom_support_mask);
            idx_highest = 1;
            idx_plateau = 1;
        elseif isnan(idx_plateau)
            idx_plateau = idx_highest;
        elseif isnan(idx_highest)
            idx_highest = idx_plateau;
        end

        metrics_high = contourMetricsToOutputs(history(idx_highest), floor_z_local, Z_raw, geom_support_mask, xy, floor_r, floor_c);
        metrics_plateau = contourMetricsToOutputs(history(idx_plateau), floor_z_local, Z_raw, geom_support_mask, xy, floor_r, floor_c);

        preferred = metrics_plateau;
        [rows, cols] = find(preferred.mask);
        centroid_px = [mean(cols), mean(rows)];
        enclosure_type = classifyEnclosureType(numel(mound_idx), preferred.contact_fraction);
        quality_flag = classifyQualityFlag( ...
            preferred.depth_um, preferred.equiv_radius_um, preferred.inscribed_radius_um, ...
            preferred.contact_fraction, preferred.cone_fit_rmse_um, any(inpaint_mask(support_mask)));

        rec = template;
        rec.depth_um = preferred.depth_um;
        rec.floor_z_um = floor_z_local;
        rec.mouth_z_um = preferred.mouth_z_um;
        rec.mouth_area_um2 = preferred.area_um2;
        rec.mouth_equiv_radius_um = preferred.equiv_radius_um;
        rec.mouth_equiv_diameter_um = preferred.equiv_diameter_um;
        rec.mouth_inscribed_radius_um = preferred.inscribed_radius_um;
        rec.cone_half_angle_deg = preferred.cone_half_angle_deg;
        rec.cone_fit_rmse_um = preferred.cone_fit_rmse_um;
        rec.persistence_um = max(persistence_group);
        rec.independent_relief_um = curr.independent_relief_um;
        rec.n_supporting_triangles = numel(tri_idx);
        rec.supporting_triangle_idx = sort(unique(tri_idx));
        rec.bounding_mound_idx = mound_idx;
        rec.cavity_support_type = support_type;
        rec.cavity_enclosure_type = enclosure_type;
        rec.cavity_quality_flag = quality_flag;
        rec.centroid_px = centroid_px;
        rec.floor_px = [floor_c, floor_r];
        rec.raw_minimum_px = [curr.col, curr.row];
        rec.n_raw_minima = numel(raw_minima);
        rec.n_surviving_minima_in_group = numel(surviving_idx);
        rec.swallowed_minimum_parent_idx = curr.parent_idx;
        rec.minimum_saddle_um = curr.saddle_um;
        rec.mouth_z_highest_valid_um = metrics_high.mouth_z_um;
        rec.mouth_area_highest_valid_um2 = metrics_high.area_um2;
        rec.mouth_equiv_radius_highest_valid_um = metrics_high.equiv_radius_um;
        rec.mouth_equiv_diameter_highest_valid_um = metrics_high.equiv_diameter_um;
        rec.mouth_inscribed_radius_highest_valid_um = metrics_high.inscribed_radius_um;
        rec.depth_highest_valid_um = metrics_high.depth_um;
        rec.cone_half_angle_highest_valid_deg = metrics_high.cone_half_angle_deg;
        rec.highest_valid_pixel_idx = history(idx_highest).pixel_idx;
        rec.mouth_z_plateau_top_um = metrics_plateau.mouth_z_um;
        rec.mouth_area_plateau_top_um2 = metrics_plateau.area_um2;
        rec.mouth_equiv_radius_plateau_top_um = metrics_plateau.equiv_radius_um;
        rec.mouth_equiv_diameter_plateau_top_um = metrics_plateau.equiv_diameter_um;
        rec.mouth_inscribed_radius_plateau_top_um = metrics_plateau.inscribed_radius_um;
        rec.depth_plateau_top_um = metrics_plateau.depth_um;
        rec.cone_half_angle_plateau_top_deg = metrics_plateau.cone_half_angle_deg;
        rec.plateau_top_pixel_idx = history(idx_plateau).pixel_idx;
        rec.mask = preferred.mask;
        rec.mouth_mask = preferred.mask;
        rec.mouth_perimeter_mask = bwperim(preferred.mask);
        rec.support_mask = geom_support_mask;
        rec.is_inpainted = any(inpaint_mask(support_mask));
        rec.support_contact_fraction = preferred.contact_fraction;
        rec.contour_level_history_um = [history.level_um]';
        rec.contour_area_history_px = [history.area_px]';
        rec.contour_candidate_flag = logical([history.is_candidate_level]');
        rec.contour_admissible_flag = logical([history.is_admissible]');
        cavities(end+1, 1) = rec; %#ok<AGROW>
    end
end

keep = isfinite([cavities.depth_um]);
cavities = cavities(keep);

for k = 1:numel(cavities)
    cavity_label(cavities(k).mask) = k;
end
end


function raw_minima = detectRawMinimaInMask(Z_smooth, support_mask)
min_mask = imregionalmin(Z_smooth) & support_mask;
cc = bwconncomp(min_mask, 8);
if cc.NumObjects == 0
    raw_minima = struct('row', {}, 'col', {}, 'z_um', {}, 'pixel_count', {}, ...
        'parent_idx', {}, 'saddle_um', {}, 'independent_relief_um', {});
    return;
end

raw_minima = repmat(struct('row', NaN, 'col', NaN, 'z_um', NaN, 'pixel_count', NaN, ...
    'parent_idx', NaN, 'saddle_um', NaN, 'independent_relief_um', NaN), cc.NumObjects, 1);
for i = 1:cc.NumObjects
    px = cc.PixelIdxList{i};
    [rows, cols] = ind2sub(size(Z_smooth), px);
    [zmin, idx_local] = min(Z_smooth(px));
    raw_minima(i).row = rows(idx_local);
    raw_minima(i).col = cols(idx_local);
    raw_minima(i).z_um = zmin;
    raw_minima(i).pixel_count = numel(px);
end
end


function minima = consolidateLocalMinima(raw_minima, Z_smooth, relief_threshold, merge_dist_px)
if isempty(raw_minima)
    minima = raw_minima;
    return;
end

minima = raw_minima;
for i = 1:numel(minima)
    minima(i).is_surviving = true;
    minima(i).parent_idx = NaN;
    minima(i).saddle_um = NaN;
    minima(i).independent_relief_um = Inf;
end

[~, order] = sort([minima.z_um], 'ascend');
for oi = 2:numel(order)
    idx_i = order(oi);
    best_parent = NaN;
    best_saddle = NaN;
    best_relief = Inf;

    for oj = 1:oi-1
        idx_j = order(oj);
        if ~minima(idx_j).is_surviving
            continue;
        end
        dist_px = hypot(minima(idx_i).col - minima(idx_j).col, minima(idx_i).row - minima(idx_j).row);
        if dist_px > merge_dist_px
            continue;
        end

        saddle_um = sampleBridgeMax(Z_smooth, [minima(idx_i).col minima(idx_i).row], [minima(idx_j).col minima(idx_j).row]);
        relief_um = saddle_um - minima(idx_i).z_um;
        if relief_um < best_relief
            best_relief = relief_um;
            best_parent = idx_j;
            best_saddle = saddle_um;
        end
    end

    minima(idx_i).independent_relief_um = best_relief;
    minima(idx_i).saddle_um = best_saddle;
    if isfinite(best_relief) && best_relief < relief_threshold
        minima(idx_i).is_surviving = false;
        minima(idx_i).parent_idx = best_parent;
    end
end

for i = 1:numel(minima)
    if ~isfinite(minima(i).independent_relief_um)
        minima(i).independent_relief_um = max(relief_threshold, 0);
    end
end
end


function history = buildContourHistoryForMinimum( ...
    Z_raw, Z_smooth, support_mask, min_r, min_c, floor_z, surviving_pts_rc, self_pt_rc, opts, xy)

[imgH, imgW] = size(support_mask);
[sr, sc] = find(support_mask);
r1 = max(1, min(sr) - 2); r2 = min(imgH, max(sr) + 2);
c1 = max(1, min(sc) - 2); c2 = min(imgW, max(sc) + 2);
support_local = support_mask(r1:r2, c1:c2);
Zs_local = Z_smooth(r1:r2, c1:c2);
min_r_local = min_r - r1 + 1;
min_c_local = min_c - c1 + 1;

support_perim = bwperim(support_mask);
boundary_vals = Z_smooth(support_perim);
search_hi = max(prctile(boundary_vals, 75), floor_z + opts.min_depth_um);
levels = linspace(floor_z + 1e-3, search_hi, opts.search_levels);

template = struct('level_um', NaN, 'pixel_idx', zeros(0,1), 'image_size', [imgH imgW], 'area_px', NaN, ...
    'equiv_radius_px', NaN, 'inscribed_radius_px', NaN, 'aspect_ratio', NaN, ...
    'solidity', NaN, 'contact_fraction', NaN, 'merge_with_other_minimum', false, ...
    'is_candidate_level', false, 'is_admissible', false);
history = repmat(template, numel(levels), 1);

other_pts = surviving_pts_rc;
other_self = all(other_pts == self_pt_rc, 2);
other_pts(other_self, :) = [];

for li = 1:numel(levels)
    zt = levels(li);
    comp_local = extractMinimumComponentLocal(Zs_local, support_local, min_r_local, min_c_local, zt);
    if ~any(comp_local(:))
        history(li).level_um = zt;
        continue;
    end

    stats = regionprops(comp_local, 'MajorAxisLength', 'MinorAxisLength', 'Solidity');
    if isempty(stats)
        aspect_ratio = Inf;
        solidity = NaN;
    else
        major = max(stats(1).MajorAxisLength, eps);
        minor = max(stats(1).MinorAxisLength, eps);
        aspect_ratio = major / minor;
        solidity = stats(1).Solidity;
    end

    area_px = nnz(comp_local);
    equiv_radius_px = sqrt(area_px / pi);
    inscribed_radius_px = maxDistanceInsideMask(comp_local);
    support_perim_local = bwperim(support_local);
    n_contact = nnz(comp_local & support_perim_local);
    contact_fraction = n_contact / max(1, nnz(support_perim_local));
    merge_with_other = false;
    for oi = 1:size(other_pts, 1)
        rr = other_pts(oi, 1);
        cc = other_pts(oi, 2);
        rr_local = rr - r1 + 1;
        cc_local = cc - c1 + 1;
        if rr_local >= 1 && rr_local <= size(comp_local, 1) && cc_local >= 1 && cc_local <= size(comp_local, 2) && comp_local(rr_local, cc_local)
            merge_with_other = true;
            break;
        end
    end

    is_candidate = n_contact >= opts.contact_px_threshold;
    roundness_ratio = inscribed_radius_px / max(equiv_radius_px, eps);
    is_admissible = is_candidate && ~merge_with_other && ...
        aspect_ratio <= 3.5 && roundness_ratio >= 0.28 && ...
        contact_fraction <= 0.55 && solidity >= 0.45 && area_px >= 4;

    history(li).level_um = zt;
    [comp_rows, comp_cols] = find(comp_local);
    history(li).pixel_idx = sub2ind([imgH imgW], comp_rows + r1 - 1, comp_cols + c1 - 1);
    history(li).area_px = area_px;
    history(li).equiv_radius_px = equiv_radius_px;
    history(li).inscribed_radius_px = inscribed_radius_px;
    history(li).aspect_ratio = aspect_ratio;
    history(li).solidity = solidity;
    history(li).contact_fraction = contact_fraction;
    history(li).merge_with_other_minimum = merge_with_other;
    history(li).is_candidate_level = is_candidate;
    history(li).is_admissible = is_admissible;
end
end


function comp = extractMinimumComponentLocal(Z_smooth_local, support_mask_local, min_r_local, min_c_local, zt)
bw = support_mask_local & (Z_smooth_local <= zt);
comp = false(size(bw));
if ~bw(min_r_local, min_c_local)
    return;
end
cc = bwconncomp(bw, 8);
min_lin = sub2ind(size(bw), min_r_local, min_c_local);
for ci = 1:cc.NumObjects
    if any(cc.PixelIdxList{ci} == min_lin)
        comp(cc.PixelIdxList{ci}) = true;
        return;
    end
end
end


function idx = chooseHighestAdmissibleContour(history)
idx = NaN;
for i = numel(history):-1:1
    if history(i).is_admissible
        idx = i;
        return;
    end
end
end


function idx = choosePlateauContour(history)
idx = NaN;
valid = find([history.is_admissible]);
if isempty(valid)
    return;
end

min_plateau_len = 3;
runs = zeros(0, 3);
run_start = valid(1);
prev = valid(1);
for k = 2:numel(valid)
    curr = valid(k);
    stable = isStablePlateauStep(history(prev), history(curr));
    if ~(curr == prev + 1 && stable)
        runs(end+1, :) = [run_start, prev, prev - run_start + 1]; %#ok<AGROW>
        run_start = curr;
    end
    prev = curr;
end
runs(end+1, :) = [run_start, prev, prev - run_start + 1]; %#ok<AGROW>

eligible = runs(runs(:, 3) >= min_plateau_len, :);
if isempty(eligible)
    eligible = runs(runs(:, 3) >= 2, :);
end
if isempty(eligible)
    idx = valid(1);
    return;
end

[~, order] = sortrows([eligible(:, 2), eligible(:, 3)], [-1 -2]);
best = eligible(order(1), :);
idx = best(2);
end


function tf = isStablePlateauStep(prev_entry, curr_entry)
if ~prev_entry.is_admissible || ~curr_entry.is_admissible
    tf = false;
    return;
end

area_rel = abs(curr_entry.area_px - prev_entry.area_px) / max(prev_entry.area_px, eps);
radius_rel = abs(curr_entry.equiv_radius_px - prev_entry.equiv_radius_px) / max(prev_entry.equiv_radius_px, eps);
aspect_rel = abs(curr_entry.aspect_ratio - prev_entry.aspect_ratio) / max(prev_entry.aspect_ratio, 1);
contact_abs = abs(curr_entry.contact_fraction - prev_entry.contact_fraction);
solidity_drop = max(prev_entry.solidity - curr_entry.solidity, 0);

tf = area_rel <= 0.18 && ...
     radius_rel <= 0.10 && ...
     aspect_rel <= 0.16 && ...
     contact_abs <= 0.06 && ...
     solidity_drop <= 0.05;
end


function history = buildFallbackContourHistory(history, floor_mask, floor_z, ~, ~, ~, ~, ~)
template = history(1);
template.level_um = floor_z;
template.pixel_idx = find(floor_mask);
template.area_px = nnz(floor_mask);
template.equiv_radius_px = sqrt(max(template.area_px, 0) / pi);
template.inscribed_radius_px = maxDistanceInsideMask(floor_mask);
template.aspect_ratio = 1;
template.solidity = 1;
template.contact_fraction = 0;
template.merge_with_other_minimum = false;
template.is_candidate_level = true;
template.is_admissible = true;
history = template;
end


function metrics = contourMetricsToOutputs(entry, floor_z, Z_raw, support_mask, xy, floor_r, floor_c)
mouth_mask = refineSelectedContourOnRawZ(entry, Z_raw, support_mask, floor_r, floor_c);
if ~any(mouth_mask(:))
    mouth_mask = false(entry.image_size);
    mouth_mask(entry.pixel_idx) = true;
end

mouth_perim = bwperim(mouth_mask);
mouth_perim_vals = Z_raw(mouth_perim);
if isempty(mouth_perim_vals)
    mouth_perim_vals = Z_raw(mouth_mask);
end
mouth_z = max(entry.level_um, median(mouth_perim_vals));

refined_mask = refineSelectedContourOnRawZAtLevel(mouth_mask, Z_raw, support_mask, floor_r, floor_c, mouth_z);
if any(refined_mask(:))
    mouth_mask = refined_mask;
    mouth_perim = bwperim(mouth_mask);
    mouth_perim_vals = Z_raw(mouth_perim);
    if isempty(mouth_perim_vals)
        mouth_perim_vals = Z_raw(mouth_mask);
    end
    mouth_z = max(entry.level_um, median(mouth_perim_vals));
end

support_perim = bwperim(support_mask);
contact_fraction = nnz(mouth_mask & support_perim) / max(1, nnz(support_perim));
area_px = nnz(mouth_mask);
area_um2 = area_px * (xy ^ 2);
equiv_radius_um = sqrt(max(area_um2, 0) / pi);
equiv_diameter_um = 2 * equiv_radius_um;
inscribed_radius_um = maxDistanceInsideMask(mouth_mask) * xy;
depth_um = max(mouth_z - floor_z, 0);
cone_half_angle_deg = atand(equiv_radius_um / max(depth_um, eps));
cone_fit_rmse_um = estimateConeFitRmse(Z_raw, mouth_mask, floor_r, floor_c, floor_z, mouth_z, equiv_radius_um, xy);

metrics = struct( ...
    'mask', mouth_mask, ...
    'mouth_z_um', mouth_z, ...
    'area_um2', area_um2, ...
    'equiv_radius_um', equiv_radius_um, ...
    'equiv_diameter_um', equiv_diameter_um, ...
    'inscribed_radius_um', inscribed_radius_um, ...
    'depth_um', depth_um, ...
    'cone_half_angle_deg', cone_half_angle_deg, ...
    'cone_fit_rmse_um', cone_fit_rmse_um, ...
    'contact_fraction', contact_fraction);
end


function mouth_mask = refineSelectedContourOnRawZ(entry, Z_raw, support_mask, floor_r, floor_c)
mouth_mask = refineSelectedContourOnRawZAtLevel(false(entry.image_size), Z_raw, support_mask, floor_r, floor_c, entry.level_um);
end


function mouth_mask = refineSelectedContourOnRawZAtLevel(fallback_mask, Z_raw, support_mask, floor_r, floor_c, level_um)
mouth_mask = false(size(support_mask));
if ~support_mask(floor_r, floor_c)
    if any(fallback_mask(:))
        mouth_mask = fallback_mask;
    end
    return;
end

bw = support_mask & (Z_raw <= level_um);
if ~bw(floor_r, floor_c)
    if any(fallback_mask(:))
        mouth_mask = fallback_mask;
    end
    return;
end

cc = bwconncomp(bw, 8);
floor_lin = sub2ind(size(bw), floor_r, floor_c);
for ci = 1:cc.NumObjects
    if any(cc.PixelIdxList{ci} == floor_lin)
        mouth_mask(cc.PixelIdxList{ci}) = true;
        return;
    end
end

if any(fallback_mask(:))
    mouth_mask = fallback_mask;
end
end


function makeTriangleDiagnosticFigure(I_raw, imageName, outputDir, tri_seed_centroids, original_centroids, dt, candidates, groups)
fig = figure('Name', 'Triangle cavity candidates', 'Position', [40 40 1250 950], 'Color', 'w');
I_rgb = repmat(I_raw, [1 1 3]);
imshow(I_rgb);
hold on;

tri = dt.ConnectivityList;
for t = 1:size(tri, 1)
    pts = tri_seed_centroids(tri(t, [1 2 3 1]), :);
    if candidates(t).is_valid
        plot(pts(:,1), pts(:,2), '-', 'Color', [0.10 0.95 0.75], 'LineWidth', 0.7);
        plot(candidates(t).min_x_px, candidates(t).min_y_px, 'yo', ...
            'MarkerSize', 4.5, 'MarkerFaceColor', [1 0.95 0.1], 'MarkerEdgeColor', 'k');
    else
        plot(pts(:,1), pts(:,2), '-', 'Color', [0.45 0.45 0.45], 'LineWidth', 0.4);
    end
end

if ~isempty(original_centroids)
    plot(original_centroids(:,1), original_centroids(:,2), 'r+', 'MarkerSize', 5, 'LineWidth', 0.8);
end

for g = 1:numel(groups)
    valid_members = groups(g).candidate_idx;
    if isempty(valid_members)
        continue;
    end
    xg = mean([candidates(valid_members).min_x_px]);
    yg = mean([candidates(valid_members).min_y_px]);
        text(xg, yg, sprintf('G%d', g), 'Color', 'w', 'FontWeight', 'bold', ...
        'FontSize', 8, 'HorizontalAlignment', 'center', 'BackgroundColor', [0 0 0]);
end

title(sprintf('%s | triangle cavity candidates and merged groups', imageName), ...
    'Interpreter', 'none', 'Color', 'w');
set(gca, 'Color', 'k');
hold off;
exportgraphics(fig, fullfile(outputDir, [imageName '_triangle_candidates.png']), 'Resolution', 150);
end


function makeMergedOverlayFigure(I_raw, imageName, outputDir, centroids, real_cavities, shallow_cavities, xy, added_edge_seed_centroids)
fig = figure('Name','Merged cavity overlay', 'Position', [50 50 1250 950], 'Color', 'w');
I_rgb = repmat(I_raw, [1 1 3]);
imshow(I_rgb);
hold on;

if ~isempty(real_cavities)
    d = [real_cavities.depth_um];
    d = d(isfinite(d));
    if isempty(d)
        d = 0;
    end
    cmap = parula(256);
    [dlo, dhi] = safeColorLimits(d);

    for k = 1:numel(real_cavities)
        c = real_cavities(k);
        t = max(0, min(1, (c.depth_um - dlo) / (dhi - dlo)));
        idx = max(1, min(256, 1 + round(t * 255)));
        col = cmap(idx, :);
        plotSmoothedMaskBoundaries(c.mouth_mask, col, 1.3);

        r_px = c.mouth_equiv_radius_um / xy;
        th = linspace(0, 2*pi, 64);
        plot(c.centroid_px(1) + r_px * cos(th), c.centroid_px(2) + r_px * sin(th), ...
            ':', 'Color', col, 'LineWidth', 0.8);

        plot(c.centroid_px(1), c.centroid_px(2), 'o', ...
            'MarkerSize', 5.5, 'MarkerFaceColor', col, 'MarkerEdgeColor', 'w', 'LineWidth', 0.6);
        text(c.centroid_px(1), c.centroid_px(2) - 8, sprintf('%dT', c.n_supporting_triangles), ...
            'Color', 'w', 'FontSize', 7, 'HorizontalAlignment', 'center');
    end

    if isfinite(dlo) && isfinite(dhi) && dhi > dlo
        colormap(gca, parula);
        clim([dlo dhi]);
        cb = colorbar('Location', 'eastoutside');
        cb.Label.String = 'Cavity depth (um)';
    end
end

if ~isempty(shallow_cavities)
    xs = arrayfun(@(c) c.centroid_px(1), shallow_cavities);
    ys = arrayfun(@(c) c.centroid_px(2), shallow_cavities);
    plot(xs, ys, 'x', 'Color', [0.6 0.6 0.6], 'MarkerSize', 5, 'LineWidth', 0.8);
end

plot(centroids(:,1), centroids(:,2), 'r+', 'MarkerSize', 5, 'LineWidth', 0.8);
if nargin >= 8 && ~isempty(added_edge_seed_centroids)
    plot(added_edge_seed_centroids(:,1), added_edge_seed_centroids(:,2), 'x', ...
        'Color', [0.95 0.8 0.2], 'MarkerSize', 4.5, 'LineWidth', 0.7);
end
title(sprintf('%s | accepted inter-mound cavities', imageName), 'Interpreter', 'none', 'Color', 'w');
set(gca, 'Color', 'k');
hold off;
exportgraphics(fig, fullfile(outputDir, [imageName '_cavities.png']), 'Resolution', 150);
end


function makeMethodOverlayFigure(I_raw, imageName, outputDir, centroids, real_cavities, shallow_cavities, xy, added_edge_seed_centroids, method_name)
fig = figure('Name', ['Cavity overlay - ' method_name], 'Position', [70 70 1250 950], 'Color', 'w');
I_rgb = repmat(I_raw, [1 1 3]);
imshow(I_rgb);
hold on;

if ~isempty(real_cavities)
    switch method_name
        case 'highest_valid'
            d = [real_cavities.depth_highest_valid_um];
        case 'plateau_top'
            d = [real_cavities.depth_plateau_top_um];
        otherwise
            d = [real_cavities.depth_um];
    end
    d = d(isfinite(d));
    if isempty(d)
        d = 0;
    end
    cmap = parula(256);
    [dlo, dhi] = safeColorLimits(d);

    for k = 1:numel(real_cavities)
        c = real_cavities(k);
        switch method_name
            case 'highest_valid'
                mask = false(size(c.mask));
                mask(c.highest_valid_pixel_idx) = true;
                depth_val = c.depth_highest_valid_um;
                radius_um = c.mouth_equiv_radius_highest_valid_um;
            case 'plateau_top'
                mask = false(size(c.mask));
                mask(c.plateau_top_pixel_idx) = true;
                depth_val = c.depth_plateau_top_um;
                radius_um = c.mouth_equiv_radius_plateau_top_um;
            otherwise
                mask = c.mouth_mask;
                depth_val = c.depth_um;
                radius_um = c.mouth_equiv_radius_um;
        end

        t = max(0, min(1, (depth_val - dlo) / max(dhi - dlo, eps)));
        idx = max(1, min(256, 1 + round(t * 255)));
        col = cmap(idx, :);
        plotSmoothedMaskBoundaries(mask, col, 1.35);

        r_px = radius_um / xy;
        th = linspace(0, 2*pi, 64);
        plot(c.centroid_px(1) + r_px * cos(th), c.centroid_px(2) + r_px * sin(th), ...
            ':', 'Color', col, 'LineWidth', 0.8);
        plot(c.centroid_px(1), c.centroid_px(2), 'o', ...
            'MarkerSize', 5.5, 'MarkerFaceColor', col, 'MarkerEdgeColor', 'w', 'LineWidth', 0.6);
        text(c.centroid_px(1), c.centroid_px(2) - 8, sprintf('%dT', c.n_supporting_triangles), ...
            'Color', 'w', 'FontSize', 7, 'HorizontalAlignment', 'center');
    end

    if isfinite(dlo) && isfinite(dhi) && dhi > dlo
        colormap(gca, parula);
        clim([dlo dhi]);
        cb = colorbar('Location', 'eastoutside');
        cb.Label.String = sprintf('Cavity depth (%s) (um)', strrep(method_name, '_', ' '));
    end
end

if ~isempty(shallow_cavities)
    xs = arrayfun(@(c) c.centroid_px(1), shallow_cavities);
    ys = arrayfun(@(c) c.centroid_px(2), shallow_cavities);
    plot(xs, ys, 'x', 'Color', [0.6 0.6 0.6], 'MarkerSize', 5, 'LineWidth', 0.8);
end

plot(centroids(:,1), centroids(:,2), 'r+', 'MarkerSize', 5, 'LineWidth', 0.8);
if nargin >= 8 && ~isempty(added_edge_seed_centroids)
    plot(added_edge_seed_centroids(:,1), added_edge_seed_centroids(:,2), 'x', ...
        'Color', [0.95 0.8 0.2], 'MarkerSize', 4.5, 'LineWidth', 0.7);
end
title(sprintf('%s | cavity overlay - %s', imageName, strrep(method_name, '_', ' ')), ...
    'Interpreter', 'none', 'Color', 'w');
set(gca, 'Color', 'k');
hold off;
exportgraphics(fig, fullfile(outputDir, [imageName '_cavities_' method_name '.png']), 'Resolution', 150);
end


function summary = summarizeMethodComparison(real_cavities)
n = numel(real_cavities);
summary = struct( ...
    'n_compared', n, ...
    'n_different', 0, ...
    'fraction_different', 0, ...
    'different_idx', zeros(0, 1), ...
    'abs_mouth_delta_um', zeros(0, 1), ...
    'abs_depth_delta_um', zeros(0, 1), ...
    'max_abs_mouth_delta_um', 0, ...
    'median_abs_mouth_delta_um', 0, ...
    'max_abs_depth_delta_um', 0, ...
    'median_abs_depth_delta_um', 0);

if isempty(real_cavities)
    fprintf('  Method comparison: no accepted cavities to compare.\n');
    return;
end

mouth_high = [real_cavities.mouth_z_highest_valid_um]';
mouth_plateau = [real_cavities.mouth_z_plateau_top_um]';
depth_high = [real_cavities.depth_highest_valid_um]';
depth_plateau = [real_cavities.depth_plateau_top_um]';

abs_mouth_delta = abs(mouth_high - mouth_plateau);
abs_depth_delta = abs(depth_high - depth_plateau);
is_diff = abs_mouth_delta > 1e-9 | abs_depth_delta > 1e-9;

summary.n_different = nnz(is_diff);
summary.fraction_different = summary.n_different / max(n, 1);
summary.different_idx = find(is_diff);
summary.abs_mouth_delta_um = abs_mouth_delta;
summary.abs_depth_delta_um = abs_depth_delta;
summary.max_abs_mouth_delta_um = max(abs_mouth_delta);
summary.median_abs_mouth_delta_um = median(abs_mouth_delta);
summary.max_abs_depth_delta_um = max(abs_depth_delta);
summary.median_abs_depth_delta_um = median(abs_depth_delta);

fprintf(['  Method comparison: %d / %d cavities differ between highest-valid and plateau-top ' ...
         '(max |delta mouth| = %.3f um, max |delta depth| = %.3f um).\n'], ...
    summary.n_different, n, summary.max_abs_mouth_delta_um, summary.max_abs_depth_delta_um);
if ~isempty(summary.different_idx)
    idx_show = summary.different_idx(1:min(12, numel(summary.different_idx)))';
    fprintf('    Differing cavity indices: %s\n', mat2str(idx_show));
end
end


function makeMethodDifferenceFigure(I_raw, imageName, outputDir, real_cavities, xy, summary)
fig = figure('Name', 'Cavity method differences', 'Position', [80 80 1250 950], 'Color', 'w');
I_rgb = repmat(I_raw, [1 1 3]);
imshow(I_rgb);
hold on;
h_high = plot(nan, nan, '-', 'Color', [0.95 0.20 0.80], 'LineWidth', 1.45);
h_plateau = plot(nan, nan, '-', 'Color', [0.10 0.95 0.95], 'LineWidth', 1.20);

title(sprintf('%s | method differences only (magenta=highest valid, cyan=plateau top)', imageName), ...
    'Interpreter', 'none', 'Color', 'w');
set(gca, 'Color', 'k');

if isempty(real_cavities) || summary.n_different == 0
    text(size(I_raw, 2) / 2, size(I_raw, 1) / 2, 'No method differences detected', ...
        'Color', 'w', 'FontSize', 16, 'HorizontalAlignment', 'center', ...
        'BackgroundColor', [0 0 0 0.55]);
    hold off;
    exportgraphics(fig, fullfile(outputDir, [imageName '_cavities_method_diff.png']), 'Resolution', 150);
    return;
end

for idx = summary.different_idx(:)'
    c = real_cavities(idx);

    mask_high = false(size(c.mask));
    mask_high(c.highest_valid_pixel_idx) = true;
    plotSmoothedMaskBoundaries(mask_high, [0.95 0.20 0.80], 1.45);

    mask_plateau = false(size(c.mask));
    mask_plateau(c.plateau_top_pixel_idx) = true;
    plotSmoothedMaskBoundaries(mask_plateau, [0.10 0.95 0.95], 1.20);

    r_px = c.mouth_equiv_radius_um / xy;
    th = linspace(0, 2*pi, 64);
    plot(c.centroid_px(1) + r_px * cos(th), c.centroid_px(2) + r_px * sin(th), ...
        ':', 'Color', [0.95 0.85 0.1], 'LineWidth', 0.7);
    plot(c.centroid_px(1), c.centroid_px(2), 'o', ...
        'MarkerSize', 5.5, 'MarkerFaceColor', [0.95 0.85 0.1], 'MarkerEdgeColor', 'k', 'LineWidth', 0.6);
    text(c.centroid_px(1), c.centroid_px(2) - 10, ...
        sprintf('%d | dz=%.2f', idx, abs(c.mouth_z_highest_valid_um - c.mouth_z_plateau_top_um)), ...
        'Color', 'w', 'FontSize', 7, 'HorizontalAlignment', 'center', ...
        'BackgroundColor', [0 0 0 0.45]);
end

legend([h_high, h_plateau], {'highest valid', 'plateau top'}, ...
    'TextColor', 'w', 'Color', [0 0 0], 'Location', 'southoutside');
hold off;
exportgraphics(fig, fullfile(outputDir, [imageName '_cavities_method_diff.png']), 'Resolution', 150);
end


function make3DCavityFigure(Z_smooth, imageName, outputDir, real_cavities, xy)
fig = figure('Name','3D surface + cavity cones', 'Position', [60 60 1200 850], 'Color', 'w');
ax = axes('Parent', fig);

ds = 4;
[imgH, imgW] = size(Z_smooth);
Zd = Z_smooth(1:ds:end, 1:ds:end);
[Xd, Yd] = meshgrid((1:ds:imgW) * xy, (1:ds:imgH) * xy);
surf(ax, Xd, Yd, Zd, 'EdgeColor', 'none', 'FaceColor', 'interp', 'FaceAlpha', 0.85);
colormap(ax, gray);
hold(ax, 'on');

if ~isempty(real_cavities)
    d = [real_cavities.depth_um];
    d = d(isfinite(d));
    [dlo, dhi] = safeColorLimits(d);
    cmap = parula(256);
    theta = linspace(0, 2*pi, 32);

    for k = 1:numel(real_cavities)
        c = real_cavities(k);
        t = max(0, min(1, (c.depth_um - dlo) / (dhi - dlo)));
        idx = max(1, min(256, 1 + round(t * 255)));
        col = cmap(idx, :);
        cx = c.centroid_px(1) * xy;
        cy = c.centroid_px(2) * xy;
        z0 = c.floor_z_um;
        z1 = c.mouth_z_um;
        r  = c.mouth_equiv_radius_um;
        bx = cx + r * cos(theta);
        by = cy + r * sin(theta);
        bz = repmat(z1, size(theta));

        for j = 1:4:numel(theta)
            plot3(ax, [cx bx(j)], [cy by(j)], [z0 bz(j)], '-', 'Color', col, 'LineWidth', 0.8);
        end
        plot3(ax, bx, by, bz, '-', 'Color', col, 'LineWidth', 1.1);
        plot3(ax, cx, cy, z0, 'o', 'MarkerSize', 4, 'MarkerFaceColor', col, 'MarkerEdgeColor', 'w');
    end
end

xlabel(ax, 'x (um)');
ylabel(ax, 'y (um)');
zlabel(ax, 'Height (um)');
title(ax, sprintf('%s | 3D surface + effective cavity cones', imageName), ...
    'Interpreter', 'none', 'FontSize', 10);
view(ax, -35, 35);
grid(ax, 'on');
lighting(ax, 'gouraud');
camlight(ax, 'headlight');
hold(ax, 'off');
exportgraphics(fig, fullfile(outputDir, [imageName '_3D_cones.png']), 'Resolution', 150);
end


function makeHistogramFigure(imageName, outputDir, real_cavities, min_depth_um)
fig = figure('Name','Cavity distributions', 'Position', [200 200 1100 750], 'Color', 'w');

if isempty(real_cavities)
    tiledlayout(1, 1);
    ax = nexttile;
    axis(ax, 'off');
    text(0.5, 0.5, 'No cavities passed the current depth threshold.', ...
        'HorizontalAlignment', 'center', 'FontSize', 12);
    exportgraphics(fig, fullfile(outputDir, [imageName '_cavity_hist.png']), 'Resolution', 150);
    return;
end

depths = [real_cavities.depth_um];
r_eq   = [real_cavities.mouth_equiv_radius_um];
beta   = [real_cavities.cone_half_angle_deg];
nsupp  = [real_cavities.n_supporting_triangles];

subplot(2,2,1);
histogram(depths, 30, 'FaceColor', [0.2 0.5 0.85], 'EdgeColor', 'none');
xline(mean(depths), 'r-', 'LineWidth', 1.4, 'Label', sprintf('%.2f um', mean(depths)));
xlabel('Depth (um)'); ylabel('Count'); title('Cavity depth'); grid on;

subplot(2,2,2);
histogram(r_eq, 30, 'FaceColor', [0.2 0.75 0.5], 'EdgeColor', 'none');
xline(mean(r_eq), 'r-', 'LineWidth', 1.4, 'Label', sprintf('%.2f um', mean(r_eq)));
xlabel('Equivalent mouth radius (um)'); ylabel('Count'); title('Mouth radius'); grid on;

subplot(2,2,3);
histogram(beta, 30, 'FaceColor', [0.85 0.5 0.2], 'EdgeColor', 'none');
xline(mean(beta), 'r-', 'LineWidth', 1.4, 'Label', sprintf('%.1f deg', mean(beta)));
xlabel('Cone half-angle (deg)'); ylabel('Count'); title('Cone half-angle'); grid on;

subplot(2,2,4);
histogram(nsupp, 'BinMethod', 'integers', 'FaceColor', [0.55 0.35 0.75], 'EdgeColor', 'none');
xlabel('Supporting triangles'); ylabel('Count'); title('Merged support count'); grid on;

sgtitle(sprintf('Cavity analysis - %s (depth threshold = %.1f um)', imageName, min_depth_um), ...
    'Interpreter', 'none');
exportgraphics(fig, fullfile(outputDir, [imageName '_cavity_hist.png']), 'Resolution', 150);
end


function writeCavityWorkbook(xlsx_path, imageName, real_cavities, shallow_cavities, min_depth_um)
if isempty(real_cavities)
    cav_table = table();
else
    tri_idx_text = cell(numel(real_cavities), 1);
    mound_idx_text = cell(numel(real_cavities), 1);
    for i = 1:numel(real_cavities)
        tri_idx_text{i} = char(joinNumericList(real_cavities(i).supporting_triangle_idx));
        mound_idx_text{i} = char(joinNumericList(real_cavities(i).bounding_mound_idx));
    end

    cav_table = table( ...
        (1:numel(real_cavities))', ...
        columnField(real_cavities, 'centroid_px', 1), ...
        columnField(real_cavities, 'centroid_px', 2), ...
        columnField(real_cavities, 'depth_um'), ...
        columnField(real_cavities, 'floor_z_um'), ...
        columnField(real_cavities, 'mouth_z_um'), ...
        columnField(real_cavities, 'mouth_area_um2'), ...
        columnField(real_cavities, 'mouth_equiv_radius_um'), ...
        columnField(real_cavities, 'mouth_equiv_diameter_um'), ...
        columnField(real_cavities, 'mouth_inscribed_radius_um'), ...
        columnField(real_cavities, 'cone_half_angle_deg'), ...
        columnField(real_cavities, 'cone_fit_rmse_um'), ...
        columnField(real_cavities, 'persistence_um'), ...
        columnField(real_cavities, 'independent_relief_um'), ...
        columnField(real_cavities, 'n_supporting_triangles'), ...
        tri_idx_text, ...
        mound_idx_text, ...
        columnField(real_cavities, 'n_raw_minima'), ...
        columnField(real_cavities, 'n_surviving_minima_in_group'), ...
        columnField(real_cavities, 'mouth_z_highest_valid_um'), ...
        columnField(real_cavities, 'mouth_area_highest_valid_um2'), ...
        columnField(real_cavities, 'depth_highest_valid_um'), ...
        columnField(real_cavities, 'cone_half_angle_highest_valid_deg'), ...
        columnField(real_cavities, 'mouth_z_plateau_top_um'), ...
        columnField(real_cavities, 'mouth_area_plateau_top_um2'), ...
        columnField(real_cavities, 'depth_plateau_top_um'), ...
        columnField(real_cavities, 'cone_half_angle_plateau_top_deg'), ...
        string({real_cavities.cavity_support_type})', ...
        string({real_cavities.cavity_enclosure_type})', ...
        string({real_cavities.cavity_quality_flag})', ...
        double([real_cavities.is_inpainted])', ...
        'VariableNames', { ...
            'CavityIndex', 'X_px', 'Y_px', 'Depth_um', 'FloorZ_um', 'MouthZ_um', ...
            'MouthArea_um2', 'MouthEquivRadius_um', 'MouthEquivDiameter_um', ...
            'MouthInscribedRadius_um', 'ConeHalfAngle_deg', 'ConeFitRmse_um', ...
            'Persistence_um', 'IndependentRelief_um', 'NSupportingTriangles', 'SupportingTriangleIdx', ...
            'BoundingMoundIdx', 'NRawMinima', 'NSurvivingMinimaInGroup', ...
            'MouthZ_HighestValid_um', 'MouthArea_HighestValid_um2', 'Depth_HighestValid_um', 'ConeHalfAngle_HighestValid_deg', ...
            'MouthZ_PlateauTop_um', 'MouthArea_PlateauTop_um2', 'Depth_PlateauTop_um', 'ConeHalfAngle_PlateauTop_deg', ...
            'SupportType', 'EnclosureType', 'QualityFlag', ...
            'DepthModelEstimated'});
end
writetable(cav_table, xlsx_path, 'Sheet', 'Cavities');

if isempty(shallow_cavities)
    shallow_table = table();
else
    shallow_table = table( ...
        (1:numel(shallow_cavities))', ...
        columnField(shallow_cavities, 'centroid_px', 1), ...
        columnField(shallow_cavities, 'centroid_px', 2), ...
        columnField(shallow_cavities, 'depth_um'), ...
        columnField(shallow_cavities, 'persistence_um'), ...
        string({shallow_cavities.cavity_enclosure_type})', ...
        'VariableNames', {'CandidateIndex','X_px','Y_px','Depth_um','Persistence_um','EnclosureType'});
end
writetable(shallow_table, xlsx_path, 'Sheet', 'Shallow_or_rejected');

method_diff_count = 0;
method_max_abs_depth_delta = 0;
method_max_abs_mouth_delta = 0;
if ~isempty(real_cavities)
    mouth_delta = abs(columnField(real_cavities, 'mouth_z_highest_valid_um') - columnField(real_cavities, 'mouth_z_plateau_top_um'));
    depth_delta = abs(columnField(real_cavities, 'depth_highest_valid_um') - columnField(real_cavities, 'depth_plateau_top_um'));
    method_diff_count = nnz(mouth_delta > 1e-9 | depth_delta > 1e-9);
    method_max_abs_depth_delta = max(depth_delta);
    method_max_abs_mouth_delta = max(mouth_delta);
end

summary = table( ...
    {imageName}, numel(real_cavities), numel(shallow_cavities), min_depth_um, ...
    meanOrNan(real_cavities, 'depth_um'), stdOrNan(real_cavities, 'depth_um'), medianOrNan(real_cavities, 'depth_um'), ...
    meanOrNan(real_cavities, 'mouth_equiv_radius_um'), stdOrNan(real_cavities, 'mouth_equiv_radius_um'), medianOrNan(real_cavities, 'mouth_equiv_radius_um'), ...
    meanOrNan(real_cavities, 'cone_half_angle_deg'), stdOrNan(real_cavities, 'cone_half_angle_deg'), ...
    meanOrNan(real_cavities, 'persistence_um'), method_diff_count, method_max_abs_mouth_delta, method_max_abs_depth_delta, ...
    'VariableNames', { ...
        'ImageName', 'N_cavities', 'N_shallow', 'DepthThreshold_um', ...
        'Mean_depth_um', 'Std_depth_um', 'Median_depth_um', ...
        'Mean_mouthEquivRadius_um', 'Std_mouthEquivRadius_um', 'Median_mouthEquivRadius_um', ...
        'Mean_beta_deg', 'Std_beta_deg', 'Mean_persistence_um', ...
        'MethodDiffCount', 'MethodMaxAbsMouthDelta_um', 'MethodMaxAbsDepthDelta_um'});
writetable(summary, xlsx_path, 'Sheet', 'Summary');
end


function [cavResults, mat_path] = assembleOutputStruct( ...
    m1, imageName, min_depth_um, real_cavities, shallow_cavities, cavity_label, tri_support_label, Z_smooth, smooth_sigma, spacing_px, outputDir, method_compare)

if nargin < 11 || isempty(outputDir)
    outputDir = fileparts(m1.imagePath);
end
if isempty(outputDir), outputDir = pwd; end
mat_path = fullfile(outputDir, [imageName '_cavities.mat']);

cavResults.n_cavities = numel(real_cavities);
cavResults.n_shallow = numel(shallow_cavities);
cavResults.min_depth_um = min_depth_um;
cavResults.depth_um = columnField(real_cavities, 'depth_um');
cavResults.floor_z_um = columnField(real_cavities, 'floor_z_um');
cavResults.valley_z_um = cavResults.floor_z_um;
cavResults.mouth_z_um = columnField(real_cavities, 'mouth_z_um');
cavResults.mouth_area_um2 = columnField(real_cavities, 'mouth_area_um2');
cavResults.mouth_equiv_radius_um = columnField(real_cavities, 'mouth_equiv_radius_um');
cavResults.mouth_equiv_diameter_um = columnField(real_cavities, 'mouth_equiv_diameter_um');
cavResults.mouth_inscribed_radius_um = columnField(real_cavities, 'mouth_inscribed_radius_um');
cavResults.r_mouth_um = cavResults.mouth_equiv_radius_um;
cavResults.cone_half_angle_deg = columnField(real_cavities, 'cone_half_angle_deg');
cavResults.beta_deg = cavResults.cone_half_angle_deg;
cavResults.cone_fit_rmse_um = columnField(real_cavities, 'cone_fit_rmse_um');
cavResults.persistence_um = columnField(real_cavities, 'persistence_um');
cavResults.independent_relief_um = columnField(real_cavities, 'independent_relief_um');
cavResults.n_supporting_triangles = columnField(real_cavities, 'n_supporting_triangles');
cavResults.supporting_triangle_idx = {real_cavities.supporting_triangle_idx}';
cavResults.bounding_mound_idx = {real_cavities.bounding_mound_idx}';
cavResults.n_bounding_mounds = cellfun(@numel, cavResults.bounding_mound_idx);
cavResults.cavity_support_type = string({real_cavities.cavity_support_type})';
cavResults.cavity_enclosure_type = string({real_cavities.cavity_enclosure_type})';
cavResults.cavity_quality_flag = string({real_cavities.cavity_quality_flag})';
cavResults.n_raw_minima = columnField(real_cavities, 'n_raw_minima');
cavResults.n_surviving_minima_in_group = columnField(real_cavities, 'n_surviving_minima_in_group');
cavResults.minimum_saddle_um = columnField(real_cavities, 'minimum_saddle_um');
cavResults.mouth_z_highest_valid_um = columnField(real_cavities, 'mouth_z_highest_valid_um');
cavResults.mouth_area_highest_valid_um2 = columnField(real_cavities, 'mouth_area_highest_valid_um2');
cavResults.mouth_equiv_radius_highest_valid_um = columnField(real_cavities, 'mouth_equiv_radius_highest_valid_um');
cavResults.mouth_equiv_diameter_highest_valid_um = columnField(real_cavities, 'mouth_equiv_diameter_highest_valid_um');
cavResults.mouth_inscribed_radius_highest_valid_um = columnField(real_cavities, 'mouth_inscribed_radius_highest_valid_um');
cavResults.depth_highest_valid_um = columnField(real_cavities, 'depth_highest_valid_um');
cavResults.cone_half_angle_highest_valid_deg = columnField(real_cavities, 'cone_half_angle_highest_valid_deg');
cavResults.mouth_z_plateau_top_um = columnField(real_cavities, 'mouth_z_plateau_top_um');
cavResults.mouth_area_plateau_top_um2 = columnField(real_cavities, 'mouth_area_plateau_top_um2');
cavResults.mouth_equiv_radius_plateau_top_um = columnField(real_cavities, 'mouth_equiv_radius_plateau_top_um');
cavResults.mouth_equiv_diameter_plateau_top_um = columnField(real_cavities, 'mouth_equiv_diameter_plateau_top_um');
cavResults.mouth_inscribed_radius_plateau_top_um = columnField(real_cavities, 'mouth_inscribed_radius_plateau_top_um');
cavResults.depth_plateau_top_um = columnField(real_cavities, 'depth_plateau_top_um');
cavResults.cone_half_angle_plateau_top_deg = columnField(real_cavities, 'cone_half_angle_plateau_top_deg');
if isempty(real_cavities)
    cavResults.centroid_px = zeros(0, 2);
    cavResults.floor_px = zeros(0, 2);
    cavResults.raw_minimum_px = zeros(0, 2);
else
    cavResults.centroid_px = vertcat(real_cavities.centroid_px);
    cavResults.floor_px = vertcat(real_cavities.floor_px);
    cavResults.raw_minimum_px = vertcat(real_cavities.raw_minimum_px);
end
cavResults.is_inpainted = logical([real_cavities.is_inpainted])';
cavResults.contour_level_history_um = {real_cavities.contour_level_history_um}';
cavResults.contour_area_history_px = {real_cavities.contour_area_history_px}';
cavResults.contour_candidate_flag = {real_cavities.contour_candidate_flag}';
cavResults.contour_admissible_flag = {real_cavities.contour_admissible_flag}';
cavResults.method_compare_n_different = method_compare.n_different;
cavResults.method_compare_fraction_different = method_compare.fraction_different;
cavResults.method_compare_different_idx = method_compare.different_idx;
cavResults.method_compare_abs_mouth_delta_um = method_compare.abs_mouth_delta_um;
cavResults.method_compare_abs_depth_delta_um = method_compare.abs_depth_delta_um;
cavResults.method_compare_max_abs_mouth_delta_um = method_compare.max_abs_mouth_delta_um;
cavResults.method_compare_median_abs_mouth_delta_um = method_compare.median_abs_mouth_delta_um;
cavResults.method_compare_max_abs_depth_delta_um = method_compare.max_abs_depth_delta_um;
cavResults.method_compare_median_abs_depth_delta_um = method_compare.median_abs_depth_delta_um;
cavResults.cavity_label = cavity_label;
cavResults.basin_label = cavity_label;
cavResults.triangle_support_label = tri_support_label;
cavResults.Z_smooth = Z_smooth;
cavResults.cavity_smooth_sigma_px = smooth_sigma;
cavResults.cavity_spacing_px = spacing_px;
cavResults.cavity_smooth_sigma_over_spacing = smooth_sigma / max(spacing_px, eps);
cavResults.imageName = imageName;
cavResults.imagePath = m1.imagePath;
cavResults.m1 = m1;
end


function [seed_centroids, seed_to_original_idx, added_edge_seed_centroids, mode] = buildAugmentedCavitySeedCentroids(m1, original_centroids)
seed_centroids = original_centroids;
seed_to_original_idx = (1:size(original_centroids, 1))';
added_edge_seed_centroids = zeros(0, 2);
mode = 'original centroids';

[all_centroids, ok, ~] = detectBorderInclusiveCentroidsLocal(m1);
if ~ok || isempty(all_centroids) || isempty(original_centroids)
    return;
end

idx_near = knnsearch(original_centroids, all_centroids);
d_near = sqrt(sum((all_centroids - original_centroids(idx_near, :)) .^ 2, 2));
added_mask = d_near > 1.5;
added_edge_seed_centroids = all_centroids(added_mask, :);
if isempty(added_edge_seed_centroids)
    return;
end

seed_centroids = [original_centroids; added_edge_seed_centroids];
seed_to_original_idx = [(1:size(original_centroids, 1))'; zeros(size(added_edge_seed_centroids, 1), 1)];
mode = 'border-inclusive augmented centroids';
end


function [centroids_all, ok, reason] = detectBorderInclusiveCentroidsLocal(m1)
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
mask = double(applyDetectionContrastLocal(Iblur, char(p.contrastMethod), double(p.clipLimit)));
Iobrcbr = preprocessDetectionImageLocal(mask, double(p.openRadius));
fgm4 = extractDetectionRegionalMaximaLocal(Iobrcbr, dilateRadius, minObjectArea, ...
    fillDeepPits, Iblur, fillThreshold);

stats = regionprops(logical(fgm4), 'Centroid');
if isempty(stats)
    centroids_all = zeros(0, 2);
else
    centroids_all = double(cat(1, stats.Centroid));
end
ok = true;
end


function spacing_px = computeCavityRepresentativeSpacingPx(m1, fallbackSpacing)
spacing_px = double(fallbackSpacing);
if isfield(m1, 'nn_dist_px')
    valid = double(m1.nn_dist_px(:));
    valid = valid(isfinite(valid) & valid > 0);
    if ~isempty(valid)
        spacing_px = median(valid);
    end
end
if ~isfinite(spacing_px) || spacing_px <= 0
    spacing_px = max(1, double(fallbackSpacing));
end
end


function smooth_sigma = selectCavitySmoothingSigmaPx(spacing_px)
smooth_sigma = max(0.8, min(12, 0.08 * double(spacing_px)));
smooth_sigma = round(smooth_sigma, 2);
end


function mask = applyDetectionContrastLocal(I, method, clipLimit)
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


function Iobrcbr = preprocessDetectionImageLocal(mask, radius)
se = strel('disk', radius);
Ie = imerode(mask, se);
Iobr = imreconstruct(Ie, mask);
Iobrd = imdilate(Iobr, se);
Iobrcbr = imreconstruct(imcomplement(Iobrd), imcomplement(Iobr));
Iobrcbr = imcomplement(Iobrcbr);
end


function fgm4 = extractDetectionRegionalMaximaLocal(Iobrcbr, dilateRadius, minArea, fillDeepPits, Iblur, fillThreshold)
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


function [mask, mode] = buildCentroidHullMask(centroids, imgH, imgW, padPx)
pts = unique(centroids, 'rows', 'stable');
padPx = max(2, ceil(max(1, padPx)));

if isempty(pts)
    mask = true(imgH, imgW);
    mode = 'full image fallback (no centroids)';
    return;
end

if size(pts, 1) >= 3 && pointSetSpansArea(pts)
    try
        K = convhull(pts(:,1), pts(:,2));
        hull_poly = pts(K, :);
        mask = poly2mask(hull_poly(:,1), hull_poly(:,2), imgH, imgW);
        mode = 'convex hull';
        return;
    catch
    end
end

xMin = max(1, floor(min(pts(:,1)) - padPx));
xMax = min(imgW, ceil(max(pts(:,1)) + padPx));
yMin = max(1, floor(min(pts(:,2)) - padPx));
yMax = min(imgH, ceil(max(pts(:,2)) + padPx));

mask = false(imgH, imgW);
mask(yMin:yMax, xMin:xMax) = true;
mode = 'padded bounding-box fallback';
end


function tf = pointSetSpansArea(pts)
if size(pts, 1) < 3
    tf = false;
    return;
end
pts0 = pts - mean(pts, 1);
tf = rank(pts0, 1e-9) >= 2;
end


function mask = buildLocalDiskMask(imgH, imgW, row0, col0, radius_px)
[X, Y] = meshgrid(1:imgW, 1:imgH);
mask = (X - col0).^2 + (Y - row0).^2 <= radius_px^2;
end


function v = columnField(S, fieldName, colIdx)
if nargin < 3
    colIdx = [];
end
if isempty(S)
    v = zeros(0, 1);
    return;
end
if isempty(colIdx)
    vals = {S.(fieldName)};
    if isnumeric(vals{1}) && isscalar(vals{1})
        v = reshape(cell2mat(vals), [], 1);
    else
        v = vals;
    end
else
    vals = vertcat(S.(fieldName));
    v = vals(:, colIdx);
end
end


function zmax = sampleBridgeMax(Z, pt1, pt2)
n = max(2, ceil(hypot(pt1(1) - pt2(1), pt1(2) - pt2(2))));
xs = round(linspace(pt1(1), pt2(1), n));
ys = round(linspace(pt1(2), pt2(2), n));
xs = max(1, min(size(Z, 2), xs));
ys = max(1, min(size(Z, 1), ys));
idx = sub2ind(size(Z), ys, xs);
zmax = max(Z(idx));
end


function rpx = maxDistanceInsideMask(mask)
if ~any(mask(:))
    rpx = 0;
    return;
end
D = bwdist(~mask);
rpx = max(D(mask));
end


function plotSmoothedMaskBoundaries(mask, color_rgb, line_width)
if ~any(mask(:))
    return;
end
mask_s = imgaussfilt(double(mask), 0.8);
C = contourc(mask_s, [0.5 0.5]);
idx = 1;
while idx < size(C, 2)
    n_pts = C(2, idx);
    pts = C(:, idx+1:idx+n_pts);
    xy_pts = smoothClosedCurve(pts');
    plot(xy_pts(:,1), xy_pts(:,2), '-', 'Color', color_rgb, 'LineWidth', line_width);
    idx = idx + n_pts + 1;
end
end


function xy_out = smoothClosedCurve(xy_in)
if size(xy_in, 1) < 5
    xy_out = xy_in;
    return;
end
w = 7;
pad = floor(w / 2);
xy_pad = [xy_in(end-pad+1:end, :); xy_in; xy_in(1:pad, :)];
kernel = ones(w, 1) / w;
x_s = conv(xy_pad(:,1), kernel, 'same');
y_s = conv(xy_pad(:,2), kernel, 'same');
xy_out = [x_s(pad+1:end-pad), y_s(pad+1:end-pad)];
end


function rmse = estimateConeFitRmse(Z_raw, mouth_mask, min_r, min_c, floor_z, mouth_z, r_eq_um, xy)
pts = mouth_mask & Z_raw >= floor_z & Z_raw <= mouth_z;
if nnz(pts) < 12 || r_eq_um <= 0 || mouth_z <= floor_z
    rmse = NaN;
    return;
end

[rows, cols] = find(pts);
r_um = hypot((cols - min_c) * xy, (rows - min_r) * xy);
z_pred = floor_z + (mouth_z - floor_z) * min(r_um / max(r_eq_um, eps), 1);
z_obs = Z_raw(pts);
rmse = sqrt(mean((z_obs - z_pred) .^ 2));
end


function out = classifySupportType(n_tri)
if n_tri <= 1
    out = "single_triangle";
elseif n_tri == 2
    out = "merged_two_triangle";
else
    out = "merged_multi_triangle";
end
end


function out = classifyEnclosureType(n_mounds, contact_fraction)
if n_mounds >= 3 && contact_fraction <= 0.20
    out = "enclosed";
elseif n_mounds >= 3 && contact_fraction <= 0.50
    out = "semi_enclosed";
else
    out = "open_trough_like";
end
end


function out = classifyQualityFlag(depth_um, r_eq_um, r_inscribed_um, contact_fraction, cone_rmse_um, is_inpainted)
flags = strings(0, 1);
if is_inpainted
    flags(end+1) = "reflection_affected";
end
if r_eq_um > 0 && r_inscribed_um / r_eq_um < 0.60
    flags(end+1) = "irregular_mouth";
end
if contact_fraction > 0.60
    flags(end+1) = "open_geometry";
end
if isfinite(cone_rmse_um) && depth_um > 0 && cone_rmse_um > max(0.5, 0.35 * depth_um)
    flags(end+1) = "poor_cone_fit";
end
if isempty(flags)
    out = "good";
else
    out = string(strjoin(cellstr(flags), '|'));
end
end


function txt = joinNumericList(v)
if isempty(v)
    txt = "";
else
    txt = strjoin(string(v), ',');
end
end


function out = meanOrNan(S, fieldName)
if isempty(S)
    out = NaN;
else
    out = mean(columnField(S, fieldName), 'omitnan');
end
end


function out = stdOrNan(S, fieldName)
if isempty(S)
    out = NaN;
else
    out = std(columnField(S, fieldName), 'omitnan');
end
end


function out = medianOrNan(S, fieldName)
if isempty(S)
    out = NaN;
else
    out = median(columnField(S, fieldName), 'omitnan');
end
end


function [lo, hi] = safeColorLimits(v)
v = v(isfinite(v));
if isempty(v)
    lo = 0;
    hi = 1;
    return;
end
if isscalar(v)
    lo = v - max(abs(v) * 0.01, 1e-6);
    hi = v + max(abs(v) * 0.01, 1e-6);
    return;
end
lo = prctile(v, 5);
hi = prctile(v, 95);
if ~isfinite(lo) || ~isfinite(hi)
    lo = min(v);
    hi = max(v);
end
if hi <= lo
    pad = max(max(abs(v)) * 0.01, 1e-6);
    lo = lo - pad;
    hi = hi + pad;
end
end


function out = ternary(tf, a, b)
if tf
    out = a;
else
    out = b;
end
end
