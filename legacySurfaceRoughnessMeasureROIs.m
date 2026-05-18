function results = legacySurfaceRoughnessMeasureROIs(Z, xy_um_per_px, imagePath, rois)
% legacySurfaceRoughnessMeasureROIs
% Compute legacy ROI roughness measurements against a whole-image reference plane.

arguments
    Z (:,:) double
    xy_um_per_px (1,1) double {mustBePositive}
    imagePath char
    rois struct = struct('type', {}, 'x1', {}, 'x2', {}, 'y1', {}, 'y2', {})
end

[imgH, imgW] = size(Z);
image_size_px = [imgW, imgH];
image_size_um = image_size_px .* xy_um_per_px;

refPlane_um = mean(Z(:), 'omitnan');
Rp_global = max(Z(:)) - refPlane_um;
Rv_global = refPlane_um - min(Z(:));
Rz_global = Rp_global + Rv_global;
[surface_area_global_um2, projected_area_global_um2, SA_to_A_ratio_global] = ...
    calculateSurfaceAreaRatio(Z, xy_um_per_px);

perRoiTable = buildPerRoiTable(Z, xy_um_per_px, rois);
n_rois = height(perRoiTable);

[mean_Rp_um, std_Rp_um] = summarizeMetric(perRoiTable.Rp_um);
[mean_Rv_um, std_Rv_um] = summarizeMetric(perRoiTable.Rv_um);
[mean_Rz_um, std_Rz_um] = summarizeMetric(perRoiTable.Rz_um);
[mean_SA_to_A_ratio, std_SA_to_A_ratio] = summarizeMetric(perRoiTable.SA_to_A_ratio);

results = struct();
results.imagePath = imagePath;
results.xy_um_per_px = xy_um_per_px;
results.image_size_px = image_size_px;
results.image_size_um = image_size_um;
results.refPlane_um = refPlane_um;
results.Rp_global = Rp_global;
results.Rv_global = Rv_global;
results.Rz_global = Rz_global;
results.surface_area_global_um2 = surface_area_global_um2;
results.projected_area_global_um2 = projected_area_global_um2;
results.SA_to_A_ratio_global = SA_to_A_ratio_global;
results.roi_table = perRoiTable;
results.n_rois = n_rois;
results.mean_Rp_um = mean_Rp_um;
results.std_Rp_um = std_Rp_um;
results.mean_Rv_um = mean_Rv_um;
results.std_Rv_um = std_Rv_um;
results.mean_Rz_um = mean_Rz_um;
results.std_Rz_um = std_Rz_um;
results.mean_SA_to_A_ratio = mean_SA_to_A_ratio;
results.std_SA_to_A_ratio = std_SA_to_A_ratio;
results.rois = rois;
end

function perRoiTable = buildPerRoiTable(Z, xy_um_per_px, rois)
if isempty(rois)
    perRoiTable = table('Size', [0, 20], ...
        'VariableTypes', {'double', 'string', 'double', 'double', 'double', 'double', ...
                          'double', 'double', 'double', 'double', 'double', 'double', ...
                          'double', 'double', 'double', 'double', 'double', 'double', ...
                          'double', 'double'}, ...
        'VariableNames', {'ROI_Index', 'ROI_Type', 'X_Min_px', 'X_Max_px', 'Y_Min_px', 'Y_Max_px', ...
                          'Center_X_px', 'Center_Y_px', 'Width_px', 'Height_px', ...
                          'Center_X_um', 'Center_Y_um', 'Width_um', 'Height_um', ...
                          'Rp_um', 'Rv_um', 'Rz_um', ...
                          'SurfaceArea_um2', 'ProjectedArea_um2', 'SA_to_A_ratio'});
    return;
end

refPlane_um = mean(Z(:), 'omitnan');
n = numel(rois);

roiIndex = (1:n).';
roiType = strings(n, 1);
xMin = nan(n, 1);
xMax = nan(n, 1);
yMin = nan(n, 1);
yMax = nan(n, 1);
centerXpx = nan(n, 1);
centerYpx = nan(n, 1);
widthPx = nan(n, 1);
heightPx = nan(n, 1);
centerXum = nan(n, 1);
centerYum = nan(n, 1);
widthUm = nan(n, 1);
heightUm = nan(n, 1);
Rp_um = nan(n, 1);
Rv_um = nan(n, 1);
Rz_um = nan(n, 1);
surfaceAreaUm2 = nan(n, 1);
projectedAreaUm2 = nan(n, 1);
SA_to_A_ratio = nan(n, 1);

