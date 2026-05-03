function cavResults = analyzeCavities(m1, min_depth_um, fillDeepPits, fillThreshold, reflThreshold, outputDir)
% =========================================================================
%  analyzeCavities  —  Module 2: Cavity geometry from LSCM height map
%
%  USAGE:
%    cavResults = analyzeCavities(m1)
%    cavResults = analyzeCavities(m1, 2.0, false, 0.3)
%    cavResults = analyzeCavities(m1, 2.0, true, 0.52, 0.35)
%    cavResults = analyzeCavities(m1, 2.0, true, 0.52, 0.35, 'output_folder')
%
%  INPUTS:
%    m1             - results struct from analyzeMounds (Module 1)
%    min_depth_um   - depth threshold in µm (default: 2.0 µm)
%    fillDeepPits   - boolean; true to correct reflection artifacts
%                    (default: false)
%    fillThreshold  - intensity threshold used to locate pit regions
%                    (same value used in autoTuneMounds; default: 0.3)
%    reflThreshold  - intensity threshold to identify reflection pixels
%                    within pit regions; from pickReflectionThreshold
%                    (default: auto — mean + 0.5*std of pit pixel values)
%    outputDir      - (optional) output folder; default = same as Module 1
%
%  OUTPUTS (struct fields):
%    n_cavities        - number of cavities passing depth filter
%    n_shallow         - number of basins below depth threshold
%    depth_um          - cavity depths in µm
%    r_mouth_um        - equivalent mouth radii in µm
%    beta_deg          - cone half-angles in degrees
%    n_bounding_mounds - number of mounds surrounding each cavity
%%    mouth_area_um2    - mouth cross-section areas in µm²
%    valley_z_um       - valley floor heights in µm
%    mouth_z_um        - mouth plane heights in µm (mean of surrounding peaks)
%    centroid_px       - Nx2 basin centroid positions in pixels
%    basin_label       - label image (0=background, i=cavity i)
%    ... (see also per-cavity table in Excel output)
%
%  SAVES:
%    <n>_cavities.png      - cavity overlay on height map
%    <n>_cavity_hist.png   - depth / radius / angle histograms
%    <n>_cavities.xlsx     - per-cavity table + summary
%    <n>_cavities.mat      - full cavResults struct
%
%  REQUIRES: Image Processing Toolbox
% =========================================================================

% --- Defaults and setup --------------------------------------------------
if nargin < 2 || isempty(min_depth_um),   min_depth_um   = 2.0;   end
if nargin < 3 || isempty(fillDeepPits),   fillDeepPits   = false;  end
if nargin < 4 || isempty(fillThreshold),  fillThreshold  = 0.3;    end
if nargin < 5 || isempty(reflThreshold),  reflThreshold  = [];     end  % [] = auto
% Type safety
min_depth_um  = double(min_depth_um);
fillDeepPits  = logical(fillDeepPits);
fillThreshold = double(fillThreshold);

[imageFolder, imageName, ~] = fileparts(m1.imagePath);
if nargin < 6 || isempty(outputDir)
    outputDir = imageFolder;
end
if isempty(outputDir), outputDir = pwd; end
if ~exist(outputDir, 'dir'), mkdir(outputDir); end

fprintf('analyzeCavities: %s\n', imageName);

% Unpack frequently used fields
Z            = m1.Z;                  % height map in µm
centroids    = m1.centroids;          % mound centroids [x,y] in px
xy           = m1.xy_um_per_px;
[imgH, imgW] = size(Z);
nn_mean_px   = m1.nn_mean_px;

% =========================================================================
%  STEP 1: Smooth height map to suppress LSCM noise in valley floors
% =========================================================================
smooth_sigma = 10;
Z_smooth     = imgaussfilt(Z, smooth_sigma);
fprintf('  Height map smoothed (sigma=%d px)\n', smooth_sigma);

% Restrict analysis to the interior of the mound convex hull to avoid
% image-edge artefacts in both reflection handling and watershed seeding.
K         = convhull(centroids(:,1), centroids(:,2));
hull_poly = centroids(K, :);
hull_mask = poly2mask(hull_poly(:,1), hull_poly(:,2), imgH, imgW);

