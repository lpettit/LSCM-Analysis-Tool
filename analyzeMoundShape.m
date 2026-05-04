function moundResults = analyzeMoundShape(m1, varargin)
% =========================================================================
%  analyzeMoundShape  -  Module 3: Per-mound shape and roughness analysis
%
%  Preferred reporting uses Method B (nearest-neighbour-radius circle) for
%  valley-dependent quantities, watershed-contained peaks for direct mound
%  height, and watershed-restricted raw half-max footprints for per-mound
%  shape geometry.
%
%  USAGE:
%    moundResults = analyzeMoundShape(m1)
%    moundResults = analyzeMoundShape(m1, 'output_folder')
%
%  INPUTS:
%    m1           - results struct from analyzeMounds (Module 1)
%    outputDir    - folder to save outputs; default = same folder as image
%
%  OUTPUT HIGHLIGHTS:
%    Rp_global, Rv_global, Rz_global
%    Rz_per_mound             - preferred per-mound roughness (Method B)
%    preferred_Rz_per_mound   - same preferred per-mound roughness
%    mound_base_position_um   - preferred mound-base position from Method C
%    mound_height_um          - preferred mound height from watershed peak + Method C base position
%    footprint_um2            - preferred watershed-restricted raw half-max footprint area
%    equiv_diam_um            - preferred watershed-restricted raw equivalent diameter
%    preferred_aspect_ratio   - preferred height-to-diameter aspect ratio
%    feret_max_um, feret_min_um, feret_aspect_ratio, feret_orientation_deg
%    perimeter_um, circularity, solidity, convexity, convex_area_ratio,
%    extent, major_axis_um, minor_axis_um
%
%  REQUIRES: Image Processing Toolbox, Statistics and Machine Learning
%            Toolbox (knnsearch)
% =========================================================================

[imageFolder, imageName, ~] = fileparts(m1.imagePath);
if nargin < 2 || isempty(varargin{1})
    outputDir = imageFolder;
elseif nargin >= 4
    outputDir = varargin{3};
else
    outputDir = varargin{1};
end
if isempty(outputDir), outputDir = pwd; end
if ~exist(outputDir, 'dir'), mkdir(outputDir); end

fprintf('analyzeMoundShape: %s\n', imageName);

Z_raw        = m1.Z;
centroids    = m1.centroids;
n_total      = size(centroids, 1);
xy           = m1.xy_um_per_px;
nn_mean_px   = m1.nn_mean_px;
I_rgb        = repmat(m1.I_raw, [1 1 3]);
[imgH, imgW] = size(Z_raw);
METHOD_C_BASE_BAND_WIDTH_PX = 2;

D_nn = computeNearestNeighborDistances(centroids, nn_mean_px);
spacing_px = computeRepresentativeSpacingPx(D_nn, nn_mean_px);

refPlane_um = mean(Z_raw(:));
Rp_global   = max(Z_raw(:)) - refPlane_um;
Rv_global   = refPlane_um   - min(Z_raw(:));
Rz_global   = Rp_global + Rv_global;

fprintf('  Reference plane  : %.2f µm (= mean Z_raw)\n', refPlane_um);
fprintf('  Rp (global)      : %.2f µm\n', Rp_global);
fprintf('  Rv (global)      : %.2f µm\n', Rv_global);
fprintf('  Rz (global)      : %.2f µm\n', Rz_global);

fprintf('  Building centroid-seeded watershed partition...\n');
[watershed_seed_centroids, added_edge_seed_centroids, aug_ok, aug_reason] = buildAugmentedWatershedSeeds(m1, centroids);
if ~aug_ok
    fprintf('  Augmented edge seeds unavailable (%s); using original centroids only.\n', aug_reason);
    watershed_seed_centroids = centroids;
    added_edge_seed_centroids = zeros(0, 2);
end
watershed_selection = selectWatershedSmoothing(Z_raw, watershed_seed_centroids, centroids, spacing_px);
smooth_sigma = watershed_selection.best_sigma_px;
Z_smooth = watershed_selection.Z_smooth;
watershed_L = watershed_selection.watershed_L;
fprintf('  Height map smoothed (selected sigma=%.2f px from spacing %.2f px)\n', ...
    smooth_sigma, spacing_px);
fprintf('  Watershed sigma candidates: %s\n', mat2str(watershed_selection.candidate_sigmas_px, 3));
fprintf('  Selected watershed score: %.3f\n', watershed_selection.best_score);
fprintf('  Watershed partition complete\n');
[X_full, Y_full] = meshgrid(1:imgW, 1:imgH);
bbox_r = ceil(max(D_nn) * 1.10) + 4;

peak_z_um            = nan(n_total, 1);
centroid_peak_z_um   = nan(n_total, 1);
centroid_peak_Rp_um  = nan(n_total, 1);
Rp_per_mound         = nan(n_total, 1);
watershed_peak_z_um  = nan(n_total, 1);
watershed_peak_rowcol_px = nan(n_total, 2);
watershed_peak_Rp_um = nan(n_total, 1);
Rp_vs_watershed_peak_diff_um = nan(n_total, 1);

valley_z_nn_um       = nan(n_total, 1);
mound_height_nn_um   = nan(n_total, 1);
nn_radius_px         = nan(n_total, 1);
Rv_nn_per_mound      = nan(n_total, 1);
Rz_b_per_mound       = nan(n_total, 1);
valid_flag_nn        = false(n_total, 1);
skip_reason_nn       = repmat({''}, n_total, 1);

valley_z_c_um        = nan(n_total, 1);
mound_base_position_um = nan(n_total, 1);
mound_height_c_um    = nan(n_total, 1);
Rv_c_per_mound       = nan(n_total, 1);
Rz_c_per_mound       = nan(n_total, 1);
valid_flag_c         = false(n_total, 1);
skip_reason_c        = repmat({''}, n_total, 1);

footprint_ws_um2         = nan(n_total, 1);
equiv_diam_ws_um         = nan(n_total, 1);
aspect_ratio_ws          = nan(n_total, 1);
perimeter_ws_um          = nan(n_total, 1);
circularity_ws           = nan(n_total, 1);
solidity_ws              = nan(n_total, 1);
convexity_ws             = nan(n_total, 1);
convex_area_ratio_ws     = nan(n_total, 1);
extent_ws                = nan(n_total, 1);
major_axis_ws_um         = nan(n_total, 1);
minor_axis_ws_um         = nan(n_total, 1);
feret_max_ws_um          = nan(n_total, 1);
feret_min_ws_um          = nan(n_total, 1);
feret_aspect_ratio_ws    = nan(n_total, 1);
feret_orientation_ws_deg = nan(n_total, 1);
valid_flag_ws            = false(n_total, 1);

circle_mask_store    = cell(n_total, 1);
base_band_store      = cell(n_total, 1);
footprint_mask_store = cell(n_total, 1);
crop_boxes           = nan(n_total, 4);
valley_px_b          = nan(n_total, 2);
boundary_band_boxes  = nan(n_total, 4);
base_band_label_img  = zeros(imgH, imgW);
watershed_border_mask_img = false(imgH, imgW);

fprintf('  Computing per-mound geometry (%d mounds)...\n', n_total);

