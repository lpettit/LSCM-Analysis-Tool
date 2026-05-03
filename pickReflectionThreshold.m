function reflThreshold = pickReflectionThreshold(imagePath, fillThreshold)
% =========================================================================
%  pickReflectionThreshold  —  Interactive GUI to select the intensity
%                              threshold that identifies reflection pixels
%                              within pit regions for Z_smooth correction.
%
%  USAGE:
%    reflThreshold = pickReflectionThreshold('Left-50x.vk4', 0.52)
%    reflThreshold = pickReflectionThreshold('Left-50x.bmp', 0.52)
%    % Then pass to analyzeCavities:
%    cavResults = analyzeCavities(m1, 2.0, true, 0.52, reflThreshold)
%
%  HOW IT WORKS:
%    1. Computes pit regions using fillThreshold (same as autoTuneMounds)
%    2. Shows original image with:
%         - Pit regions outlined in cyan
%         - Reflection pixels (above reflThreshold) overlaid in red
%         - Dark ring pixels (annulus outside reflection) overlaid in green
%    3. User adjusts slider until red covers only the reflective bright spots
%       and green covers the surrounding dark ring cleanly
%
%  INPUTS:
%    imagePath      - path to .vk4 file OR grayscale/RGB image (.bmp/.tif/.png)
%    fillThreshold  - the pit fill threshold used in autoTuneMounds
%
%  OUTPUT:
%    reflThreshold  - confirmed threshold in [0,1] for reflection detection
%
%  REQUIRES: Image Processing Toolbox
%            readVK4.m + vk4mat library (VK4 input only)
% =========================================================================

