function results = legacySurfaceRoughnessGUI(inputSource, outputDir)
% legacySurfaceRoughnessGUI
% Standalone manual ROI tool for legacy roughness measurements.

arguments
    inputSource
    outputDir = ''
end

surfaceInput = resolveSurfaceInput(inputSource);
Z = surfaceInput.Z;
xy_um_per_px = surfaceInput.xy_um_per_px;
imagePath = surfaceInput.imagePath;
[imgH, imgW] = size(Z);
[imageFolder, imageName, ~] = fileparts(imagePath);

if nargin < 2 || isempty(outputDir)
    outputDir = imageFolder;
end
if isempty(outputDir)
    outputDir = pwd;
end
if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

maxRois = 20;
roiColor = 'k';
defaultAreaWidthUm = 10.00;
defaultAreaHeightUm = 10.00;
fixedAreaWidthUm = min(defaultAreaWidthUm, imgW * xy_um_per_px);
fixedAreaHeightUm = min(defaultAreaHeightUm, imgH * xy_um_per_px);
fixedAreaWidthPx = max(1, round(fixedAreaWidthUm / xy_um_per_px));
fixedAreaHeightPx = max(1, round(fixedAreaHeightUm / xy_um_per_px));

rois = struct('type', {}, 'x1', {}, 'x2', {}, 'y1', {}, 'y2', {});
roiGraphics = gobjects(0);
previewGraphic = gobjects(1);
clickStage = 0;
anchorPoint = [NaN, NaN];
activeMode = '';
finalized = false;
results = buildGuiResults(false, '', '');

fig = figure( ...
    'Name', 'Surface roughness', ...
    'NumberTitle', 'off', ...
    'MenuBar', 'none', ...
    'ToolBar', 'none', ...
    'Color', [0.94 0.94 0.94], ...
    'Units', 'pixels', ...
    'Position', [100 100 1180 760], ...
    'CloseRequestFcn', @onCloseRequest);

ax = axes('Parent', fig, 'Units', 'normalized', 'Position', [0.04 0.08 0.66 0.86]);
imagesc(ax, Z);
axis(ax, 'image');
axis(ax, 'ij');
colormap(ax, jet(256));
set(ax, 'XLim', [0.5, imgW + 0.5], 'YLim', [0.5, imgH + 0.5], 'YDir', 'reverse');
title(ax, sprintf('%s | Legacy roughness ROI tool', imageName), 'Interpreter', 'none');
xlabel(ax, sprintf('x (px) | %.4f \\mum/px', xy_um_per_px));
ylabel(ax, 'y (px)');
hold(ax, 'on');

panel = uipanel('Parent', fig, 'Units', 'normalized', 'Position', [0.74 0.06 0.23 0.88], ...
    'Title', '', 'BackgroundColor', [0.94 0.94 0.94]);

buttonW = 0.27;
buttonH = 0.08;
gapX = 0.05;
x1 = 0.06;
x2 = x1 + buttonW + gapX;
x3 = x2 + buttonW + gapX;
yRow1 = 0.84;
yRow2 = 0.74;

btnAll = uicontrol(panel, 'Style', 'pushbutton', 'String', 'All areas', ...
    'Units', 'normalized', 'Position', [x1 yRow1 buttonW buttonH], ...
    'Callback', @onAllAreas);
btnRect = uicontrol(panel, 'Style', 'pushbutton', 'String', 'Rect.', ...
    'Units', 'normalized', 'Position', [x2 yRow1 buttonW buttonH], ...
    'Callback', @(~, ~) setMode('rect'));
btnSquare = uicontrol(panel, 'Style', 'pushbutton', 'String', 'Square', ...
    'Units', 'normalized', 'Position', [x3 yRow1 buttonW buttonH], ...
    'Callback', @(~, ~) setMode('square'));