for k = 1:n_total
    cx = centroids(k, 1);
    cy = centroids(k, 2);

    r_c = max(1, min(imgH, round(cy)));
    c_c = max(1, min(imgW, round(cx)));
    peak_win = 2;
    r_p1 = max(1, r_c - peak_win); r_p2 = min(imgH, r_c + peak_win);
    c_p1 = max(1, c_c - peak_win); c_p2 = min(imgW, c_c + peak_win);
    centroid_peak_z_um(k) = max(max(Z_raw(r_p1:r_p2, c_p1:c_p2)));
    centroid_peak_Rp_um(k) = centroid_peak_z_um(k) - refPlane_um;

    r1 = max(1, r_c - bbox_r); r2 = min(imgH, r_c + bbox_r);
    c1 = max(1, c_c - bbox_r); c2 = min(imgW, c_c + bbox_r);
    crop_boxes(k, :) = [r1 r2 c1 c2];

    watershed_loc = watershed_L(r1:r2, c1:c2);
    Z_loc_raw   = Z_raw(r1:r2, c1:c2);

    r_nn_k = D_nn(k);
    nn_radius_px(k) = r_nn_k;

    r1_nn = max(1, r_c - ceil(r_nn_k) - 1);
    r2_nn = min(imgH, r_c + ceil(r_nn_k) + 1);
    c1_nn = max(1, c_c - ceil(r_nn_k) - 1);
    c2_nn = min(imgW, c_c + ceil(r_nn_k) + 1);

    X_nn = X_full(r1_nn:r2_nn, c1_nn:c2_nn);
    Y_nn = Y_full(r1_nn:r2_nn, c1_nn:c2_nn);
    D_nn_loc = sqrt((X_nn - cx).^2 + (Y_nn - cy).^2);
    circle_px = (D_nn_loc <= r_nn_k);
    circle_mask_store{k} = false(size(watershed_loc));
    circle_mask_store{k}((r1_nn:r2_nn) - r1 + 1, (c1_nn:c2_nn) - c1 + 1) = circle_px;

    if sum(circle_px(:)) < 5
        skip_reason_nn{k} = sprintf('too few circle pixels (%d)', sum(circle_px(:)));
        continue;
    end

    Z_circle_raw = Z_raw(r1_nn:r2_nn, c1_nn:c2_nn);
    [valley_z_nn_um(k), idx_min_b] = min(Z_circle_raw(circle_px));
    [rows_k, cols_k] = find(watershed_L == k);
    if isempty(rows_k)
        skip_reason_c{k} = 'empty watershed region';
        continue;
    end
    r1_c = max(1, min(rows_k) - 1); r2_c = min(imgH, max(rows_k) + 1);
    c1_c = max(1, min(cols_k) - 1); c2_c = min(imgW, max(cols_k) + 1);
    boundary_band_boxes(k, :) = [r1_c r2_c c1_c c2_c];
    watershed_loc_c = watershed_L(r1_c:r2_c, c1_c:c2_c);
    region_c = (watershed_loc_c == k);
    boundary_c = getRegionWatershedBorderMask(watershed_loc_c, k);
    watershed_border_mask_img(r1_c:r2_c, c1_c:c2_c) = watershed_border_mask_img(r1_c:r2_c, c1_c:c2_c) | boundary_c;
    centroid_loc_xy = [cx - c1_c + 1, cy - r1_c + 1];
    [base_band_mask, base_samples_um] = buildMethodCBaseBand(region_c, boundary_c, Z_raw(r1_c:r2_c, c1_c:c2_c), centroid_loc_xy);
    base_band_store{k} = base_band_mask;
    [watershed_peak_z_um(k), watershed_peak_rowcol_px(k, :)] = findRegionPeakPixel(region_c, Z_raw(r1_c:r2_c, c1_c:c2_c), r1_c, c1_c);
    watershed_peak_Rp_um(k) = watershed_peak_z_um(k) - refPlane_um;
    peak_z_um(k) = watershed_peak_z_um(k);
    Rp_per_mound(k) = watershed_peak_Rp_um(k);
    Rp_vs_watershed_peak_diff_um(k) = centroid_peak_Rp_um(k) - watershed_peak_Rp_um(k);
    if ~isfinite(peak_z_um(k)) || ~isfinite(Rp_per_mound(k))
        skip_reason_nn{k} = 'invalid watershed peak';
        skip_reason_c{k} = 'invalid watershed peak';
        continue;
    end

    mound_height_nn_um(k) = peak_z_um(k) - valley_z_nn_um(k);
    if mound_height_nn_um(k) <= 0
        skip_reason_nn{k} = 'NN circle: watershed peak not above valley';
        continue;
    end

    Rv_nn_per_mound(k) = refPlane_um - valley_z_nn_um(k);
    Rz_b_per_mound(k) = Rp_per_mound(k) + Rv_nn_per_mound(k);
    valley_px_b(k, :) = findMaskPixel(circle_px, idx_min_b, r1_nn, c1_nn);
    valid_flag_nn(k) = true;
    if numel(base_samples_um) < 5
        skip_reason_c{k} = sprintf('too few base-band samples (%d)', numel(base_samples_um));
    else
        valley_z_c_um(k) = mean(base_samples_um, 'omitnan');
        mound_base_position_um(k) = refPlane_um - valley_z_c_um(k);
        mound_height_c_um(k) = watershed_peak_Rp_um(k) + mound_base_position_um(k);
        if mound_height_c_um(k) > 0 && isfinite(valley_z_c_um(k))
            Rv_c_per_mound(k) = mound_base_position_um(k);
            Rz_c_per_mound(k) = watershed_peak_Rp_um(k) + Rv_c_per_mound(k);
            valid_flag_c(k) = true;
            base_band_label_img(r1_c:r2_c, c1_c:c2_c) = max(base_band_label_img(r1_c:r2_c, c1_c:c2_c), double(base_band_mask) * k);
        else
            skip_reason_c{k} = 'Method C base estimate not below peak';
        end
    end

    z_halfmax_raw = valley_z_nn_um(k) + 0.5 * mound_height_nn_um(k);
    halfmax_mask = (watershed_loc == k) & (Z_loc_raw >= z_halfmax_raw);
    component_mask = extractCentroidComponent(halfmax_mask, r_c - r1 + 1, c_c - c1 + 1);
    if ~any(component_mask(:))
        skip_reason_nn{k} = 'no watershed half-max component near centroid';
        continue;
    end

    footprint_mask_store{k} = component_mask;
    stats_ws = regionprops(component_mask, 'Area', 'Perimeter', 'Solidity', ...
        'Extent', 'MajorAxisLength', 'MinorAxisLength', 'ConvexArea');
    if isempty(stats_ws)
        skip_reason_nn{k} = 'empty watershed footprint stats';
        continue;
    end
    fp_ws = stats_ws(1);
    if fp_ws.Area < 5 || fp_ws.Perimeter <= 0 || fp_ws.ConvexArea <= 0
        skip_reason_nn{k} = sprintf('degenerate watershed footprint (area=%.1f, perimeter=%.3g)', ...
            fp_ws.Area, fp_ws.Perimeter);
        continue;
    end
    [feret_max_ws_um(k), feret_min_ws_um(k), feret_orientation_ws_deg(k), ...
        feret_aspect_ratio_ws(k), convex_perimeter_ws_um] = computeFeretMetrics(component_mask, xy);
    if ~isfinite(feret_max_ws_um(k)) || ~isfinite(feret_min_ws_um(k)) || ...
            feret_max_ws_um(k) <= 0 || feret_min_ws_um(k) <= 0 || ...
            ~isfinite(convex_perimeter_ws_um) || convex_perimeter_ws_um <= 0
        skip_reason_nn{k} = 'invalid Feret geometry for watershed footprint';
        continue;
    end

    footprint_ws_um2(k)      = fp_ws.Area * xy^2;
    equiv_diam_ws_um(k)      = 2 * sqrt(footprint_ws_um2(k) / pi);
    aspect_ratio_ws(k)       = mound_height_c_um(k) / max(equiv_diam_ws_um(k), eps);
    perimeter_ws_um(k)       = fp_ws.Perimeter * xy;
    circularity_ws(k)        = 4 * pi * fp_ws.Area / (fp_ws.Perimeter^2);
    solidity_ws(k)           = fp_ws.Solidity;
    convex_area_ratio_ws(k)  = fp_ws.Area / max(fp_ws.ConvexArea, eps);
    extent_ws(k)             = fp_ws.Extent;
    major_axis_ws_um(k)      = fp_ws.MajorAxisLength * xy;
    minor_axis_ws_um(k)      = fp_ws.MinorAxisLength * xy;
    convexity_ws(k)          = convex_perimeter_ws_um / max(perimeter_ws_um(k), eps);
    if ~isfinite(circularity_ws(k)) || circularity_ws(k) <= 0 || circularity_ws(k) > 2 || ...
            ~isfinite(solidity_ws(k)) || ~isfinite(convexity_ws(k))
        skip_reason_nn{k} = 'invalid watershed shape metrics';
        continue;
    end
    valid_flag_ws(k)         = true;
end
n_valid_nn = sum(valid_flag_nn);
if n_valid_nn < 3
    error('analyzeMoundShape: fewer than 3 preferred-valid mounds.');
end

preferred_valid_flag = valid_flag_nn & valid_flag_ws;
if sum(preferred_valid_flag) < 3
    error('analyzeMoundShape: fewer than 3 preferred-valid watershed mounds.');
end
preferred_peak_v     = peak_z_um(preferred_valid_flag);
preferred_valley_v   = valley_z_nn_um(preferred_valid_flag);
preferred_height_b_v = mound_height_nn_um(preferred_valid_flag);
preferred_rp_v       = Rp_per_mound(preferred_valid_flag);
preferred_rv_v       = Rv_nn_per_mound(preferred_valid_flag);
preferred_rz_v       = Rz_b_per_mound(preferred_valid_flag);
preferred_cx_v       = centroids(preferred_valid_flag, 1);
preferred_cy_v       = centroids(preferred_valid_flag, 2);
preferred_fp_v       = footprint_ws_um2(preferred_valid_flag);
preferred_diam_v     = equiv_diam_ws_um(preferred_valid_flag);
preferred_perim_v    = perimeter_ws_um(preferred_valid_flag);
preferred_circ_v     = circularity_ws(preferred_valid_flag);
preferred_solid_v    = solidity_ws(preferred_valid_flag);
preferred_convexity_v = convexity_ws(preferred_valid_flag);
preferred_extent_v   = extent_ws(preferred_valid_flag);
preferred_major_v    = major_axis_ws_um(preferred_valid_flag);
preferred_minor_v    = minor_axis_ws_um(preferred_valid_flag);
preferred_fmax_v     = feret_max_ws_um(preferred_valid_flag);
preferred_fmin_v     = feret_min_ws_um(preferred_valid_flag);
preferred_fratio_v   = feret_aspect_ratio_ws(preferred_valid_flag);
preferred_nn_radius_v = nn_radius_px(preferred_valid_flag);
preferred_valley_c_v   = valley_z_c_um(preferred_valid_flag & valid_flag_c);
preferred_base_position_c_v = mound_base_position_um(preferred_valid_flag & valid_flag_c);
preferred_height_c_v   = mound_height_c_um(preferred_valid_flag & valid_flag_c);
preferred_rv_c_v       = Rv_c_per_mound(preferred_valid_flag & valid_flag_c);
preferred_rz_c_v       = Rz_c_per_mound(preferred_valid_flag & valid_flag_c);
bc_both_valid = preferred_valid_flag & valid_flag_c;
preferred_shape_valid_flag = preferred_valid_flag & valid_flag_c;
preferred_ar_shape_v = aspect_ratio_ws(preferred_shape_valid_flag);
preferred_diam_shape_v = equiv_diam_ws_um(preferred_shape_valid_flag);
preferred_cx_shape_v = centroids(preferred_shape_valid_flag, 1);
preferred_cy_shape_v = centroids(preferred_shape_valid_flag, 2);
n_valid_c = sum(valid_flag_c);
n_bc_both = sum(bc_both_valid);

fprintf('  Valid preferred mounds : %d / %d\n', sum(preferred_valid_flag), n_total);
fprintf('  Added edge-only watershed seeds : %d\n', size(added_edge_seed_centroids, 1));
if any(~preferred_valid_flag)
    fprintf('  Skipped preferred mounds:\n');
    for k = 1:n_total
        if ~preferred_valid_flag(k) && ~isempty(skip_reason_nn{k})
            fprintf('    Mound %d: %s\n', k, skip_reason_nn{k});
        end
    end
end

fprintf('\n  --- Preferred reporting summary (Method B, n=%d) ---\n', sum(preferred_valid_flag));
fprintf('  NN radius used              : %.1f +/- %.1f px  (%.2f +/- %.2f um)\n', ...
    mean(preferred_nn_radius_v), std(preferred_nn_radius_v), ...
    mean(preferred_nn_radius_v) * xy, std(preferred_nn_radius_v) * xy);
fprintf('  Peak Z (watershed max)      : %.2f +/- %.2f um\n', mean(preferred_peak_v), std(preferred_peak_v));
fprintf('  Valley Z (NN circle)        : %.2f +/- %.2f um\n', mean(preferred_valley_v), std(preferred_valley_v));
fprintf('  Roughness span (Method B)   : %.2f +/- %.2f um\n', mean(preferred_height_b_v), std(preferred_height_b_v));
fprintf('  Rp per mound (above plane)  : %.2f +/- %.2f um\n', mean(preferred_rp_v), std(preferred_rp_v));
fprintf('  Rv per mound (NN circle)    : %.2f +/- %.2f um\n', mean(preferred_rv_v), std(preferred_rv_v));
fprintf('  Rz per mound (preferred)    : %.2f +/- %.2f um\n', mean(preferred_rz_v), std(preferred_rz_v));
fprintf('  Footprint area              : %.1f +/- %.1f um^2\n', mean(preferred_fp_v), std(preferred_fp_v));
fprintf('  Equiv. diameter             : %.2f +/- %.2f um\n', mean(preferred_diam_v), std(preferred_diam_v));
fprintf('  Feret max / min             : %.2f +/- %.2f  /  %.2f +/- %.2f um\n', ...
    mean(preferred_fmax_v), std(preferred_fmax_v), mean(preferred_fmin_v), std(preferred_fmin_v));
fprintf('  Circularity / solidity      : %.3f +/- %.3f  /  %.3f +/- %.3f\n', ...
    mean(preferred_circ_v), std(preferred_circ_v), mean(preferred_solid_v), std(preferred_solid_v));
fprintf('  Method C valid mounds       : %d / %d\n', n_valid_c, n_total);
if n_bc_both > 0
    fprintf('  Mound base Z (Method C)     : %.2f +/- %.2f um\n', mean(preferred_valley_c_v), std(preferred_valley_c_v));
    fprintf('  Mound base position         : %.2f +/- %.2f um\n', mean(preferred_base_position_c_v), std(preferred_base_position_c_v));
    fprintf('  Mound height (Method C)     : %.2f +/- %.2f um\n', mean(preferred_height_c_v), std(preferred_height_c_v));
    fprintf('  Watershed peak Z            : %.2f +/- %.2f um\n', ...
        mean(watershed_peak_z_um(preferred_valid_flag), 'omitnan'), std(watershed_peak_z_um(preferred_valid_flag), 'omitnan'));
    fprintf('  Centroid-window Rp - watershed-peak Rp : %.2f +/- %.2f um\n', ...
        mean(Rp_vs_watershed_peak_diff_um(preferred_valid_flag), 'omitnan'), std(Rp_vs_watershed_peak_diff_um(preferred_valid_flag), 'omitnan'));
    fprintf('  Paired difference (C-B Rv)  : %.2f +/- %.2f um  (n=%d paired)\n', ...
        mean(Rv_c_per_mound(bc_both_valid) - Rv_nn_per_mound(bc_both_valid)), ...
        std(Rv_c_per_mound(bc_both_valid) - Rv_nn_per_mound(bc_both_valid)), n_bc_both);