% =========================================================================
%  STEP 2b: Correct reflection artifacts via median fill (fillDeepPits only)
% =========================================================================
% LSCM reflections appear as bright islands inside dark pits, creating
% spurious local Z maxima that displace watershed seeds to the surrounding
% dark ring rather than the pit center.
%
% Strategy: locate the reflection as the regional maximum within each pit
% region, then replace it with the median Z of a narrow annulus just outside
% it — the dark ring pixels, which are genuine measurements. This is stable,
% requires no matrix fitting, and keeps the fill value grounded in real data.
% The replaced region becomes a flat area whose minimum (used as seed) falls
% at its geometric center — the correct pit location.
%
% Cavities where any pixel was replaced are flagged as 'corrected' in output.
inpaint_mask = false(imgH, imgW);
if fillDeepPits
    fprintf('  Correcting reflection artifacts (fillThreshold=%.3f)...\n', fillThreshold);

    % Use display image stored by analyzeMounds — works for VK4 and BMP.
    % For VK4 input, I_raw is derived from Z (uint8 scaled 0-255) so
    % imbinarize and intensity thresholds work identically to BMP input.
    I_raw_inp = m1.I_raw;
    I_double  = double(I_raw_inp) / 255;

    % Pit mask from high threshold (covers reflection + surrounding dark ring)
    BW_high  = imbinarize(I_raw_inp, double(fillThreshold));
    filled   = imcomplement(imfill(imcomplement(BW_high), 'holes'));
    pit_mask = ~filled & hull_mask;

    pit_cc      = bwconncomp(pit_mask);
    n_corrected = 0;

    % Diagnostic storage
    diag_data = struct('refl_mask',{}, 'ring_mask',{}, ...
                       'region_px',{}, 'replaced',{});

    fprintf('  Total pit regions: %d\n', pit_cc.NumObjects);
    for pi_idx = 1:pit_cc.NumObjects
        region_px = pit_cc.PixelIdxList{pi_idx};
        if numel(region_px) < 9
            fprintf('  Pit %d: too small (%d px), skipping\n', pi_idx, numel(region_px));
            continue;
        end

        % --- Find reflection using reflThreshold within pit ----------------
        % reflThreshold separates bright reflection from dark ring pixels.
        % Auto-computed per-pit if not user-supplied.
        pit_vals = I_double(region_px);
        if isempty(reflThreshold)
            T_refl = mean(pit_vals) + 0.5 * std(pit_vals);
            T_refl = max(0.01, min(0.99, T_refl));
        else
            T_refl = double(reflThreshold);
        end

        refl_local = pit_vals >= T_refl;
        fprintf('  Pit %d: %d px, T_refl=%.3f, refl_px=%d (%.0f%%)\n', ...
                pi_idx, numel(region_px), T_refl, sum(refl_local), ...
                100*sum(refl_local)/numel(region_px));
        if sum(refl_local) < 3
            fprintf('    -> skipped: too few reflection pixels\n'); continue;
        end
        if sum(refl_local) >= numel(region_px)*0.7
            fprintf('    -> skipped: threshold too low (covers >70%% of pit)\n'); continue;
        end

        refl_mask = false(imgH, imgW);
        refl_mask(region_px(refl_local)) = true;
        refl_mask = imdilate(refl_mask, strel('disk', 2)) & pit_mask;

        refl_px = find(refl_mask);
        if isempty(refl_px)
            fprintf('    -> skipped: refl_mask empty after dilation\n'); continue;
        end

        % --- Dark ring: narrow annulus outside reflection, inside pit ----
        ring_outer = imdilate(refl_mask, strel('disk', 8));
        ring_inner = imdilate(refl_mask, strel('disk', 1));
        ring_mask  = ring_outer & ~ring_inner & pit_mask & ~refl_mask;
        ring_px    = find(ring_mask);

        if numel(ring_px) < 4
            % Fallback: all non-reflection pit pixels
            ring_px = setdiff(region_px, refl_px);
        end
        if numel(ring_px) < 4, continue; end

        % Median Z of dark ring — genuine measured depth, no extrapolation
        fill_z = median(Z_smooth(ring_px));

        % Replace reflection pixels with fill_z only where Z > fill_z
        current_z = Z_smooth(refl_px);
        replace   = current_z > fill_z;

        [ry_c, rx_c] = ind2sub([imgH imgW], region_px);
        diag_data(end+1) = struct( ...
            'refl_mask', refl_mask, ...
            'ring_mask', ring_mask, ...
            'region_px', region_px, ...
            'replaced',  any(replace)); %#ok<AGROW>

        if any(replace)
            Z_smooth(refl_px(replace)) = fill_z;
            inpaint_mask(refl_px(replace)) = true;
            n_corrected = n_corrected + 1;
        end
    end
    fprintf('  Corrected %d reflection(s) (%d pixels)\n', ...
            n_corrected, sum(inpaint_mask(:)));

    % --- Diagnostic figure -----------------------------------------------
    fprintf('  diag_data has %d entries\n', numel(diag_data));
    if ~isempty(diag_data)
        n_show = min(numel(diag_data), 12);
        n_cols = 4;
        n_rows = ceil(n_show / n_cols);
        fig_inp = figure('Name','Reflection correction diagnostic', ...
                         'Position',[50 50 1400 350*n_rows],'Color','w');
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

            % Build RGB overlay
            Ir = uint8(I_crop * 255);
            Ig = Ir; Ib = Ir;
            % Red: reflection region
            Ir = min(255, Ir + uint8(refl_crop) * 100);
            Ig = uint8(max(0, double(Ig) - double(uint8(refl_crop)) * 60));
            Ib = uint8(max(0, double(Ib) - double(uint8(refl_crop)) * 60));
            % Green: dark ring (fit reference)
            Ir = uint8(max(0, double(Ir) - double(uint8(ring_crop)) * 40));
            Ig = min(255, Ig + uint8(ring_crop) * 100);
            Ib = uint8(max(0, double(Ib) - double(uint8(ring_crop)) * 40));
            % Yellow: replaced pixels
            Ir = min(255, Ir + uint8(inp_crop) * 80);
            Ig = min(255, Ig + uint8(inp_crop) * 80);

            subplot(n_rows, n_cols, k);
            imshow(cat(3, Ir, Ig, Ib));
            status = 'corrected'; if ~dd.replaced, status = 'skipped'; end
            title(sprintf('Pit %d (%s)', k, status), 'FontSize',8);
        end
        sgtitle(sprintf('%s  |  red=reflection  green=dark ring  yellow=replaced', ...
                imageName), 'Interpreter','none','FontSize',9);

        inp_path = fullfile(outputDir, [imageName '_reflection_diag.png']);
        exportgraphics(fig_inp, inp_path, 'Resolution', 150);
        fprintf('  Saved: %s\n', inp_path);
    end