btnArea = uicontrol(panel, 'Style', 'pushbutton', 'String', 'Area', ...
    'Units', 'normalized', 'Position', [x3 yRow2 buttonW buttonH], ...
    'Callback', @onAreaMode);
uicontrol(panel, 'Style', 'pushbutton', 'String', 'Clear', ...
    'Units', 'normalized', 'Position', [x2 yRow2 buttonW buttonH], ...
    'Callback', @onClear);
uicontrol(panel, 'Style', 'pushbutton', 'String', 'Save', ...
    'Units', 'normalized', 'Position', [x1 yRow2 buttonW buttonH], ...
    'FontWeight', 'bold', 'Callback', @onDone);

summaryBox = uicontrol(panel, 'Style', 'edit', 'Units', 'normalized', ...
    'Position', [0.06 0.49 0.88 0.18], 'Max', 10, 'Min', 0, ...
    'Enable', 'inactive', 'HorizontalAlignment', 'left', ...
    'BackgroundColor', 'w');

tableBox = uitable(panel, 'Units', 'normalized', 'Position', [0.06 0.20 0.88 0.25], ...
    'ColumnName', {'ROI', 'Type', 'Rp (um)', 'Rv (um)', 'Rz (um)', 'SA/A'}, ...
    'ColumnEditable', false(1, 6), ...
    'ColumnWidth', {38, 58, 52, 52, 52, 55}, ...
    'RowName', []);

statusBox = uicontrol(panel, 'Style', 'edit', 'Units', 'normalized', ...
    'Position', [0.06 0.05 0.88 0.11], 'Max', 10, 'Min', 0, ...
    'Enable', 'inactive', 'HorizontalAlignment', 'left', ...
    'BackgroundColor', 'w');

set(fig, 'WindowButtonDownFcn', @onMouseDown, 'WindowButtonMotionFcn', @onMouseMove);
refreshDisplay();
drawnow;
uiwait(fig);

if isgraphics(fig)
    delete(fig);
