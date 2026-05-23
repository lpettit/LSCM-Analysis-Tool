function metrics = vkSurfaceAreaMetrics(Zpatch, xy_um_per_px)
% vkSurfaceAreaMetrics
% Compute VK-matched triangulated surface-area metrics for a height patch.

arguments
    Zpatch (:,:) double
    xy_um_per_px (1,1) double {mustBePositive}
end

surfaceDensityUm2 = nan(size(Zpatch));
surfaceAreaUm2 = NaN;
projectedAreaUm2 = NaN;
ratio = NaN;

if size(Zpatch, 1) < 2 || size(Zpatch, 2) < 2
    metrics = packageMetrics(surfaceAreaUm2, projectedAreaUm2, ratio, surfaceDensityUm2);
    return;
end

dx = xy_um_per_px;
[interiorSurfaceAreaUm2, validCells, cellSurfaceUm2] = calculateOppositeDiagonalInteriorSurface(Zpatch, dx);
if isnan(interiorSurfaceAreaUm2)
    metrics = packageMetrics(surfaceAreaUm2, projectedAreaUm2, ratio, surfaceDensityUm2);
    return;
end

surfaceDensityUm2(:) = 0;
surfaceDensityUm2(1:end-1, 1:end-1) = surfaceDensityUm2(1:end-1, 1:end-1) + 0.25 .* cellSurfaceUm2;
surfaceDensityUm2(1:end-1, 2:end) = surfaceDensityUm2(1:end-1, 2:end) + 0.25 .* cellSurfaceUm2;
surfaceDensityUm2(2:end, 1:end-1) = surfaceDensityUm2(2:end, 1:end-1) + 0.25 .* cellSurfaceUm2;
surfaceDensityUm2(2:end, 2:end) = surfaceDensityUm2(2:end, 2:end) + 0.25 .* cellSurfaceUm2;

[bottomEdgeArea, bottomDensity] = edgeStripArea(Zpatch(end, 1:end-1), Zpatch(end, 2:end), dx);
surfaceDensityUm2(end, 1:end-1) = surfaceDensityUm2(end, 1:end-1) + 0.5 .* bottomDensity;
surfaceDensityUm2(end, 2:end) = surfaceDensityUm2(end, 2:end) + 0.5 .* bottomDensity;

[rightEdgeArea, rightDensity] = edgeStripArea(Zpatch(1:end-1, end), Zpatch(2:end, end), dx);
surfaceDensityUm2(1:end-1, end) = surfaceDensityUm2(1:end-1, end) + 0.5 .* rightDensity;
surfaceDensityUm2(2:end, end) = surfaceDensityUm2(2:end, end) + 0.5 .* rightDensity;

cornerArea = 0;
if isfinite(Zpatch(end, end))
    cornerArea = dx^2 / 4;
    surfaceDensityUm2(end, end) = surfaceDensityUm2(end, end) + cornerArea;
end

surfaceDensityUm2(~isfinite(Zpatch)) = NaN;
surfaceAreaUm2 = interiorSurfaceAreaUm2 + bottomEdgeArea + rightEdgeArea + cornerArea;
projectedAreaUm2 = nnz(isfinite(Zpatch)) * dx^2;
if projectedAreaUm2 > 0 && any(validCells(:))
    ratio = surfaceAreaUm2 / projectedAreaUm2;
end

metrics = packageMetrics(surfaceAreaUm2, projectedAreaUm2, ratio, surfaceDensityUm2);
end

function metrics = packageMetrics(surfaceAreaUm2, projectedAreaUm2, ratio, surfaceDensityUm2)
metrics = struct( ...
    'surfaceAreaUm2', surfaceAreaUm2, ...
    'projectedAreaUm2', projectedAreaUm2, ...
    'ratio', ratio, ...
    'surfaceAreaDensityUm2', surfaceDensityUm2);
end

function [surfaceOpposite, validCells, cellSurfaceUm2] = calculateOppositeDiagonalInteriorSurface(Zpatch, dx)
z11 = Zpatch(1:end-1, 1:end-1);
z12 = Zpatch(1:end-1, 2:end);
z21 = Zpatch(2:end, 1:end-1);
z22 = Zpatch(2:end, 2:end);
validCells = isfinite(z11) & isfinite(z12) & isfinite(z21) & isfinite(z22);
cellSurfaceUm2 = nan(size(validCells));
if ~any(validCells(:))
    surfaceOpposite = NaN;
    return;
end

dz12 = z12(validCells) - z11(validCells);
dz21 = z21(validCells) - z11(validCells);
dz22 = z22(validCells) - z11(validCells);
oppositeTri1 = 0.5 .* sqrt((dx .* dz21).^2 + (dx .* dz12).^2 + dx.^4);
oppositeTri2 = 0.5 .* sqrt((dx .* (dz21 - dz22)).^2 + (dx .* (dz22 - dz12)).^2 + dx.^4);
cellSurfaceUm2(validCells) = oppositeTri1 + oppositeTri2;
surfaceOpposite = sum(cellSurfaceUm2(:), 'omitnan');
end

function [area, density] = edgeStripArea(zA, zB, dx)
valid = isfinite(zA) & isfinite(zB);
density = nan(size(zA));
density(valid) = sqrt(dx^2 + (zB(valid) - zA(valid)).^2) .* (dx / 2);
area = sum(density(:), 'omitnan');
end
