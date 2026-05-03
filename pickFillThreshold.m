function fillThreshold = pickFillThreshold(imagePath)
% =========================================================================
%  pickFillThreshold  —  Interactive GUI to select the intensity threshold
%                        that separates mound peaks from deep pit regions.
%
%  Run this before autoTuneMounds when fillDeepPits = true.  The returned
%  value is passed unchanged to autoTuneMounds, refineMounds, analyzeMounds,
%  analyzeCavities, and pickReflectionThreshold.
%
%  USAGE:
%    fillThreshold = pickFillThreshold('Left-50x.vk4')
%    fillThreshold = pickFillThreshold('Left-50x.bmp')
%    % Then use in the pipeline:
%    bestParams = autoTuneMounds('Left-50x.vk4', true, fillThreshold, 3, 20)
%
%  HOW IT WORKS:
%    Shows the original image with an overlay of the pit mask computed
%    from the current threshold:
%      - Cyan overlay   = pixels classified as deep pits (below threshold)
%      - Image as-is    = pixels classified as mound surface
%    Adjust the slider until the cyan covers all the deep reflective pits
%    but does NOT spill onto mound flanks or saddle regions.
%
%    The threshold operates on normalised [0,1] intensity.  For a typical
%    LSCM mound surface, the correct value is 0.48–0.55 — pits appear
%    darker than mound tops, so lower threshold = larger pit mask.
%
%  INPUTS:
%    imagePath   - path to .vk4 file OR grayscale/RGB image (.bmp/.tif/.png)
%
%  OUTPUT:
%    fillThreshold - confirmed threshold in [0,1]
%
%  REQUIRES: Image Processing Toolbox
%            readVK4.m + vk4mat library (VK4 input only)
% =========================================================================

% --- Load image ----------------------------------------------------------
[~, ~, imageExt] = fileparts(imagePath);
if strcmpi(imageExt, '.vk4')
    if ~exist('readVK4', 'file')
        error(['pickFillThreshold: readVK4.m not found on MATLAB path.\n' ...
               'Required for .vk4 input. Add readVK4.m and the vk4mat\n' ...
               'library (https://github.com/matt-black/vk4mat) to path.']);
    end
    [Z_load, ~, total_h] = readVK4(imagePath);
    I_raw = uint8(round(Z_load / total_h * 255));
    clear Z_load total_h;
else
    I_raw = imread(imagePath);
    if size(I_raw,3)==3, I_raw = rgb2gray(I_raw); end
end
[imgH, imgW] = size(I_raw);
I_double = double(I_raw) / 255;

% --- Initial threshold estimate ------------------------------------------
% Start near the lower quartile of intensity — a reasonable first guess
% that places the threshold below typical mound peaks but above noise floor.
T_init = max(0.01, min(0.99, prctile(I_double(:), 40)));

% --- Build figure --------------------------------------------------------
fig = figure('Name', 'Pick Fill Threshold', ...
             'Position', [80 80 1200 720], ...
             'Color', [0.15 0.15 0.15], ...
             'CloseRequestFcn', @onClose);

ax = axes('Parent', fig, 'Position', [0.03 0.13 0.93 0.82]);

ctrl = uipanel('Parent', fig, 'Position', [0 0 1 0.11], ...
               'BackgroundColor', [0.2 0.2 0.2], 'BorderType', 'none');

slider = uicontrol('Parent', ctrl, 'Style', 'slider', ...
    'Min', 0.01, 'Max', 0.99, 'Value', T_init, ...
    'SliderStep', [0.005 0.02], ...
    'Units', 'normalized', 'Position', [0.10 0.35 0.55 0.35], ...
    'BackgroundColor', [0.35 0.35 0.35], ...
    'Callback', @onSlider);

thresh_label = uicontrol('Parent', ctrl, 'Style', 'text', ...
    'Units', 'normalized', 'Position', [0.67 0.3 0.12 0.45], ...
    'String', sprintf('T = %.3f', T_init), ...
    'FontSize', 12, 'FontWeight', 'bold', ...
    'ForegroundColor', 'w', 'BackgroundColor', [0.2 0.2 0.2], ...
    'HorizontalAlignment', 'center');