end

    function onAllAreas(~, ~)
        cancelPlacement();
        clearAllRois();
        addRoi(struct('type', 'all_areas', 'x1', 1, 'x2', imgW, 'y1', 1, 'y2', imgH));
        setStatus({ ...
            'Stored ROI 1 as the full image.', ...
            sprintf('ROI count: %d/%d', numel(rois), maxRois)});
    end

    function onAreaMode(~, ~)
        [widthUm, heightUm, accepted] = promptForAreaSize(fixedAreaWidthUm, fixedAreaHeightUm);
        if ~accepted
            return;
        end
        fixedAreaWidthUm = widthUm;
        fixedAreaHeightUm = heightUm;
        fixedAreaWidthPx = max(1, round(fixedAreaWidthUm / xy_um_per_px));
        fixedAreaHeightPx = max(1, round(fixedAreaHeightUm / xy_um_per_px));
        setMode('area');
        setStatus({ ...
            sprintf('Area mode armed: %.2f um x %.2f um.', fixedAreaWidthUm, fixedAreaHeightUm), ...
            'First click centers the preview. Second click places the ROI.'});
    end

    function setMode(modeName)
        activeMode = modeName;
        clickStage = 0;
        anchorPoint = [NaN, NaN];
        deletePreview();
        setButtonStates();
        switch modeName
            case 'rect'
                setStatus({'Rectangle mode armed.', ...
                    'First click sets a corner. Second click sets the opposite corner.'});
            case 'square'
                setStatus({'Square mode armed.', ...
                    'First click sets a corner. Second click sets the opposite corner with equal sides.'});
            case 'area'
                setStatus({ ...
                    sprintf('Area mode armed: %.2f um x %.2f um.', fixedAreaWidthUm, fixedAreaHeightUm), ...
                    'First click centers the preview. Second click places the ROI.'});
            otherwise
                setStatus({'Idle.', 'Choose a placement mode or click Save.'});
        end
    end

    function setButtonStates()
        set([btnAll, btnRect, btnSquare, btnArea], 'FontWeight', 'normal');
        switch activeMode
            case 'rect'
                set(btnRect, 'FontWeight', 'bold');
            case 'square'
                set(btnSquare, 'FontWeight', 'bold');
            case 'area'
                set(btnArea, 'FontWeight', 'bold');
        end
    end

    function onClear(~, ~)
        clearAllRois();
        refreshDisplay();
        resetActivePlacement();
        setButtonStates();
        switch activeMode
            case 'rect'
                setStatus({'All ROIs cleared.', ...
                    'Rectangle mode is still armed. First click sets a corner.'});
            case 'square'
                setStatus({'All ROIs cleared.', ...
                    'Square mode is still armed. First click sets a corner.'});
            case 'area'
                setStatus({'All ROIs cleared.', ...
                    'Area mode is still armed. Move the mouse and click to start placing ROIs again.'});
            otherwise
                setStatus({'All ROIs cleared.', 'Ready for new placement.'});
        end
    end

    function onDone(~, ~)
        results = buildGuiResults(true, '', '');
        results.gui_settings = struct( ...
            'colormap', 'jet', ...
            'roi_color', roiColor, ...
            'max_rois', maxRois, ...
            'default_area_width_um', fixedAreaWidthUm, ...
            'default_area_height_um', fixedAreaHeightUm, ...
            'done_timestamp', char(datetime('now', 'TimeZone', 'local', 'Format', 'yyyy-MM-dd HH:mm:ss Z')));

        matPath = fullfile(outputDir, sprintf('%s_legacy_surface_roughness.mat', imageName));
        csvPath = fullfile(outputDir, sprintf('%s_legacy_surface_roughness.csv', imageName));
        results.saved = true;
        results.saved_files = struct('mat', matPath, 'csv', csvPath);

        save(matPath, 'results');
        writecell(buildCsvExport(results), csvPath);

        finalized = true;
        setStatus({ ...
            'Saved legacy roughness outputs.', ...
            matPath, ...
            csvPath});
        uiresume(fig);
    end

    function out = buildGuiResults(savedFlag, matPath, csvPath)
        out = legacySurfaceRoughnessMeasureROIs(Z, xy_um_per_px, imagePath, rois);
        out.saved = savedFlag;
        out.saved_files = struct('mat', matPath, 'csv', csvPath);
    end

    function onMouseDown(~, ~)
        if isempty(activeMode)
            return;
        end

        point = getAxesPoint();
        if isempty(point)
            return;
        end

        switch activeMode
            case {'rect', 'square'}
                handleRectLikeClick(point, activeMode);
            case 'area'
                handleAreaClick(point);
        end
    end

    function handleRectLikeClick(point, modeName)
        if numel(rois) >= maxRois
            warnRoiLimit();
            return;
        end

        if clickStage == 0
            anchorPoint = point;
            clickStage = 1;
            updatePreview(point, modeName);
            return;
        end

        roi = rectLikeRoiFromPoints(anchorPoint, point, modeName);
        if isempty(roi)
            return;
        end
        addRoi(roi);
        if numel(rois) >= maxRois
            cancelPlacement();
            return;
        end

        resetActivePlacement();
        setButtonStates();
        switch modeName
            case 'rect'
                setStatus({ ...
                    sprintf('Stored ROI %d/%d (rect).', numel(rois), maxRois), ...
                    'Rectangle mode is still armed. First click sets the next corner.'});
            case 'square'
                setStatus({ ...
                    sprintf('Stored ROI %d/%d (square).', numel(rois), maxRois), ...
                    'Square mode is still armed. First click sets the next corner.'});
        end
    end

    function handleAreaClick(point)
        if numel(rois) >= maxRois
            warnRoiLimit();
            return;
        end

        if clickStage == 0
            clickStage = 1;
            updatePreview(point, 'area');
            setStatus({ ...
                sprintf('Area preview centered at x=%.1f px, y=%.1f px.', point(1), point(2)), ...
                'Move the mouse if needed, then click again to place the ROI.'});
            return;
        end

        roi = areaRoiFromCenter(point);
        addRoi(roi);
        if numel(rois) >= maxRois
            cancelPlacement();
            return;
        end

        resetActivePlacement();
        setStatus({ ...
            sprintf('Stored ROI %d/%d (area).', numel(rois), maxRois), ...
            'Area mode is still armed. Click once on the surface to prime the next placement.'});
    end

    function onMouseMove(~, ~)
        if isempty(activeMode) || clickStage == 0
            return;
        end
        point = getAxesPoint();
        if isempty(point)
            return;
        end
        updatePreview(point, activeMode);
    end

    function point = getAxesPoint()
        if ~isgraphics(ax)
            point = [];
            return;
        end
        cp = get(ax, 'CurrentPoint');
        x = cp(1, 1);
        y = cp(1, 2);
        if x < 0.5 || x > imgW + 0.5 || y < 0.5 || y > imgH + 0.5
            point = [];
            return;
        end
        point = [min(max(x, 1), imgW), min(max(y, 1), imgH)];
    end

    function updatePreview(point, modeName)
        switch modeName
            case {'rect', 'square'}
                roi = rectLikeRoiFromPoints(anchorPoint, point, modeName);
            case 'area'
                roi = areaRoiFromCenter(point);
            otherwise
                roi = [];
        end
        if isempty(roi)
            deletePreview();
            return;
        end

        pos = roiToRectanglePosition(roi);
        if ~isgraphics(previewGraphic)
            previewGraphic = rectangle(ax, 'Position', pos, 'EdgeColor', roiColor, ...
                'LineStyle', '--', 'LineWidth', 1.25);
        else
            set(previewGraphic, 'Position', pos);
        end
    end

    function roi = rectLikeRoiFromPoints(pt1, pt2, modeName)
        if any(~isfinite(pt1)) || any(~isfinite(pt2))
            roi = [];
            return;
        end

        x1 = pt1(1);
        y1 = pt1(2);
        x2 = pt2(1);
        y2 = pt2(2);

        if strcmp(modeName, 'square')
            dx = x2 - x1;
            dy = y2 - y1;
            sx = signWithDefault(dx);
            sy = signWithDefault(dy);
            sideWanted = max(abs(dx), abs(dy));
            sideMaxX = maxSquareDelta(x1, sx, imgW);
            sideMaxY = maxSquareDelta(y1, sy, imgH);
            side = max(0, min([sideWanted, sideMaxX, sideMaxY]));
            x2 = x1 + sx * side;
            y2 = y1 + sy * side;
        end

        x1 = min(max(x1, 1), imgW);
        x2 = min(max(x2, 1), imgW);
        y1 = min(max(y1, 1), imgH);
        y2 = min(max(y2, 1), imgH);

        roi = struct( ...
            'type', modeName, ...
            'x1', round(min(x1, x2)), ...
            'x2', round(max(x1, x2)), ...
            'y1', round(min(y1, y2)), ...
            'y2', round(max(y1, y2)));
    end

    function roi = areaRoiFromCenter(point)
        centerX = point(1);
        centerY = point(2);
        halfW = (fixedAreaWidthPx - 1) / 2;
        halfH = (fixedAreaHeightPx - 1) / 2;

        x1 = round(centerX - halfW);
        y1 = round(centerY - halfH);
        x1 = min(max(x1, 1), imgW - fixedAreaWidthPx + 1);
        y1 = min(max(y1, 1), imgH - fixedAreaHeightPx + 1);
        x2 = x1 + fixedAreaWidthPx - 1;
        y2 = y1 + fixedAreaHeightPx - 1;

        roi = struct('type', 'area', 'x1', x1, 'x2', x2, 'y1', y1, 'y2', y2);
    end

    function addRoi(roi)
        if numel(rois) >= maxRois
            warnRoiLimit();
            return;
        end
        rois(end + 1) = roi;
        drawRoiGraphic(roi);
        refreshDisplay();
        setStatus({ ...
            sprintf('Stored ROI %d/%d (%s).', numel(rois), maxRois, strrep(roi.type, '_', ' ')), ...
            'Metrics and summary updated.'});
    end

    function drawRoiGraphic(roi)
        roiGraphics(end + 1) = rectangle(ax, 'Position', roiToRectanglePosition(roi), ...
            'EdgeColor', roiColor, 'LineWidth', 1.3);
    end

    function pos = roiToRectanglePosition(roi)
        pos = [roi.x1 - 0.5, roi.y1 - 0.5, roi.x2 - roi.x1 + 1, roi.y2 - roi.y1 + 1];
    end

    function clearAllRois()
        rois = struct('type', {}, 'x1', {}, 'x2', {}, 'y1', {}, 'y2', {});
        if ~isempty(roiGraphics)
            delete(roiGraphics(isgraphics(roiGraphics)));
        end
        roiGraphics = gobjects(0);
    end

    function refreshDisplay()
        currentResults = buildGuiResults(false, '', '');
        updateSummaryBox(currentResults);
        updateTableBox(currentResults.roi_table);
    end

    function updateSummaryBox(currentResults)
        lines = { ...
            sprintf('Output folder: %s', outputDir), ...
            sprintf('Surface source: %s', surfaceInput.source_label), ...
            sprintf('Image size: %.2f um x %.2f um', currentResults.image_size_um(1), currentResults.image_size_um(2)), ...
            sprintf('Ref plane: %.4f um', currentResults.refPlane_um), ...
            sprintf('Global Rp / Rv / Rz: %.4f / %.4f / %.4f um', ...
                currentResults.Rp_global, currentResults.Rv_global, currentResults.Rz_global), ...
            sprintf('Global SA/A: %.4f', currentResults.SA_to_A_ratio_global), ...
            sprintf('ROI count: %d / %d', currentResults.n_rois, maxRois)}.';

        if currentResults.n_rois > 0
            extraLines = { ...
                sprintf('Mean Rp +/- std: %.4f +/- %.4f um', currentResults.mean_Rp_um, currentResults.std_Rp_um), ...
                sprintf('Mean Rv +/- std: %.4f +/- %.4f um', currentResults.mean_Rv_um, currentResults.std_Rv_um), ...
                sprintf('Mean Rz +/- std: %.4f +/- %.4f um', currentResults.mean_Rz_um, currentResults.std_Rz_um), ...
                sprintf('Mean SA/A +/- std: %.4f +/- %.4f', currentResults.mean_SA_to_A_ratio, currentResults.std_SA_to_A_ratio)}.';
            lines = [lines; extraLines];
        else
            lines = [lines; {'No ROIs placed yet.'}];
        end

        set(summaryBox, 'String', lines);
    end

    function updateTableBox(roiTable)
        if isempty(roiTable)
            set(tableBox, 'Data', cell(0, 6));
            return;
        end
        tableData = [num2cell(roiTable.ROI_Index), ...
            cellstr(roiTable.ROI_Type), ...
            num2cell(round(roiTable.Rp_um, 4)), ...
            num2cell(round(roiTable.Rv_um, 4)), ...
            num2cell(round(roiTable.Rz_um, 4)), ...
            num2cell(round(roiTable.SA_to_A_ratio, 4))];
        set(tableBox, 'Data', tableData);
    end

    function setStatus(lines)
        if ischar(lines)
            lines = {lines};
        end
        set(statusBox, 'String', lines);
    end

    function cancelPlacement()
        activeMode = '';
        resetActivePlacement();
        setButtonStates();
    end

    function resetActivePlacement()
        clickStage = 0;
        anchorPoint = [NaN, NaN];
        deletePreview();
    end

    function deletePreview()
        if isgraphics(previewGraphic)
            delete(previewGraphic);
        end
        previewGraphic = gobjects(1);
    end

    function onCloseRequest(~, ~)
        if finalized
            delete(fig);
            return;
        end

        choice = questdlg( ...
            'Close without clicking Save? Unsaved legacy roughness results will be discarded.', ...
            'Close Surface Roughness Tool', ...
            'Close Without Saving', 'Cancel', 'Cancel');
        if strcmp(choice, 'Close Without Saving')
            results = buildGuiResults(false, '', '');
            results.gui_settings = struct( ...
                'colormap', 'jet', ...
                'roi_color', roiColor, ...
                'max_rois', maxRois, ...
                'default_area_width_um', fixedAreaWidthUm, ...
                'default_area_height_um', fixedAreaHeightUm);
            uiresume(fig);
        end
    end

    function warnRoiLimit()
        warndlg(sprintf('A maximum of %d ROIs can be stored in this tool.', maxRois), ...
            'ROI Limit Reached', 'modal');
    end

    function [widthUm, heightUm, accepted] = promptForAreaSize(currentWidthUm, currentHeightUm)
        widthUm = currentWidthUm;
        heightUm = currentHeightUm;
        accepted = false;

        dlg = dialog('Name', 'Set area', 'WindowStyle', 'modal', 'Position', [420 320 300 190]);
        uicontrol(dlg, 'Style', 'text', 'String', 'Image size', ...
            'HorizontalAlignment', 'left', 'Position', [28 145 80 18]);
        uicontrol(dlg, 'Style', 'text', ...
            'String', sprintf('%.2fum X %.2fum', imgW * xy_um_per_px, imgH * xy_um_per_px), ...
            'HorizontalAlignment', 'left', 'Position', [28 124 180 18]);

        uicontrol(dlg, 'Style', 'text', 'String', 'Width', ...
            'HorizontalAlignment', 'left', 'Position', [28 88 42 18]);
        widthEdit = uicontrol(dlg, 'Style', 'edit', 'String', sprintf('%.2f', currentWidthUm), ...
            'Position', [78 86 84 24], 'BackgroundColor', 'w');
        uicontrol(dlg, 'Style', 'text', 'String', 'um', ...
            'HorizontalAlignment', 'left', 'Position', [170 88 24 18]);

        uicontrol(dlg, 'Style', 'text', 'String', 'Height', ...
            'HorizontalAlignment', 'left', 'Position', [28 58 42 18]);
        heightEdit = uicontrol(dlg, 'Style', 'edit', 'String', sprintf('%.2f', currentHeightUm), ...
            'Position', [78 56 84 24], 'BackgroundColor', 'w');
        uicontrol(dlg, 'Style', 'text', 'String', 'um', ...
            'HorizontalAlignment', 'left', 'Position', [170 58 24 18]);

        uicontrol(dlg, 'Style', 'pushbutton', 'String', 'OK', ...
            'Position', [55 16 74 28], 'Callback', @onOk);
        uicontrol(dlg, 'Style', 'pushbutton', 'String', 'Cancel', ...
            'Position', [150 16 74 28], 'Callback', @(~, ~) delete(dlg));

        uiwait(dlg);

        function onOk(~, ~)
            widthCandidate = str2double(get(widthEdit, 'String'));
            heightCandidate = str2double(get(heightEdit, 'String'));
            maxWidthUm = imgW * xy_um_per_px;
            maxHeightUm = imgH * xy_um_per_px;

            if ~isfinite(widthCandidate) || ~isfinite(heightCandidate) || ...
                    widthCandidate <= 0 || heightCandidate <= 0
                errordlg('Width and height must be positive numeric values.', 'Invalid Area Size', 'modal');
                return;
            end
            if widthCandidate > maxWidthUm || heightCandidate > maxHeightUm
                errordlg('Width and height must fit inside the image bounds.', 'Area Too Large', 'modal');
                return;
            end

            widthUm = widthCandidate;
            heightUm = heightCandidate;
            accepted = true;
            delete(dlg);
        end
    end