end

fprintf('  Generating figures...\n');
makeWatershedDiagnosticFigure(I_rgb, imageName, outputDir, centroids, watershed_L, preferred_valid_flag, added_edge_seed_centroids);
makeAugmentedSeedDiagnosticFigure(m1, I_rgb, imageName, outputDir, centroids, Z_smooth, preferred_valid_flag);
makeMethodCBaseBandDiagnosticFigure(I_rgb, imageName, outputDir, base_band_label_img, watershed_border_mask_img, ...
    centroids, watershed_peak_rowcol_px, valid_flag_c);
makeMethodBCComparisonFigure(I_rgb, centroids, preferred_valid_flag, circle_mask_store, base_band_store, ...
    crop_boxes, boundary_band_boxes, valley_px_b, imageName, outputDir, Rv_nn_per_mound, Rv_c_per_mound, ...
    bc_both_valid, nn_radius_px, xy, preferred_height_b_v, preferred_height_c_v, n_valid_nn, n_valid_c);
makeShapeOverlayFigure(I_rgb, imageName, outputDir, centroids, preferred_valid_flag, ...
    preferred_cx_shape_v, preferred_cy_shape_v, preferred_diam_shape_v, preferred_height_c_v, preferred_ar_shape_v, xy);
makeMorphologyHistFigure(imageName, outputDir, preferred_peak_v, preferred_valley_v, ...
    preferred_height_c_v, preferred_fp_v, preferred_diam_shape_v, preferred_ar_shape_v, ...
    preferred_fmax_v, preferred_fmin_v, preferred_fratio_v, preferred_circ_v, ...
    preferred_solid_v, preferred_convexity_v);
makeRzDiagFigure(imageName, outputDir, preferred_rp_v, preferred_rv_v, preferred_rz_v, ...
    Z_raw, Z_smooth, refPlane_um, Rp_global, Rv_global, Rz_global, ...
    preferred_cx_v, preferred_cy_v, preferred_peak_v, nn_mean_px, xy);

fprintf('  Writing Excel output...\n');
xlsx_path = fullfile(outputDir, [imageName '_mound_shapes.xlsx']);
mound_table = table( ...
    (1:n_total)', ...
    centroids(:,1), centroids(:,2), centroids(:,1) * xy, centroids(:,2) * xy, ...
    peak_z_um, centroid_peak_z_um, watershed_peak_z_um, watershed_peak_rowcol_px(:,2), watershed_peak_rowcol_px(:,1), ...
    Rp_per_mound, centroid_peak_Rp_um, watershed_peak_Rp_um, Rp_vs_watershed_peak_diff_um, ...
    nn_radius_px, nn_radius_px * xy, ...
    valley_z_nn_um, mound_height_nn_um, Rv_nn_per_mound, Rz_b_per_mound, double(valid_flag_nn), ...
    valley_z_c_um, mound_base_position_um, mound_height_c_um, Rv_c_per_mound, Rz_c_per_mound, double(valid_flag_c), ...
    footprint_ws_um2, equiv_diam_ws_um, aspect_ratio_ws, perimeter_ws_um, circularity_ws, solidity_ws, convexity_ws, ...
    convex_area_ratio_ws, extent_ws, major_axis_ws_um, minor_axis_ws_um, ...
    feret_max_ws_um, feret_min_ws_um, feret_aspect_ratio_ws, feret_orientation_ws_deg, double(valid_flag_ws), ...
    'VariableNames', { ...
        'MoundIndex', 'X_px', 'Y_px', 'X_um', 'Y_um', ...
        'PeakZ_um', 'CentroidPeakZ_um', 'WatershedPeakZ_um', 'WatershedPeakX_px', 'WatershedPeakY_px', ...
        'Rp_um', 'CentroidPeakRp_um', 'WatershedPeakRp_um', 'CentroidPeakRpMinusWatershedPeakRp_um', ...
        'NNradius_px', 'NNradius_um', ...
        'ValleyZ_B_um', 'MoundHeight_B_um', 'Rv_B_um', 'Rz_B_um', 'Valid_B', ...
        'BaseZ_C_um', 'BasePosition_C_um', 'MoundHeight_C_um', 'Rv_C_um', 'Rz_C_um', 'Valid_C', ...
        'FootprintArea_um2', 'EquivDiameter_um', 'AspectRatio', 'Perimeter_um', ...
        'Circularity', 'Solidity', 'Convexity', 'ConvexAreaRatio', 'Extent', ...
        'MajorAxis_um', 'MinorAxis_um', ...
        'FeretMax_um', 'FeretMin_um', 'FeretAspectRatio', 'FeretOrientation_deg', 'Valid_Footprint'});
writetable(mound_table, xlsx_path, 'Sheet', 'PerMound');

summary = table( ...
    {imageName}, {'NN_circle_watershed_halfmax'}, ...
    sum(preferred_valid_flag), n_valid_c, n_total - sum(preferred_valid_flag), ...
    refPlane_um, Rp_global, Rv_global, Rz_global, ...
    mean(preferred_height_c_v), std(preferred_height_c_v), ...
    mean(preferred_rp_v), std(preferred_rp_v), ...
    mean(preferred_rv_v), std(preferred_rv_v), ...
    mean(preferred_rz_v), std(preferred_rz_v), ...
    mean(preferred_base_position_c_v), std(preferred_base_position_c_v), ...
    mean(preferred_height_c_v), std(preferred_height_c_v), ...
    mean(preferred_rv_c_v), std(preferred_rv_c_v), ...
    mean(preferred_rz_c_v), std(preferred_rz_c_v), ...
    mean(preferred_fp_v), std(preferred_fp_v), ...
    mean(preferred_diam_v), std(preferred_diam_v), ...
    mean(preferred_perim_v), std(preferred_perim_v), ...
    mean(preferred_circ_v), std(preferred_circ_v), ...
    mean(preferred_solid_v), std(preferred_solid_v), ...
    mean(preferred_convexity_v), std(preferred_convexity_v), ...
    mean(preferred_extent_v), std(preferred_extent_v), ...
    mean(preferred_major_v), std(preferred_major_v), ...
    mean(preferred_minor_v), std(preferred_minor_v), ...
    mean(preferred_fmax_v), std(preferred_fmax_v), ...
    mean(preferred_fmin_v), std(preferred_fmin_v), ...
    mean(preferred_fratio_v), std(preferred_fratio_v), ...
    'VariableNames', { ...
        'ImageName', 'PreferredMethod', ...
        'N_valid_preferred', 'N_valid_C', 'N_invalid_preferred', ...
        'RefPlane_um', 'Rp_global_um', 'Rv_global_um', 'Rz_global_um', ...
        'Mean_MoundHeight_preferred_um', 'Std_MoundHeight_preferred_um', ...
        'Mean_Rp_preferred_um', 'Std_Rp_preferred_um', ...
        'Mean_Rv_preferred_um', 'Std_Rv_preferred_um', ...
        'Mean_Rz_preferred_um', 'Std_Rz_preferred_um', ...
        'Mean_MoundBasePosition_um', 'Std_MoundBasePosition_um', ...
        'Mean_MoundHeight_C_um', 'Std_MoundHeight_C_um', ...
        'Mean_Rv_C_um', 'Std_Rv_C_um', ...
        'Mean_Rz_C_um', 'Std_Rz_C_um', ...
        'Mean_FootprintArea_um2', 'Std_FootprintArea_um2', ...
        'Mean_EquivDiameter_um', 'Std_EquivDiameter_um', ...
        'Mean_Perimeter_um', 'Std_Perimeter_um', ...
        'Mean_Circularity', 'Std_Circularity', ...
        'Mean_Solidity', 'Std_Solidity', ...
        'Mean_Convexity', 'Std_Convexity', ...
        'Mean_Extent', 'Std_Extent', ...
        'Mean_MajorAxis_um', 'Std_MajorAxis_um', ...
        'Mean_MinorAxis_um', 'Std_MinorAxis_um', ...
        'Mean_FeretMax_um', 'Std_FeretMax_um', ...
        'Mean_FeretMin_um', 'Std_FeretMin_um', ...
        'Mean_FeretAspectRatio', 'Std_FeretAspectRatio'});
writetable(summary, xlsx_path, 'Sheet', 'Summary');
fprintf('  Saved: %s\n', xlsx_path);