% --- Load image ----------------------------------------------------------
[~, ~, imageExt] = fileparts(imagePath);
if strcmpi(imageExt, '.vk4')
    if ~exist('readVK4', 'file')
        error(['pickReflectionThreshold: readVK4.m not found on MATLAB path.\n' ...
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

% --- Compute pit mask using fillThreshold --------------------------------
BW_high  = imbinarize(I_raw, double(fillThreshold));
filled   = imcomplement(imfill(imcomplement(BW_high), 'holes'));
pit_mask = ~filled;
pit_mask = imerode(pit_mask, strel('disk',1));   % slight erosion to clean edges

if ~any(pit_mask(:))
    warning('pickReflectionThreshold: no pit regions found at fillThreshold=%.3f', fillThreshold);
    reflThreshold = fillThreshold * 0.6;
    return;
end

fprintf('pickReflectionThreshold: found %d pit pixels in %d region(s)\n', ...
        sum(pit_mask(:)), max(max(bwlabel(pit_mask))));

% Initial reflection threshold: mean intensity of pit pixels
pit_vals     = I_double(pit_mask);
T_init       = mean(pit_vals) + 0.5 * std(pit_vals);
T_init       = max(0.01, min(0.99, T_init));

% --- Build figure --------------------------------------------------------
fig = figure('Name','Pick Reflection Threshold', ...
             'Position',[80 80 1200 720], ...
             'Color',[0.15 0.15 0.15], ...
             'CloseRequestFcn', @onClose);

ax = axes('Parent',fig, 'Position',[0.03 0.13 0.93 0.82]);

ctrl = uipanel('Parent',fig, 'Position',[0 0 1 0.11], ...
               'BackgroundColor',[0.2 0.2 0.2], 'BorderType','none');

slider = uicontrol('Parent',ctrl, 'Style','slider', ...
    'Min',0.01, 'Max',0.99, 'Value',T_init, ...
    'SliderStep',[0.005 0.02], ...
    'Units','normalized', 'Position',[0.10 0.35 0.55 0.35], ...
    'BackgroundColor',[0.35 0.35 0.35], ...
    'Callback', @onSlider);

thresh_label = uicontrol('Parent',ctrl, 'Style','text', ...
    'Units','normalized', 'Position',[0.67 0.3 0.12 0.45], ...
    'String',sprintf('T = %.3f', T_init), ...
    'FontSize',12, 'FontWeight','bold', ...
    'ForegroundColor','w', 'BackgroundColor',[0.2 0.2 0.2], ...
    'HorizontalAlignment','center');

uicontrol('Parent',ctrl, 'Style','text', ...
    'Units','normalized', 'Position',[0.10 0.75 0.55 0.22], ...
    'String',['Adjust: red = reflection pixels  |  green = dark ring  |  ' ...
              'cyan outline = pit boundary'], ...
    'FontSize',9, 'ForegroundColor',[0.8 0.8 0.8], ...
    'BackgroundColor',[0.2 0.2 0.2], 'HorizontalAlignment','center');

uicontrol('Parent',ctrl, 'Style','pushbutton', ...
    'Units','normalized', 'Position',[0.81 0.2 0.12 0.6], ...
    'String','Confirm', 'FontSize',11, 'FontWeight','bold', ...
    'ForegroundColor','w', 'BackgroundColor',[0.2 0.55 0.3], ...
    'Callback',@onConfirm);

% --- Shared state --------------------------------------------------------
state.T         = T_init;
state.confirmed = false;
guidata(fig, state);

% Initial render
updateOverlay(ax, I_double, I_raw, pit_mask, T_init, imgH, imgW);

% Wait for user
uiwait(fig);

% Retrieve result
if ishandle(fig)
    state = guidata(fig);
    reflThreshold = state.T;
    close(fig);
else
    reflThreshold = T_init;
    fprintf('Window closed without confirming. Using T = %.3f\n', reflThreshold);
end

fprintf('pickReflectionThreshold: confirmed reflThreshold = %.3f\n', reflThreshold);

% =========================================================================
%  CALLBACKS
% =========================================================================
    function onSlider(src, ~)
        state   = guidata(fig);
        state.T = src.Value;
        guidata(fig, state);
        set(thresh_label, 'String', sprintf('T = %.3f', state.T));
        updateOverlay(ax, I_double, I_raw, pit_mask, state.T, imgH, imgW);
    end

    function onConfirm(~,~)
        state           = guidata(fig);
        state.confirmed = true;
        guidata(fig, state);
        uiresume(fig);
    end

    function onClose(~,~)
        uiresume(fig);
        delete(fig);
    end

end % pickReflectionThreshold


% =========================================================================
%  OVERLAY RENDERING
% =========================================================================
function updateOverlay(ax, I_double, I_raw, pit_mask, T, imgH, imgW)

    % Reflection pixels: above threshold AND inside pit
    refl_mask = (I_double >= T) & pit_mask;

    % Dark ring: annulus just outside reflection, inside pit
    if any(refl_mask(:))
        ring_outer = imdilate(refl_mask, strel('disk', 8));
        ring_inner = imdilate(refl_mask, strel('disk', 1));
        ring_mask  = ring_outer & ~ring_inner & pit_mask & ~refl_mask;
    else
        ring_mask = false(imgH, imgW);
    end

    % Pit boundary outline
    pit_edge = edge(pit_mask, 'Canny');

    % Build RGB
    Ir = uint8(I_double * 255);
    Ig = Ir; Ib = Ir;

    % Cyan pit outline
    Ir = uint8(max(0, double(Ir) - double(pit_edge)*80));
    Ig = min(255, Ig + uint8(pit_edge)*100);
    Ib = min(255, Ib + uint8(pit_edge)*100);

    % Red: reflection
    Ir = min(255, Ir + uint8(refl_mask)*130);
    Ig = uint8(max(0, double(Ig) - double(uint8(refl_mask))*80));
    Ib = uint8(max(0, double(Ib) - double(uint8(refl_mask))*80));

    % Green: dark ring
    Ir = uint8(max(0, double(Ir) - double(uint8(ring_mask))*50));
    Ig = min(255, Ig + uint8(ring_mask)*120);
    Ib = uint8(max(0, double(Ib) - double(uint8(ring_mask))*50));

    n_refl = sum(refl_mask(:));
    n_ring = sum(ring_mask(:));
    pct_r  = 100 * n_refl / max(sum(pit_mask(:)), 1);

    axes(ax); %#ok<LAXES>
    imshow(cat(3, Ir, Ig, Ib), 'Parent', ax);
    title(ax, sprintf(['T = %.3f  |  Reflection: %d px (%.1f%% of pits)  |  ' ...
                       'Dark ring: %d px  |  ' ...
                       'Aim: red covers bright spots only, green in dark ring'], ...
          T, n_refl, pct_r, n_ring), ...
          'Color','w', 'FontSize',9);
    drawnow;
end