end

function csvCell = buildCsvExport(results)
summaryRows = {
    'Summary metric', 'Value'
    'n_rois', results.n_rois
    'mean_Rp_um', results.mean_Rp_um
    'std_Rp_um', results.std_Rp_um
    'mean_Rv_um', results.mean_Rv_um
    'std_Rv_um', results.std_Rv_um
    'mean_Rz_um', results.mean_Rz_um
    'std_Rz_um', results.std_Rz_um
    'surface_area_global_um2', results.surface_area_global_um2
    'projected_area_global_um2', results.projected_area_global_um2
    'SA_to_A_ratio_global', results.SA_to_A_ratio_global
    'mean_SA_to_A_ratio', results.mean_SA_to_A_ratio
    'std_SA_to_A_ratio', results.std_SA_to_A_ratio
    };

roiHeader = results.roi_table.Properties.VariableNames;
roiData = table2cell(results.roi_table);

csvCell = cell(size(summaryRows, 1) + 2 + size(roiData, 1), max(2, numel(roiHeader)));
csvCell(1:size(summaryRows, 1), 1:2) = summaryRows;
csvCell(size(summaryRows, 1) + 2, 1:numel(roiHeader)) = roiHeader;
if ~isempty(roiData)
    csvCell(size(summaryRows, 1) + 3:end, 1:numel(roiHeader)) = roiData;