moundResults.n_mounds         = sum(preferred_valid_flag);
moundResults.n_valid_nn       = n_valid_nn;
moundResults.n_valid_c        = n_valid_c;
moundResults.n_total          = n_total;
moundResults.peak_z_um        = peak_z_um;
moundResults.centroid_peak_z_um = centroid_peak_z_um;
moundResults.centroid_peak_Rp_um = centroid_peak_Rp_um;
moundResults.Rp_per_mound     = Rp_per_mound;
moundResults.watershed_peak_z_um = watershed_peak_z_um;
moundResults.watershed_peak_rowcol_px = watershed_peak_rowcol_px;
moundResults.watershed_peak_Rp_um = watershed_peak_Rp_um;
moundResults.Rp_minus_watershed_peak_Rp_um = Rp_vs_watershed_peak_diff_um;
moundResults.valley_z_nn_um   = valley_z_nn_um;
moundResults.mound_height_nn_um = mound_height_nn_um;
moundResults.nn_radius_px     = nn_radius_px;
moundResults.Rv_nn_per_mound  = Rv_nn_per_mound;
moundResults.Rz_b_per_mound   = Rz_b_per_mound;
moundResults.valid_flag_nn    = valid_flag_nn;
moundResults.valley_z_c_um    = valley_z_c_um;
moundResults.mound_base_position_um = mound_base_position_um;
moundResults.mound_height_c_um = mound_height_c_um;
moundResults.Rv_c_per_mound   = Rv_c_per_mound;
moundResults.Rz_c_per_mound   = Rz_c_per_mound;
moundResults.valid_flag_c     = valid_flag_c;
moundResults.mound_base_valid_flag = valid_flag_c;
moundResults.method_c_band_width_px = METHOD_C_BASE_BAND_WIDTH_PX;
moundResults.footprint_um2    = footprint_ws_um2;
moundResults.equiv_diam_um    = equiv_diam_ws_um;
moundResults.aspect_ratio     = aspect_ratio_ws;
moundResults.perimeter_um     = perimeter_ws_um;
moundResults.circularity      = circularity_ws;
moundResults.solidity         = solidity_ws;
moundResults.convexity        = convexity_ws;
moundResults.convex_area_ratio = convex_area_ratio_ws;
moundResults.extent           = extent_ws;
moundResults.major_axis_um    = major_axis_ws_um;
moundResults.minor_axis_um    = minor_axis_ws_um;
moundResults.feret_max_um     = feret_max_ws_um;
moundResults.feret_min_um     = feret_min_ws_um;
moundResults.feret_aspect_ratio = feret_aspect_ratio_ws;
moundResults.feret_orientation_deg = feret_orientation_ws_deg;
moundResults.watershed_valid_flag = valid_flag_ws;
moundResults.watershed_footprint_um2 = footprint_ws_um2;
moundResults.watershed_equiv_diam_um = equiv_diam_ws_um;
moundResults.watershed_aspect_ratio = aspect_ratio_ws;
moundResults.watershed_perimeter_um = perimeter_ws_um;
moundResults.watershed_circularity = circularity_ws;
moundResults.watershed_solidity = solidity_ws;
moundResults.watershed_convexity = convexity_ws;
moundResults.watershed_convex_area_ratio = convex_area_ratio_ws;
moundResults.watershed_extent = extent_ws;
moundResults.watershed_major_axis_um = major_axis_ws_um;
moundResults.watershed_minor_axis_um = minor_axis_ws_um;
moundResults.watershed_feret_max_um = feret_max_ws_um;
moundResults.watershed_feret_min_um = feret_min_ws_um;
moundResults.watershed_feret_aspect_ratio = feret_aspect_ratio_ws;
moundResults.watershed_feret_orientation_deg = feret_orientation_ws_deg;
moundResults.Rz_per_mound     = Rz_b_per_mound;
moundResults.preferred_method = 'NN_circle_watershed_halfmax';
moundResults.preferred_valid_flag = preferred_valid_flag;
moundResults.preferred_peak_z_um = peak_z_um;
moundResults.preferred_valley_z_um = valley_z_nn_um;
moundResults.preferred_Rp_per_mound = Rp_per_mound;
moundResults.preferred_Rv_per_mound = Rv_nn_per_mound;
moundResults.preferred_Rz_per_mound = Rz_b_per_mound;
moundResults.mound_base_z_um = valley_z_c_um;
moundResults.mound_height_um = mound_height_c_um;
moundResults.preferred_mound_base_z_um = valley_z_c_um;
moundResults.preferred_mound_base_position_um = mound_base_position_um;
moundResults.preferred_mound_height_um = mound_height_c_um;
moundResults.method_c_valley_z_um = valley_z_c_um;
moundResults.method_c_valid_flag = valid_flag_c;
moundResults.method_c_base_z_um = valley_z_c_um;
moundResults.method_c_base_position_um = mound_base_position_um;
moundResults.method_c_mound_height_um = mound_height_c_um;
moundResults.method_c_base_band_label_img = base_band_label_img;
moundResults.method_c_watershed_border_mask = watershed_border_mask_img;
moundResults.method_c_Rv_per_mound = Rv_c_per_mound;
moundResults.method_c_Rz_per_mound = Rz_c_per_mound;
moundResults.preferred_n_mounds = sum(preferred_valid_flag);
moundResults.preferred_footprint_um2 = footprint_ws_um2;
moundResults.preferred_equiv_diam_um = equiv_diam_ws_um;
moundResults.preferred_aspect_ratio = aspect_ratio_ws;
moundResults.preferred_perimeter_um = perimeter_ws_um;
moundResults.preferred_circularity = circularity_ws;
moundResults.preferred_solidity = solidity_ws;
moundResults.preferred_convexity = convexity_ws;
moundResults.preferred_convex_area_ratio = convex_area_ratio_ws;
moundResults.preferred_extent = extent_ws;
moundResults.preferred_major_axis_um = major_axis_ws_um;
moundResults.preferred_minor_axis_um = minor_axis_ws_um;
moundResults.preferred_feret_max_um = feret_max_ws_um;
moundResults.preferred_feret_min_um = feret_min_ws_um;
moundResults.preferred_feret_aspect_ratio = feret_aspect_ratio_ws;
moundResults.preferred_feret_orientation_deg = feret_orientation_ws_deg;
moundResults.centroid_px      = centroids;
moundResults.refPlane_um      = refPlane_um;
moundResults.Rp_global        = Rp_global;
moundResults.Rv_global        = Rv_global;
moundResults.Rz_global        = Rz_global;
moundResults.Z_smooth         = Z_smooth;
moundResults.watershed_L      = watershed_L;
moundResults.watershed_seed_centroids_px = watershed_seed_centroids;
moundResults.added_edge_seed_centroids_px = added_edge_seed_centroids;
moundResults.watershed_smooth_sigma_px = smooth_sigma;
moundResults.watershed_spacing_px = spacing_px;
moundResults.watershed_sigma_candidates_px = watershed_selection.candidate_sigmas_px;
moundResults.watershed_sigma_scores = watershed_selection.candidate_scores;
moundResults.watershed_sigma_metrics = watershed_selection.metrics;
moundResults.imageName        = imageName;
moundResults.imagePath        = m1.imagePath;
moundResults.m1               = m1;

mat_path = fullfile(outputDir, [imageName '_mound_shapes.mat']);
save(mat_path, 'moundResults');
fprintf('  Saved: %s\n', mat_path);
fprintf('analyzeMoundShape complete.\n\n');
end

function [rowColGlobal] = findMaskPixel(mask, maskedIndex, r0, c0)
lin_idx = find(mask);
[rr, cc] = ind2sub(size(mask), lin_idx(maskedIndex));
rowColGlobal = [rr + r0 - 1, cc + c0 - 1];
end

function [peak_z_um, peak_rowcol_global] = findRegionPeakPixel(region_mask, Z_local_raw, r0, c0)
peak_z_um = NaN;
peak_rowcol_global = [NaN NaN];
if ~any(region_mask(:))
    return;
end

z_vals = Z_local_raw(region_mask);
[peak_z_um, idx_max] = max(z_vals);
lin_idx = find(region_mask);
[rr, cc] = ind2sub(size(region_mask), lin_idx(idx_max));
peak_rowcol_global = [rr + r0 - 1, cc + c0 - 1];
end

function [base_band_mask, base_samples_um] = buildMethodCBaseBand(region_mask, boundary_mask, Z_local_raw, centroid_xy)
base_band_mask = false(size(region_mask));
base_samples_um = zeros(0, 1);

if ~any(boundary_mask(:))
    return;
end

D_in = bwdist(~region_mask);
[rb, cb] = find(boundary_mask);
base_band_mask(boundary_mask) = true;

for i = 1:numel(rb)
    r0 = rb(i);
    c0 = cb(i);
    z_boundary = Z_local_raw(r0, c0);

    rr1 = max(1, r0 - 1);
    rr2 = min(size(region_mask,1), r0 + 1);
    cc1 = max(1, c0 - 1);
    cc2 = min(size(region_mask,2), c0 + 1);

    local_region = region_mask(rr1:rr2, cc1:cc2);
    local_dist   = D_in(rr1:rr2, cc1:cc2);
    local_rows   = rr1:rr2;
    local_cols   = cc1:cc2;
    [Rloc, Cloc] = ndgrid(local_rows, local_cols);
    inward_mask = local_region & (local_dist > 0);

    if any(inward_mask(:))
        inward_rows = Rloc(inward_mask);
        inward_cols = Cloc(inward_mask);
        inward_z    = Z_local_raw(sub2ind(size(Z_local_raw), inward_rows, inward_cols));
        inward_dist = D_in(sub2ind(size(D_in), inward_rows, inward_cols));
        inward_centroid_d2 = (inward_cols - centroid_xy(1)).^2 + (inward_rows - centroid_xy(2)).^2;
        min_step = min(inward_dist);
        keep = (inward_dist == min_step);
        inward_rows = inward_rows(keep);
        inward_cols = inward_cols(keep);
        inward_z = inward_z(keep);
        inward_centroid_d2 = inward_centroid_d2(keep);
        [~, order_idx] = sort(inward_centroid_d2, 'ascend');
        r_in = inward_rows(order_idx(1));
        c_in = inward_cols(order_idx(1));
        z_in = inward_z(order_idx(1));
        base_band_mask(r_in, c_in) = true;
        base_samples_um(end+1, 1) = min(z_boundary, z_in); %#ok<AGROW>
    else
        base_samples_um(end+1, 1) = z_boundary; %#ok<AGROW>
    end
end
end

function boundary_mask = getRegionWatershedBorderMask(local_ws_labels, target_label)
region_mask = (local_ws_labels == target_label);
boundary_mask = false(size(region_mask));
if ~any(region_mask(:))
    return;
end

adjacent_to_region = imdilate(region_mask, true(3));
zero_border = (local_ws_labels == 0) & adjacent_to_region;
boundary_mask = boundary_mask | zero_border;

touches_image_edge = any(region_mask(1,:)) || any(region_mask(end,:)) || any(region_mask(:,1)) || any(region_mask(:,end));
if touches_image_edge
    boundary_mask = boundary_mask | bwperim(region_mask, 4);
end

if ~any(boundary_mask(:))
    boundary_mask = bwperim(region_mask, 4);
end
end

function component_mask = extractCentroidComponent(binaryMask, r_c_loc, c_c_loc)
component_mask = false(size(binaryMask));
if ~any(binaryMask(:))
    return;
end
L = bwlabel(binaryMask, 4);
r_c_loc = max(1, min(size(binaryMask,1), r_c_loc));
c_c_loc = max(1, min(size(binaryMask,2), c_c_loc));
lbl = L(r_c_loc, c_c_loc);
if lbl == 0
    [rr, cc] = find(L > 0);
    if isempty(rr)
        return;
    end
    [~, i_near] = min((rr - r_c_loc).^2 + (cc - c_c_loc).^2);
    lbl = L(rr(i_near), cc(i_near));
end
component_mask = (L == lbl);
end

function [fmax_um, fmin_um, orient_deg, aspect_ratio, convex_perimeter_um] = computeFeretMetrics(binaryMask, xy)
B = bwboundaries(binaryMask, 'noholes');
if isempty(B) || size(B{1},1) < 2
    fmax_um = NaN; fmin_um = NaN; orient_deg = NaN; aspect_ratio = NaN; convex_perimeter_um = NaN;
    return;
end
pts = unique([B{1}(:,2), B{1}(:,1)], 'rows', 'stable');
if size(pts, 1) < 2
    fmax_um = NaN; fmin_um = NaN; orient_deg = NaN; aspect_ratio = NaN; convex_perimeter_um = NaN;
    return;
end

if size(pts, 1) >= 3 && pointSetSpansArea(pts)
    K = convhull(pts(:,1), pts(:,2));
    hull = pts(K, :);
else
    hull = pts;
end

pair_d = squareform(pdist(hull));
[fmax_px, idx] = max(pair_d(:));
[i1, i2] = ind2sub(size(pair_d), idx);
vec = hull(i2,:) - hull(i1,:);
orient_deg = mod(atan2d(vec(2), vec(1)), 180);

if size(hull, 1) >= 3 && pointSetSpansArea(hull)
    widths = nan(size(hull,1)-1, 1);
    for i = 1:size(hull,1)-1
        edge = hull(i+1,:) - hull(i,:);
        if norm(edge) < eps
            continue;
        end
        normal = [-edge(2), edge(1)] / norm(edge);
        proj = hull * normal';
        widths(i) = max(proj) - min(proj);
    end
    fmin_px = min(widths);
    seg = diff(hull, 1, 1);
    convex_perimeter_um = sum(sqrt(sum(seg.^2, 2))) * xy;
else
    fmin_px = 1;
    convex_perimeter_um = fmax_px * xy;
end
if isempty(fmin_px) || ~isfinite(fmin_px) || fmin_px <= 0
    fmin_px = 1;
end

fmax_um = fmax_px * xy;
fmin_um = fmin_px * xy;
aspect_ratio = fmax_um / max(fmin_um, eps);
end

function tf = pointSetSpansArea(pts)
if size(pts, 1) < 3
    tf = false;
    return;
end

pts0 = pts - mean(pts, 1);
tf = rank(pts0, 1e-9) >= 2;
end

function makeMethodCBaseBandDiagnosticFigure(I_rgb, imageName, outputDir, base_band_labels, watershed_border_mask, centroids, watershed_peak_rowcol_px, valid_flag_c)
valid_labels = unique(base_band_labels(base_band_labels > 0));
if isempty(valid_labels)
    fprintf('  Skipped Method C base-band diagnostic: no valid base bands.\n');
    return;
end

fig = figure('Name', 'Method C base-band diagnostic', 'Position', [60 60 1450 780], 'Color', 'w');
ax = axes(fig);
imshow(I_rgb, 'Parent', ax); hold(ax, 'on');