end

% =========================================================================
%  STEP 2: Find valley minima — one seed per cavity
%  Runs AFTER optional reflection correction so seed selection sees the
%  corrected surface rather than the pre-correction artifact geometry.
% =========================================================================
min_pts = computeValleySeeds(Z_smooth, hull_mask, centroids, nn_mean_px, m1.dt);

% =========================================================================
%  STEP 3: Watershed on inverted smoothed Z, seeded by valley minima
% =========================================================================
% Build seed marker image — one label per validated minimum
seed_img = zeros(imgH, imgW, 'uint32');
for k = 1:size(min_pts,1)
    r = max(1, min(imgH, round(min_pts(k,2))));
    c = max(1, min(imgW, round(min_pts(k,1))));
    seed_img(r, c) = k;
end

% Impose minima at seed locations and run watershed on Z_smooth directly.
% Basins grow from valley floors UPWARD to the saddle/ridge between mounds.
% max(Z within basin) = ridge height = cavity mouth plane
% min(Z within basin) = valley floor
% Using -Z_smooth was wrong: it made mound peaks the lowest points,
% producing near-zero depth basins centred on peaks rather than valleys.
Z_imposed = imimposemin(Z_smooth, seed_img > 0);      % suppress all other minima
L_raw     = watershed(Z_imposed);                     % 0 = ridge lines, >0 = basins

% Restrict to interior of convex hull
L_raw(~hull_mask) = 0;