end
end

function s = signWithDefault(v)
if v >= 0
    s = 1;
else
    s = -1;
end
end

function sideMax = maxSquareDelta(anchorCoord, directionSign, maxCoord)
if directionSign >= 0
    sideMax = maxCoord - anchorCoord;
else
    sideMax = anchorCoord - 1;
end
end

function surfaceInput = resolveSurfaceInput(inputSource)
if isstruct(inputSource)
    validateattributes(inputSource, {'struct'}, {'scalar'}, mfilename, 'inputSource', 1);
    requiredFields = {'Z', 'xy_um_per_px', 'imagePath'};
    for i = 1:numel(requiredFields)
        if ~isfield(inputSource, requiredFields{i})
            error('legacySurfaceRoughnessGUI:MissingField', ...
                'Input struct is missing required field "%s".', requiredFields{i});
        end
    end

    surfaceInput = struct();
    surfaceInput.Z = double(inputSource.Z);
    surfaceInput.xy_um_per_px = double(inputSource.xy_um_per_px);
    surfaceInput.imagePath = char(inputSource.imagePath);
    surfaceInput.source_label = 'existing analysis surface struct';
    return;
end

if isstring(inputSource) || ischar(inputSource)
    imagePath = char(string(inputSource));
    if strlength(string(imagePath)) == 0
        error('legacySurfaceRoughnessGUI:MissingInput', ...
            'Input file path must be a non-empty string or char vector.');
    end
    if ~exist(imagePath, 'file')
        error('legacySurfaceRoughnessGUI:MissingInputFile', ...
            'Input file not found: %s', imagePath);
    end

    [~, ~, ext] = fileparts(imagePath);
    if ~strcmpi(ext, '.vk4')
        error('legacySurfaceRoughnessGUI:UnsupportedInput', ...
            'Standalone launching currently supports .vk4 input files only.');
    end

    [Z, xy_um_per_px] = readVK4(imagePath);
    surfaceInput = struct();
    surfaceInput.Z = double(Z);
    surfaceInput.xy_um_per_px = double(xy_um_per_px);
    surfaceInput.imagePath = imagePath;
    surfaceInput.source_label = 'direct VK4 load';
    return;
end

error('legacySurfaceRoughnessGUI:UnsupportedInput', ...
    'Input must be either an analysis struct or a .vk4 file path.');
end