cmap = turbo(max(valid_labels));
overlay = zeros(size(I_rgb), 'uint8');
alpha_mask = zeros(size(base_band_labels));
for i = 1:numel(valid_labels)
    k = valid_labels(i);
    mask_k = (base_band_labels == k);
    color_k = uint8(round(255 * cmap(k, :)));
    for ch = 1:3
        layer = overlay(:,:,ch);
        layer(mask_k) = color_k(ch);
        overlay(:,:,ch) = layer;
    end
    alpha_mask(mask_k) = 0.88;
end

h = imshow(overlay, 'Parent', ax);
h.AlphaData = alpha_mask;

ws_overlay = zeros(size(I_rgb), 'uint8');
for ch = 1:3
    layer = ws_overlay(:,:,ch);
    layer(watershed_border_mask) = 255;
    ws_overlay(:,:,ch) = layer;
end
h_ws = imshow(ws_overlay, 'Parent', ax);
h_ws.AlphaData = 0.95 * double(watershed_border_mask);

plot(ax, centroids(valid_flag_c,1), centroids(valid_flag_c,2), 'c+', 'MarkerSize', 4.8, 'LineWidth', 0.9);
peak_valid = all(isfinite(watershed_peak_rowcol_px), 2);
plot(ax, watershed_peak_rowcol_px(peak_valid,2), watershed_peak_rowcol_px(peak_valid,1), 'wo', ...
    'MarkerSize', 4.8, 'LineWidth', 0.9);
if any(~valid_flag_c)
    plot(ax, centroids(~valid_flag_c,1), centroids(~valid_flag_c,2), 'x', ...
        'Color', [0.75 0.15 0.15], 'MarkerSize', 5, 'LineWidth', 0.8);
end
title(ax, sprintf('Method C base band: white watershed pixel + 1 inward pixel (n=%d valid)', sum(valid_flag_c)), 'FontSize', 10);
hold(ax, 'off');

sgtitle(fig, sprintf('%s | Method C base band with centroid and watershed-peak markers', imageName), 'Interpreter', 'none');
outPath = fullfile(outputDir, [imageName '_method_c_base_band_diag.png']);
exportgraphics(fig, outPath, 'Resolution', 150);
fprintf('  Saved: %s\n', outPath);
end

function makeWatershedDiagnosticFigure(I_rgb, imageName, outputDir, centroids, ws_labels, preferred_valid_flag, added_edge_seed_centroids)
ws_boundary = imdilate(getWatershedBoundaryMask(ws_labels), strel('disk', 1));

fig = figure('Name', 'Watershed diagnostic', 'Position', [40 40 1500 760], 'Color', 'w');

ax1 = subplot(1, 2, 1);
showBoundaryOverlay(ax1, I_rgb, centroids, preferred_valid_flag, ws_boundary, [0 220 255]);
if ~isempty(added_edge_seed_centroids)
    hold(ax1, 'on');
    plot(ax1, added_edge_seed_centroids(:,1), added_edge_seed_centroids(:,2), 'yo', ...
        'MarkerSize', 4.5, 'LineWidth', 0.9);
    hold(ax1, 'off');
end
title(ax1, sprintf('Full-image watershed boundaries on raw image (n=%d preferred valid)', ...
    sum(preferred_valid_flag)), 'FontSize', 10);

ax2 = subplot(1, 2, 2);
imagesc(ax2, ws_labels);
axis(ax2, 'image');
set(ax2, 'YDir', 'normal');
hold(ax2, 'on');
plotPartitionCentroids(ax2, centroids, preferred_valid_flag, 'w');
if ~isempty(added_edge_seed_centroids)
    plot(ax2, added_edge_seed_centroids(:,1), added_edge_seed_centroids(:,2), 'yo', ...
        'MarkerSize', 4.5, 'LineWidth', 0.9);
end
title(ax2, 'Watershed label map', 'FontSize', 10);
colormap(ax2, turbo);
cb = colorbar(ax2);
cb.Label.String = 'Watershed mound label';
hold(ax2, 'off');

sgtitle(fig, sprintf('%s | Watershed footprint diagnostic', imageName), 'Interpreter', 'none');
outPath = fullfile(outputDir, [imageName '_watershed_diag.png']);
exportgraphics(fig, outPath, 'Resolution', 150);
fprintf('  Saved: %s\n', outPath);
end

function makeAugmentedSeedDiagnosticFigure(m1, I_rgb, imageName, outputDir, centroids, Z_smooth, preferred_valid_flag)
[all_centroids, ok, reason] = detectBorderInclusiveCentroids(m1);
if ~ok
    fprintf('  Skipped augmented-seed diagnostic: %s\n', reason);
    return;
end

if isempty(all_centroids)
    fprintf('  Skipped augmented-seed diagnostic: no centroids detected without border clearing.\n');
    return;
end

base_watershed_L = computeSeededWatershedLabels(Z_smooth, centroids);
if isempty(centroids)
    added_mask = true(size(all_centroids,1),1);
else
    idx_near = knnsearch(centroids, all_centroids);
    d_near = sqrt(sum((all_centroids - centroids(idx_near,:)).^2, 2));
    added_mask = d_near > 1.5;
end
added_centroids = all_centroids(added_mask, :);
aug_watershed_L = computeSeededWatershedLabels(Z_smooth, all_centroids);

curr_boundary = imdilate(getWatershedBoundaryMask(base_watershed_L), strel('disk', 1));
aug_boundary  = imdilate(getWatershedBoundaryMask(aug_watershed_L), strel('disk', 1));

fig = figure('Name', 'Augmented seed watershed diagnostic', 'Position', [60 60 1500 760], 'Color', 'w');

ax1 = subplot(1, 2, 1);
showBoundaryOverlay(ax1, I_rgb, centroids, preferred_valid_flag, curr_boundary, [0 220 255]);
title(ax1, sprintf('Original-only watershed | %d centroids', size(centroids,1)), 'FontSize', 10);

ax2 = subplot(1, 2, 2);
imshow(I_rgb, 'Parent', ax2); hold(ax2, 'on');
overlay = zeros(size(I_rgb), 'uint8');
overlay(:,:,1) = uint8(aug_boundary) * 255;
overlay(:,:,2) = uint8(aug_boundary) * 180;
h = imshow(overlay, 'Parent', ax2);
h.AlphaData = double(aug_boundary) * 0.82;
plot(ax2, centroids(:,1), centroids(:,2), 'g+', 'MarkerSize', 5, 'LineWidth', 0.8);
if ~isempty(added_centroids)
    plot(ax2, added_centroids(:,1), added_centroids(:,2), 'yo', 'MarkerSize', 4.5, 'LineWidth', 0.9);
end
title(ax2, sprintf('Augmented watershed | %d total seeds | %d added edge seeds', ...
    size(all_centroids,1), size(added_centroids,1)), 'FontSize', 10);
legend(ax2, {'Interior centroids', 'Added edge centroids'}, 'Location', 'southoutside');
hold(ax2, 'off');

sgtitle(fig, sprintf('%s | Diagnostic: edge-inclusive centroid reseeding', imageName), 'Interpreter', 'none');
outPath = fullfile(outputDir, [imageName '_watershed_augmented_seed_diag.png']);
exportgraphics(fig, outPath, 'Resolution', 150);
fprintf('  Saved: %s\n', outPath);
end

function D_nn = computeNearestNeighborDistances(centroids, fallbackSpacing)
n_total = size(centroids, 1);
if n_total <= 1
    D_nn = repmat(max(1, double(fallbackSpacing)), n_total, 1);
    return;
end

