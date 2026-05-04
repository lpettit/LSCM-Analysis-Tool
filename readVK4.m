function [Z, xy_um_per_px, total_height_um, imgH, imgW] = readVK4(vk4Path)
% =========================================================================
%  readVK4  —  Read a Keyence VK4 file and return a calibrated height map
%
%  Extracts full 32-bit precision height data and all calibration constants
%  directly from the .vk4 binary, bypassing the 8-bit quantisation loss
%  (~0.316 µm/count) that occurs when working from exported BMP files.
%
%  USAGE:
%    [Z, xy, z_range] = readVK4('Left-50x.vk4')
%
%    % Drop-in replacement for the BMP imread + manual calibration:
%    %   OLD: I = imread('Left-50x.bmp'); Z = double(I)/255 * 80.58;
%    %   NEW: [Z, xy_um_per_px, total_height_um] = readVK4('Left-50x.vk4');
%
%  OUTPUTS:
%    Z               - calibrated height map in µm, zeroed to scan floor
%                      (double, H×W, same orientation as imread BMP)
%    xy_um_per_px    - lateral calibration in µm/pixel  (e.g. 0.141740)
%    total_height_um - full z range in µm  = max(Z(:))  (e.g. 80.58)
%    imgH            - image height in pixels  (rows)
%    imgW            - image width  in pixels  (columns)
%
%  PHYSICS NOTE:
%    With full 32-bit precision, mean(Z) reproduces the LSCM software's
%    refPlane (= structureVolume / scanArea) exactly.  From the BMP,
%    8-bit quantisation caused a systematic ~3.6 µm underestimate.
%
%  CONFIRMED BYTE OFFSETS (VK4 format, verified on Keyence VK-X series):
%    Offset table          : file bytes 12–83 (18 × uint32 little-endian)
%    Measurement conditions: offs(1) = 84  (absolute byte, 0-indexed)
%      xy_length_per_pixel : mc_offset + 168  (uint32, pm/pixel, x)
%      xy_length_per_pixel : mc_offset + 172  (uint32, pm/pixel, y — same)
%      z_length_per_digit  : mc_offset + 176  (uint32, pm/count)
%    Height image data     : offs(5)  (absolute byte, 0-indexed)
%      width               : +0   (uint32, pixels)
%      height              : +4   (uint32, pixels)
%      bit_depth           : +8   (uint32, always 32)
%      compression         : +12  (uint32, 0 = none)
%      data_byte_length    : +16  (uint32)
%      pixel data          : +20  (W×H uint32 little-endian, row-major)
%
%  REQUIRES:
%    vk4mat MATLAB library  —  https://github.com/matt-black/vk4mat
%    Add all .m files from that repo to your MATLAB path before calling.
%
%  KNOWN LIMITATION:
%    Byte offsets are confirmed on Keyence VK-X series (vk4 format v1).
%    VK6/VK7 files use a different container format and are not supported.
% =========================================================================

% --- Validate input -------------------------------------------------------
if ~exist(vk4Path, 'file')
    error('readVK4: file not found: %s', vk4Path);
end
[~, ~, ext] = fileparts(vk4Path);
if ~strcmpi(ext, '.vk4')
    warning('readVK4: expected .vk4 extension, got %s — proceeding anyway', ext);
end

% --- Check vk4mat is on path ---------------------------------------------
ensureLocalVk4matOnPath();
if ~exist('vk4_readVk4Binary', 'file') || ~exist('vk4_computeVk4Offsets', 'file')
    localHint = fullfile(fileparts(mfilename('fullpath')), 'vk4mat-main');
    error(['readVK4: vk4mat library not found on MATLAB path.\n' ...
           'Expected bundled copy at: ' localHint '\n' ...
           'If it is missing, download from https://github.com/matt-black/vk4mat and add to path.']);
end

% --- Read binary data and compute offset table ---------------------------
bin  = vk4_readVk4Binary(vk4Path);     % uint8 column vector, full file
offs = vk4_computeVk4Offsets(bin);     % 18×1 double, absolute byte offsets (0-indexed)

% --- Read calibration from measurement conditions block ------------------
mc = offs(1);   % absolute byte offset to measurement conditions (0-indexed)

xy_pm          = readUint32(bin, mc + 168);   % x pixel size in pm
xy_pm_y        = readUint32(bin, mc + 172);   % y pixel size in pm  (should match x)
z_pm_per_count = readUint32(bin, mc + 176);   % z resolution in pm/count

if xy_pm ~= xy_pm_y
    warning('readVK4: x and y pixel sizes differ (%d vs %d pm) — using x', ...
            xy_pm, xy_pm_y);
end
if z_pm_per_count == 0
    error('readVK4: z_length_per_digit = 0, calibration block may be at wrong offset.');
end

xy_um_per_px   = double(xy_pm)          * 1e-6;   % pm → µm
z_um_per_count = double(z_pm_per_count) * 1e-6;   % pm → µm

fprintf('readVK4: xy = %d pm/px  (%.6f µm/px)\n',  xy_pm, xy_um_per_px);
fprintf('readVK4: z  = %d pm/count  (%.2e µm/count)\n', z_pm_per_count, z_um_per_count);

% --- Read height image from vk4mat ---------------------------------------
% vk4_readVk4All returns [optical, laser+optical, intensity, height]
% The height layer is a H×W uint32 array of raw z-counts.
[~, ~, ~, height_counts] = vk4_readVk4All(vk4Path);
height_counts = double(height_counts);   % ensure double for arithmetic

[imgH, imgW] = size(height_counts);
fprintf('readVK4: image %d × %d px  (%d total)\n', imgH, imgW, imgH * imgW);

% --- Convert counts to µm, zeroed at scan floor --------------------------
% Subtract minimum count so scan floor = 0 µm, matching the BMP convention
% (BMP pixel 0 → Z = 0 µm; BMP pixel 255 → Z = total_height_um).
z_min_count     = min(height_counts(:));
z_max_count     = max(height_counts(:));

Z               = (height_counts - z_min_count) * z_um_per_count;
total_height_um = (z_max_count   - z_min_count) * z_um_per_count;

% --- Sanity checks -------------------------------------------------------
fprintf('readVK4: Z range      = %.4f µm  (= total_height_um)\n', total_height_um);
fprintf('readVK4: mean(Z)      = %.4f µm  (= refPlane above scan floor)\n', mean(Z(:)));
fprintf('readVK4: refPlane check: structureVolume / scanArea = %.4f µm\n', ...
        mean(Z(:)));

% Warn if total_height_um is wildly different from a typical LSCM range
if total_height_um < 0.1 || total_height_um > 5000
    warning('readVK4: total_height_um = %.2f µm looks unusual — check calibration.', ...
            total_height_um);
end

end  % readVK4


% =========================================================================
%  HELPER: read a uint32 little-endian from byte vector
%  byte_offset : 0-indexed absolute byte position in file
% =========================================================================
function val = readUint32(bin, byte_offset)
    i   = byte_offset + 1;   % convert to MATLAB 1-indexed
    val = double(bin(i))            + ...
          double(bin(i+1)) * 256    + ...
          double(bin(i+2)) * 65536  + ...
          double(bin(i+3)) * 16777216;
end

function ensureLocalVk4matOnPath()
    if exist('vk4_readVk4Binary', 'file') && exist('vk4_computeVk4Offsets', 'file')
        return;
    end

    localRoot = fullfile(fileparts(mfilename('fullpath')), 'vk4mat-main');
    if exist(localRoot, 'dir')
        addpath(genpath(localRoot));
    end
end