% Re-label sequentially (watershed labels don't align with seed indices)
% Match each seed to its basin label
basin_labels = zeros(size(min_pts,1), 1);
for k = 1:size(min_pts,1)
    r = max(1, min(imgH, round(min_pts(k,2))));
    c = max(1, min(imgW, round(min_pts(k,1))));
    basin_labels(k) = L_raw(r, c);
end

% Build clean label image with sequential indices
L = zeros(imgH, imgW, 'uint32');
valid_basins = basin_labels > 0;
seq_idx = 0;
seq_map = containers.Map('KeyType','uint32','ValueType','uint32');
for k = 1:size(min_pts,1)
    if ~valid_basins(k), continue; end
    lbl = basin_labels(k);
    if ~isKey(seq_map, lbl)
        seq_idx = seq_idx + 1;
        seq_map(lbl) = seq_idx;
    end
    L(L_raw == lbl) = seq_map(lbl);
end
n_basins = seq_idx;
fprintf('  Watershed complete: %d basins\n', n_basins);

% Remove basins that touch the image border
L = removeBorderBasins(L, hull_mask);
remaining = unique(L); remaining(remaining==0) = [];
n_basins  = numel(remaining);
fprintf('  After border removal: %d basins\n', n_basins);

% =========================================================================
%  STEP 4: Per-cavity geometry
% =========================================================================
fprintf('  Computing cavity geometry...\n');

% Pre-compute mound peak heights from Z_raw at centroid locations.
% Cavity depth is intended as a physical height measurement, so use raw Z
% rather than smoothed Z for peak and valley magnitudes.
peak_z = zeros(size(centroids,1), 1);
for k = 1:size(centroids,1)
    r = max(1, min(imgH, round(centroids(k,2))));
    c = max(1, min(imgW,  round(centroids(k,1))));
    peak_z(k) = Z(r, c);
end

% Allocate output arrays
depth_um            = nan(n_basins, 1);
r_mouth_um          = nan(n_basins, 1);
mouth_area_um2      = nan(n_basins, 1);
beta_deg            = nan(n_basins, 1);
n_bounding_mounds   = nan(n_basins, 1);
is_inpainted        = false(n_basins, 1);  % true if depth was model-estimated
bounding_mound_idx  = cell(n_basins, 1);   % indices into centroids array
valley_z_um         = nan(n_basins, 1);
mouth_z_um          = nan(n_basins, 1);
basin_cx_px         = nan(n_basins, 1);
basin_cy_px         = nan(n_basins, 1);

for bi = 1:n_basins
    lbl  = remaining(bi);
    mask = L == lbl;

    % Basin centroid (computed directly from pixel coordinates to avoid
    % regionprops struct-array indexing issues with multi-component masks)
    [rows, cols]    = find(mask);
    basin_cx_px(bi) = mean(cols);
    basin_cy_px(bi) = mean(rows);

    % Valley floor: minimum raw z in basin.
    % The basin geometry comes from Z_smooth, but the reported depth uses
    % the underlying calibrated raw heights.
    z_vals          = Z(mask);
    valley_z_um(bi) = min(z_vals);
    % Flag if any inpainted pixel falls in this basin (depth is model-estimated)
    is_inpainted(bi) = any(inpaint_mask(mask));

    % Bounding mounds: centroids within 1.2 * mean_NN_spacing of basin center
    dists_to_mounds   = sqrt((centroids(:,1) - basin_cx_px(bi)).^2 + ...
                             (centroids(:,2) - basin_cy_px(bi)).^2);
    nearby_idx        = dists_to_mounds < 1.2 * nn_mean_px;
    if sum(nearby_idx) < 2
        [~, sorted] = sort(dists_to_mounds);
        nearby_idx  = false(size(centroids,1),1);
        nearby_idx(sorted(1:min(3,end))) = true;
    end
    n_bounding_mounds(bi)  = sum(nearby_idx);
    bounding_mound_idx{bi} = find(nearby_idx);

    % --- Mouth plane and cross-sectional radius -----------------------------
    %
    % --- Inscribed circle radius at mouth plane -------------------------
    % The mouth radius is the radius of the largest circle that fits
    % entirely inside the cavity cross-section at the mouth plane height.
    % This maximises the radius while guaranteeing no cone-mound intersection
    % by definition — it is the tightest meaningful estimate available.
    %
    % Method: compute bwdist on the binary mouth mask. The distance transform
    % gives each pixel its distance to the nearest non-cavity pixel. The
    % maximum of this within the cavity mask is the inscribed circle radius.
    %
    % Mouth plane: minimum of nearby peak heights — the lowest surrounding
    % mound top, giving the most conservative opening threshold.
    mouth_z_target = min(peak_z(nearby_idx));
    mouth_z_um(bi) = mouth_z_target;
    d              = mouth_z_um(bi) - valley_z_um(bi);
    depth_um(bi)   = max(d, 0.001);

    % Binary mouth mask: cavity pixels below the mouth plane.
    % Use raw Z so the opening threshold is measured on the same surface
    % used for peak/valley depth.
    mouth_mask_bi = mask & (Z <= mouth_z_target);
    if sum(mouth_mask_bi(:)) < 4
        mouth_mask_bi = mask;   % fallback to full basin if mask is tiny
    end

    % Distance transform: each pixel's distance to nearest non-cavity pixel
    D_mouth          = bwdist(~mouth_mask_bi);
    r_inscribed_px   = max(D_mouth(mouth_mask_bi));

    % Fallback if distance transform gives zero (degenerate mask)
    if r_inscribed_px < 1
        r_inscribed_px = sqrt(sum(mouth_mask_bi(:)) / pi);
    end

    r_mouth_um(bi)     = r_inscribed_px * xy;
    mouth_area_um2(bi) = pi * r_mouth_um(bi)^2;
    if d > 0
        beta_deg(bi) = atand(r_mouth_um(bi) / d);
    end
end

% =========================================================================
%  STEP 5: Apply depth filter
% =========================================================================
is_real   = depth_um >= min_depth_um & ~isnan(depth_um);
n_real    = sum(is_real);
n_shallow = sum(~is_real);
fprintf('  Cavities >= %.1f µm depth: %d\n', min_depth_um, n_real);
fprintf('  Shallow basins (filtered): %d\n', n_shallow);

% Filtered arrays
d_f   = depth_um(is_real);
r_f   = r_mouth_um(is_real);
b_f   = beta_deg(is_real);
nb_f  = n_bounding_mounds(is_real);
ma_f  = mouth_area_um2(is_real);
vz_f  = valley_z_um(is_real);
mz_f  = mouth_z_um(is_real);
cx_f       = basin_cx_px(is_real);
inpaint_f  = is_inpainted(is_real);
cy_f     = basin_cy_px(is_real);
bmid_f   = bounding_mound_idx(is_real);   % cell array of bounding mound indices

% =========================================================================
%  STEP 6: Figures
% =========================================================================
fprintf('  Generating figures...\n');

% --- Diagnostic Figure A: Watershed ridgelines + cavity minima -----------
figA = figure('Name','Watershed diagnostic','Position',[30 30 1200 900],'Color','w');

I_rgb_diag = repmat(m1.I_raw, [1 1 3]);
imshow(I_rgb_diag); hold on;

% Overlay watershed ridgelines (L==0 inside hull) in cyan
ridge_mask = (L == 0) & hull_mask;
ridge_overlay = zeros(imgH, imgW, 3, 'uint8');
ridge_overlay(:,:,1) = uint8(ridge_mask) * 0;
ridge_overlay(:,:,2) = uint8(ridge_mask) * 220;
ridge_overlay(:,:,3) = uint8(ridge_mask) * 220;
h_r = imshow(ridge_overlay);
h_r.AlphaData = double(ridge_mask) * 0.55;

% All cavity minima (seeds) — colour by whether they passed depth filter
% Real cavities: yellow circles; shallow: grey x
for k = 1:size(min_pts,1)
    is_r = any(abs(cx_f - min_pts(k,1)) < 3 & abs(cy_f - min_pts(k,2)) < 3);
    if is_r
        plot(min_pts(k,1), min_pts(k,2), 'o', ...
             'MarkerSize',7,'MarkerFaceColor',[1 0.9 0],...
             'MarkerEdgeColor','w','LineWidth',0.8);
    else
        plot(min_pts(k,1), min_pts(k,2), 'x', ...
             'MarkerSize',5,'Color',[0.6 0.6 0.6],'LineWidth',0.8);
    end
end

% Mound centroids for spatial reference
plot(centroids(:,1), centroids(:,2), 'r+', 'MarkerSize',5,'LineWidth',0.8);

legend({'Ridgelines','Real cavity min','Shallow min','Mound centroids'}, ...
       'Location','northeast','TextColor','w','Color',[0.2 0.2 0.2]);
title(sprintf('%s  |  Watershed ridgelines + cavity seeds  |  %d real  %d shallow', ...
      imageName, n_real, n_shallow), 'Interpreter','none','Color','w','FontSize',10);
set(gca,'Color','k');
hold off;

diagA_path = fullfile(outputDir, [imageName '_watershed_diag.png']);
exportgraphics(figA, diagA_path, 'Resolution',150);
fprintf('  Saved: %s\n', diagA_path);

% --- Diagnostic Figure B: 3D surface + cavity cones ----------------------
figB = figure('Name','3D surface + cavity cones',...
              'Position',[60 60 1200 850],'Color','w');

ax3d = axes('Parent', figB);

% Downsample Z_smooth for 3D plot (full resolution is very slow to render)
ds = 4;   % downsample factor — increase if slow
Zd = Z_smooth(1:ds:end, 1:ds:end);
[Xd, Yd] = meshgrid((1:ds:imgW)*xy, (1:ds:imgH)*xy);   % in µm

surf(ax3d, Xd, Yd, Zd, ...
     'EdgeColor','none','FaceColor','interp','FaceAlpha',0.85);
colormap(ax3d, gray);
hold(ax3d, 'on');

% Draw each real cavity as a cone: apex at valley floor, base at mouth plane
% The cone is drawn as a set of lines from apex to a circle at mouth height
n_cone_pts = 32;
theta_c    = linspace(0, 2*pi, n_cone_pts);
cmap_cone  = parula(256);
dlim_lo_3d = prctile(d_f, 5);
dlim_hi_3d = prctile(d_f, 95);

for k = 1:n_real
    % Colour by depth
    t    = (d_f(k) - dlim_lo_3d) / max(dlim_hi_3d - dlim_lo_3d, eps);
    t    = max(0, min(1, t));
    cidx = max(1, round(t*255)+1);
    col  = cmap_cone(cidx,:);

    % Cone apex: cavity minimum in µm coordinates
    cx_um  = cx_f(k) * xy;
    cy_um  = cy_f(k) * xy;
    z_apex = vz_f(k);
    z_mouth = mz_f(k);
    r_um   = r_f(k);

    % Cone base circle at mouth plane height
    base_x = cx_um + r_um * cos(theta_c);
    base_y = cy_um + r_um * sin(theta_c);
    base_z = repmat(z_mouth, 1, n_cone_pts);

    % Draw lines from apex to base circle
    for j = 1:4:n_cone_pts   % every 4th line to keep it clean
        plot3(ax3d, [cx_um, base_x(j)], [cy_um, base_y(j)], ...
              [z_apex, base_z(j)], '-', 'Color', [col, 0.7], 'LineWidth', 0.8);
    end

    % Draw base circle
    plot3(ax3d, base_x, base_y, base_z, '-', 'Color', col, 'LineWidth', 1.2);

    % Apex dot
    plot3(ax3d, cx_um, cy_um, z_apex, 'o', ...
          'MarkerSize',4,'MarkerFaceColor',col,'MarkerEdgeColor','w','LineWidth',0.5);
end

xlabel(ax3d,'x (µm)'); ylabel(ax3d,'y (µm)'); zlabel(ax3d,'Height (µm)');
colormap(ax3d, parula);
clim(ax3d, [dlim_lo_3d, dlim_hi_3d]);
cb3d = colorbar(ax3d);
cb3d.Label.String = 'Cavity depth (µm)';
title(ax3d, sprintf('%s  |  3D surface + %d cavity cones', imageName, n_real), ...
      'Interpreter','none','FontSize',10);
view(ax3d, -35, 35);
grid(ax3d, 'on');
lighting(ax3d, 'gouraud');
camlight(ax3d, 'headlight');
hold(ax3d, 'off');

diagB_path = fullfile(outputDir, [imageName '_3D_cones.png']);
exportgraphics(figB, diagB_path, 'Resolution',150);
fprintf('  Saved: %s\n', diagB_path);

% --- Figure 1: Cavity overlay on original image --------------------------
fig1 = figure('Name','Cavity map','Position',[50 50 1200 900],'Color','w');

% Original image as RGB so colormap doesn't affect background
I_rgb = repmat(m1.I_raw, [1 1 3]);
imshow(I_rgb); hold on;

if n_real > 0
    cmap2   = parula(256);
    dlim_lo = prctile(d_f, 5);
    dlim_hi = prctile(d_f, 95);
    theta   = linspace(0, 2*pi, 64);   % for drawing circles

    for k = 1:n_real
        % Colour for this cavity (depth-mapped)
        t    = (d_f(k) - dlim_lo) / max(dlim_hi - dlim_lo, eps);
        t    = max(0, min(1, t));
        cidx = max(1, round(t*255)+1);
        col  = cmap2(cidx,:);

        % Mouth radius circle (radius in pixels)
        r_px = r_f(k) / xy;
        circ_x = cx_f(k) + r_px * cos(theta);
        circ_y = cy_f(k) + r_px * sin(theta);
        plot(circ_x, circ_y, '-', 'Color', col, 'LineWidth', 1.2);

        % Lines to bounding mounds
        bm_idx = bmid_f{k};
        for m = 1:numel(bm_idx)
            plot([cx_f(k), centroids(bm_idx(m),1)], ...
                 [cy_f(k), centroids(bm_idx(m),2)], ...
                 '-', 'Color', [col, 0.35], 'LineWidth', 0.7);
        end

        % Cavity centre dot — diamond if depth was model-estimated (inpainted)
        if inpaint_f(k)
            plot(cx_f(k), cy_f(k), 'd', ...
                 'MarkerSize', 7, 'MarkerFaceColor', col, ...
                 'MarkerEdgeColor', 'w', 'LineWidth', 0.8);
        else
            plot(cx_f(k), cy_f(k), 'o', ...
                 'MarkerSize', 5, 'MarkerFaceColor', col, ...
                 'MarkerEdgeColor', 'w', 'LineWidth', 0.5);
        end
    end

    % Bounding mounds — all unique mounds used across all cavities
    all_bm = unique(vertcat(bmid_f{:}));
    plot(centroids(all_bm,1), centroids(all_bm,2), 's', ...
         'MarkerSize', 6, 'MarkerFaceColor', 'none', ...
         'MarkerEdgeColor', [1 0.85 0.1], 'LineWidth', 1.0);

    % All other mound centroids
    other_idx = setdiff(1:size(centroids,1), all_bm);
    if ~isempty(other_idx)
        plot(centroids(other_idx,1), centroids(other_idx,2), '.', ...
             'MarkerSize', 5, 'Color', [0.7 0.7 0.7]);
    end

    % Colourbar (parula mapped to depth)
    colormap(gca, parula);
    clim([dlim_lo, dlim_hi]);
    cb2 = colorbar('Location','eastoutside');
    cb2.Label.String = 'Cavity depth (µm)';
end

% Shallow basins
if n_shallow > 0
    cx_s = basin_cx_px(~is_real & ~isnan(depth_um));
    cy_s = basin_cy_px(~is_real & ~isnan(depth_um));
    plot(cx_s, cy_s, 'x', 'Color', [0.55 0.55 0.55], 'MarkerSize', 4);
end

title(sprintf('%s  |  %d cavities (≥%.1f µm deep)  |  %d shallow', ...
      imageName, n_real, min_depth_um, n_shallow), ...
      'Interpreter','none','FontSize',10, 'Color','w');
set(gca,'Color','k');
hold off;

cav_path = fullfile(outputDir, [imageName '_cavities.png']);
exportgraphics(fig1, cav_path, 'Resolution',150);
fprintf('  Saved: %s\n', cav_path);

% --- Figure 2: Histograms ------------------------------------------------
fig2 = figure('Name','Cavity distributions','Position',[200 200 1100 750],'Color','w');

subplot(2,2,1);
histogram(d_f, 30, 'FaceColor',[0.2 0.5 0.85],'EdgeColor','none');
xline(mean(d_f),'r-','LineWidth',1.5,'Label',sprintf('%.1f µm',mean(d_f)));
xlabel('Depth (µm)'); ylabel('Count'); title('Cavity depth');
grid on;

subplot(2,2,2);
histogram(r_f, 30, 'FaceColor',[0.2 0.75 0.5],'EdgeColor','none');
xline(mean(r_f),'r-','LineWidth',1.5,'Label',sprintf('%.1f µm',mean(r_f)));
xlabel('Mouth radius (µm)'); ylabel('Count'); title('Equivalent mouth radius');
grid on;

subplot(2,2,3);
histogram(b_f, 30, 'FaceColor',[0.85 0.5 0.2],'EdgeColor','none');
xline(mean(b_f),'r-','LineWidth',1.5,'Label',sprintf('%.1f°',mean(b_f)));
xlabel('Cone half-angle β (°)'); ylabel('Count'); title('Cone half-angle');
grid on;

subplot(2,2,4);
histogram(nb_f, 'BinMethod','integers', ...
          'FaceColor',[0.6 0.3 0.7],'EdgeColor','none');
xlabel('Number of bounding mounds'); ylabel('Count');
title('Bounding mound count');
grid on;

sgtitle(sprintf('Cavity analysis — %s  (depth threshold = %.1f µm)', ...
        imageName, min_depth_um), 'Interpreter','none');

hist_path = fullfile(outputDir, [imageName '_cavity_hist.png']);
exportgraphics(fig2, hist_path, 'Resolution',150);
fprintf('  Saved: %s\n', hist_path);

% =========================================================================
%  STEP 7: Excel + MAT output
% =========================================================================
fprintf('  Writing outputs...\n');
xlsx_path = fullfile(outputDir, [imageName '_cavities.xlsx']);

% Sheet 1: per-cavity data
cav_table = table(...
    (1:n_real)', cx_f, cy_f, ...
    cx_f * xy, cy_f * xy, ...
    d_f, r_f, ma_f, b_f, ...
    nb_f, vz_f, mz_f, double(inpaint_f), ...
    'VariableNames', { ...
        'CavityIndex', 'X_px','Y_px','X_um','Y_um', ...
        'Depth_um','MouthRadius_um','MouthArea_um2', ...
        'ConeHalfAngle_deg', ...
        'N_BoundingMounds','ValleyFloor_um','MouthPlane_um','DepthModelEstimated'});
writetable(cav_table, xlsx_path, 'Sheet','Cavities');

% Sheet 2: shallow basins
if n_shallow > 0
    sh_idx = find(~is_real & ~isnan(depth_um));
    shallow_table = table(...
        sh_idx, basin_cx_px(sh_idx), basin_cy_px(sh_idx), ...
        depth_um(sh_idx), ...
        'VariableNames',{'BasinIndex','X_px','Y_px','Depth_um'});
    writetable(shallow_table, xlsx_path, 'Sheet','Shallow_basins');
end

% Sheet 3: summary
summary = table(...
    {imageName}, n_real, n_shallow, min_depth_um, ...
    sum(double(inpaint_f)), ...
    mean(d_f), std(d_f), median(d_f), ...
    mean(r_f), std(r_f), median(r_f), ...
    mean(b_f), std(b_f), ...
    'VariableNames',{ ...
        'ImageName','N_cavities','N_shallow','N_inpainted','DepthThreshold_um', ...
        'Mean_depth_um','Std_depth_um','Median_depth_um', ...
        'Mean_mouthRadius_um','Std_mouthRadius_um','Median_mouthRadius_um', ...
        'Mean_beta_deg','Std_beta_deg'});
writetable(summary, xlsx_path, 'Sheet','Summary');
fprintf('  Saved: %s\n', xlsx_path);

% =========================================================================
%  Assemble output struct
% =========================================================================
cavResults.n_cavities        = n_real;
cavResults.n_shallow         = n_shallow;
cavResults.min_depth_um      = min_depth_um;
cavResults.depth_um          = d_f;
cavResults.r_mouth_um        = r_f;
cavResults.mouth_area_um2    = ma_f;
cavResults.beta_deg          = b_f;
cavResults.n_bounding_mounds = nb_f;
cavResults.valley_z_um       = vz_f;
cavResults.mouth_z_um        = mz_f;
cavResults.centroid_px          = [cx_f, cy_f];
cavResults.is_inpainted         = inpaint_f;
cavResults.bounding_mound_idx   = bmid_f;
cavResults.basin_label       = L;
cavResults.Z_smooth          = Z_smooth;
cavResults.imageName         = imageName;
cavResults.imagePath         = m1.imagePath;
cavResults.m1                = m1;

mat_path = fullfile(outputDir, [imageName '_cavities.mat']);
save(mat_path, 'cavResults');
fprintf('  Saved: %s\n', mat_path);

fprintf('analyzeCavities complete.\n\n');

end % analyzeCavities


% =========================================================================
%  COMPUTE VALLEY SEEDS FROM CORRECTED SURFACE
% =========================================================================
function min_pts = computeValleySeeds(Z_smooth, hull_mask, centroids, nn_mean_px, dt)
min_mask = imregionalmin(Z_smooth) & hull_mask;

min_cc    = bwconncomp(min_mask);
min_props = regionprops(min_cc, 'Centroid');
if isempty(min_props)
    error('analyzeCavities: no valley minima found inside mound hull.');
end
min_pts = cat(1, min_props.Centroid);
fprintf('  Found %d raw valley minima\n', size(min_pts,1));

sep_thresh = nn_mean_px / 2;
[imgH, imgW] = size(Z_smooth);
min_z = zeros(size(min_pts,1), 1);
for k = 1:size(min_pts,1)
    r = max(1, min(imgH, round(min_pts(k,2))));
    c = max(1, min(imgW, round(min_pts(k,1))));
    min_z(k) = Z_smooth(r, c);
end

[~, sort_idx] = sort(min_z);
keep_flag     = true(size(min_pts,1), 1);
for i = 1:numel(sort_idx)
    if ~keep_flag(sort_idx(i)), continue; end
    dists = sqrt((min_pts(:,1) - min_pts(sort_idx(i),1)).^2 + ...
                 (min_pts(:,2) - min_pts(sort_idx(i),2)).^2);
    too_close = dists < sep_thresh;
    too_close(sort_idx(i)) = false;
    keep_flag(too_close) = false;
end
min_pts = min_pts(keep_flag, :);
fprintf('  After separation filter: %d valley seeds\n', size(min_pts,1));

tri_conn  = dt.ConnectivityList;
tri_cents = zeros(size(tri_conn,1), 2);
for t = 1:size(tri_conn,1)
    tri_cents(t,:) = mean(centroids(tri_conn(t,:), :), 1);
end

cross_thresh = 0.6 * nn_mean_px;
valid_seed   = false(size(min_pts,1), 1);
for k = 1:size(min_pts,1)
    d2tri = sqrt((tri_cents(:,1) - min_pts(k,1)).^2 + ...
                 (tri_cents(:,2) - min_pts(k,2)).^2);
    valid_seed(k) = min(d2tri) < cross_thresh;
end
min_pts = min_pts(valid_seed, :);
fprintf('  After Delaunay cross-check: %d cavity seeds\n', size(min_pts,1));

if isempty(min_pts)
    error('analyzeCavities: no valid seeds after cross-check. Try relaxing cross_thresh.');
end
end


% =========================================================================
%  REMOVE BASINS TOUCHING IMAGE BORDER OR OUTSIDE HULL
% =========================================================================
function L = removeBorderBasins(L, hull_mask)
% Remove any labeled basin that:
%   (a) touches the 1-pixel image border, OR
%   (b) has its majority area outside the convex hull mask
[imgH, imgW] = size(L);

% Cast to double for reliable comparisons regardless of input integer type
L = double(L);

% (a) Basins touching the 1-px border
border = false(imgH, imgW);
border(1,:) = true; border(end,:) = true;
border(:,1) = true; border(:,end) = true;
border_labels = unique(L(border));
border_labels(border_labels == 0) = [];
if ~isempty(border_labels)
    L(ismember(L, border_labels)) = 0;
end

% (b) Basins whose majority area falls outside the hull mask
remaining = unique(L(:));
remaining(remaining == 0) = [];
remove_labels = zeros(numel(remaining), 1);
n_remove = 0;
for k = 1:numel(remaining)
    basin_px     = L == remaining(k);
    frac_in_hull = sum(basin_px(:) & hull_mask(:)) / sum(basin_px(:));
    if frac_in_hull < 0.5
        n_remove = n_remove + 1;
        remove_labels(n_remove) = remaining(k);
    end
end
if n_remove > 0
    L(ismember(L, remove_labels(1:n_remove))) = 0;
end
end