dist_matrix = sqrt( ...
    (centroids(:,1) - centroids(:,1)').^2 + ...
    (centroids(:,2) - centroids(:,2)').^2);
dist_matrix(logical(eye(n_total))) = Inf;
D_nn = min(dist_matrix, [], 2);
D_nn(~isfinite(D_nn) | D_nn <= 0) = max(1, double(fallbackSpacing));
end

function spacing_px = computeRepresentativeSpacingPx(D_nn, fallbackSpacing)
valid = D_nn(isfinite(D_nn) & D_nn > 0);
if isempty(valid)
    spacing_px = max(1, double(fallbackSpacing));
else
    spacing_px = median(valid);
end

if ~isfinite(spacing_px) || spacing_px <= 0
    spacing_px = max(1, double(fallbackSpacing));
end
end

function selection = selectWatershedSmoothing(Z_raw, watershed_seed_centroids, original_centroids, spacing_px)
candidate_sigmas = buildWatershedSigmaCandidates(spacing_px);
n_candidates = numel(candidate_sigmas);
candidate_scores = -Inf(n_candidates, 1);
metrics = repmat(struct( ...
    'valid_fraction', NaN, ...
    'median_normalized_clearance', NaN, ...
    'median_normalized_boundary_drop', NaN, ...
    'median_circularity', NaN, ...
    'tiny_region_fraction', NaN, ...
    'oversized_region_fraction', NaN, ...
    'median_log_area_error', NaN), n_candidates, 1);
Z_smooth_all = cell(n_candidates, 1);
ws_all = cell(n_candidates, 1);

for i = 1:n_candidates
    sigma = candidate_sigmas(i);
    Z_try = imgaussfilt(Z_raw, sigma);
    ws_try = computeSeededWatershedLabels(Z_try, watershed_seed_centroids);
    [candidate_scores(i), metrics(i)] = scoreSeededWatershed(ws_try, Z_try, original_centroids, spacing_px);
    Z_smooth_all{i} = Z_try;
    ws_all{i} = ws_try;
end

[best_score, best_idx] = max(candidate_scores);
selection = struct( ...
    'best_sigma_px', candidate_sigmas(best_idx), ...
    'best_score', best_score, ...
    'candidate_sigmas_px', candidate_sigmas(:)', ...
    'candidate_scores', candidate_scores(:)', ...
    'metrics', {metrics}, ...
    'Z_smooth', Z_smooth_all{best_idx}, ...
    'watershed_L', ws_all{best_idx});
end

function candidate_sigmas = buildWatershedSigmaCandidates(spacing_px)
base_sigma = max(0.8, min(12, 0.08 * spacing_px));
candidate_sigmas = base_sigma * [0.55 0.8 1.0 1.2 1.45];
candidate_sigmas = min(12, max(0.6, candidate_sigmas));
candidate_sigmas = unique(round(candidate_sigmas, 2), 'stable');
end

function [score, metrics] = scoreSeededWatershed(ws_labels, Z_smooth, centroids, spacing_px)
n_total = size(centroids, 1);
if n_total == 0
    score = -Inf;
    metrics = struct( ...
        'valid_fraction', 0, ...
        'median_normalized_clearance', 0, ...
        'median_normalized_boundary_drop', 0, ...
        'median_circularity', 0, ...
        'tiny_region_fraction', 1, ...
        'oversized_region_fraction', 1, ...
        'median_log_area_error', Inf);
    return;
end

z_scale = prctile(Z_smooth(:), 95) - prctile(Z_smooth(:), 5);
z_scale = max(z_scale, eps);
expected_area_px = pi * max(1, 0.5 * spacing_px)^2;

region_area = nan(n_total, 1);
norm_clearance = nan(n_total, 1);
norm_boundary_drop = nan(n_total, 1);
circularity = nan(n_total, 1);

for k = 1:n_total
    region_mask = (ws_labels == k);
    if ~any(region_mask(:))
        continue;
    end

    region_area(k) = sum(region_mask(:));
    eq_radius = sqrt(region_area(k) / pi);

    dist_in = bwdist(~region_mask);
    c = max(1, min(size(ws_labels, 2), round(centroids(k, 1))));
    r = max(1, min(size(ws_labels, 1), round(centroids(k, 2))));
    norm_clearance(k) = dist_in(r, c) / max(eq_radius, 1);

    boundary_mask = bwperim(region_mask, 8);
    boundary_vals = Z_smooth(boundary_mask);
    region_vals = Z_smooth(region_mask);
    if ~isempty(boundary_vals) && ~isempty(region_vals)
        norm_boundary_drop(k) = (max(region_vals) - mean(boundary_vals, 'omitnan')) / z_scale;
    end

    stats = regionprops(region_mask, 'Area', 'Perimeter');
    if ~isempty(stats)
        circularity(k) = 4 * pi * stats.Area / max(stats.Perimeter^2, eps);
    end
end

valid = isfinite(region_area) & region_area > 0;
if ~any(valid)
    score = -Inf;
    metrics = struct( ...
        'valid_fraction', 0, ...
        'median_normalized_clearance', 0, ...
        'median_normalized_boundary_drop', 0, ...
        'median_circularity', 0, ...
        'tiny_region_fraction', 1, ...
        'oversized_region_fraction', 1, ...
        'median_log_area_error', Inf);
    return;
end

valid_fraction = mean(valid);
tiny_region_fraction = mean(region_area(valid) < 0.35 * expected_area_px);
oversized_region_fraction = mean(region_area(valid) > 3.0 * expected_area_px);
median_log_area_error = median(abs(log(region_area(valid) / expected_area_px)));
median_normalized_clearance = median(norm_clearance(valid), 'omitnan');
median_normalized_boundary_drop = median(norm_boundary_drop(valid), 'omitnan');
median_circularity = median(circularity(valid), 'omitnan');

median_normalized_clearance = clampFiniteMetric(median_normalized_clearance, 0);
median_normalized_boundary_drop = clampFiniteMetric(median_normalized_boundary_drop, 0);
median_circularity = clampFiniteMetric(median_circularity, 0);
median_log_area_error = clampFiniteMetric(median_log_area_error, 5);

score = ...
    5.0 * valid_fraction + ...
    2.5 * median_normalized_clearance + ...
    1.5 * median_normalized_boundary_drop + ...
    1.0 * median_circularity - ...
    1.75 * tiny_region_fraction - ...
    1.0 * oversized_region_fraction - ...
    0.75 * median_log_area_error;

metrics = struct( ...
    'valid_fraction', valid_fraction, ...
    'median_normalized_clearance', median_normalized_clearance, ...
    'median_normalized_boundary_drop', median_normalized_boundary_drop, ...
    'median_circularity', median_circularity, ...
    'tiny_region_fraction', tiny_region_fraction, ...
    'oversized_region_fraction', oversized_region_fraction, ...
    'median_log_area_error', median_log_area_error);
end

function val = clampFiniteMetric(val, fallbackVal)
if ~isfinite(val)
    val = fallbackVal;
end
end

function ws_labels = computeSeededWatershedLabels(Z_smooth, centroids)
marker_mask = false(size(Z_smooth));
cx = max(1, min(size(Z_smooth,2), round(centroids(:,1))));
cy = max(1, min(size(Z_smooth,1), round(centroids(:,2))));
marker_idx = sub2ind(size(marker_mask), cy, cx);
marker_mask(marker_idx) = true;

L_markers = bwlabel(marker_mask, 8);
if max(L_markers(:)) < size(centroids,1)
    % Expand single-pixel seeds slightly so nearby duplicate-rounded centroids
    % still create stable imposed minima for the diagnostic segmentation.
    marker_mask = imdilate(marker_mask, strel('disk', 1));
    L_markers = bwlabel(marker_mask, 8);
end

topo = -Z_smooth;
topo_imp = imimposemin(topo, L_markers > 0);
ws_raw = watershed(topo_imp, 8);
ws_labels = relabelWatershedByCentroids(ws_raw, centroids);
end

function [seed_centroids, added_edge_seed_centroids, ok, reason] = buildAugmentedWatershedSeeds(m1, original_centroids)
[all_centroids, ok, reason] = detectBorderInclusiveCentroids(m1);
if ~ok
    seed_centroids = original_centroids;
    added_edge_seed_centroids = zeros(0, 2);
    return;
end

if isempty(all_centroids) || isempty(original_centroids)
    seed_centroids = original_centroids;
    added_edge_seed_centroids = zeros(0, 2);
    return;
end

idx_near = knnsearch(original_centroids, all_centroids);
d_near = sqrt(sum((all_centroids - original_centroids(idx_near,:)).^2, 2));
added_mask = d_near > 1.5;
added_edge_seed_centroids = all_centroids(added_mask, :);
seed_centroids = [original_centroids; added_edge_seed_centroids];
end

function [centroids_all, ok, reason] = detectBorderInclusiveCentroids(m1)
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
mask = double(applyDetectionContrast(Iblur, char(p.contrastMethod), double(p.clipLimit)));
Iobrcbr = preprocessDetectionImage(mask, double(p.openRadius));
fgm4 = extractDetectionRegionalMaxima(Iobrcbr, dilateRadius, minObjectArea, ...
    fillDeepPits, Iblur, fillThreshold);

stats = regionprops(logical(fgm4), 'Centroid');
if isempty(stats)
    centroids_all = zeros(0, 2);
else
    centroids_all = double(cat(1, stats.Centroid));
end
ok = true;
end

function mask = applyDetectionContrast(I, method, clipLimit)
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

function Iobrcbr = preprocessDetectionImage(mask, radius)
se = strel('disk', radius);
Ie = imerode(mask, se);
Iobr = imreconstruct(Ie, mask);
Iobrd = imdilate(Iobr, se);
Iobrcbr = imreconstruct(imcomplement(Iobrd), imcomplement(Iobr));
Iobrcbr = imcomplement(Iobrcbr);
end

function fgm4 = extractDetectionRegionalMaxima(Iobrcbr, dilateRadius, minArea, fillDeepPits, Iblur, fillThreshold)
fgm  = imregionalmax(Iobrcbr);
se   = strel('disk', dilateRadius);
fgm2 = imclose(fgm, se);
fgm3 = imdilate(fgm2, se);
fgm4 = bwareaopen(fgm3, minArea);
if fillDeepPits
    filled = imcomplement(imfill(imcomplement(imbinarize(Iblur, fillThreshold)), 'holes'));
    fgm4 = and(filled, fgm4);
end
end

function ws_labels = relabelWatershedByCentroids(ws_raw, centroids)
ws_labels = zeros(size(ws_raw));
basin_labels = bwlabel(ws_raw > 0, 4);
n_basins = max(basin_labels(:));
cx = max(1, min(size(ws_raw,2), round(centroids(:,1))));
cy = max(1, min(size(ws_raw,1), round(centroids(:,2))));
centroid_lin = sub2ind(size(ws_raw), cy, cx);
centroid_basin = basin_labels(centroid_lin);

for rid = 1:n_basins
    region_mask = (basin_labels == rid);
    member_idx = find(centroid_basin == rid);
    if isempty(member_idx)
        continue;
    elseif numel(member_idx) == 1
        ws_labels(region_mask) = member_idx;
    else
        [rr, cc] = find(region_mask);
        region_xy = [cc, rr];
        seed_xy = centroids(member_idx, :);
        assign_idx = knnsearch(seed_xy, region_xy);
        assigned_k = member_idx(assign_idx);
        ws_labels(region_mask) = assigned_k;
    end
end
end

function showBoundaryOverlay(ax, I_rgb, centroids, preferred_valid_flag, boundary_mask, rgbColor)
imshow(I_rgb, 'Parent', ax); hold(ax, 'on');
overlay = zeros(size(I_rgb), 'uint8');
overlay(:,:,1) = uint8(boundary_mask) * rgbColor(1);
overlay(:,:,2) = uint8(boundary_mask) * rgbColor(2);
overlay(:,:,3) = uint8(boundary_mask) * rgbColor(3);
h = imshow(overlay, 'Parent', ax);
h.AlphaData = double(boundary_mask) * 0.85;
plot(ax, centroids(preferred_valid_flag,1), centroids(preferred_valid_flag,2), 'g+', 'MarkerSize', 5, 'LineWidth', 0.8);
if any(~preferred_valid_flag)
    plot(ax, centroids(~preferred_valid_flag,1), centroids(~preferred_valid_flag,2), 'x', ...
        'Color', [0.75 0.15 0.15], 'MarkerSize', 5, 'LineWidth', 0.8);
end
hold(ax, 'off');
end

function plotPartitionCentroids(ax, centroids, preferred_valid_flag, colorSpec)
plot(ax, centroids(preferred_valid_flag,1), centroids(preferred_valid_flag,2), 'o', ...
    'Color', colorSpec, 'MarkerSize', 3.5, 'LineWidth', 0.7);
if any(~preferred_valid_flag)
    plot(ax, centroids(~preferred_valid_flag,1), centroids(~preferred_valid_flag,2), 'x', ...
        'Color', colorSpec, 'MarkerSize', 4.0, 'LineWidth', 0.7);
end
end

function boundary_mask = getLabelBoundaryMask(labelImage)
boundary_mask = false(size(labelImage));
L = labelImage;
valid = L > 0;

right_diff = valid(:,1:end-1) & valid(:,2:end) & (L(:,1:end-1) ~= L(:,2:end));
down_diff = valid(1:end-1,:) & valid(2:end,:) & (L(1:end-1,:) ~= L(2:end,:));

boundary_mask(:,1:end-1) = boundary_mask(:,1:end-1) | right_diff;
boundary_mask(:,2:end) = boundary_mask(:,2:end) | right_diff;
boundary_mask(1:end-1,:) = boundary_mask(1:end-1,:) | down_diff;
boundary_mask(2:end,:) = boundary_mask(2:end,:) | down_diff;
end

function boundary_mask = getWatershedBoundaryMask(ws_labels)
boundary_mask = (ws_labels == 0);
boundary_mask = boundary_mask | getLabelBoundaryMask(ws_labels);
end

function makeLegacyValleyFigure(I_rgb, centroids, valid_flag, annulus_masks, crop_boxes, valley_px_a, imageName, outputDir, r_inner_px, r_outer_px, refPlane_um, Z_raw, Z_smooth) %#ok<DEFNU>
fig = figure('Name', 'Valley finding diagnostic', 'Position', [40 40 1400 700], 'Color', 'w');
ax1 = subplot(1, 2, 1);
imshow(I_rgb, 'Parent', ax1); hold(ax1, 'on');
annulus_global = false(size(I_rgb,1), size(I_rgb,2));
for k = 1:size(centroids,1)
    if isempty(annulus_masks{k}), continue; end
    box = crop_boxes(k,:);
    annulus_global(box(1):box(2), box(3):box(4)) = annulus_global(box(1):box(2), box(3):box(4)) | annulus_masks{k};
end
overlay = zeros(size(I_rgb), 'uint8');
overlay(:,:,1) = uint8(annulus_global) * 210;
overlay(:,:,2) = uint8(annulus_global) * 185;
h = imshow(overlay, 'Parent', ax1);
h.AlphaData = double(annulus_global) * 0.28;
vp = false(size(annulus_global));
valid_rows = all(isfinite(valley_px_a), 2);
vp(sub2ind(size(vp), valley_px_a(valid_rows,1), valley_px_a(valid_rows,2))) = true;
vp = imdilate(vp, strel('disk', 2));
vp_overlay = zeros(size(I_rgb), 'uint8');
vp_overlay(:,:,2) = uint8(vp) * 220;
vp_overlay(:,:,3) = uint8(vp) * 220;
h2 = imshow(vp_overlay, 'Parent', ax1);
h2.AlphaData = double(vp) * 0.9;
plot(ax1, centroids(valid_flag,1), centroids(valid_flag,2), 'r+', 'MarkerSize', 5, 'LineWidth', 0.8);
if any(~valid_flag)
    plot(ax1, centroids(~valid_flag,1), centroids(~valid_flag,2), 'x', 'Color', [0.55 0.55 0.55], 'MarkerSize', 5);
end
title(ax1, sprintf('Legacy Method A annulus overlay (n=%d valid)', sum(valid_flag)), 'FontSize', 9);
hold(ax1, 'off');

ax2 = subplot(1, 2, 2);
prof_row = max(1, min(size(Z_raw,1), round(median(centroids(valid_flag,2)))));
plot(ax2, Z_raw(prof_row,:), '-', 'Color', [0.55 0.55 0.55], 'LineWidth', 0.7); hold(ax2, 'on');
plot(ax2, Z_smooth(prof_row,:), '-', 'Color', [0.2 0.5 0.85], 'LineWidth', 1.5);
yline(ax2, refPlane_um, 'k--', 'LineWidth', 1.3, 'Label', sprintf('refPlane %.2f', refPlane_um));
xline(ax2, mean([r_inner_px r_outer_px]), '--', 'Color', [0.8 0.6 0], 'LineWidth', 1.2, ...
    'Label', sprintf('annulus %.1f-%.1f px', r_inner_px, r_outer_px));
xlabel(ax2, 'x (px)'); ylabel(ax2, 'Height (µm)');
title(ax2, sprintf('Centreline profile for legacy annulus context (row %d)', prof_row), 'FontSize', 9);
grid(ax2, 'on'); hold(ax2, 'off');

sgtitle(fig, sprintf('%s | Legacy valley diagnostic', imageName), 'Interpreter', 'none');
outPath = fullfile(outputDir, [imageName '_valley_diag.png']);
exportgraphics(fig, outPath, 'Resolution', 150);
fprintf('  Saved: %s\n', outPath);
end

function makeMethodComparisonFigure(I_rgb, centroids, valid_flag_nn, circle_masks, crop_boxes, valley_px_b, imageName, outputDir, rv_a, rv_b, both_valid, nn_radius_px, xy, height_a, height_b, n_valid_a, n_valid_nn) %#ok<DEFNU>
fig = figure('Name', 'Valley diagnostic - Method B', 'Position', [50 50 1500 650], 'Color', 'w');
ax1 = subplot(1, 3, 1);
imshow(I_rgb, 'Parent', ax1); hold(ax1, 'on');
circle_global = false(size(I_rgb,1), size(I_rgb,2));
for k = 1:size(centroids,1)
    if isempty(circle_masks{k}), continue; end
    box = crop_boxes(k,:);
    circle_global(box(1):box(2), box(3):box(4)) = circle_global(box(1):box(2), box(3):box(4)) | circle_masks{k};
end
overlay = zeros(size(I_rgb), 'uint8');
overlay(:,:,2) = uint8(circle_global) * 190;
overlay(:,:,3) = uint8(circle_global) * 80;
h = imshow(overlay, 'Parent', ax1);
h.AlphaData = double(circle_global) * 0.22;
vp = false(size(circle_global));
valid_rows = all(isfinite(valley_px_b), 2);
vp(sub2ind(size(vp), valley_px_b(valid_rows,1), valley_px_b(valid_rows,2))) = true;
vp = imdilate(vp, strel('disk', 2));
vp_overlay = zeros(size(I_rgb), 'uint8');
vp_overlay(:,:,2) = uint8(vp) * 220;
vp_overlay(:,:,3) = uint8(vp) * 220;
h2 = imshow(vp_overlay, 'Parent', ax1);
h2.AlphaData = double(vp) * 0.9;
plot(ax1, centroids(valid_flag_nn,1), centroids(valid_flag_nn,2), 'r+', 'MarkerSize', 5, 'LineWidth', 0.8);
if any(~valid_flag_nn)
    plot(ax1, centroids(~valid_flag_nn,1), centroids(~valid_flag_nn,2), 'x', 'Color', [0.55 0.55 0.55], 'MarkerSize', 5);
end
title(ax1, sprintf('Preferred Method B circles (n=%d valid)', n_valid_nn), 'FontSize', 9);
hold(ax1, 'off');

ax2 = subplot(1, 3, 2);
if any(both_valid)
    rvA = rv_a(both_valid);
    rvB = rv_b(both_valid);
    scatter(ax2, rvA, rvB, 30, nn_radius_px(both_valid) * xy, 'filled', 'MarkerFaceAlpha', 0.75);
    hold(ax2, 'on');
    lims = [min([rvA; rvB]), max([rvA; rvB])];
    plot(ax2, lims, lims, 'k--', 'LineWidth', 1.2);
    pfit = polyfit(rvA, rvB, 1);
    xx = linspace(lims(1), lims(2), 100);
    plot(ax2, xx, polyval(pfit, xx), 'r-', 'LineWidth', 1.2);
    cb = colorbar(ax2);
    cb.Label.String = 'NN radius (µm)';
    xlabel(ax2, 'Rv - Method A (µm)');
    ylabel(ax2, 'Rv - Method B (µm)');
    title(ax2, sprintf('Paired Rv comparison (n=%d)', sum(both_valid)), 'FontSize', 9);
    legend(ax2, {'Mounds', '1:1 line', 'Linear fit'}, 'Location', 'northwest');
    grid(ax2, 'on');
    hold(ax2, 'off');
else
    axis(ax2, 'off');
    text(ax2, 0.5, 0.5, 'No paired valid mounds', 'HorizontalAlignment', 'center');
end

ax3 = subplot(1, 3, 3);
all_heights = [height_a; height_b];
edges = linspace(min(all_heights) * 0.9, max(all_heights) * 1.05, 31);
histogram(ax3, height_a, edges, 'FaceColor', [0.25 0.55 0.85], 'EdgeColor', 'none', 'FaceAlpha', 0.65); hold(ax3, 'on');
histogram(ax3, height_b, edges, 'FaceColor', [0.90 0.50 0.15], 'EdgeColor', 'none', 'FaceAlpha', 0.65);
xline(ax3, mean(height_a), '-', 'Color', [0.10 0.35 0.75], 'LineWidth', 1.8);
xline(ax3, mean(height_b), '-', 'Color', [0.75 0.30 0.05], 'LineWidth', 1.8);
xlabel(ax3, 'Mound height peak-valley (µm)');
ylabel(ax3, 'Count');
legend(ax3, {sprintf('Method A (n=%d)', n_valid_a), sprintf('Method B (n=%d)', n_valid_nn)}, 'Location', 'northeast');
title(ax3, 'Mound height distribution - method comparison', 'FontSize', 9);
grid(ax3, 'on'); hold(ax3, 'off');

sgtitle(fig, sprintf('%s | Valley method comparison', imageName), 'Interpreter', 'none');
outPath = fullfile(outputDir, [imageName '_valley_nn_diag.png']);
exportgraphics(fig, outPath, 'Resolution', 150);
fprintf('  Saved: %s\n', outPath);
end

function makeShapeOverlayFigure(I_rgb, imageName, outputDir, centroids, preferred_valid_flag, cx_v, cy_v, diam_v, height_v, ar_v, xy)
fig = figure('Name', 'Mound shape overlay', 'Position', [60 60 1200 900], 'Color', 'w');
imshow(I_rgb); hold on;
theta = linspace(0, 2*pi, 80);
cmap = parula(256);
hlim_lo = prctile(height_v, 5);
hlim_hi = prctile(height_v, 95);
for k = 1:numel(height_v)
    t = (height_v(k) - hlim_lo) / max(hlim_hi - hlim_lo, eps);
    cidx = max(1, min(256, round(t * 255) + 1));
    col = cmap(cidx, :);
    r_px = (diam_v(k) / 2) / xy;
    plot(cx_v(k) + r_px * cos(theta), cy_v(k) + r_px * sin(theta), '-', 'Color', col, 'LineWidth', 1.0);
    plot(cx_v(k), cy_v(k), 'o', 'MarkerSize', 4, 'MarkerFaceColor', col, 'MarkerEdgeColor', 'w', 'LineWidth', 0.5);
end
if any(~preferred_valid_flag)
    plot(centroids(~preferred_valid_flag,1), centroids(~preferred_valid_flag,2), 'x', 'Color', [0.55 0.55 0.55], 'MarkerSize', 5);
end
colormap(gca, parula);
clim([hlim_lo, hlim_hi]);
cb = colorbar('Location', 'eastoutside');
cb.Label.String = 'Preferred mound height (µm)';
title(sprintf('%s | %d preferred mounds | height %.1f +/- %.1f µm | AR %.3f +/- %.3f', ...
    imageName, numel(height_v), mean(height_v), std(height_v), mean(ar_v), std(ar_v)), ...
    'Interpreter', 'none', 'FontSize', 10);
hold off;
outPath = fullfile(outputDir, [imageName '_mound_shapes.png']);
exportgraphics(fig, outPath, 'Resolution', 150);
fprintf('  Saved: %s\n', outPath);
end

function makeMorphologyHistFigure(imageName, outputDir, peak_v, valley_v, height_v, fp_v, diam_v, ar_v, fmax_v, fmin_v, fratio_v, circ_v, solid_v, convexity_v)
fig = figure('Name', 'Mound shape distributions', 'Position', [100 100 1500 900], 'Color', 'w');
data = {peak_v, valley_v, height_v, fp_v, diam_v, ar_v, fmax_v, fmin_v, fratio_v, circ_v, solid_v, convexity_v};
labels = {'Peak Z (µm)', 'Valley Z (µm)', 'Mound height (µm)', 'Footprint area (µm²)', ...
    'Equiv. diameter (µm)', 'Aspect ratio h/d', 'Feret max (µm)', 'Feret min (µm)', ...
    'Feret aspect ratio', 'Circularity', 'Solidity', 'Convexity'};
titles = {'Peak height', 'Preferred valley floor', 'Preferred mound height', 'Raw half-max footprint area', ...
    'Equivalent diameter', 'Height-to-diameter ratio', 'Maximum Feret diameter', 'Minimum Feret diameter', ...
    'Feret aspect ratio', 'Footprint circularity', 'Footprint solidity', 'Footprint convexity'};
for i = 1:12
    ax = subplot(3, 4, i);
    histogram(ax, data{i}, 30, 'FaceColor', [0.25 0.55 0.85], 'EdgeColor', 'none', 'FaceAlpha', 0.85);
    hold(ax, 'on');
    xline(ax, mean(data{i}), 'r-', 'LineWidth', 1.6, 'Label', sprintf('mean = %.2f', mean(data{i})));
    xline(ax, median(data{i}), 'k--', 'LineWidth', 1.0, 'Label', sprintf('med = %.2f', median(data{i})));
    xlabel(ax, labels{i});
    ylabel(ax, 'Count');
    title(ax, titles{i});
    grid(ax, 'on');
    hold(ax, 'off');
end
sgtitle(fig, sprintf('%s | Preferred footprint and roughness distributions', imageName), 'Interpreter', 'none');
outPath = fullfile(outputDir, [imageName '_mound_hist.png']);
exportgraphics(fig, outPath, 'Resolution', 150);
fprintf('  Saved: %s\n', outPath);
end

function makeRzDiagFigure(imageName, outputDir, rp_v, rv_v, rz_v, Z_raw, Z_smooth, refPlane_um, Rp_global, Rv_global, Rz_global, cx_v, cy_v, peak_v, nn_mean_px, xy)
fig = figure('Name', 'Rp Rv Rz diagnostic', 'Position', [140 140 1300 560], 'Color', 'w');
ax1 = subplot(1, 2, 1);
all_vals = [rp_v; rv_v; rz_v];
edges = linspace(floor(min(all_vals) * 10) / 10, ceil(max(all_vals) * 10) / 10, 31);
histogram(ax1, rp_v, edges, 'FaceColor', [0.25 0.55 0.85], 'EdgeColor', 'none', 'FaceAlpha', 0.75); hold(ax1, 'on');
histogram(ax1, rv_v, edges, 'FaceColor', [0.85 0.40 0.20], 'EdgeColor', 'none', 'FaceAlpha', 0.75);
histogram(ax1, rz_v, edges, 'FaceColor', [0.45 0.65 0.25], 'EdgeColor', 'none', 'FaceAlpha', 0.55);
xline(ax1, mean(rp_v), '-', 'LineWidth', 1.8, 'Color', [0.10 0.35 0.75], 'Label', sprintf('mean Rp = %.2f', mean(rp_v)));
xline(ax1, mean(rv_v), '-', 'LineWidth', 1.8, 'Color', [0.75 0.25 0.10], 'Label', sprintf('mean Rv = %.2f', mean(rv_v)));
xline(ax1, mean(rz_v), '-', 'LineWidth', 1.8, 'Color', [0.25 0.55 0.15], 'Label', sprintf('mean Rz = %.2f', mean(rz_v)));
legend(ax1, {'Rp', 'Rv', 'Rz per mound'}, 'Location', 'northwest');
xlabel(ax1, 'Distance from reference plane (µm)');
ylabel(ax1, 'Mound count');
title(ax1, 'Preferred per-mound roughness distributions');
grid(ax1, 'on'); hold(ax1, 'off');

ax2 = subplot(1, 2, 2);
prof_row = max(1, min(size(Z_raw,1), round(median(cy_v))));
z_raw_prof = Z_raw(prof_row, :);
x_um = (1:size(Z_raw,2)) * xy;
plot(ax2, x_um, z_raw_prof, '-', 'Color', [0.55 0.55 0.55], 'LineWidth', 0.7); hold(ax2, 'on');
plot(ax2, x_um, Z_smooth(prof_row,:), '-', 'Color', [0.2 0.5 0.85], 'LineWidth', 1.5);
yline(ax2, refPlane_um, 'k--', 'LineWidth', 1.5, 'Label', sprintf('refPlane = %.2f', refPlane_um));
annotation_x = x_um(round(0.88 * numel(x_um)));
plot(ax2, [annotation_x annotation_x], [refPlane_um max(z_raw_prof)], 'r-', 'LineWidth', 1.5);
text(ax2, annotation_x * 1.005, mean([refPlane_um max(z_raw_prof)]), sprintf('Rp=%.1fµm', Rp_global), 'Color', 'r', 'FontSize', 8, 'FontWeight', 'bold');
plot(ax2, [annotation_x annotation_x], [min(z_raw_prof) refPlane_um], '-', 'Color', [0.85 0.40 0.20], 'LineWidth', 1.5);
text(ax2, annotation_x * 1.005, mean([min(z_raw_prof) refPlane_um]), sprintf('Rv=%.1fµm', Rv_global), 'Color', [0.85 0.40 0.20], 'FontSize', 8, 'FontWeight', 'bold');
near_row = abs(cy_v - prof_row) < nn_mean_px * 0.4;
if any(near_row)
    plot(ax2, cx_v(near_row) * xy, peak_v(near_row), 'v', 'MarkerSize', 6, 'MarkerFaceColor', [1 0.85 0], 'MarkerEdgeColor', 'w', 'LineWidth', 0.5);
end
legend(ax2, {'Z_{raw}', 'Z_{smooth}', 'Reference plane', 'Rp', 'Rv', 'Mound peaks'}, 'Location', 'southeast', 'FontSize', 8);
xlabel(ax2, 'x (µm)'); ylabel(ax2, 'Height (µm)');
title(ax2, sprintf('Centreline profile (row %d) | Rz = %.2f µm', prof_row, Rz_global));
grid(ax2, 'on'); hold(ax2, 'off');

sgtitle(fig, sprintf('%s | Global Rz = %.2f µm | mean preferred per-mound Rz = %.2f µm', imageName, Rz_global, mean(rz_v)), 'Interpreter', 'none', 'FontSize', 10);
outPath = fullfile(outputDir, [imageName '_rz_diag.png']);
exportgraphics(fig, outPath, 'Resolution', 150);
fprintf('  Saved: %s\n', outPath);
end

function makeMethodBCComparisonFigure(I_rgb, centroids, valid_flag_b, circle_masks, boundary_band_masks, ...
    crop_boxes_b, boundary_band_boxes, valley_px_b, imageName, outputDir, rv_b, rv_c, ...
    both_valid, nn_radius_px, xy, height_b, height_c, n_valid_b, n_valid_c)
fig = figure('Name', 'Valley diagnostic - Methods B and C', 'Position', [50 50 1650 760], 'Color', 'w');

ax1 = subplot(2, 2, 1);
imshow(I_rgb, 'Parent', ax1); hold(ax1, 'on');
circle_global = false(size(I_rgb,1), size(I_rgb,2));
for k = 1:size(centroids,1)
    if isempty(circle_masks{k}), continue; end
    box = crop_boxes_b(k,:);
    circle_global(box(1):box(2), box(3):box(4)) = circle_global(box(1):box(2), box(3):box(4)) | circle_masks{k};
end
overlay_b = zeros(size(I_rgb), 'uint8');
overlay_b(:,:,2) = uint8(circle_global) * 190;
overlay_b(:,:,3) = uint8(circle_global) * 80;
h = imshow(overlay_b, 'Parent', ax1);
h.AlphaData = double(circle_global) * 0.22;
vp = false(size(circle_global));
valid_rows = all(isfinite(valley_px_b), 2);
vp(sub2ind(size(vp), valley_px_b(valid_rows,1), valley_px_b(valid_rows,2))) = true;
vp = imdilate(vp, strel('disk', 2));
vp_overlay = zeros(size(I_rgb), 'uint8');
vp_overlay(:,:,2) = uint8(vp) * 220;
vp_overlay(:,:,3) = uint8(vp) * 220;
h2 = imshow(vp_overlay, 'Parent', ax1);
h2.AlphaData = double(vp) * 0.9;
plot(ax1, centroids(valid_flag_b,1), centroids(valid_flag_b,2), 'g+', 'MarkerSize', 5, 'LineWidth', 0.8);
if any(~valid_flag_b)
    plot(ax1, centroids(~valid_flag_b,1), centroids(~valid_flag_b,2), 'x', 'Color', [0.55 0.55 0.55], 'MarkerSize', 5);
end
title(ax1, sprintf('Method B circles on raw image (n=%d valid)', n_valid_b), 'FontSize', 10);
hold(ax1, 'off');

ax2 = subplot(2, 2, 2);
imshow(I_rgb, 'Parent', ax2); hold(ax2, 'on');
boundary_global = false(size(I_rgb,1), size(I_rgb,2));
for k = 1:size(centroids,1)
    if isempty(boundary_band_masks{k}), continue; end
    box = boundary_band_boxes(k,:);
    boundary_global(box(1):box(2), box(3):box(4)) = boundary_global(box(1):box(2), box(3):box(4)) | boundary_band_masks{k};
end
overlay_c = zeros(size(I_rgb), 'uint8');
overlay_c(:,:,1) = uint8(boundary_global) * 255;
overlay_c(:,:,2) = uint8(boundary_global) * 165;
h = imshow(overlay_c, 'Parent', ax2);
h.AlphaData = double(boundary_global) * 0.45;
plot(ax2, centroids(valid_flag_b,1), centroids(valid_flag_b,2), 'g+', 'MarkerSize', 5, 'LineWidth', 0.8);
if any(~valid_flag_b)
    plot(ax2, centroids(~valid_flag_b,1), centroids(~valid_flag_b,2), 'x', 'Color', [0.55 0.55 0.55], 'MarkerSize', 5);
end
title(ax2, 'Method C two-pixel watershed base band', 'FontSize', 10);
hold(ax2, 'off');

ax3 = subplot(2, 2, 3);
if any(both_valid)
    rvB = rv_b(both_valid);
    rvC = rv_c(both_valid);
    scatter(ax3, rvB, rvC, 30, nn_radius_px(both_valid) * xy, 'filled', 'MarkerFaceAlpha', 0.75);
    hold(ax3, 'on');
    lims = [min([rvB; rvC]), max([rvB; rvC])];
    if diff(lims) < eps
        lims = lims + [-0.1 0.1];
    end
    plot(ax3, lims, lims, 'k--', 'LineWidth', 1.2);
    pfit = polyfit(rvB, rvC, 1);
    xx = linspace(lims(1), lims(2), 100);
    plot(ax3, xx, polyval(pfit, xx), 'r-', 'LineWidth', 1.2);
    cb = colorbar(ax3);
    cb.Label.String = 'NN radius (um)';
    xlabel(ax3, 'Rv - Method B circles (um)');
    ylabel(ax3, 'Base position - Method C (um)');
    title(ax3, sprintf('Paired Rv comparison (n=%d)', sum(both_valid)), 'FontSize', 10);
    legend(ax3, {'Mounds', '1:1 line', 'Linear fit'}, 'Location', 'northwest');
    grid(ax3, 'on');
    hold(ax3, 'off');
else
    axis(ax3, 'off');
    text(ax3, 0.5, 0.5, 'No paired valid mounds', 'HorizontalAlignment', 'center');
end

ax4 = subplot(2, 2, 4);
all_heights = [height_b(:); height_c(:)];
all_heights = all_heights(isfinite(all_heights));
if isempty(all_heights)
    axis(ax4, 'off');
    text(ax4, 0.5, 0.5, 'No valid height data', 'HorizontalAlignment', 'center');
else
    lo = min(all_heights);
    hi = max(all_heights);
    if hi <= lo
        hi = lo + 0.1;
    end
    edges = linspace(lo * 0.9, hi * 1.05, 31);
    histogram(ax4, height_b, edges, 'FaceColor', [0.25 0.55 0.85], 'EdgeColor', 'none', 'FaceAlpha', 0.65); hold(ax4, 'on');
    histogram(ax4, height_c, edges, 'FaceColor', [0.90 0.50 0.15], 'EdgeColor', 'none', 'FaceAlpha', 0.65);
    xline(ax4, mean(height_b, 'omitnan'), '-', 'Color', [0.10 0.35 0.75], 'LineWidth', 1.8);
    xline(ax4, mean(height_c, 'omitnan'), '-', 'Color', [0.75 0.30 0.05], 'LineWidth', 1.8);
    xlabel(ax4, 'Height / base-position magnitude (um)');
    ylabel(ax4, 'Count');
    legend(ax4, {sprintf('Method B (n=%d)', n_valid_b), sprintf('Method C (n=%d)', n_valid_c)}, 'Location', 'northeast');
    title(ax4, 'Mound height distribution - method comparison', 'FontSize', 10);
    grid(ax4, 'on');
    hold(ax4, 'off');
end

sgtitle(fig, sprintf('%s | Valley method comparison: Method B vs Method C', imageName), 'Interpreter', 'none');
outPath = fullfile(outputDir, [imageName '_valley_method_compare.png']);
exportgraphics(fig, outPath, 'Resolution', 150);
fprintf('  Saved: %s\n', outPath);
end