uicontrol('Parent', ctrl, 'Style', 'text', ...
    'Units', 'normalized', 'Position', [0.10 0.75 0.55 0.22], ...
    'String', ['Adjust: cyan = pit mask (deep pits)  |  ' ...
               'Aim: cyan covers all dark pits, does NOT spill onto mound flanks'], ...
    'FontSize', 9, 'ForegroundColor', [0.8 0.8 0.8], ...
    'BackgroundColor', [0.2 0.2 0.2], 'HorizontalAlignment', 'center');

uicontrol('Parent', ctrl, 'Style', 'pushbutton', ...
    'Units', 'normalized', 'Position', [0.81 0.2 0.12 0.6], ...
    'String', 'Confirm', 'FontSize', 11, 'FontWeight', 'bold', ...
    'ForegroundColor', 'w', 'BackgroundColor', [0.2 0.55 0.3], ...
    'Callback', @onConfirm);

% --- Shared state --------------------------------------------------------
state.T         = T_init;
state.confirmed = false;
guidata(fig, state);

% Initial render
updateOverlay(ax, I_double, I_raw, T_init, imgH, imgW);

% Wait for user
uiwait(fig);

% Retrieve result
if ishandle(fig)
    state = guidata(fig);
    fillThreshold = state.T;
    close(fig);
else
    fillThreshold = T_init;
    fprintf('Window closed without confirming. Using T = %.3f\n', fillThreshold);
end

fprintf('pickFillThreshold: confirmed fillThreshold = %.3f\n', fillThreshold);

% =========================================================================
%  CALLBACKS
% =========================================================================
    function onSlider(src, ~)
        state   = guidata(fig);
        state.T = src.Value;
        guidata(fig, state);
        set(thresh_label, 'String', sprintf('T = %.3f', state.T));
        updateOverlay(ax, I_double, I_raw, state.T, imgH, imgW);
    end

    function onConfirm(~, ~)
        state           = guidata(fig);
        state.confirmed = true;
        guidata(fig, state);
        uiresume(fig);
    end

    function onClose(~, ~)
        uiresume(fig);
        delete(fig);
    end

end % pickFillThreshold


% =========================================================================
%  OVERLAY RENDERING
% =========================================================================
function updateOverlay(ax, I_double, I_raw, T, imgH, imgW)

    % Pit mask: pixels below threshold, holes filled so pits are solid
    BW_high  = imbinarize(I_raw, double(T));
    filled   = imcomplement(imfill(imcomplement(BW_high), 'holes'));
    pit_mask = ~filled;
    pit_mask = imerode(pit_mask, strel('disk', 1));  % clean edges

    % Pit boundary outline
    pit_edge = edge(pit_mask, 'Canny');

    % Build RGB overlay
    Ir = uint8(I_double * 255);
    Ig = Ir; Ib = Ir;

    % Cyan fill: pit interior
    Ir = uint8(max(0, double(Ir) - double(pit_mask) * 60));
    Ig = min(255, Ig + uint8(pit_mask) * 80);
    Ib = min(255, Ib + uint8(pit_mask) * 80);

    % Brighter cyan: pit boundary edge
    Ir = uint8(max(0, double(Ir) - double(pit_edge) * 80));
    Ig = min(255, Ig + uint8(pit_edge) * 120);
    Ib = min(255, Ib + uint8(pit_edge) * 120);

    n_pit  = sum(pit_mask(:));
    pct    = 100 * n_pit / (imgH * imgW);
    n_pits = max(max(bwlabel(pit_mask)));

    axes(ax); %#ok<LAXES>
    imshow(cat(3, Ir, Ig, Ib), 'Parent', ax);
    title(ax, sprintf(['T = %.3f  |  Pit pixels: %d (%.1f%% of image)  |  ' ...
                       'Pit regions: %d  |  ' ...
                       'Aim: cyan fills deep pits only — no spill onto mound flanks'], ...
          T, n_pit, pct, n_pits), ...
          'Color', 'w', 'FontSize', 9);
    drawnow;
end