for i = 1:n
    roi = rois(i);
    roiType(i) = string(roi.type);
    x1 = max(1, round(min(roi.x1, roi.x2)));
    x2 = min(size(Z, 2), round(max(roi.x1, roi.x2)));
    y1 = max(1, round(min(roi.y1, roi.y2)));
    y2 = min(size(Z, 1), round(max(roi.y1, roi.y2)));

    roiZ = Z(y1:y2, x1:x2);

    xMin(i) = x1;
    xMax(i) = x2;
    yMin(i) = y1;
    yMax(i) = y2;
    centerXpx(i) = (x1 + x2) / 2;
    centerYpx(i) = (y1 + y2) / 2;
    widthPx(i) = x2 - x1 + 1;
    heightPx(i) = y2 - y1 + 1;
    centerXum(i) = centerXpx(i) * xy_um_per_px;
    centerYum(i) = centerYpx(i) * xy_um_per_px;
    widthUm(i) = widthPx(i) * xy_um_per_px;
    heightUm(i) = heightPx(i) * xy_um_per_px;
    Rp_um(i) = max(roiZ(:)) - refPlane_um;
    Rv_um(i) = refPlane_um - min(roiZ(:));
    Rz_um(i) = Rp_um(i) + Rv_um(i);
    [surfaceAreaUm2(i), projectedAreaUm2(i), SA_to_A_ratio(i)] = ...
        calculateSurfaceAreaRatio(roiZ, xy_um_per_px);
end

perRoiTable = table(roiIndex, roiType, xMin, xMax, yMin, yMax, centerXpx, centerYpx, ...
    widthPx, heightPx, centerXum, centerYum, widthUm, heightUm, Rp_um, Rv_um, Rz_um, ...
    surfaceAreaUm2, projectedAreaUm2, SA_to_A_ratio, ...
    'VariableNames', {'ROI_Index', 'ROI_Type', 'X_Min_px', 'X_Max_px', 'Y_Min_px', 'Y_Max_px', ...
                      'Center_X_px', 'Center_Y_px', 'Width_px', 'Height_px', ...
                      'Center_X_um', 'Center_Y_um', 'Width_um', 'Height_um', ...
                      'Rp_um', 'Rv_um', 'Rz_um', ...
                      'SurfaceArea_um2', 'ProjectedArea_um2', 'SA_to_A_ratio'});
end

function [surfaceAreaUm2, projectedAreaUm2, ratio] = calculateSurfaceAreaRatio(Zpatch, xy_um_per_px)
% Approximate the VK Analyzer convention found during testing:
% opposite-diagonal cell facets, full finite-pixel projected area, and
% right/bottom edge extension.
if size(Zpatch, 1) < 2 || size(Zpatch, 2) < 2
    surfaceAreaUm2 = NaN;
    projectedAreaUm2 = NaN;
    ratio = NaN;
    return;
end

dx = xy_um_per_px;
[interiorSurfaceAreaUm2, validCells] = calculateOppositeDiagonalInteriorSurface(Zpatch, dx);
if isnan(interiorSurfaceAreaUm2)
    surfaceAreaUm2 = NaN;
    projectedAreaUm2 = NaN;
    ratio = NaN;
    return;
end

surfaceAreaUm2 = interiorSurfaceAreaUm2;
surfaceAreaUm2 = surfaceAreaUm2 + edgeStripArea(Zpatch(end, 1:end-1), Zpatch(end, 2:end), dx);
surfaceAreaUm2 = surfaceAreaUm2 + edgeStripArea(Zpatch(1:end-1, end), Zpatch(2:end, end), dx);

if isfinite(Zpatch(end, end))
    surfaceAreaUm2 = surfaceAreaUm2 + dx^2 / 4;
end

projectedAreaUm2 = nnz(isfinite(Zpatch)) * dx^2;
if projectedAreaUm2 == 0 || ~any(validCells(:))
    ratio = NaN;
else
    ratio = surfaceAreaUm2 / projectedAreaUm2;
end
end

function [surfaceOpposite, validCells] = calculateOppositeDiagonalInteriorSurface(Zpatch, dx)
z11 = Zpatch(1:end-1, 1:end-1);
z12 = Zpatch(1:end-1, 2:end);
z21 = Zpatch(2:end, 1:end-1);
z22 = Zpatch(2:end, 2:end);
validCells = isfinite(z11) & isfinite(z12) & isfinite(z21) & isfinite(z22);
if ~any(validCells(:))
    surfaceOpposite = NaN;
    return;
end

dz12 = z12(validCells) - z11(validCells);
dz21 = z21(validCells) - z11(validCells);
dz22 = z22(validCells) - z11(validCells);
oppositeTri1 = 0.5 .* sqrt((dx .* dz21).^2 + (dx .* dz12).^2 + dx.^4);
oppositeTri2 = 0.5 .* sqrt((dx .* (dz21 - dz22)).^2 + (dx .* (dz22 - dz12)).^2 + dx.^4);
surfaceOpposite = sum(oppositeTri1 + oppositeTri2, 'omitnan');
end

function area = edgeStripArea(zA, zB, dx)
valid = isfinite(zA) & isfinite(zB);
area = sum(sqrt(dx^2 + (zB(valid) - zA(valid)).^2) .* (dx / 2), 'omitnan');
end

function [metricMean, metricStd] = summarizeMetric(v)
if isempty(v)
    metricMean = NaN;
    metricStd = NaN;
    return;
end

metricMean = mean(v, 'omitnan');
if isscalar(v)
    metricStd = 0;
else
    metricStd = std(v, 0, 'omitnan');
end
end
