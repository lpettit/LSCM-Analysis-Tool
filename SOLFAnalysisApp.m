classdef SOLFAnalysisApp < matlab.apps.AppBase
    properties (Access = public)
        UIFigure matlab.ui.Figure
        MainGrid matlab.ui.container.GridLayout

        LeftPanel matlab.ui.container.Panel
        LeftGrid matlab.ui.container.GridLayout
        InputEditField matlab.ui.control.EditField
        OutputEditField matlab.ui.control.EditField
        BestParamsEditField matlab.ui.control.EditField
        MoundDetectionButton matlab.ui.control.Button
        CavityAnalysisButton matlab.ui.control.Button
        MoundSurfaceButton matlab.ui.control.Button
        SpatialAnalysisButton matlab.ui.control.Button
        LegacyRoughnessButton matlab.ui.control.Button

        DividerPanel matlab.ui.container.Panel

        MoundSettingsPanel matlab.ui.container.Panel
        MoundSettingsGrid matlab.ui.container.GridLayout
        FillDeepPitsCheckBox matlab.ui.control.CheckBox
        FillThresholdField matlab.ui.control.NumericEditField
        PickFillThresholdButton matlab.ui.control.Button
        MaxEvalsField matlab.ui.control.NumericEditField
        RunMoundDetectionButton matlab.ui.control.Button

        MoundSurfaceSettingsPanel matlab.ui.container.Panel
        MoundSurfaceSettingsGrid matlab.ui.container.GridLayout
        MoundSpacingCheckBox matlab.ui.control.CheckBox
        RoughnessCheckBox matlab.ui.control.CheckBox
        DirectHeightCheckBox matlab.ui.control.CheckBox
        FootprintShapeCheckBox matlab.ui.control.CheckBox
        AxesOrientationCheckBox matlab.ui.control.CheckBox
        SurfaceAreaVolumeCheckBox matlab.ui.control.CheckBox
        WholeImageSlicesCheckBox matlab.ui.control.CheckBox
        QADiagnosticsCheckBox matlab.ui.control.CheckBox
        RunMoundSurfaceButton matlab.ui.control.Button

        ReviewPanel matlab.ui.container.Panel
        ReviewGrid matlab.ui.container.GridLayout
        ReviewTabGroup matlab.ui.container.TabGroup
        TierButtonGrid matlab.ui.container.GridLayout
        DoneButton matlab.ui.control.Button
        TooFewButton matlab.ui.control.Button
        TooManyButton matlab.ui.control.Button
        ManualCountField matlab.ui.control.NumericEditField
        ManualCountButton matlab.ui.control.Button
        SaveCurrentTabButton matlab.ui.control.Button
        SaveAllTabsButton matlab.ui.control.Button
        ReviewSummaryTable matlab.ui.control.Table
        ReviewInfoTextArea matlab.ui.control.TextArea
        StatusTextArea matlab.ui.control.TextArea

        LegacyAxes matlab.ui.control.UIAxes
        LegacySummaryTextArea matlab.ui.control.TextArea
        LegacyTable matlab.ui.control.Table
        LegacyStatusTextArea matlab.ui.control.TextArea
        LegacyAllButton matlab.ui.control.Button
        LegacyRectButton matlab.ui.control.Button
        LegacySquareButton matlab.ui.control.Button
        LegacyAreaButton matlab.ui.control.Button
        LegacyClearButton matlab.ui.control.Button
        LegacyDoneButton matlab.ui.control.Button
        LegacyAreaWidthField matlab.ui.control.NumericEditField
        LegacyAreaHeightField matlab.ui.control.NumericEditField
    end

    properties (Access = private)
        OutputWasAutoDefaulted logical = false
        BestParamsIsValid logical = false
        BestParamsHasDetectionSettings logical = false
        MoundGuiState struct = struct()
        MoundReviewResults cell = {}
        MoundResultCount double = 0
        M1GuiResults struct = struct()
        MoundShapeGuiResults struct = struct()
        MoundSurfaceTabData cell = {}
        MoundSurfaceSession struct = struct()
        MoundSurfaceRenderedGroups cell = {}
        MoundSurfaceExportedPlotPaths cell = {}
        CurrentAnalysisId char = ''
        UnsavedAnalysisIds cell = {}
        IdleButtonColor double = [0.94 0.94 0.94]
        ActiveButtonColor double = [0.55 0.82 0.58]
        RunningButtonColor double = [0.30 0.68 0.35]
        LegacySurfaceInput struct = struct()
        LegacyZ double = []
        LegacyXyUmPerPx double = NaN
        LegacyImagePath char = ''
        LegacyImageName char = ''
        LegacyRois struct = struct('type', {}, 'x1', {}, 'x2', {}, 'y1', {}, 'y2', {})
        LegacyRoiGraphics = gobjects(0)
        LegacyPreviewGraphic = gobjects(1)
        LegacyClickStage double = 0
        LegacyAnchorPoint double = [NaN NaN]
        LegacyActiveMode char = ''
        LegacyMaxRois double = 20
        LegacyRoiColor char = 'k'
    end

    methods (Access = private)
        function startup(app)
            app.logStatus({
                'SOLF VK4 Analysis App'
                'Choose a .vk4 file to begin.'
                'Optional: choose a matching bestParams_<imageName>.mat file to unlock downstream analysis modules.'
                });
            app.updateModuleButtonStates();
        end

        function onBrowseInput(app, ~, ~)
            [f, p] = uigetfile('*.vk4', 'Choose VK4 file');
            if isequal(f, 0), return; end

            app.InputEditField.Value = fullfile(p, f);
            app.clearMoundSurfaceSession();
            if strlength(string(app.OutputEditField.Value)) == 0 || app.OutputWasAutoDefaulted
                app.OutputEditField.Value = p;
                app.OutputWasAutoDefaulted = true;
            end
            app.logStatus({
                'Input VK4 selected.'
                ['Input: ' char(app.InputEditField.Value)]
                ['Output: ' char(app.OutputEditField.Value)]
                });
            app.updateModuleButtonStates();
        end

        function onBrowseOutput(app, ~, ~)
            startDir = char(app.OutputEditField.Value);
            if strlength(string(startDir)) == 0 || ~exist(startDir, 'dir')
                startDir = pwd;
            end
            p = uigetdir(startDir, 'Choose output folder');
            if isequal(p, 0), return; end
            app.OutputEditField.Value = p;
            app.OutputWasAutoDefaulted = false;
            app.clearMoundSurfaceSession();
            app.logStatus({'Output folder selected.'; ['Output: ' p]});
        end

        function onBrowseBestParams(app, ~, ~)
            [f, p] = uigetfile('*.mat', 'Choose bestParams MAT file');
            if isequal(f, 0), return; end

            candidatePath = fullfile(p, f);
            [isValid, msg, hasDetectionSettings] = app.validateBestParamsFile(candidatePath);
            if ~isValid
                app.BestParamsEditField.Value = '';
                app.BestParamsIsValid = false;
                app.BestParamsHasDetectionSettings = false;
                app.clearMoundSurfaceSession();
                app.logStatus({'Invalid bestParams file.'; msg});
                uialert(app.UIFigure, msg, 'Invalid bestParams File', 'Interpreter', 'none');
            else
                app.BestParamsEditField.Value = candidatePath;
                app.BestParamsIsValid = true;
                app.BestParamsHasDetectionSettings = hasDetectionSettings;
                app.clearMoundSurfaceSession();
                if hasDetectionSettings
                    app.logStatus({'bestParams file selected.'; ['bestParams: ' candidatePath]});
                else
                    app.logStatus({
                        'bestParams file selected, but detection-setting columns were not found.'
                        'Mound/Surface Analysis needs a bestParams_<imageName>.mat file saved from the updated GUI workflow.'
                        ['bestParams: ' candidatePath]
                        });
                end
            end
            app.updateModuleButtonStates();
        end

        function [isValid, msg, hasDetectionSettings] = validateBestParamsFile(app, matPath)
            isValid = false;
            hasDetectionSettings = false;
            if ~exist(matPath, 'file')
                msg = sprintf('File not found:\n%s', matPath);
                return;
            end
            try
                info = whos('-file', matPath);
                names = {info.name};
                bestParamsVarName = app.getCurrentBestParamsVariableName();
                if strlength(string(bestParamsVarName)) == 0
                    msg = 'Choose a VK4 file before choosing bestParams for Module 3.';
                    return;
                end
                if ~ismember(bestParamsVarName, names)
                    msg = sprintf('The selected .mat file must contain a variable named %s for the selected VK4.', ...
                        bestParamsVarName);
                    return;
                end
                loaded = load(matPath, bestParamsVarName);
                selectedBestParams = loaded.(bestParamsVarName);
                required = {'morphScale', 'contrastMethod', 'gaussSigma', 'openRadius', 'clipLimit'};
                if ~istable(selectedBestParams)
                    msg = sprintf('%s must be a MATLAB table.', bestParamsVarName);
                    return;
                end
                missing = setdiff(required, selectedBestParams.Properties.VariableNames);
                if ~isempty(missing)
                    msg = [bestParamsVarName ' is missing required fields: ' strjoin(missing, ', ')];
                    return;
                end
                requiredSettings = {'fillDeepPits', 'fillThreshold', 'dilateRadius', 'minObjectArea'};
                hasDetectionSettings = all(ismember(requiredSettings, selectedBestParams.Properties.VariableNames));
                isValid = true;
                if hasDetectionSettings
                    msg = sprintf('%s is valid and includes detection settings.', bestParamsVarName);
                else
                    msg = sprintf('%s is valid, but does not include detection settings.', bestParamsVarName);
                end
            catch ME
                msg = ME.message;
            end
        end

        function updateModuleButtonStates(app)
            hasVk4 = app.hasValidVk4();
            hasBestParams = app.BestParamsIsValid && exist(char(app.BestParamsEditField.Value), 'file') == 2;
            hasModuleInputs = hasVk4 && hasBestParams && app.BestParamsHasDetectionSettings;

            app.setButtonEnabled(app.MoundDetectionButton, hasVk4);
            app.setButtonEnabled(app.LegacyRoughnessButton, hasVk4);
            app.setButtonEnabled(app.CavityAnalysisButton, false);
            app.setButtonEnabled(app.MoundSurfaceButton, hasModuleInputs);
            app.setButtonEnabled(app.SpatialAnalysisButton, hasVk4 && hasBestParams);
        end

        function tf = hasValidVk4(app)
            inputPath = char(app.InputEditField.Value);
            [~, ~, ext] = fileparts(inputPath);
            tf = strlength(string(inputPath)) > 0 && exist(inputPath, 'file') == 2 && strcmpi(ext, '.vk4');
        end

        function varName = getCurrentBestParamsVariableName(app)
            inputPath = char(app.InputEditField.Value);
            if strlength(string(inputPath)) == 0
                varName = '';
                return;
            end
            [~, imageName] = fileparts(inputPath);
            varName = ['bestParams_' matlab.lang.makeValidName(imageName)];
        end

        function setButtonEnabled(~, btn, tf)
            if tf
                btn.Enable = 'on';
            else
                btn.Enable = 'off';
            end
        end

        function tf = confirmAnalysisSwitch(app, targetAnalysisId)
            tf = true;
            if strcmp(app.CurrentAnalysisId, targetAnalysisId)
                return;
            end
            unsavedIds = app.UnsavedAnalysisIds;
            if isempty(unsavedIds)
                return;
            end

            names = cellfun(@(id) app.analysisDisplayName(id), unsavedIds, 'UniformOutput', false);
            msg = sprintf('Unsaved results exist for:\n\n%s\n\nSave before switching analyses?', ...
                strjoin(names, newline));
            choice = uiconfirm(app.UIFigure, msg, 'Unsaved Analysis Results', ...
                'Options', {'Save', 'Continue without saving', 'Cancel'}, ...
                'DefaultOption', 1, 'CancelOption', 3);
            switch choice
                case 'Save'
                    tf = app.saveUnsavedAnalyses(unsavedIds);
                case 'Continue without saving'
                    app.UnsavedAnalysisIds = setdiff(app.UnsavedAnalysisIds, unsavedIds, 'stable');
                    tf = true;
                otherwise
                    tf = false;
            end
        end

        function tf = saveUnsavedAnalyses(app, analysisIds)
            tf = true;
            for i = 1:numel(analysisIds)
                try
                    switch analysisIds{i}
                        case 'moundDetection'
                            app.onDone([], []);
                        case 'moundSurface'
                            app.onSaveAllMoundSurfaceTabs();
                        case 'legacyRoughness'
                            app.onLegacyDone();
                    end
                catch ME
                    tf = false;
                    uialert(app.UIFigure, ME.message, 'Save Error', 'Interpreter', 'none');
                    return;
                end
            end
        end

        function markAnalysisDirty(app, analysisId)
            if ~any(strcmp(app.UnsavedAnalysisIds, analysisId))
                app.UnsavedAnalysisIds{end+1} = analysisId;
            end
        end

        function markAnalysisClean(app, analysisId)
            app.UnsavedAnalysisIds = setdiff(app.UnsavedAnalysisIds, {analysisId}, 'stable');
        end

        function name = analysisDisplayName(~, analysisId)
            switch analysisId
                case 'moundDetection'
                    name = 'Mound Detection';
                case 'cavityAnalysis'
                    name = 'Cavity Analysis';
                case 'moundSurface'
                    name = 'Mound/Surface Analysis';
                case 'spatialAnalysis'
                    name = 'Spatial Analysis';
                case 'legacyRoughness'
                    name = 'Legacy Roughness';
                otherwise
                    name = analysisId;
            end
        end

        function onMoundDetection(app, ~, ~)
            if ~app.hasValidVk4()
                uialert(app.UIFigure, 'Choose a valid .vk4 file before starting mound detection.', 'Missing Input');
                return;
            end
            if ~app.confirmAnalysisSwitch('moundDetection')
                return;
            end
            app.CurrentAnalysisId = 'moundDetection';
            app.stopLegacyPointerCallbacks();
            app.MoundDetectionButton.BackgroundColor = app.ActiveButtonColor;
            app.MoundSurfaceButton.BackgroundColor = app.IdleButtonColor;
            app.LegacyRoughnessButton.BackgroundColor = app.IdleButtonColor;
            app.showMoundSettings(true);
            app.showMoundSurfaceSettings(false);
            app.showReviewPanel(false);
            app.logStatus({
                'Mound Detection selected.'
                'Set reflection-correction options, then run mound detection.'
                });
        end

        function showMoundSettings(app, isVisible)
            if isVisible
                app.LeftGrid.RowHeight = {28, 28, 28, 28, 28, 28, 30, 30, 30, 30, 30, 280, '1x'};
                app.MoundSettingsPanel.Visible = 'on';
                app.MoundSurfaceSettingsPanel.Visible = 'off';
            else
                app.MoundSettingsPanel.Visible = 'off';
                if strcmp(app.MoundSurfaceSettingsPanel.Visible, 'off')
                    app.LeftGrid.RowHeight = {28, 28, 28, 28, 28, 28, 30, 30, 30, 30, 30, 0, '1x'};
                end
            end
        end

        function showMoundSurfaceSettings(app, isVisible)
            if isVisible
                app.LeftGrid.RowHeight = {28, 28, 28, 28, 28, 28, 30, 30, 30, 30, 30, 250, '1x'};
                app.MoundSurfaceSettingsPanel.Visible = 'on';
                app.MoundSettingsPanel.Visible = 'off';
            else
                app.MoundSurfaceSettingsPanel.Visible = 'off';
                if strcmp(app.MoundSettingsPanel.Visible, 'off')
                    app.LeftGrid.RowHeight = {28, 28, 28, 28, 28, 28, 30, 30, 30, 30, 30, 0, '1x'};
                end
            end
        end

        function showReviewPanel(app, isVisible)
            if isVisible
                app.ReviewPanel.Visible = 'on';
            else
                app.ReviewPanel.Visible = 'off';
            end
        end

        function onPickFillThreshold(app, ~, ~)
            inputPath = char(app.InputEditField.Value);
            if ~app.hasValidVk4()
                uialert(app.UIFigure, 'Choose an input .vk4 file before picking a fill threshold.', 'Missing Input');
                return;
            end

            app.logStatus({
                'Picking fill threshold...'
                ['Input: ' inputPath]
                'Use the helper window, then click Confirm.'
                });
            drawnow;

            fillThreshold = pickFillThreshold(inputPath);
            app.FillDeepPitsCheckBox.Value = true;
            app.FillThresholdField.Value = fillThreshold;
            app.logStatus({
                'Fill threshold selected.'
                sprintf('fillThreshold = %.3f', fillThreshold)
                });
        end

        function onRunMoundDetection(app, ~, ~)
            if ~app.hasValidVk4()
                uialert(app.UIFigure, 'Choose a valid .vk4 file before running mound detection.', 'Missing Input');
                return;
            end
            if strlength(string(app.OutputEditField.Value)) == 0
                uialert(app.UIFigure, 'Choose an output folder before running mound detection.', 'Missing Output');
                return;
            end

            app.RunMoundDetectionButton.BackgroundColor = app.RunningButtonColor;
            app.createMoundReviewAreaContent();
            app.showReviewPanel(true);
            app.clearReviewTabs();
            app.setTierControlsEnabled(false);
            app.setMoundControlsEnabled(false);

            try
                inputPath = char(app.InputEditField.Value);
                outputDir = char(app.OutputEditField.Value);
                [~, imageName] = fileparts(inputPath);
                moundDetectionOutputDir = app.getMoundDetectionExportDir(outputDir, imageName);
                if ~exist(moundDetectionOutputDir, 'dir')
                    mkdir(moundDetectionOutputDir);
                end
                app.MoundGuiState = refineMoundsStableGuiCore('init', inputPath, ...
                    logical(app.FillDeepPitsCheckBox.Value), app.getFillThresholdValue(), ...
                    3, 20, moundDetectionOutputDir, double(app.MaxEvalsField.Value), ...
                    @(msg) app.appendLog(msg));
                [app.MoundGuiState, result] = refineMoundsStableGuiCore('runInitial', app.MoundGuiState);
                app.addMoundReviewTab(result);
                app.markAnalysisDirty('moundDetection');
                app.RunMoundDetectionButton.BackgroundColor = app.ActiveButtonColor;
                app.setTierControlsEnabled(true);
            catch ME
                app.RunMoundDetectionButton.BackgroundColor = app.IdleButtonColor;
                app.logStatus({'Mound detection failed.'; ME.message});
                uialert(app.UIFigure, ME.message, 'Mound Detection Error', 'Interpreter', 'none');
            end
            app.setMoundControlsEnabled(true);
        end

        function fillThreshold = getFillThresholdValue(app)
            fillThreshold = double(app.FillThresholdField.Value);
            if ~logical(app.FillDeepPitsCheckBox.Value) || isnan(fillThreshold) || ...
                    fillThreshold <= 0 || fillThreshold >= 1
                fillThreshold = [];
            end
        end

        function onDone(app, ~, ~)
            if isempty(fieldnames(app.MoundGuiState))
                return;
            end
            try
                selectedResult = app.getSelectedMoundReviewResult();
                app.MoundGuiState.bestParams = selectedResult.bestParams;
                [app.MoundGuiState, savePath] = refineMoundsStableGuiCore('accept', app.MoundGuiState);
                [centroidPath, spacingPath] = app.saveSelectedMoundFigures(selectedResult);
                app.BestParamsEditField.Value = savePath;
                app.BestParamsIsValid = true;
                app.BestParamsHasDetectionSettings = true;
                app.clearMoundSurfaceSession();
                app.updateModuleButtonStates();
                app.markAnalysisClean('moundDetection');
                app.logStatus({
                    'Mound detection accepted.'
                    ['Saved bestParams: ' savePath]
                    ['Saved centroid figure: ' centroidPath]
                    ['Saved spacing figure: ' spacingPath]
                    });
            catch ME
                app.logStatus({'Saving bestParams failed.'; ME.message});
                uialert(app.UIFigure, ME.message, 'Save Error', 'Interpreter', 'none');
            end
        end

        function onTooFew(app, ~, ~)
            app.runFeedback('tooFew', []);
        end

        function onTooMany(app, ~, ~)
            app.runFeedback('tooMany', []);
        end

        function onManualCount(app, ~, ~)
            manualCount = double(app.ManualCountField.Value);
            if isnan(manualCount) || manualCount < 1
                uialert(app.UIFigure, 'Enter a positive expected mound count.', 'Manual Count Required');
                return;
            end
            app.runFeedback('manual', manualCount);
        end

        function runFeedback(app, action, manualCount)
            if isempty(fieldnames(app.MoundGuiState))
                return;
            end
            app.setTierControlsEnabled(false);
            app.setMoundControlsEnabled(false);
            try
                [app.MoundGuiState, result] = refineMoundsStableGuiCore('feedback', ...
                    app.MoundGuiState, action, manualCount);
                app.addMoundReviewTab(result);
                app.markAnalysisDirty('moundDetection');
                app.setTierControlsEnabled(true);
            catch ME
                app.logStatus({'Mound detection feedback failed.'; ME.message});
                uialert(app.UIFigure, ME.message, 'Mound Detection Error', 'Interpreter', 'none');
                app.setTierControlsEnabled(true);
            end
            app.setMoundControlsEnabled(true);
        end

        function setMoundControlsEnabled(app, tf)
            state = 'off';
            if tf, state = 'on'; end
            app.FillDeepPitsCheckBox.Enable = state;
            app.FillThresholdField.Enable = state;
            app.PickFillThresholdButton.Enable = state;
            app.MaxEvalsField.Enable = state;
            app.RunMoundDetectionButton.Enable = state;
        end

        function setTierControlsEnabled(app, tf)
            state = 'off';
            if tf, state = 'on'; end
            app.DoneButton.Enable = state;
            app.TooFewButton.Enable = state;
            app.TooManyButton.Enable = state;
            app.ManualCountField.Enable = state;
            app.ManualCountButton.Enable = state;
        end

        function clearReviewTabs(app)
            existingTabs = app.ReviewTabGroup.Children;
            delete(existingTabs);
            app.MoundResultCount = 0;
            app.MoundReviewResults = {};
        end

        function addMoundReviewTab(app, result)
            app.MoundResultCount = app.MoundResultCount + 1;
            tabTitle = sprintf('%02d %s', app.MoundResultCount, result.tierLabel);
            tab = uitab(app.ReviewTabGroup, 'Title', tabTitle);
            tab.UserData = app.MoundResultCount;
            app.MoundReviewResults{app.MoundResultCount} = result;
            tabGrid = uigridlayout(tab, [1 1]);
            tabGrid.ColumnWidth = {'1x'};
            tabGrid.RowHeight = {'1x'};
            tabGrid.Padding = [8 8 8 8];

            plotTabGroup = uitabgroup(tabGrid);
            plotTabGroup.Layout.Row = 1;
            plotTabGroup.Layout.Column = 1;

            overlayTab = uitab(plotTabGroup, 'Title', 'Centroid Overlay');
            overlayGrid = uigridlayout(overlayTab, [1 1]);
            overlayGrid.Padding = [6 6 6 6];
            axOverlay = uiaxes(overlayGrid);
            imshow(result.I, [], 'Parent', axOverlay);
            hold(axOverlay, 'on');
            if ~isempty(result.centroids)
                plot(axOverlay, result.centroids(:,1), result.centroids(:,2), 'r+', ...
                    'MarkerSize', 6, 'LineWidth', 1.0);
            end
            hold(axOverlay, 'off');
            title(axOverlay, sprintf('%s | %d mounds | target %.0f', ...
                result.tierLabel, result.nCurrent, result.nMid), 'Interpreter', 'none');

            spacingTab = uitab(plotTabGroup, 'Title', 'Spacing Distribution');
            spacingGrid = uigridlayout(spacingTab, [1 1]);
            spacingGrid.Padding = [6 6 6 6];
            axHist = uiaxes(spacingGrid);
            if ~isempty(result.spacingDistances)
                histogram(axHist, result.spacingDistances, 35, ...
                    'FaceColor', [0.3 0.6 0.9], 'EdgeColor', 'none', 'FaceAlpha', 0.85);
                xline(axHist, mean(result.spacingDistances), 'r-', 'LineWidth', 1.5);
                xlabel(axHist, 'NN distance (px)');
                ylabel(axHist, 'Edge count');
                title(axHist, sprintf('NN spacing | CV=%.3f', result.spacingCv));
                grid(axHist, 'on');
            else
                text(axHist, 0.5, 0.5, 'Too few mounds', 'HorizontalAlignment', 'center');
                axis(axHist, 'off');
            end

            plotTabGroup.SelectedTab = overlayTab;
            app.ReviewTabGroup.SelectedTab = tab;
            app.updateMoundDetectionSummaryFromSelectedTab();
            app.appendLog(sprintf('Review tab added: %s (%d mounds).', tabTitle, result.nCurrent));
        end

        function updateMoundDetectionSummaryFromSelectedTab(app)
            if ~isgraphics(app.ReviewSummaryTable) || isempty(app.ReviewTabGroup.SelectedTab)
                return;
            end
            idx = app.ReviewTabGroup.SelectedTab.UserData;
            if isempty(idx) || idx < 1 || idx > numel(app.MoundReviewResults) || ...
                    isempty(app.MoundReviewResults{idx})
                return;
            end
            result = app.MoundReviewResults{idx};
            metric = {'Tier'; 'Mound count'; 'Target count'; 'Spacing CV'; 'Mean spacing (px)'};
            spacingMean = NaN;
            if isfield(result, 'spacingDistances') && ~isempty(result.spacingDistances)
                spacingMean = mean(result.spacingDistances, 'omitnan');
            end
            value = {result.tierLabel; result.nCurrent; result.nMid; result.spacingCv; spacingMean};
            app.ReviewSummaryTable.Data = table(metric, value, 'VariableNames', {'Metric', 'Value'});
            if isgraphics(app.ReviewInfoTextArea)
                app.ReviewInfoTextArea.Value = {
                    ['Review result: ' result.tierLabel]
                    'Analysis information panel reserved for future details.'
                    };
            end
        end

        function result = getSelectedMoundReviewResult(app)
            if isempty(app.ReviewTabGroup.Children) || isempty(app.ReviewTabGroup.SelectedTab)
                error('SOLFAnalysisApp:NoMoundReviewTab', ...
                    'No mound-detection review tab is selected.');
            end
            idx = app.ReviewTabGroup.SelectedTab.UserData;
            if isempty(idx) || idx < 1 || idx > numel(app.MoundReviewResults) || ...
                    isempty(app.MoundReviewResults{idx})
                error('SOLFAnalysisApp:MissingMoundReviewResult', ...
                    'The selected review tab does not have saved mound-detection data.');
            end
            result = app.MoundReviewResults{idx};
        end

        function [centroidPath, spacingPath] = saveSelectedMoundFigures(app, result)
            outputDir = char(app.OutputEditField.Value);
            if strlength(string(outputDir)) == 0
                error('SOLFAnalysisApp:MissingOutputDir', ...
                    'Choose an output folder before accepting mound detection.');
            end

            [~, imageName] = fileparts(char(app.InputEditField.Value));
            outputDir = app.getMoundDetectionExportDir(outputDir, imageName);
            if ~exist(outputDir, 'dir')
                mkdir(outputDir);
            end
            safeTier = regexprep(result.tierLabel, '[^\w.-]', '_');
            centroidPath = fullfile(outputDir, sprintf('%s_%s_centroids.png', imageName, safeTier));
            spacingPath = fullfile(outputDir, sprintf('%s_%s_spacing.png', imageName, safeTier));

            fig1 = figure('Visible', 'off', 'Name', 'Selected mound centroids', ...
                'Position', [50 50 1100 850], 'Color', 'w');
            ax1 = axes(fig1);
            imshow(result.I, [], 'Parent', ax1);
            hold(ax1, 'on');
            if ~isempty(result.centroids)
                plot(ax1, result.centroids(:,1), result.centroids(:,2), 'r+', ...
                    'MarkerSize', 6, 'LineWidth', 1.0);
            end
            title(ax1, sprintf('%s | %s | n=%d', imageName, result.tierLabel, result.nCurrent), ...
                'Interpreter', 'none');
            hold(ax1, 'off');
            exportgraphics(fig1, centroidPath, 'Resolution', 150);
            close(fig1);

            fig2 = figure('Visible', 'off', 'Name', 'Selected mound spacing', ...
                'Position', [200 200 800 500], 'Color', 'w');
            ax2 = axes(fig2);
            if ~isempty(result.spacingDistances)
                histogram(ax2, result.spacingDistances, 35, ...
                    'FaceColor', [0.25 0.55 0.85], 'EdgeColor', 'none', 'FaceAlpha', 0.85);
                hold(ax2, 'on');
                xline(ax2, mean(result.spacingDistances), 'r-', 'LineWidth', 1.5, ...
                    'Label', sprintf('mean=%.1f px', mean(result.spacingDistances)));
                hold(ax2, 'off');
                xlabel(ax2, 'NN spacing (px)');
                ylabel(ax2, 'Edge count');
                title(ax2, sprintf('%s | %s | CV=%.3f | n=%d', ...
                    imageName, result.tierLabel, result.spacingCv, result.nCurrent), ...
                    'Interpreter', 'none');
                grid(ax2, 'on');
            else
                text(ax2, 0.5, 0.5, 'Too few mounds', 'HorizontalAlignment', 'center');
                axis(ax2, 'off');
            end
            exportgraphics(fig2, spacingPath, 'Resolution', 150);
            close(fig2);
        end

        function onMoundSurfaceAnalysis(app, ~, ~)
            if ~app.hasValidVk4()
                uialert(app.UIFigure, 'Choose a valid .vk4 file before starting mound/surface analysis.', 'Missing Input');
                return;
            end
            if ~app.BestParamsHasDetectionSettings
                uialert(app.UIFigure, ...
                    'Choose the selected image''s bestParams_<imageName>.mat file saved from the updated mound-detection GUI workflow.', ...
                    'Missing Detection Settings');
                return;
            end
            if ~app.confirmAnalysisSwitch('moundSurface')
                return;
            end
            app.CurrentAnalysisId = 'moundSurface';
            app.stopLegacyPointerCallbacks();
            app.MoundDetectionButton.BackgroundColor = app.IdleButtonColor;
            app.MoundSurfaceButton.BackgroundColor = app.ActiveButtonColor;
            app.LegacyRoughnessButton.BackgroundColor = app.IdleButtonColor;
            app.showMoundSettings(false);
            app.showMoundSurfaceSettings(true);
            app.showReviewPanel(false);
            app.logStatus({
                'Mound/Surface Analysis selected.'
                'Choose output groups, then run analysis.'
                });
        end

        function onCavityAnalysis(app, ~, ~)
            if ~app.confirmAnalysisSwitch('cavityAnalysis')
                return;
            end
            app.CurrentAnalysisId = 'cavityAnalysis';
            app.stopLegacyPointerCallbacks();
            app.MoundDetectionButton.BackgroundColor = app.IdleButtonColor;
            app.MoundSurfaceButton.BackgroundColor = app.IdleButtonColor;
            app.LegacyRoughnessButton.BackgroundColor = app.IdleButtonColor;
            app.showMoundSettings(false);
            app.showMoundSurfaceSettings(false);
            app.showReviewPanel(false);
            app.logStatus({'Cavity Analysis is not implemented in the GUI yet.'});
        end

        function onSpatialAnalysis(app, ~, ~)
            if ~app.confirmAnalysisSwitch('spatialAnalysis')
                return;
            end
            app.CurrentAnalysisId = 'spatialAnalysis';
            app.stopLegacyPointerCallbacks();
            app.MoundDetectionButton.BackgroundColor = app.IdleButtonColor;
            app.MoundSurfaceButton.BackgroundColor = app.IdleButtonColor;
            app.LegacyRoughnessButton.BackgroundColor = app.IdleButtonColor;
            app.showMoundSettings(false);
            app.showMoundSurfaceSettings(false);
            app.showReviewPanel(false);
            app.logStatus({'Spatial Analysis is not implemented in the GUI yet.'});
        end

        function onRunMoundSurfaceAnalysis(app, ~, ~)
            selectedGroups = app.getSelectedMoundSurfaceGroups();
            if isempty(selectedGroups)
                uialert(app.UIFigure, 'Select at least one mound/surface output group.', 'No Groups Selected');
                return;
            end
            inputPath = char(app.InputEditField.Value);
            outputDir = char(app.OutputEditField.Value);
            bestParamsPath = char(app.BestParamsEditField.Value);
            if strlength(string(outputDir)) == 0
                uialert(app.UIFigure, 'Choose an output folder before running mound/surface analysis.', 'Missing Output');
                return;
            end

            app.RunMoundSurfaceButton.BackgroundColor = app.RunningButtonColor;
            app.setMoundSurfaceControlsEnabled(false);
            sessionWasReset = app.ensureMoundSurfaceSession(inputPath, bestParamsPath, outputDir);
            if sessionWasReset || ~isgraphics(app.ReviewTabGroup)
                app.createMoundSurfaceReviewAreaContent();
            else
                app.appendLog('Adding newly selected mound/surface output groups to the existing review.');
            end
            app.showReviewPanel(true);
            drawnow;

            try
                app.ensureMoundSpacingContext(inputPath, bestParamsPath, outputDir);
                if app.selectedGroupsNeedMoundShape(selectedGroups)
                    app.ensureMoundShapeContext(selectedGroups, outputDir);
                end
                app.addMoundSurfaceTabs(selectedGroups);
                app.markAnalysisDirty('moundSurface');
                app.RunMoundSurfaceButton.BackgroundColor = app.ActiveButtonColor;
                app.appendLog('Mound/surface analysis update complete.');
            catch ME
                app.RunMoundSurfaceButton.BackgroundColor = app.IdleButtonColor;
                app.logStatus({'Mound/surface analysis failed.'; ME.message});
                uialert(app.UIFigure, ME.message, 'Mound/Surface Analysis Error', 'Interpreter', 'none');
            end
            app.setMoundSurfaceControlsEnabled(true);
        end

        function sessionWasReset = ensureMoundSurfaceSession(app, inputPath, bestParamsPath, outputDir)
            sessionKey = app.makeMoundSurfaceSessionKey(inputPath, bestParamsPath, outputDir);
            sessionWasReset = true;
            if isfield(app.MoundSurfaceSession, 'sessionKey') && ...
                    strcmp(app.MoundSurfaceSession.sessionKey, sessionKey)
                sessionWasReset = false;
                return;
            end

            app.clearMoundSurfaceSession();
            app.MoundSurfaceSession = struct( ...
                'sessionKey', sessionKey, ...
                'inputPath', inputPath, ...
                'bestParamsPath', bestParamsPath, ...
                'outputDir', outputDir, ...
                'computedGroups', {{}}, ...
                'computedStages', {{}}, ...
                'm1Ready', false, ...
                'moundShapeReady', false);
        end

        function key = makeMoundSurfaceSessionKey(~, inputPath, bestParamsPath, outputDir)
            key = strjoin({char(inputPath), char(bestParamsPath), char(outputDir)}, '|');
        end

        function clearMoundSurfaceSession(app)
            app.M1GuiResults = struct();
            app.MoundShapeGuiResults = struct();
            app.MoundSurfaceSession = struct();
            app.MoundSurfaceTabData = {};
            app.MoundSurfaceRenderedGroups = {};
            app.MoundSurfaceExportedPlotPaths = {};
        end

        function ensureMoundSpacingContext(app, inputPath, bestParamsPath, outputDir)
            if isfield(app.MoundSurfaceSession, 'm1Ready') && app.MoundSurfaceSession.m1Ready
                app.appendLog('Reusing cached Module 1 mound-spacing context.');
                return;
            end

            bestParamsVarName = app.getCurrentBestParamsVariableName();
            loaded = load(bestParamsPath, bestParamsVarName);
            bestParams = loaded.(bestParamsVarName);
            app.appendLog('Running GUI Module 1 mound-spacing context...');
            app.M1GuiResults = analyzeMoundsGuiCore(inputPath, bestParams, ...
                logical(bestParams.fillDeepPits), bestParams.fillThreshold, ...
                bestParams.dilateRadius, bestParams.minObjectArea, [], [], outputDir);
            app.MoundSurfaceSession.m1Ready = true;
            app.MoundSurfaceSession.computedStages = app.uniqueCellStrings( ...
                [app.MoundSurfaceSession.computedStages, {'moundSpacing'}]);
        end

        function tf = selectedGroupsNeedMoundShape(~, selectedGroups)
            tf = any(~strcmp(selectedGroups, 'moundSpacing'));
        end

        function ensureMoundShapeContext(app, selectedGroups, outputDir)
            if isfield(app.MoundSurfaceSession, 'moundShapeReady') && app.MoundSurfaceSession.moundShapeReady
                app.appendLog('Reusing cached Module 3 watershed/shape context.');
                app.MoundSurfaceSession.computedGroups = app.uniqueCellStrings( ...
                    [app.MoundSurfaceSession.computedGroups, selectedGroups]);
                return;
            end

            app.appendLog('Running GUI Module 3 mound/surface analysis core...');
            app.MoundShapeGuiResults = analyzeMoundShapeGuiCore(app.M1GuiResults, outputDir, selectedGroups);
            app.MoundSurfaceSession.moundShapeReady = true;
            app.MoundSurfaceSession.computedGroups = app.uniqueCellStrings( ...
                [app.MoundSurfaceSession.computedGroups, selectedGroups]);
            if isfield(app.MoundShapeGuiResults, 'computedStages')
                app.MoundSurfaceSession.computedStages = app.uniqueCellStrings( ...
                    [app.MoundSurfaceSession.computedStages, cellstr(app.MoundShapeGuiResults.computedStages(:).')]);
            end
        end

        function out = uniqueCellStrings(~, in)
            in = in(~cellfun('isempty', in));
            out = cellstr(unique(string(in), 'stable'));
        end

        function selectedGroups = getSelectedMoundSurfaceGroups(app)
            selectedGroups = {};
            if app.MoundSpacingCheckBox.Value, selectedGroups{end+1} = 'moundSpacing'; end
            if app.RoughnessCheckBox.Value, selectedGroups{end+1} = 'roughness'; end
            if app.DirectHeightCheckBox.Value, selectedGroups{end+1} = 'directHeight'; end
            if app.FootprintShapeCheckBox.Value, selectedGroups{end+1} = 'footprintShape'; end
            if app.AxesOrientationCheckBox.Value, selectedGroups{end+1} = 'axesOrientation'; end
            if app.SurfaceAreaVolumeCheckBox.Value, selectedGroups{end+1} = 'surfaceAreaVolume'; end
            if app.WholeImageSlicesCheckBox.Value, selectedGroups{end+1} = 'wholeImageSlices'; end
            if app.QADiagnosticsCheckBox.Value, selectedGroups{end+1} = 'qaDiagnostics'; end
        end

        function setMoundSurfaceControlsEnabled(app, tf)
            state = 'off';
            if tf, state = 'on'; end
            controls = [app.MoundSpacingCheckBox, app.RoughnessCheckBox, app.DirectHeightCheckBox, ...
                app.FootprintShapeCheckBox, app.AxesOrientationCheckBox, app.SurfaceAreaVolumeCheckBox, ...
                app.WholeImageSlicesCheckBox, app.QADiagnosticsCheckBox, app.RunMoundSurfaceButton];
            for i = 1:numel(controls)
                controls(i).Enable = state;
            end
        end

        function logStatus(app, lines)
            if ischar(lines) || isstring(lines)
                lines = cellstr(lines);
            end
            app.StatusTextArea.Value = lines;
            app.scrollStatusToBottom();
        end

        function appendLog(app, msg)
            if isstring(msg), msg = char(msg); end
            current = app.StatusTextArea.Value;
            if ischar(current), current = {current}; end
            app.StatusTextArea.Value = [current; {msg}];
            app.scrollStatusToBottom();
        end

        function scrollStatusToBottom(app)
            if isgraphics(app.StatusTextArea)
                drawnow limitrate;
                scroll(app.StatusTextArea, 'bottom');
            end
        end

        function createMoundSurfaceReviewAreaContent(app)
            app.stopLegacyPointerCallbacks();
            app.ReviewPanel.Title = 'Mound/Surface Analysis Review';
            delete(app.ReviewPanel.Children);
            app.MoundSurfaceTabData = {};
            app.MoundSurfaceRenderedGroups = {};

            app.ReviewGrid = uigridlayout(app.ReviewPanel, [1 2]);
            app.ReviewGrid.ColumnWidth = {'1x', 380};
            app.ReviewGrid.RowHeight = {'1x'};
            app.ReviewGrid.Padding = [8 8 8 8];
            app.ReviewGrid.ColumnSpacing = 10;

            leftReviewGrid = uigridlayout(app.ReviewGrid, [2 1]);
            leftReviewGrid.Layout.Row = 1;
            leftReviewGrid.Layout.Column = 1;
            leftReviewGrid.RowHeight = {'1x', 42};
            leftReviewGrid.Padding = [0 0 0 0];
            leftReviewGrid.RowSpacing = 8;

            app.ReviewTabGroup = uitabgroup(leftReviewGrid);
            app.ReviewTabGroup.Layout.Row = 1;
            app.ReviewTabGroup.Layout.Column = 1;
            app.ReviewTabGroup.SelectionChangedFcn = @(src, event) app.updateSharedReviewSummaryFromSelectedTab();

            saveGrid = uigridlayout(leftReviewGrid, [1 4]);
            saveGrid.Layout.Row = 2;
            saveGrid.Layout.Column = 1;
            saveGrid.ColumnWidth = {130, 100, 110, '1x'};
            saveGrid.Padding = [0 0 0 0];

            app.SaveCurrentTabButton = uibutton(saveGrid, 'push', 'Text', 'Save Current Tab');
            app.SaveCurrentTabButton.ButtonPushedFcn = @(src, event) app.onSaveCurrentMoundSurfaceTab();
            app.SaveAllTabsButton = uibutton(saveGrid, 'push', 'Text', 'Save All');
            app.SaveAllTabsButton.ButtonPushedFcn = @(src, event) app.onSaveAllMoundSurfaceTabs();

            rightReviewGrid = uigridlayout(app.ReviewGrid, [3 1]);
            rightReviewGrid.Layout.Row = 1;
            rightReviewGrid.Layout.Column = 2;
            rightReviewGrid.RowHeight = {190, '1x', 135};
            rightReviewGrid.Padding = [0 0 0 0];
            rightReviewGrid.RowSpacing = 8;

            summaryPanel = uipanel(rightReviewGrid, 'Title', 'Summary');
            summaryPanel.Layout.Row = 1;
            summaryGrid = uigridlayout(summaryPanel, [1 1]);
            summaryGrid.Padding = [6 6 6 6];
            app.ReviewSummaryTable = uitable(summaryGrid);
            app.ReviewSummaryTable.Data = table();

            app.ReviewInfoTextArea = uitextarea(rightReviewGrid, 'Editable', 'off');
            app.ReviewInfoTextArea.Layout.Row = 2;
            app.ReviewInfoTextArea.Value = {'Analysis information panel reserved for future details.'};

            app.StatusTextArea = uitextarea(rightReviewGrid, 'Editable', 'off');
            app.StatusTextArea.Layout.Row = 3;
            app.StatusTextArea.Layout.Column = 1;
            app.logStatus({
                'Preparing mound/surface analysis...'
                ['Input: ' char(app.InputEditField.Value)]
                ['Output: ' char(app.OutputEditField.Value)]
                });
        end

        function addMoundSurfaceTabs(app, selectedGroups)
            for i = 1:numel(selectedGroups)
                groupId = selectedGroups{i};
                if any(strcmp(app.MoundSurfaceRenderedGroups, groupId))
                    app.appendLog(['Review tab already shown: ' app.moundSurfaceGroupTitle(groupId)]);
                    continue;
                end
                app.addMoundSurfaceTab(groupId);
            end
            if isempty(app.ReviewTabGroup.Children)
                app.appendLog('No review tabs were created.');
            end
        end

        function addMoundSurfaceTab(app, groupId)
            tabSpec = app.getMoundSurfaceTabSpec(groupId);
            tab = uitab(app.ReviewTabGroup, 'Title', tabSpec.title);
            tabIndex = numel(app.MoundSurfaceTabData) + 1;
            tab.UserData = tabIndex;

            tabGrid = uigridlayout(tab, [1 1]);
            tabGrid.ColumnWidth = {'1x'};
            tabGrid.RowHeight = {'1x'};
            tabGrid.Padding = [8 8 8 8];

            imagePanel = uipanel(tabGrid, 'Title', tabSpec.figureTitle);
            imagePanel.Layout.Row = 1;
            imagePanel.Layout.Column = 1;
            tabSpec = app.populatePlotPanel(imagePanel, tabSpec);
            app.MoundSurfaceTabData{tabIndex} = tabSpec;

            app.ReviewTabGroup.SelectedTab = tab;
            app.updateSharedReviewSummaryFromSelectedTab();
            app.MoundSurfaceRenderedGroups{end+1} = groupId;
            app.appendLog(['Review tab added: ' tabSpec.title]);
        end

        function updateSharedReviewSummaryFromSelectedTab(app)
            if ~isgraphics(app.ReviewSummaryTable) || isempty(app.ReviewTabGroup.SelectedTab)
                return;
            end
            idx = app.ReviewTabGroup.SelectedTab.UserData;
            if isempty(idx) || idx < 1 || idx > numel(app.MoundSurfaceTabData) || ...
                    isempty(app.MoundSurfaceTabData{idx})
                return;
            end
            tabSpec = app.MoundSurfaceTabData{idx};
            app.ReviewSummaryTable.Data = tabSpec.summaryTable;
            if isgraphics(app.ReviewInfoTextArea)
                app.ReviewInfoTextArea.Value = {
                    ['Output group: ' tabSpec.title]
                    'Analysis information panel reserved for future details.'
                    };
            end
        end

        function titleText = moundSurfaceGroupTitle(~, groupId)
            switch groupId
                case 'moundSpacing', titleText = 'Mound Spacing';
                case 'roughness', titleText = 'Roughness';
                case 'directHeight', titleText = 'Direct Height';
                case 'footprintShape', titleText = 'Footprint Shape';
                case 'axesOrientation', titleText = 'Axes And Orientation';
                case 'surfaceAreaVolume', titleText = 'Surface Area And Volume';
                case 'wholeImageSlices', titleText = 'Whole-Image Slices';
                otherwise, titleText = 'QA Diagnostics';
            end
        end

        function tabSpec = populatePlotPanel(app, parentPanel, tabSpec)
            plotPanelGrid = uigridlayout(parentPanel, [1 1]);
            plotPanelGrid.Padding = [0 0 0 0];
            plotPanelGrid.RowSpacing = 0;
            plotPanelGrid.ColumnSpacing = 0;

            plotTabGroup = uitabgroup(plotPanelGrid);
            plotTabGroup.Layout.Row = 1;
            plotTabGroup.Layout.Column = 1;
            for i = 1:numel(tabSpec.plots)
                plotTab = uitab(plotTabGroup, 'Title', tabSpec.plots(i).title);
                plotTabGrid = uigridlayout(plotTab, [1 1]);
                plotTabGrid.Padding = [6 6 6 6];
                plotTabGrid.RowSpacing = 0;
                plotTabGrid.ColumnSpacing = 0;

                ax = uiaxes(plotTabGrid);
                ax.Layout.Row = 1;
                ax.Layout.Column = 1;
                app.renderMoundSurfacePlot(ax, tabSpec.plots(i));
                tabSpec.plots(i).Axes = ax;
            end
        end

        function tabSpec = getMoundSurfaceTabSpec(app, groupId)
            switch groupId
                case 'moundSpacing'
                    tabSpec = app.makeTabSpec(groupId, 'Mound Spacing', 'Delaunay And NN Spacing', ...
                        [app.makePlotSpec('delaunay', 'Delaunay Overlay', 'delaunay', {}), ...
                         app.makePlotSpec('nn_dist_um', 'NN Histogram', 'histM1', {'nn_dist_um'})], ...
                        app.moundSpacingSummaryTable());
                case 'roughness'
                    tabSpec = app.makeTabSpec(groupId, 'Roughness', 'Rp/Rv/Rz Diagnostics', ...
                        [app.makePlotSpec('method_b_overlay', 'Nearest Neighbor Circle Overlay', 'methodBOverlay', {}), ...
                         app.makePlotSpec('rp', 'Rp', 'histM3', {'preferred_Rp_per_mound'}), ...
                         app.makePlotSpec('rv', 'Rv', 'histM3', {'preferred_Rv_per_mound'}), ...
                         app.makePlotSpec('rz', 'Rz', 'histM3', {'preferred_Rz_per_mound'})], ...
                        app.metricSummaryTable({'Rp_global','Rv_global','Rz_global','preferred_Rp_per_mound','preferred_Rv_per_mound','preferred_Rz_per_mound'}));
                case 'directHeight'
                    tabSpec = app.makeTabSpec(groupId, 'Direct Height', 'Mound Height Diagnostics', ...
                        [app.makePlotSpec('base_band_overlay', 'Base-Band Overlay', 'baseBandOverlay', {}), ...
                         app.makePlotSpec('height_open', 'Open Height', 'histM3', {'height_open_um'}), ...
                         app.makePlotSpec('height_typical', 'Median Height', 'histM3', {'height_typical_um'}), ...
                         app.makePlotSpec('height_crowded', 'Crowded Height', 'histM3', {'height_crowded_um'}), ...
                         app.makePlotSpec('border_z', 'Watershed Border Z', 'histM3', {'method_c_watershed_border_z_um'})], ...
                        app.metricSummaryTable({'preferred_mound_height_um','preferred_mound_base_position_um','height_open_um','height_typical_um','height_crowded_um','method_c_watershed_border_z_um'}));
                case 'footprintShape'
                    tabSpec = app.makeTabSpec(groupId, 'Footprint Shape', 'Footprint Size And Shape', ...
                        [app.makePlotSpec('shape_overlay', 'Equivalent-Diameter Overlay', 'shapeOverlay', {}), ...
                         app.makePlotSpec('footprint_axes_overlay', 'Q50 Half-Max Footprint Overlay', 'footprintAxesOverlay', {}), ...
                         app.makePlotSpec('footprint_area', 'Area', 'histM3', {'preferred_footprint_um2'}), ...
                         app.makePlotSpec('equiv_diam', 'Eq. Diameter', 'histM3', {'preferred_equiv_diam_um'}), ...
                         app.makePlotSpec('circularity', 'Circularity', 'histM3', {'preferred_circularity'}), ...
                         app.makePlotSpec('solidity', 'Solidity', 'histM3', {'preferred_solidity'}), ...
                         app.makePlotSpec('convexity', 'Convexity', 'histM3', {'preferred_convexity'})], ...
                        app.metricSummaryTable({'preferred_footprint_um2','preferred_equiv_diam_um','preferred_perimeter_um','preferred_circularity','preferred_solidity','preferred_convexity','preferred_extent'}));
                case 'axesOrientation'
                    tabSpec = app.makeTabSpec(groupId, 'Axes And Orientation', 'Ellipse And Feret Geometry', ...
                        [app.makePlotSpec('ellipse_feret_overlay', 'Q50 Half-Max Ellipse/Feret Overlay', 'footprintAxesOverlay', {}), ...
                         app.makePlotSpec('ellipse_major', 'Ellipse Major Axis', 'histM3', {'preferred_major_axis_um'}), ...
                         app.makePlotSpec('ellipse_minor', 'Ellipse Minor Axis', 'histM3', {'preferred_minor_axis_um'}), ...
                         app.makePlotSpec('feret_aspect', 'Feret Aspect', 'histM3', {'preferred_feret_aspect_ratio'}), ...
                         app.makePlotSpec('ellipse_axis', 'Ellipse Axis Ratio', 'histM3', {'preferred_ellipse_axis_ratio'}), ...
                         app.makePlotSpec('ellipse_orientation', 'Ellipse Orientation', 'histM3', {'preferred_ellipse_orientation_deg'}), ...
                         app.makePlotSpec('feret_orientation', 'Feret Orientation', 'histM3', {'preferred_orientation_deg'}), ...
                         app.makePlotSpec('orientation_agreement', 'Orientation Agreement', 'histM3', {'preferred_orientation_agreement_deg'}), ...
                         app.makePlotSpec('ar_geom', 'Height / Geom. Mean Width', 'histM3', {'preferred_aspect_ratio_geometric_mean_width'}), ...
                         app.makePlotSpec('ar_major', 'Height / Ellipse Major', 'histM3', {'preferred_aspect_ratio_ellipse_major'}), ...
                         app.makePlotSpec('ar_minor', 'Height / Ellipse Minor', 'histM3', {'preferred_aspect_ratio_ellipse_minor'})], ...
                        app.metricSummaryTable({'preferred_major_axis_um','preferred_minor_axis_um','preferred_feret_max_um','preferred_feret_min_um','preferred_feret_aspect_ratio','preferred_ellipse_axis_ratio','preferred_ellipse_orientation_deg','preferred_orientation_deg','preferred_orientation_agreement_deg','preferred_aspect_ratio_geometric_mean_width','preferred_aspect_ratio_ellipse_major','preferred_aspect_ratio_ellipse_minor'}));
                case 'surfaceAreaVolume'
                    tabSpec = app.makeTabSpec(groupId, 'Surface Area And Volume', 'Surface Area And Volume', ...
                        [app.makePlotSpec('surface_volume_overlay', 'Accepted Watershed Regions', 'surfaceAreaVolumeOverlay', {}), ...
                         app.makePlotSpec('surface_area', 'Surface Area', 'histM3', {'preferred_surface_area_um2'}), ...
                         app.makePlotSpec('peak_volume', 'Peak-Cap Volume', 'histM3', {'preferred_peak_cap_empty_volume_um3'}), ...
                         app.makePlotSpec('sa_volume', 'SA / Volume', 'histM3', {'preferred_surface_area_to_volume_inv_um'})], ...
                        app.metricSummaryTable({'preferred_surface_area_um2','preferred_peak_cap_empty_volume_um3','preferred_surface_area_to_volume_inv_um'}));
                case 'wholeImageSlices'
                    tabSpec = app.makeTabSpec(groupId, 'Whole-Image Slices', 'Whole-Image Height Slices', ...
                        [app.makePlotSpec('slice_area', 'Area vs Height', 'lineM3', {'whole_image_slice_z_rel_um', 'whole_image_cross_section_area_um2'}), ...
                         app.makePlotSpec('slice_perimeter', 'Perimeter vs Height', 'lineM3', {'whole_image_slice_z_rel_um', 'whole_image_perimeter_um'}), ...
                         app.makePlotSpec('peak_perimeter_threshold', 'Peak Perimeter Threshold', 'peakPerimeterThresholdOverlay', {}), ...
                         app.makePlotSpec('slice_sa', 'Surface Area vs Height', 'lineM3', {'whole_image_slice_z_rel_um', 'whole_image_cumulative_surface_area_um2'})], ...
                        app.metricSummaryTable({'whole_image_peak_perimeter_um','whole_image_z_at_peak_perimeter_um','whole_image_z_rel_at_peak_perimeter_um','whole_image_cross_section_area_at_peak_perimeter_um2','whole_image_z_rel_at_half_area_um','whole_image_cumulative_surface_area_um2'}));
                otherwise
                    tabSpec = app.makeTabSpec(groupId, 'QA Diagnostics', 'Watershed And Base Diagnostics', ...
                        [app.makePlotSpec('watershed_seeds', 'Watershed Seeds', 'watershedSeedsOverlay', {}), ...
                         app.makePlotSpec('watershed_boundaries', 'Watershed Boundaries', 'watershedBoundaryOverlay', {}), ...
                         app.makePlotSpec('base_band_overlay', 'Base-Band Overlay', 'baseBandOverlay', {}), ...
                         app.makePlotSpec('validity_overlay', 'Validity Overlay', 'validityOverlay', {}), ...
                         app.makePlotSpec('watershed_scores', 'Watershed Scores', 'watershedScores', {})], ...
                        app.metricSummaryTable({'n_mounds','n_total','n_valid_nn','n_valid_c','watershed_smooth_sigma_px','watershed_spacing_px','watershed_selection_score'}));
            end
        end

        function tabSpec = makeTabSpec(~, groupId, titleText, figureTitle, plots, summaryTable)
            tabSpec = struct('groupId', groupId, 'title', titleText, ...
                'figureTitle', figureTitle, 'plots', plots, ...
                'summaryTable', summaryTable);
        end

        function plotSpec = makePlotSpec(~, plotId, titleText, kind, fields)
            plotSpec = struct('id', plotId, 'title', titleText, ...
                'kind', kind, 'fields', {fields}, 'Axes', gobjects(1));
        end

        function renderMoundSurfacePlot(app, ax, plotSpec)
            cla(ax);
            switch plotSpec.kind
                case 'delaunay'
                    app.plotMoundSpacingOverlay(ax);
                case 'histM1'
                    v = app.M1GuiResults.(plotSpec.fields{1});
                    app.plotMetricHistogram(ax, v, plotSpec.title, plotSpec.fields{1});
                case 'histM3'
                    v = app.getMoundShapeMetric(plotSpec.fields{1});
                    app.plotMetricHistogram(ax, v, plotSpec.title, plotSpec.fields{1});
                case 'lineM3'
                    app.plotMoundSurfaceLineMetric(ax, plotSpec, 1.8);
                case 'watershedScores'
                    x = app.getMoundShapeMetric('watershed_sigma_candidates_px');
                    y = app.getMoundShapeMetric('watershed_sigma_scores');
                    plot(ax, x, y, '-o', 'LineWidth', 1.4, 'MarkerSize', 5);
                    xlabel(ax, 'Watershed smoothing sigma (px)');
                    ylabel(ax, 'Score');
                    title(ax, 'Watershed sigma selection', 'Interpreter', 'none');
                    grid(ax, 'on');
                case 'shapeOverlay'
                    app.plotShapeOverlay(ax);
                case 'footprintAxesOverlay'
                    app.plotFootprintAxesOverlay(ax);
                case 'baseBandOverlay'
                    app.plotBaseBandOverlay(ax);
                case 'watershedSeedsOverlay'
                    app.plotWatershedSeedsOverlay(ax);
                case 'methodBOverlay'
                    app.plotMethodBOverlay(ax);
                case 'surfaceAreaVolumeOverlay'
                    app.plotSurfaceAreaVolumeOverlay(ax);
                case 'peakPerimeterThresholdOverlay'
                    app.plotPeakPerimeterThresholdOverlay(ax);
                case 'watershedBoundaryOverlay'
                    app.plotWatershedBoundaryOverlay(ax);
                case 'validityOverlay'
                    app.plotValidityOverlay(ax);
                otherwise
                    text(ax, 0.5, 0.5, 'Plot not available', 'HorizontalAlignment', 'center');
                    axis(ax, 'off');
            end
        end

        function plotMoundSpacingOverlay(app, ax)
            app.showRawSurface(ax);
            hold(ax, 'on');
            centroids = app.M1GuiResults.centroids;
            edges = app.M1GuiResults.trimmed_edges;
            edgeLengths = app.M1GuiResults.nn_dist_um;
            if ~isempty(edges)
                climLo = prctile(edgeLengths, 5);
                climHi = prctile(edgeLengths, 95);
                cmap = parula(256);
                for k = 1:size(edges, 1)
                    p1 = centroids(edges(k, 1), :);
                    p2 = centroids(edges(k, 2), :);
                    t = (edgeLengths(k) - climLo) / max(climHi - climLo, eps);
                    cidx = max(1, min(256, round(max(0, min(1, t)) * 255) + 1));
                    plot(ax, [p1(1), p2(1)], [p1(2), p2(2)], '-', ...
                        'Color', cmap(cidx, :), 'LineWidth', 0.8);
                end
                colormap(ax, cmap);
                clim(ax, [climLo, climHi]);
                cb = colorbar(ax);
                cb.Label.String = 'NN spacing (um)';
            end
            plot(ax, centroids(:,1), centroids(:,2), 'r+', 'MarkerSize', 6, 'LineWidth', 1.0);
            hEdge = plot(ax, NaN, NaN, '-', 'Color', [0.15 0.45 0.75], 'LineWidth', 0.8);
            hCentroid = plot(ax, NaN, NaN, 'r+', 'MarkerSize', 6, 'LineWidth', 1.0);
            legend(ax, [hEdge hCentroid], {'Delaunay edge', 'Mound detection centroid'}, ...
                'Location', 'southoutside', 'Orientation', 'horizontal');
            title(ax, sprintf('%s | n=%d | %.2f um mean spacing', ...
                app.M1GuiResults.imageName, app.M1GuiResults.n_mounds, app.M1GuiResults.nn_mean_um), ...
                'Interpreter', 'none');
            axis(ax, 'image');
            hold(ax, 'off');
        end

        function plotMoundSurfaceLineMetric(app, ax, plotSpec, lineWidth)
            x = app.getMoundShapeMetric(plotSpec.fields{1});
            y = app.getMoundShapeMetric(plotSpec.fields{2});
            hCurve = plot(ax, x, y, '-', 'LineWidth', lineWidth, 'Color', [0.15 0.45 0.75]);
            hold(ax, 'on');
            if strcmp(plotSpec.id, 'slice_perimeter')
                xPeak = app.getMoundShapeMetric('whole_image_z_rel_at_peak_perimeter_um');
                yPeak = app.getMoundShapeMetric('whole_image_peak_perimeter_um');
                zAbs = app.getMoundShapeMetric('whole_image_z_at_peak_perimeter_um');
                if isfinite(xPeak) && isfinite(yPeak)
                    hPeak = plot(ax, xPeak, yPeak, 'o', ...
                        'Color', [0.85 0.15 0.15], 'MarkerFaceColor', [1.00 0.85 0.00], ...
                        'MarkerSize', 7, 'LineWidth', 1.2);
                    hX = xline(ax, xPeak, '--', 'Color', [0.85 0.15 0.15], 'LineWidth', 1.1);
                    hY = yline(ax, yPeak, '--', 'Color', [0.85 0.15 0.15], 'LineWidth', 1.1);
                    legend(ax, [hCurve hPeak hX hY], ...
                        {'Perimeter curve', 'Maximum perimeter', 'Peak relative height', 'Peak perimeter'}, ...
                        'Location', 'best');
                    title(ax, sprintf('%s | max %.3g um at %.3g um rel / %.3g um abs', ...
                        plotSpec.title, yPeak, xPeak, zAbs), 'Interpreter', 'none');
                else
                    title(ax, plotSpec.title, 'Interpreter', 'none');
                end
            else
                title(ax, plotSpec.title, 'Interpreter', 'none');
            end
            hold(ax, 'off');
            xlabel(ax, app.metricAxisLabel(plotSpec.fields{1}));
            ylabel(ax, app.metricAxisLabel(plotSpec.fields{2}));
            grid(ax, 'on');
        end

        function showRawSurface(app, ax)
            I = app.M1GuiResults.I_raw;
            if ismatrix(I)
                if ~isa(I, 'uint8')
                    I = uint8(255 * mat2gray(I));
                end
                I = repmat(I, [1 1 3]);
            end
            imshow(I, 'Parent', ax);
            axis(ax, 'image');
        end

        function plotShapeOverlay(app, ax)
            app.showRawSurface(ax);
            hold(ax, 'on');
            valid = app.getMoundShapeMetric('preferred_valid_flag');
            cx = app.getMoundShapeMetric('centroid_px');
            height = app.getMoundShapeMetric('preferred_mound_height_um');
            diam = app.getMoundShapeMetric('preferred_equiv_diam_um');
            xy = app.MoundShapeGuiResults.m1.xy_um_per_px;
            if ~isempty(cx) && size(cx, 2) >= 2
                theta = linspace(0, 2*pi, 80);
                validIdx = find(logical(valid(:)) & isfinite(height(:)) & isfinite(diam(:)));
                if isempty(validIdx)
                    title(ax, 'No valid preferred mound shapes', 'Interpreter', 'none');
                    hold(ax, 'off');
                    return;
                end
                cmap = parula(256);
                hLo = prctile(height(validIdx), 5);
                hHi = prctile(height(validIdx), 95);
                for ii = 1:numel(validIdx)
                    k = validIdx(ii);
                    rPx = 0.5 * diam(k) / xy;
                    t = (height(k) - hLo) / max(hHi - hLo, eps);
                    cidx = max(1, min(256, round(max(0, min(1, t)) * 255) + 1));
                    plot(ax, cx(k,1) + rPx*cos(theta), cx(k,2) + rPx*sin(theta), '-', ...
                        'Color', cmap(cidx, :), 'LineWidth', 1.0);
                end
                hCentroid = plot(ax, cx(validIdx,1), cx(validIdx,2), 'r+', 'MarkerSize', 6, 'LineWidth', 1.0);
                colormap(ax, cmap);
                clim(ax, [hLo hHi]);
                cb = colorbar(ax);
                cb.Label.String = 'Preferred mound height (um)';
                hCircle = plot(ax, NaN, NaN, '-', 'Color', cmap(round(size(cmap, 1) * 0.75), :), 'LineWidth', 1.0);
                legend(ax, [hCircle hCentroid], {'Equivalent-diameter circle', 'Mound detection centroid'}, ...
                    'Location', 'southoutside', 'Orientation', 'horizontal');
            end
            title(ax, 'Equivalent-diameter circles from Q50 half-max footprint area', 'Interpreter', 'none');
            hold(ax, 'off');
        end

        function plotFootprintAxesOverlay(app, ax)
            app.showRawSurface(ax);
            hold(ax, 'on');
            masks = app.MoundShapeGuiResults.footprint_mask_q50_halfmax;
            boxes = app.MoundShapeGuiResults.watershed_region_boxes;
            valid = logical(app.MoundShapeGuiResults.watershed_valid_flag(:));
            theta = linspace(0, 2*pi, 120);
            nDrawn = 0;
            for k = 1:numel(masks)
                if ~valid(k) || isempty(masks{k}) || any(~isfinite(boxes(k, :)))
                    continue;
                end
                mask = masks{k};
                if ~any(mask(:))
                    continue;
                end
                r1 = boxes(k, 1);
                c1 = boxes(k, 3);
                boundaries = bwboundaries(mask, 'noholes');
                for b = 1:numel(boundaries)
                    boundary = boundaries{b};
                    plot(ax, c1 - 1 + boundary(:,2), r1 - 1 + boundary(:,1), '-', ...
                        'Color', [0.10 0.90 0.95], 'LineWidth', 0.9);
                end
                stats = regionprops(mask, 'Centroid', 'MajorAxisLength', 'MinorAxisLength', 'Orientation');
                if isempty(stats) || ~isfinite(stats(1).MajorAxisLength) || ~isfinite(stats(1).MinorAxisLength)
                    continue;
                end
                xc = c1 - 1 + stats(1).Centroid(1);
                yc = r1 - 1 + stats(1).Centroid(2);
                a = 0.5 * stats(1).MajorAxisLength;
                b = 0.5 * stats(1).MinorAxisLength;
                phi = deg2rad(-stats(1).Orientation);
                xe = xc + a*cos(theta)*cos(phi) - b*sin(theta)*sin(phi);
                ye = yc + a*cos(theta)*sin(phi) + b*sin(theta)*cos(phi);
                plot(ax, xe, ye, '-', 'Color', [1.00 0.35 0.10], 'LineWidth', 1.0);
                plot(ax, [xc - a*cos(phi), xc + a*cos(phi)], [yc - a*sin(phi), yc + a*sin(phi)], '-', ...
                    'Color', [1.00 0.80 0.10], 'LineWidth', 1.0);
                [p1, p2, ok] = app.getFeretMaxEndpoints(mask);
                if ok
                    plot(ax, c1 - 1 + [p1(1), p2(1)], r1 - 1 + [p1(2), p2(2)], '-', ...
                        'Color', [0.15 1.00 0.35], 'LineWidth', 1.0);
                end
                nDrawn = nDrawn + 1;
            end
            h = findobj(ax, 'Type', 'line');
            if ~isempty(h)
                hBoundaryProxy = plot(ax, NaN, NaN, '-', 'Color', [0.10 0.90 0.95], 'LineWidth', 0.9);
                hEllipseProxy = plot(ax, NaN, NaN, '-', 'Color', [1.00 0.35 0.10], 'LineWidth', 1.0);
                hEllipseAxisProxy = plot(ax, NaN, NaN, '-', 'Color', [1.00 0.80 0.10], 'LineWidth', 1.0);
                hFeretProxy = plot(ax, NaN, NaN, '-', 'Color', [0.15 1.00 0.35], 'LineWidth', 1.0);
                legend(ax, [hBoundaryProxy hEllipseProxy hEllipseAxisProxy hFeretProxy], ...
                    {'Q50 half-max boundary', 'Ellipse fit', 'Ellipse major axis', 'Feret max axis'}, ...
                    'Location', 'southoutside', 'Orientation', 'horizontal');
            end
            title(ax, sprintf('Q50 half-max footprints with ellipse and Feret axes (n=%d)', nDrawn), 'Interpreter', 'none');
            hold(ax, 'off');
        end

        function plotPeakPerimeterThresholdOverlay(app, ax)
            app.showRawSurface(ax);
            hold(ax, 'on');
            zAbs = app.getMoundShapeMetric('whole_image_z_at_peak_perimeter_um');
            zRel = app.getMoundShapeMetric('whole_image_z_rel_at_peak_perimeter_um');
            peakPerim = app.getMoundShapeMetric('whole_image_peak_perimeter_um');
            if ~isfield(app.MoundShapeGuiResults, 'm1') || ~isfield(app.MoundShapeGuiResults.m1, 'Z') || ...
                    ~isfinite(zAbs)
                text(ax, 0.5, 0.5, 'Peak-perimeter threshold unavailable', ...
                    'HorizontalAlignment', 'center');
                axis(ax, 'off');
                hold(ax, 'off');
                return;
            end
            Z = app.MoundShapeGuiResults.m1.Z;
            thresholdMask = isfinite(Z) & Z >= zAbs;
            app.overlayMask(ax, thresholdMask, [1.00 0.85 0.00], 0.34);
            boundaryMask = bwperim(thresholdMask, 8);
            app.overlayMask(ax, imdilate(boundaryMask, strel('disk', 1)), [0.95 0.10 0.10], 0.85);
            hThreshold = plot(ax, NaN, NaN, 's', ...
                'Color', [1.00 0.85 0.00], 'MarkerFaceColor', [1.00 0.85 0.00], ...
                'MarkerSize', 7);
            hBoundary = plot(ax, NaN, NaN, 's', ...
                'Color', [0.95 0.10 0.10], 'MarkerFaceColor', [0.95 0.10 0.10], ...
                'MarkerSize', 7);
            legend(ax, [hThreshold hBoundary], {'Z >= peak-perimeter height', 'Threshold boundary'}, ...
                'Location', 'southoutside', 'Orientation', 'horizontal');
            title(ax, sprintf('Peak-perimeter threshold | %.3g um rel / %.3g um abs | perimeter %.3g um', ...
                zRel, zAbs, peakPerim), 'Interpreter', 'none');
            hold(ax, 'off');
        end

        function plotBaseBandOverlay(app, ax)
            app.showRawSurface(ax);
            hold(ax, 'on');
            baseMask = app.MoundShapeGuiResults.method_c_base_band_label_img > 0;
            borderMask = logical(app.MoundShapeGuiResults.method_c_watershed_border_mask);
            app.overlayMask(ax, baseMask, [0.00 1.00 1.00], 0.36);
            app.overlayMask(ax, borderMask, [1.00 1.00 0.00], 0.78);
            peaks = app.MoundShapeGuiResults.watershed_peak_rowcol_px;
            valid = logical(app.MoundShapeGuiResults.valid_flag_c(:)) & all(isfinite(peaks), 2);
            hPeak = plot(ax, peaks(valid,2), peaks(valid,1), 'o', ...
                'Color', [1.00 0.85 0.00], 'MarkerFaceColor', [1.00 0.85 0.00], ...
                'MarkerSize', 4.5, 'LineWidth', 0.8);
            hBase = plot(ax, NaN, NaN, 's', 'Color', [0.00 1.00 1.00], ...
                'MarkerFaceColor', [0.00 1.00 1.00], 'MarkerSize', 7);
            hBorder = plot(ax, NaN, NaN, 's', 'Color', [1.00 1.00 0.00], ...
                'MarkerFaceColor', [1.00 1.00 0.00], 'MarkerSize', 7);
            legend(ax, [hBase hBorder hPeak], {'Method C base band', 'Watershed border', 'Watershed peak'}, ...
                'Location', 'southoutside', 'Orientation', 'horizontal');
            title(ax, 'Method C base-band and watershed-border overlay', 'Interpreter', 'none');
            hold(ax, 'off');
        end

        function plotWatershedSeedsOverlay(app, ax)
            app.showRawSurface(ax);
            hold(ax, 'on');
            c = app.MoundShapeGuiResults.centroid_px;
            ws = app.MoundShapeGuiResults.watershed_seed_centroids_px;
            plot(ax, c(:,1), c(:,2), 'r+', 'MarkerSize', 6, 'LineWidth', 1.0);
            if ~isempty(ws)
                plot(ax, ws(:,1), ws(:,2), 'co', 'MarkerSize', 5, 'LineWidth', 1.0);
            end
            hCentroid = plot(ax, NaN, NaN, 'r+', 'MarkerSize', 6, 'LineWidth', 1.0);
            hSeed = plot(ax, NaN, NaN, 'co', 'MarkerSize', 5, 'LineWidth', 1.0);
            legendHandles = [hCentroid hSeed];
            legendLabels = {'Mound detection centroid', 'Watershed seed'};
            if isfield(app.MoundShapeGuiResults, 'added_edge_seed_centroids_px')
                edgeSeeds = app.MoundShapeGuiResults.added_edge_seed_centroids_px;
                if ~isempty(edgeSeeds)
                    plot(ax, edgeSeeds(:,1), edgeSeeds(:,2), 'ys', 'MarkerSize', 5, 'LineWidth', 1.0);
                    hEdge = plot(ax, NaN, NaN, 'ys', 'MarkerSize', 5, 'LineWidth', 1.0);
                    legendHandles = [legendHandles hEdge];
                    legendLabels = [legendLabels {'Added edge seed'}];
                end
            end
            legend(ax, legendHandles, legendLabels, 'Location', 'southoutside', 'Orientation', 'horizontal');
            title(ax, 'Watershed seed overlay', 'Interpreter', 'none');
            hold(ax, 'off');
        end

        function plotMethodBOverlay(app, ax)
            app.showRawSurface(ax);
            hold(ax, 'on');
            circleGlobal = app.localMaskCellsToGlobalMask( ...
                app.MoundShapeGuiResults.method_b_circle_mask, app.MoundShapeGuiResults.method_b_crop_boxes);
            app.overlayMask(ax, circleGlobal, [0.10 0.90 0.95], 0.22);
            centroids = app.MoundShapeGuiResults.centroid_px;
            valid = logical(app.MoundShapeGuiResults.valid_flag_nn(:));
            plot(ax, centroids(valid,1), centroids(valid,2), 'r+', 'MarkerSize', 6, 'LineWidth', 1.0);
            plot(ax, centroids(~valid,1), centroids(~valid,2), 'x', 'Color', [0.6 0.6 0.6], 'MarkerSize', 5);
            peaks = app.MoundShapeGuiResults.watershed_peak_rowcol_px;
            rpValid = all(isfinite(peaks), 2);
            plot(ax, peaks(rpValid,2), peaks(rpValid,1), 'o', ...
                'Color', [1.00 0.85 0.00], 'MarkerFaceColor', [1.00 0.85 0.00], ...
                'MarkerSize', 4.5, 'LineWidth', 0.8);
            valleyPx = app.MoundShapeGuiResults.method_b_valley_px;
            valleyValid = all(isfinite(valleyPx), 2);
            plot(ax, valleyPx(valleyValid,2), valleyPx(valleyValid,1), 'o', ...
                'Color', [0.55 0.10 0.90], 'MarkerFaceColor', [0.55 0.10 0.90], ...
                'MarkerSize', 4, 'LineWidth', 1.0);
            hRegion = plot(ax, NaN, NaN, 's', 'Color', [0.10 0.90 0.95], ...
                'MarkerFaceColor', [0.10 0.90 0.95], 'MarkerSize', 7);
            hCentroid = plot(ax, NaN, NaN, 'r+', 'MarkerSize', 6, 'LineWidth', 1.0);
            hRp = plot(ax, NaN, NaN, 'o', ...
                'Color', [1.00 0.85 0.00], 'MarkerFaceColor', [1.00 0.85 0.00], ...
                'MarkerSize', 4.5, 'LineWidth', 0.8);
            hValley = plot(ax, NaN, NaN, 'o', ...
                'Color', [0.55 0.10 0.90], 'MarkerFaceColor', [0.55 0.10 0.90], ...
                'MarkerSize', 4, 'LineWidth', 1.0);
            legend(ax, [hRegion hCentroid hRp hValley], ...
                {'NN search region', 'Mound detection centroid', 'Rp locations', 'Rv valley locations'}, ...
                'Location', 'southoutside', 'Orientation', 'horizontal');
            title(ax, 'Nearest-neighbor circle search regions on raw surface', 'Interpreter', 'none');
            hold(ax, 'off');
        end

        function plotSurfaceAreaVolumeOverlay(app, ax)
            app.showRawSurface(ax);
            hold(ax, 'on');
            app.overlayAcceptedWatershedRegions(ax);
            peaks = app.MoundShapeGuiResults.watershed_peak_rowcol_px;
            valid = logical(app.MoundShapeGuiResults.preferred_valid_flag(:)) & all(isfinite(peaks), 2);
            centroids = app.MoundShapeGuiResults.centroid_px;
            hCentroid = plot(ax, centroids(valid,1), centroids(valid,2), 'r+', 'MarkerSize', 6, 'LineWidth', 1.0);
            hRegion = plot(ax, NaN, NaN, 's', 'Color', [0.10 0.55 1.00], ...
                'MarkerFaceColor', [0.10 0.55 1.00], 'MarkerSize', 7);
            legend(ax, [hRegion hCentroid], {'Accepted watershed region color', 'Mound detection centroid'}, ...
                'Location', 'southoutside', 'Orientation', 'horizontal');
            title(ax, sprintf('Accepted watershed regions used for surface area and peak-cap volume (n=%d)', sum(valid)), ...
                'Interpreter', 'none');
            hold(ax, 'off');
        end

        function overlayAcceptedWatershedRegions(app, ax)
            L = app.MoundShapeGuiResults.watershed_L;
            valid = logical(app.MoundShapeGuiResults.preferred_valid_flag(:));
            validIds = find(valid);
            if isempty(validIds)
                return;
            end
            colors = hsv(max(numel(validIds), 1));
            rngState = rng;
            rng(1, 'twister');
            colors = colors(randperm(size(colors, 1)), :);
            rng(rngState);
            rgb = zeros([size(L), 3], 'uint8');
            alphaMask = zeros(size(L));
            for ii = 1:numel(validIds)
                regionMask = (L == validIds(ii));
                alphaMask(regionMask) = 0.34;
                for c = 1:3
                    channel = rgb(:,:,c);
                    channel(regionMask) = uint8(round(255 * colors(ii, c)));
                    rgb(:,:,c) = channel;
                end
            end
            h = imshow(rgb, 'Parent', ax);
            h.AlphaData = alphaMask;
        end

        function plotWatershedBoundaryOverlay(app, ax)
            app.showRawSurface(ax);
            hold(ax, 'on');
            L = app.MoundShapeGuiResults.watershed_L;
            boundaryMask = false(size(L));
            boundaryMask(:, 1:end-1) = boundaryMask(:, 1:end-1) | (L(:, 1:end-1) ~= L(:, 2:end));
            boundaryMask(1:end-1, :) = boundaryMask(1:end-1, :) | (L(1:end-1, :) ~= L(2:end, :));
            boundaryMask = boundaryMask & L > 0;
            app.overlayMask(ax, imdilate(boundaryMask, strel('disk', 1)), [1.00 0.80 0.05], 0.65);
            c = app.MoundShapeGuiResults.centroid_px;
            hCentroid = plot(ax, c(:,1), c(:,2), 'r+', 'MarkerSize', 6, 'LineWidth', 1.0);
            hBoundary = plot(ax, NaN, NaN, 's', 'Color', [1.00 0.80 0.05], ...
                'MarkerFaceColor', [1.00 0.80 0.05], 'MarkerSize', 7);
            legend(ax, [hBoundary hCentroid], {'Watershed boundary', 'Mound detection centroid'}, ...
                'Location', 'southoutside', 'Orientation', 'horizontal');
            title(ax, 'Selected watershed boundaries on raw surface', 'Interpreter', 'none');
            hold(ax, 'off');
        end

        function plotValidityOverlay(app, ax)
            app.showRawSurface(ax);
            hold(ax, 'on');
            c = app.MoundShapeGuiResults.centroid_px;
            preferred = logical(app.MoundShapeGuiResults.preferred_valid_flag(:));
            methodB = logical(app.MoundShapeGuiResults.valid_flag_nn(:));
            methodC = logical(app.MoundShapeGuiResults.valid_flag_c(:));
            footprint = logical(app.MoundShapeGuiResults.watershed_valid_flag(:));
            validAll = preferred & methodB & methodC & footprint;
            rejected = ~validAll;
            plot(ax, c(validAll,1), c(validAll,2), 'r+', 'MarkerSize', 6, 'LineWidth', 1.0);
            plot(ax, c(rejected,1), c(rejected,2), 'rx', 'MarkerSize', 6, 'LineWidth', 1.0);
            hValid = plot(ax, NaN, NaN, 'r+', 'MarkerSize', 6, 'LineWidth', 1.0);
            hRejected = plot(ax, NaN, NaN, 'rx', 'MarkerSize', 6, 'LineWidth', 1.0);
            legend(ax, [hValid hRejected], {'Accepted mound detection centroid', 'Rejected mound'}, ...
                'Location', 'southoutside', 'Orientation', 'horizontal');
            title(ax, sprintf('Valid preferred mounds: %d / %d', sum(validAll), numel(validAll)), ...
                'Interpreter', 'none');
            hold(ax, 'off');
        end

        function globalMask = localMaskCellsToGlobalMask(app, maskCells, boxes)
            imgSize = size(app.M1GuiResults.I_raw);
            globalMask = false(imgSize(1), imgSize(2));
            for k = 1:numel(maskCells)
                if isempty(maskCells{k}) || any(~isfinite(boxes(k, :)))
                    continue;
                end
                r1 = boxes(k, 1);
                r2 = boxes(k, 2);
                c1 = boxes(k, 3);
                c2 = boxes(k, 4);
                localMask = logical(maskCells{k});
                r2 = min(r2, r1 + size(localMask, 1) - 1);
                c2 = min(c2, c1 + size(localMask, 2) - 1);
                localMask = localMask(1:(r2-r1+1), 1:(c2-c1+1));
                globalMask(r1:r2, c1:c2) = globalMask(r1:r2, c1:c2) | localMask;
            end
        end

        function overlayMask(~, ax, mask, color, alphaValue)
            if ~any(mask(:))
                return;
            end
            rgb = zeros([size(mask), 3], 'uint8');
            for c = 1:3
                rgb(:,:,c) = uint8(mask) * uint8(round(255 * color(c)));
            end
            h = imshow(rgb, 'Parent', ax);
            h.AlphaData = double(mask) * alphaValue;
        end

        function [p1, p2, ok] = getFeretMaxEndpoints(~, mask)
            p1 = [NaN NaN];
            p2 = [NaN NaN];
            ok = false;
            boundaries = bwboundaries(mask, 'noholes');
            if isempty(boundaries)
                return;
            end
            pts = boundaries{1}(:, [2 1]);
            if size(pts, 1) < 2
                return;
            end
            try
                hullIdx = convhull(pts(:,1), pts(:,2));
                pts = pts(hullIdx, :);
            catch
            end
            dx = pts(:,1) - pts(:,1).';
            dy = pts(:,2) - pts(:,2).';
            [~, idx] = max(dx(:).^2 + dy(:).^2);
            [i, j] = ind2sub(size(dx), idx);
            p1 = pts(i, :);
            p2 = pts(j, :);
            ok = true;
        end

        function plotMetricHistogram(app, ax, values, titleText, xLabelText)
            values = values(isfinite(values));
            if isempty(values)
                text(ax, 0.5, 0.5, 'No valid data', 'HorizontalAlignment', 'center');
                axis(ax, 'off');
                return;
            end
            histogram(ax, values, 30, 'FaceColor', [0.25 0.55 0.85], ...
                'EdgeColor', 'none', 'FaceAlpha', 0.85);
            hold(ax, 'on');
            meanVal = mean(values, 'omitnan');
            medianVal = median(values, 'omitnan');
            xline(ax, meanVal, '-', 'Color', [0.85 0.15 0.15], 'LineWidth', 1.5);
            xline(ax, medianVal, '--', 'Color', [0.1 0.1 0.1], 'LineWidth', 1.2);
            hold(ax, 'off');
            title(ax, sprintf('%s | mean %.3g | median %.3g', titleText, meanVal, medianVal), ...
                'Interpreter', 'none');
            xlabel(ax, app.metricAxisLabel(xLabelText));
            ylabel(ax, 'Count');
            grid(ax, 'on');
        end

        function label = metricAxisLabel(~, fieldName)
            labels = containers.Map( ...
                {'nn_dist_um','preferred_Rp_per_mound','preferred_Rv_per_mound','preferred_Rz_per_mound', ...
                 'height_open_um','height_typical_um','height_crowded_um','method_c_watershed_border_z_um','preferred_mound_base_position_um', ...
                 'preferred_footprint_um2','preferred_equiv_diam_um','preferred_perimeter_um', ...
                 'preferred_major_axis_um','preferred_minor_axis_um','preferred_feret_max_um','preferred_feret_min_um', ...
                 'preferred_surface_area_um2','preferred_peak_cap_empty_volume_um3','preferred_surface_area_to_volume_inv_um', ...
                 'preferred_circularity','preferred_solidity','preferred_convexity','preferred_extent', ...
                 'preferred_feret_aspect_ratio','preferred_ellipse_axis_ratio','preferred_orientation_deg', ...
                 'preferred_ellipse_orientation_deg','preferred_orientation_agreement_deg', ...
                 'preferred_aspect_ratio_geometric_mean_width','preferred_aspect_ratio_ellipse_major', ...
                 'preferred_aspect_ratio_ellipse_minor','whole_image_slice_z_um','whole_image_slice_z_rel_um', ...
                 'whole_image_z_at_peak_perimeter_um','whole_image_z_rel_at_peak_perimeter_um', ...
                 'whole_image_peak_perimeter_um','whole_image_cross_section_area_at_peak_perimeter_um2', ...
                 'whole_image_cross_section_area_um2','whole_image_perimeter_um', ...
                 'whole_image_cumulative_surface_area_um2'}, ...
                {'NN spacing (um)','Rp (um)','Rv (um)','Rz (um)', ...
                 'Open-side height (um)','Median height (um)','Crowded-side height (um)','Watershed border Z height (um)','Base position (um)', ...
                 'Footprint area (um^2)','Equivalent diameter (um)','Perimeter (um)', ...
                 'Ellipse major axis (um)','Ellipse minor axis (um)','Feret max (um)','Feret min (um)', ...
                 'Surface area (um^2)','Peak-cap empty volume (um^3)','Surface area / volume (1/um)', ...
                 'Circularity (unitless)','Solidity (unitless)','Convexity (unitless)','Extent (unitless)', ...
                 'Feret aspect ratio (unitless)','Ellipse axis ratio (unitless)','Feret orientation (deg)', ...
                 'Ellipse orientation (deg)','Orientation agreement (deg)', ...
                 'Q50-to-peak height / geometric mean ellipse width', ...
                 'Q50-to-peak height / ellipse major axis', ...
                 'Q50-to-peak height / ellipse minor axis', ...
                 'Absolute height (um)', ...
                 'Height relative to reference plane (um)', ...
                 'Peak-perimeter absolute height (um)', ...
                 'Peak-perimeter relative height (um)', ...
                 'Maximum perimeter (um)', ...
                 'Area at peak-perimeter height (um^2)', ...
                 'Cross-sectional area above height (um^2)', ...
                 'Cross-section perimeter at height (um)', ...
                 'Cumulative surface area above height (um^2)'});
            if isKey(labels, fieldName)
                label = labels(fieldName);
            else
                label = strrep(fieldName, '_', '\_');
            end
        end

        function v = getMoundShapeMetric(app, fieldName)
            if isfield(app.MoundShapeGuiResults, fieldName)
                v = app.MoundShapeGuiResults.(fieldName);
            else
                v = NaN;
            end
        end

        function summary = moundSpacingSummaryTable(app)
            m1 = app.M1GuiResults;
            metric = {'Mound count'; 'Density (mounds/mm2)'; 'Mean NN spacing (px)'; ...
                'Mean NN spacing (um)'; 'Std NN spacing (px)'; 'Std NN spacing (um)'; 'NN CV'};
            value = [m1.n_mounds; m1.density_mm2; m1.nn_mean_px; m1.nn_mean_um; ...
                m1.nn_std_px; m1.nn_std_um; m1.nn_cv];
            summary = table(metric, value, 'VariableNames', {'Metric', 'Value'});
        end

        function summary = metricSummaryTable(app, fields)
            rows = {};
            values = [];
            for i = 1:numel(fields)
                fieldName = fields{i};
                if ~isfield(app.MoundShapeGuiResults, fieldName)
                    continue;
                end
                v = app.MoundShapeGuiResults.(fieldName);
                if isnumeric(v)
                    rows(end+1, 1) = {fieldName}; %#ok<AGROW>
                    values(end+1, 1) = mean(v(:), 'omitnan'); %#ok<AGROW>
                end
            end
            summary = table(string(rows), values, 'VariableNames', {'Metric', 'MeanOrValue'});
        end

        function onSaveCurrentMoundSurfaceTab(app)
            if isempty(app.ReviewTabGroup.SelectedTab)
                return;
            end
            app.setMoundSurfaceSaveControlsEnabled(false);
            try
                idx = app.ReviewTabGroup.SelectedTab.UserData;
                app.saveMoundSurfaceTabData(app.MoundSurfaceTabData{idx}, true);
            catch ME
                app.setMoundSurfaceSaveControlsEnabled(true);
                rethrow(ME);
            end
            app.setMoundSurfaceSaveControlsEnabled(true);
        end

        function onSaveAllMoundSurfaceTabs(app)
            app.setMoundSurfaceSaveControlsEnabled(false);
            try
                for i = 1:numel(app.MoundSurfaceTabData)
                    app.saveMoundSurfaceTabData(app.MoundSurfaceTabData{i}, false);
                end
                app.markAnalysisClean('moundSurface');
                app.appendLog('Saved all mound/surface GUI tab exports.');
            catch ME
                app.setMoundSurfaceSaveControlsEnabled(true);
                rethrow(ME);
            end
            app.setMoundSurfaceSaveControlsEnabled(true);
        end

        function setMoundSurfaceSaveControlsEnabled(app, tf)
            state = 'off';
            if tf
                state = 'on';
            end
            if isgraphics(app.SaveCurrentTabButton)
                app.SaveCurrentTabButton.Enable = state;
            end
            if isgraphics(app.SaveAllTabsButton)
                app.SaveAllTabsButton.Enable = state;
            end
            drawnow limitrate;
        end

        function saveMoundSurfaceTabData(app, tabSpec, forceOverwrite)
            if nargin < 3
                forceOverwrite = true;
            end
            outputDir = char(app.OutputEditField.Value);
            imageName = app.M1GuiResults.imageName;
            exportDir = app.getMoundAnalysisExportRoot(outputDir, imageName);
            categoryDir = fullfile(exportDir, app.safeExportFolderName(tabSpec.title));
            if ~exist(categoryDir, 'dir')
                mkdir(categoryDir);
            end

            baseName = sprintf('%s_%s', imageName, tabSpec.groupId);
            csvPath = fullfile(exportDir, [baseName '_summary.csv']);
            writetable(tabSpec.summaryTable, csvPath);
            rawCsvPath = fullfile(categoryDir, [baseName '_raw_data.csv']);
            rawTable = app.moundSurfaceRawDataTable(tabSpec.groupId);
            if ~isempty(rawTable)
                writetable(rawTable, rawCsvPath);
            end

            for i = 1:numel(tabSpec.plots)
                if isgraphics(tabSpec.plots(i).Axes)
                    pngPath = fullfile(categoryDir, sprintf('%s_%s.png', baseName, tabSpec.plots(i).id));
                    if ~forceOverwrite && app.wasMoundSurfacePlotExported(pngPath)
                        continue;
                    end
                    app.exportMoundSurfacePlot(tabSpec.plots(i), pngPath);
                    app.MoundSurfaceExportedPlotPaths{end+1} = char(pngPath);
                end
            end
            app.appendLog(['Saved GUI tab export group: ' tabSpec.title]);
        end

        function rawTable = moundSurfaceRawDataTable(app, groupId)
            fields = app.moundSurfaceRawDataFields(groupId);
            rawTable = table();
            for i = 1:numel(fields)
                fieldName = fields{i};
                value = app.getRawDataField(fieldName);
                if isempty(value) || ~isnumeric(value)
                    continue;
                end
                value = double(value);
                if isvector(value)
                    value = value(:);
                else
                    value = reshape(value, size(value, 1), []);
                end
                names = app.rawDataColumnNames(fieldName, size(value, 2));
                for j = 1:size(value, 2)
                    rawTable = app.addRawDataColumn(rawTable, names{j}, value(:, j));
                end
            end
        end

        function fields = moundSurfaceRawDataFields(~, groupId)
            switch groupId
                case 'moundSpacing'
                    fields = {'centroids','trimmed_edges','nn_dist_px','nn_dist_um'};
                case 'roughness'
                    fields = {'centroid_px','valid_flag_nn','preferred_Rp_per_mound', ...
                        'preferred_Rv_per_mound','preferred_Rz_per_mound', ...
                        'watershed_peak_rowcol_px','method_b_valley_px'};
                case 'directHeight'
                    fields = {'centroid_px','valid_flag_c','height_open_um','height_typical_um', ...
                        'height_crowded_um','method_c_watershed_border_z_um', ...
                        'base_q10_z_um','base_q50_z_um','base_q90_z_um', ...
                        'watershed_peak_z_um','watershed_peak_rowcol_px'};
                case 'footprintShape'
                    fields = {'centroid_px','watershed_valid_flag','preferred_footprint_um2', ...
                        'preferred_equiv_diam_um','preferred_perimeter_um', ...
                        'preferred_circularity','preferred_solidity','preferred_convexity', ...
                        'preferred_extent'};
                case 'axesOrientation'
                    fields = {'centroid_px','preferred_major_axis_um','preferred_minor_axis_um', ...
                        'preferred_feret_max_um','preferred_feret_min_um', ...
                        'preferred_feret_aspect_ratio','preferred_ellipse_axis_ratio', ...
                        'preferred_ellipse_orientation_deg','preferred_orientation_deg', ...
                        'preferred_orientation_agreement_deg', ...
                        'preferred_aspect_ratio_geometric_mean_width', ...
                        'preferred_aspect_ratio_ellipse_major', ...
                        'preferred_aspect_ratio_ellipse_minor'};
                case 'surfaceAreaVolume'
                    fields = {'centroid_px','preferred_valid_flag','preferred_surface_area_um2', ...
                        'preferred_peak_cap_empty_volume_um3', ...
                        'preferred_surface_area_to_volume_inv_um'};
                case 'wholeImageSlices'
                    fields = {'whole_image_slice_z_um','whole_image_slice_z_rel_um', ...
                        'whole_image_cross_section_area_um2','whole_image_perimeter_um', ...
                        'whole_image_cumulative_surface_area_um2', ...
                        'whole_image_cumulative_surface_area_fraction', ...
                        'whole_image_peak_perimeter_um', ...
                        'whole_image_z_at_peak_perimeter_um', ...
                        'whole_image_z_rel_at_peak_perimeter_um', ...
                        'whole_image_cross_section_area_at_peak_perimeter_um2'};
                otherwise
                    fields = {'centroid_px','preferred_valid_flag','valid_flag_nn','valid_flag_c', ...
                        'watershed_seed_centroids_px','added_edge_seed_centroids_px', ...
                        'watershed_sigma_candidates_px','watershed_sigma_scores'};
            end
        end

        function value = getRawDataField(app, fieldName)
            if isfield(app.MoundShapeGuiResults, fieldName)
                value = app.MoundShapeGuiResults.(fieldName);
            elseif isfield(app.M1GuiResults, fieldName)
                value = app.M1GuiResults.(fieldName);
            else
                value = [];
            end
        end

        function names = rawDataColumnNames(~, fieldName, nCols)
            switch fieldName
                case {'centroids','centroid_px','watershed_seed_centroids_px','added_edge_seed_centroids_px'}
                    baseNames = {sprintf('%s_x_px', fieldName), sprintf('%s_y_px', fieldName)};
                case {'watershed_peak_rowcol_px','method_b_valley_px'}
                    baseNames = {sprintf('%s_row_px', fieldName), sprintf('%s_col_px', fieldName)};
                case 'trimmed_edges'
                    baseNames = {'trimmed_edge_mound_index_1', 'trimmed_edge_mound_index_2'};
                otherwise
                    baseNames = {};
            end
            names = cell(1, nCols);
            for i = 1:nCols
                if i <= numel(baseNames)
                    names{i} = baseNames{i};
                elseif nCols == 1
                    names{i} = fieldName;
                else
                    names{i} = sprintf('%s_col%d', fieldName, i);
                end
                names{i} = matlab.lang.makeValidName(names{i});
            end
        end

        function outTable = addRawDataColumn(~, inTable, columnName, values)
            values = values(:);
            nExisting = height(inTable);
            nNew = numel(values);
            if nExisting == 0
                outTable = table(values, 'VariableNames', {columnName});
                return;
            end
            if nNew < nExisting
                values(end+1:nExisting, 1) = NaN;
                outTable = inTable;
            elseif nNew > nExisting
                outTable = [inTable; array2table(NaN(nNew - nExisting, width(inTable)), ...
                    'VariableNames', inTable.Properties.VariableNames)];
            else
                outTable = inTable;
            end
            outTable.(columnName) = values;
        end

        function tf = wasMoundSurfacePlotExported(app, pngPath)
            tf = exist(pngPath, 'file') == 2 && any(strcmp(app.MoundSurfaceExportedPlotPaths, char(pngPath)));
        end

        function exportMoundSurfacePlot(app, plotSpec, pngPath)
            if app.isExportRenderedPlotKind(plotSpec.kind)
                app.exportRenderedMoundSurfacePlot(plotSpec, pngPath);
                return;
            end

            ax = plotSpec.Axes;
            exportTextState = app.applyMoundSurfaceExportTextScaling(ax, plotSpec.kind);
            try
                exportgraphics(ax, pngPath, 'Resolution', 150);
            catch ME
                app.restoreMoundSurfaceExportTextScaling(exportTextState);
                rethrow(ME);
            end
            app.restoreMoundSurfaceExportTextScaling(exportTextState);
        end

        function tf = isExportRenderedPlotKind(~, plotKind)
            tf = any(strcmp(plotKind, {'histM1', 'histM3', 'lineM3', 'watershedScores'}));
        end

        function exportRenderedMoundSurfacePlot(app, plotSpec, pngPath)
            fig = figure('Visible', 'off', 'Color', 'w', 'Position', app.exportFigurePosition(plotSpec.kind));
            cleanupObj = onCleanup(@() close(fig));
            ax = axes(fig);
            app.applyDefaultExportFont(ax, plotSpec.kind);

            switch plotSpec.kind
                case 'histM1'
                    v = app.M1GuiResults.(plotSpec.fields{1});
                    app.plotMetricHistogram(ax, v, plotSpec.title, plotSpec.fields{1});
                case 'histM3'
                    v = app.getMoundShapeMetric(plotSpec.fields{1});
                    app.plotMetricHistogram(ax, v, plotSpec.title, plotSpec.fields{1});
                case 'lineM3'
                    app.plotMoundSurfaceLineMetric(ax, plotSpec, 2.2);
                case 'watershedScores'
                    x = app.getMoundShapeMetric('watershed_sigma_candidates_px');
                    y = app.getMoundShapeMetric('watershed_sigma_scores');
                    plot(ax, x, y, '-o', 'LineWidth', 2.0, 'MarkerSize', 7);
                    xlabel(ax, 'Watershed smoothing sigma (px)');
                    ylabel(ax, 'Score');
                    title(ax, 'Watershed sigma selection', 'Interpreter', 'none');
                    grid(ax, 'on');
            end

            app.applyDefaultExportFont(ax, plotSpec.kind);
            exportgraphics(fig, pngPath, 'Resolution', 150);
        end

        function position = exportFigurePosition(~, plotKind)
            if strcmp(plotKind, 'histM1') || strcmp(plotKind, 'histM3')
                position = [80 80 1250 850];
            elseif strcmp(plotKind, 'lineM3') || strcmp(plotKind, 'watershedScores')
                position = [80 80 1400 850];
            else
                position = [80 80 1300 850];
            end
        end

        function applyDefaultExportFont(app, ax, plotKind)
            fontName = app.defaultMatlabFontName();
            if strcmp(plotKind, 'histM1') || strcmp(plotKind, 'histM3')
                axesFontSize = 22;
                titleFontSize = 28;
                labelFontSize = 26;
                legendFontSize = 20;
            else
                axesFontSize = 18;
                titleFontSize = 22;
                labelFontSize = 20;
                legendFontSize = 16;
            end

            ax.FontName = fontName;
            ax.FontSize = axesFontSize;
            ax.Title.FontName = fontName;
            ax.Title.FontSize = titleFontSize;
            ax.XLabel.FontName = fontName;
            ax.XLabel.FontSize = labelFontSize;
            ax.YLabel.FontName = fontName;
            ax.YLabel.FontSize = labelFontSize;
            ax.ZLabel.FontName = fontName;
            ax.ZLabel.FontSize = labelFontSize;

            legends = findall(ancestor(ax, 'figure'), 'Type', 'Legend');
            for i = 1:numel(legends)
                legends(i).FontName = fontName;
                legends(i).FontSize = legendFontSize;
            end
            colorbars = findall(ancestor(ax, 'figure'), 'Type', 'ColorBar');
            for i = 1:numel(colorbars)
                colorbars(i).FontName = fontName;
                colorbars(i).FontSize = legendFontSize;
                colorbars(i).Label.FontName = fontName;
                colorbars(i).Label.FontSize = labelFontSize;
            end
        end

        function fontName = defaultMatlabFontName(~)
            fontName = get(groot, 'defaultAxesFontName');
            if isempty(fontName)
                fontName = get(groot, 'factoryAxesFontName');
            end
            if isempty(fontName)
                fontName = 'Helvetica';
            end
        end

        function folderName = safeExportFolderName(~, titleText)
            folderName = regexprep(char(titleText), '[^\w.-]+', '_');
            folderName = regexprep(folderName, '^_+|_+$', '');
            if isempty(folderName)
                folderName = 'Output_Group';
            end
        end

        function exportDir = getMoundAnalysisExportRoot(~, outputDir, imageName)
            exportDir = fullfile(outputDir, sprintf('%s_mound_analysis_exports', imageName));
        end

        function exportDir = getMoundDetectionExportDir(app, outputDir, imageName)
            exportDir = fullfile(app.getMoundAnalysisExportRoot(outputDir, imageName), 'Mound_Detection');
        end

        function exportDir = getLegacyRoughnessExportDir(app, outputDir, imageName)
            exportDir = fullfile(app.getMoundAnalysisExportRoot(outputDir, imageName), 'Legacy_Roughness');
        end

        function state = applyMoundSurfaceExportTextScaling(app, ax, plotKind)
            state = struct();
            state.Axes = ax;
            state.AxesFontSize = ax.FontSize;
            state.AxesFontName = ax.FontName;
            state.TextHandles = [ax.Title, ax.XLabel, ax.YLabel, ax.ZLabel];
            state.TextFontSizes = arrayfun(@(h) h.FontSize, state.TextHandles);
            state.TextFontNames = arrayfun(@(h) string(h.FontName), state.TextHandles);
            state.Legends = findall(app.UIFigure, 'Type', 'Legend');
            state.LegendFontSizes = arrayfun(@(h) h.FontSize, state.Legends);
            state.LegendFontNames = arrayfun(@(h) string(h.FontName), state.Legends);
            state.Colorbars = findall(app.UIFigure, 'Type', 'ColorBar');
            state.ColorbarFontSizes = arrayfun(@(h) h.FontSize, state.Colorbars);
            state.ColorbarLabelFontSizes = arrayfun(@(h) h.Label.FontSize, state.Colorbars);
            state.ColorbarFontNames = arrayfun(@(h) string(h.FontName), state.Colorbars);
            state.ColorbarLabelFontNames = arrayfun(@(h) string(h.Label.FontName), state.Colorbars);
            fontName = app.defaultMatlabFontName();

            hasHistogram = strcmp(plotKind, 'histM1') || strcmp(plotKind, 'histM3') || ...
                ~isempty(findobj(ax, 'Type', 'Histogram'));
            if hasHistogram
                axisMin = 22;
                textMin = 26;
                legendMin = 20;
                scaleFactor = 2.25;
            else
                axisMin = 14;
                textMin = 15;
                legendMin = 13;
                scaleFactor = 1.45;
            end

            ax.FontName = fontName;
            ax.FontSize = max(axisMin, state.AxesFontSize * scaleFactor);
            for i = 1:numel(state.TextHandles)
                if isgraphics(state.TextHandles(i))
                    state.TextHandles(i).FontName = fontName;
                    state.TextHandles(i).FontSize = max(textMin, state.TextFontSizes(i) * scaleFactor);
                end
            end
            for i = 1:numel(state.Legends)
                if isgraphics(state.Legends(i))
                    state.Legends(i).FontName = fontName;
                    state.Legends(i).FontSize = max(legendMin, state.LegendFontSizes(i) * scaleFactor);
                end
            end
            for i = 1:numel(state.Colorbars)
                if isgraphics(state.Colorbars(i))
                    state.Colorbars(i).FontName = fontName;
                    state.Colorbars(i).FontSize = max(legendMin, state.ColorbarFontSizes(i) * scaleFactor);
                    state.Colorbars(i).Label.FontName = fontName;
                    state.Colorbars(i).Label.FontSize = max(textMin, state.ColorbarLabelFontSizes(i) * scaleFactor);
                end
            end
        end

        function restoreMoundSurfaceExportTextScaling(~, state)
            if isfield(state, 'Axes') && isgraphics(state.Axes)
                state.Axes.FontName = state.AxesFontName;
                state.Axes.FontSize = state.AxesFontSize;
            end
            for i = 1:numel(state.TextHandles)
                if isgraphics(state.TextHandles(i))
                    state.TextHandles(i).FontName = char(state.TextFontNames(i));
                    state.TextHandles(i).FontSize = state.TextFontSizes(i);
                end
            end
            for i = 1:numel(state.Legends)
                if isgraphics(state.Legends(i))
                    state.Legends(i).FontName = char(state.LegendFontNames(i));
                    state.Legends(i).FontSize = state.LegendFontSizes(i);
                end
            end
            for i = 1:numel(state.Colorbars)
                if isgraphics(state.Colorbars(i))
                    state.Colorbars(i).FontName = char(state.ColorbarFontNames(i));
                    state.Colorbars(i).FontSize = state.ColorbarFontSizes(i);
                    state.Colorbars(i).Label.FontName = char(state.ColorbarLabelFontNames(i));
                    state.Colorbars(i).Label.FontSize = state.ColorbarLabelFontSizes(i);
                end
            end
        end

        function onLaunchLegacyRoughness(app, ~, ~)
            try
                inputPath = char(app.InputEditField.Value);
                outputDir = char(app.OutputEditField.Value);
                if strlength(inputPath) == 0
                    uialert(app.UIFigure, 'Choose an input .vk4 file first.', 'Missing Input');
                    return;
                end
                if strlength(outputDir) == 0
                    uialert(app.UIFigure, 'Choose an output folder first.', 'Missing Output');
                    return;
                end
                if ~app.confirmAnalysisSwitch('legacyRoughness')
                    return;
                end
                app.CurrentAnalysisId = 'legacyRoughness';

                if ~exist(outputDir, 'dir')
                    mkdir(outputDir);
                end
                [~, imageName, ~] = fileparts(inputPath);
                legacyOutputDir = app.getLegacyRoughnessExportDir(outputDir, imageName);
                if ~exist(legacyOutputDir, 'dir')
                    mkdir(legacyOutputDir);
                end

                app.MoundDetectionButton.BackgroundColor = app.IdleButtonColor;
                app.MoundSurfaceButton.BackgroundColor = app.IdleButtonColor;
                app.LegacyRoughnessButton.BackgroundColor = app.ActiveButtonColor;
                app.showMoundSettings(false);
                app.showMoundSurfaceSettings(false);
                app.showReviewPanel(true);
                app.ReviewPanel.Title = 'Legacy Surface Roughness';
                app.createLegacyLoadingAreaContent(inputPath, legacyOutputDir);
                useCachedSurface = app.hasCachedLegacySurface(inputPath);
                if useCachedSurface
                    app.appendLog('Using cached VK4 surface data for this file.');
                end
                drawnow;

                app.loadLegacySurface(inputPath);
                app.logStatus({
                    'Building embedded legacy roughness tool...'
                    ['Input: ' inputPath]
                    ['Output: ' legacyOutputDir]
                    'Preparing ROI placement controls.'
                    });
                drawnow;

                delete(app.ReviewPanel.Children);
                app.createLegacyRoughnessAreaContent(legacyOutputDir);
                app.refreshLegacyDisplay();
            app.setLegacyStatus({
                'Legacy roughness ROI tool ready.'
                'Choose an ROI mode, place ROIs on the surface, then click Save.'
                });

            catch ME
                app.logStatus({'Legacy roughness GUI launch failed.'; ME.message});
                uialert(app.UIFigure, ME.message, 'Legacy Roughness GUI Error', 'Interpreter', 'none');
            end
        end

        function createComponents(app)
            app.UIFigure = uifigure('Name', 'SOLF VK4 Analysis App');
            app.UIFigure.WindowState = 'maximized';

            app.MainGrid = uigridlayout(app.UIFigure, [1 3]);
            app.MainGrid.ColumnWidth = {310, 2, '1x'};
            app.MainGrid.RowHeight = {'1x'};
            app.MainGrid.Padding = [10 10 10 10];
            app.MainGrid.ColumnSpacing = 10;

            app.createLeftColumn();
            app.createMoundSettingsColumn();
            app.createMoundSurfaceSettingsColumn();
            app.createReviewArea();
        end

        function createLeftColumn(app)
            app.LeftPanel = uipanel(app.MainGrid, 'Title', '');
            app.LeftPanel.Layout.Row = 1;
            app.LeftPanel.Layout.Column = 1;

            app.LeftGrid = uigridlayout(app.LeftPanel, [13 1]);
            app.LeftGrid.RowHeight = {28, 28, 28, 28, 28, 28, 30, 30, 30, 30, 30, 0, '1x'};
            app.LeftGrid.Padding = [8 8 8 8];
            app.LeftGrid.RowSpacing = 6;
            app.LeftGrid.Scrollable = 'on';

            inputHeaderGrid = uigridlayout(app.LeftGrid, [1 2]);
            inputHeaderGrid.ColumnWidth = {'1x', 105};
            inputHeaderGrid.Padding = [0 0 0 0];
            inputHeaderGrid.ColumnSpacing = 6;
            uilabel(inputHeaderGrid, 'Text', 'Input .vk4 file', 'FontWeight', 'bold');
            btnIn = uibutton(inputHeaderGrid, 'push', 'Text', 'Browse VK4...');
            btnIn.ButtonPushedFcn = @(src, event) app.onBrowseInput(src, event);
            app.InputEditField = uieditfield(app.LeftGrid, 'text', 'Editable', 'off');

            outputHeaderGrid = uigridlayout(app.LeftGrid, [1 2]);
            outputHeaderGrid.ColumnWidth = {'1x', 105};
            outputHeaderGrid.Padding = [0 0 0 0];
            outputHeaderGrid.ColumnSpacing = 6;
            uilabel(outputHeaderGrid, 'Text', 'Output folder', 'FontWeight', 'bold');
            btnOut = uibutton(outputHeaderGrid, 'push', 'Text', 'Browse Output...');
            btnOut.ButtonPushedFcn = @(src, event) app.onBrowseOutput(src, event);
            app.OutputEditField = uieditfield(app.LeftGrid, 'text', 'Editable', 'off');

            bestParamsHeaderGrid = uigridlayout(app.LeftGrid, [1 2]);
            bestParamsHeaderGrid.ColumnWidth = {'1x', 130};
            bestParamsHeaderGrid.Padding = [0 0 0 0];
            bestParamsHeaderGrid.ColumnSpacing = 6;
            uilabel(bestParamsHeaderGrid, 'Text', 'bestParams .mat', 'FontWeight', 'bold');
            btnBest = uibutton(bestParamsHeaderGrid, 'push', 'Text', 'Browse bestParams...');
            btnBest.ButtonPushedFcn = @(src, event) app.onBrowseBestParams(src, event);
            app.BestParamsEditField = uieditfield(app.LeftGrid, 'text', 'Editable', 'off');

            app.MoundDetectionButton = uibutton(app.LeftGrid, 'push', 'Text', '1. Mound Detection');
            app.MoundDetectionButton.ButtonPushedFcn = @(src, event) app.onMoundDetection(src, event);
            app.CavityAnalysisButton = uibutton(app.LeftGrid, 'push', 'Text', '2. Cavity Analysis');
            app.CavityAnalysisButton.ButtonPushedFcn = @(src, event) app.onCavityAnalysis(src, event);
            app.MoundSurfaceButton = uibutton(app.LeftGrid, 'push', 'Text', '3. Mound/Surface Analysis');
            app.MoundSurfaceButton.ButtonPushedFcn = @(src, event) app.onMoundSurfaceAnalysis(src, event);
            app.SpatialAnalysisButton = uibutton(app.LeftGrid, 'push', 'Text', '4. Spatial Analysis');
            app.SpatialAnalysisButton.ButtonPushedFcn = @(src, event) app.onSpatialAnalysis(src, event);
            app.LegacyRoughnessButton = uibutton(app.LeftGrid, 'push', 'Text', '5. Legacy Roughness');
            app.LegacyRoughnessButton.ButtonPushedFcn = @(src, event) app.onLaunchLegacyRoughness(src, event);

            app.DividerPanel = uipanel(app.MainGrid, 'BorderType', 'none', 'BackgroundColor', [0.55 0.55 0.55]);
            app.DividerPanel.Layout.Row = 1;
            app.DividerPanel.Layout.Column = 2;
        end

        function createMoundSettingsColumn(app)
            app.MoundSettingsPanel = uipanel(app.LeftGrid, 'Title', 'Mound Detection');
            app.MoundSettingsPanel.Layout.Row = 12;
            app.MoundSettingsPanel.Layout.Column = 1;
            app.MoundSettingsPanel.Visible = 'off';

            app.MoundSettingsGrid = uigridlayout(app.MoundSettingsPanel, [7 1]);
            app.MoundSettingsGrid.RowHeight = {30, 28, 28, 24, 28, 42, '1x'};
            app.MoundSettingsGrid.Padding = [8 10 8 10];
            app.MoundSettingsGrid.RowSpacing = 7;

            app.FillDeepPitsCheckBox = uicheckbox(app.MoundSettingsGrid, ...
                'Text', 'Use reflection correction', 'Value', false);

            fillHeaderGrid = uigridlayout(app.MoundSettingsGrid, [1 2]);
            fillHeaderGrid.ColumnWidth = {'1x', 120};
            fillHeaderGrid.Padding = [0 0 0 0];
            fillHeaderGrid.ColumnSpacing = 6;
            uilabel(fillHeaderGrid, 'Text', 'Fill threshold', 'FontWeight', 'bold');
            app.PickFillThresholdButton = uibutton(fillHeaderGrid, 'push', ...
                'Text', 'Pick Fill...');
            app.PickFillThresholdButton.ButtonPushedFcn = @(src, event) app.onPickFillThreshold(src, event);
            app.FillThresholdField = uieditfield(app.MoundSettingsGrid, 'numeric', ...
                'Value', 0.50, 'Limits', [0 1], ...
                'LowerLimitInclusive', false, 'UpperLimitInclusive', false);
            app.FillThresholdField.Tooltip = 'fillThreshold used when reflection correction is enabled';

            uilabel(app.MoundSettingsGrid, 'Text', 'Max evals', 'FontWeight', 'bold');
            app.MaxEvalsField = uieditfield(app.MoundSettingsGrid, 'numeric', ...
                'Value', 60, 'Limits', [1 Inf], 'RoundFractionalValues', true);
            app.MaxEvalsField.Tooltip = 'Max Bayesian optimization evaluations for initial mound detection';

            app.RunMoundDetectionButton = uibutton(app.MoundSettingsGrid, 'push', ...
                'Text', 'Run Mound Detection', 'FontWeight', 'bold', ...
                'BackgroundColor', app.RunningButtonColor, 'FontColor', [1 1 1]);
            app.RunMoundDetectionButton.Layout.Row = 6;
            app.RunMoundDetectionButton.Layout.Column = 1;
            app.RunMoundDetectionButton.ButtonPushedFcn = @(src, event) app.onRunMoundDetection(src, event);
        end

        function createMoundSurfaceSettingsColumn(app)
            app.MoundSurfaceSettingsPanel = uipanel(app.LeftGrid, 'Title', 'Mound/Surface Analysis');
            app.MoundSurfaceSettingsPanel.Layout.Row = 12;
            app.MoundSurfaceSettingsPanel.Layout.Column = 1;
            app.MoundSurfaceSettingsPanel.Visible = 'off';

            app.MoundSurfaceSettingsGrid = uigridlayout(app.MoundSurfaceSettingsPanel, [4 1]);
            app.MoundSurfaceSettingsGrid.RowHeight = {24, 116, 42, '1x'};
            app.MoundSurfaceSettingsGrid.Padding = [8 10 8 10];
            app.MoundSurfaceSettingsGrid.RowSpacing = 8;

            uilabel(app.MoundSurfaceSettingsGrid, 'Text', 'Output groups', 'FontWeight', 'bold');

            outputGroupGrid = uigridlayout(app.MoundSurfaceSettingsGrid, [4 2]);
            outputGroupGrid.Layout.Row = 2;
            outputGroupGrid.Layout.Column = 1;
            outputGroupGrid.RowHeight = {24, 24, 24, 24};
            outputGroupGrid.ColumnWidth = {'1x', '1x'};
            outputGroupGrid.Padding = [0 0 0 0];
            outputGroupGrid.RowSpacing = 5;
            outputGroupGrid.ColumnSpacing = 8;

            app.MoundSpacingCheckBox = uicheckbox(outputGroupGrid, 'Text', 'Mound Spacing', 'Value', true);
            app.MoundSpacingCheckBox.Layout.Row = 1; app.MoundSpacingCheckBox.Layout.Column = 1;
            app.RoughnessCheckBox = uicheckbox(outputGroupGrid, 'Text', 'Roughness', 'Value', true);
            app.RoughnessCheckBox.Layout.Row = 1; app.RoughnessCheckBox.Layout.Column = 2;
            app.DirectHeightCheckBox = uicheckbox(outputGroupGrid, 'Text', 'Direct Height', 'Value', true);
            app.DirectHeightCheckBox.Layout.Row = 2; app.DirectHeightCheckBox.Layout.Column = 1;
            app.FootprintShapeCheckBox = uicheckbox(outputGroupGrid, 'Text', 'Footprint Shape', 'Value', true);
            app.FootprintShapeCheckBox.Layout.Row = 2; app.FootprintShapeCheckBox.Layout.Column = 2;
            app.AxesOrientationCheckBox = uicheckbox(outputGroupGrid, 'Text', 'Axes/Orientation', 'Value', true);
            app.AxesOrientationCheckBox.Layout.Row = 3; app.AxesOrientationCheckBox.Layout.Column = 1;
            app.SurfaceAreaVolumeCheckBox = uicheckbox(outputGroupGrid, 'Text', 'SA And Volume', 'Value', true);
            app.SurfaceAreaVolumeCheckBox.Layout.Row = 3; app.SurfaceAreaVolumeCheckBox.Layout.Column = 2;
            app.WholeImageSlicesCheckBox = uicheckbox(outputGroupGrid, 'Text', 'Image Slices', 'Value', false);
            app.WholeImageSlicesCheckBox.Layout.Row = 4; app.WholeImageSlicesCheckBox.Layout.Column = 1;
            app.QADiagnosticsCheckBox = uicheckbox(outputGroupGrid, 'Text', 'QA Diagnostics', 'Value', true);
            app.QADiagnosticsCheckBox.Layout.Row = 4; app.QADiagnosticsCheckBox.Layout.Column = 2;

            app.RunMoundSurfaceButton = uibutton(app.MoundSurfaceSettingsGrid, 'push', ...
                'Text', 'Run Analysis', 'FontWeight', 'bold', ...
                'BackgroundColor', app.RunningButtonColor, 'FontColor', [1 1 1]);
            app.RunMoundSurfaceButton.Layout.Row = 3;
            app.RunMoundSurfaceButton.Layout.Column = 1;
            app.RunMoundSurfaceButton.ButtonPushedFcn = @(src, event) app.onRunMoundSurfaceAnalysis(src, event);
        end

        function createReviewArea(app)
            app.ReviewPanel = uipanel(app.MainGrid, 'Title', 'Mound Detection Review');
            app.ReviewPanel.Layout.Row = 1;
            app.ReviewPanel.Layout.Column = 3;
            app.ReviewPanel.Visible = 'off';
            app.createMoundReviewAreaContent();
        end

        function createMoundReviewAreaContent(app)
            app.stopLegacyPointerCallbacks();
            app.ReviewPanel.Title = 'Mound Detection Review';
            delete(app.ReviewPanel.Children);

            app.ReviewGrid = uigridlayout(app.ReviewPanel, [1 2]);
            app.ReviewGrid.ColumnWidth = {'1x', 380};
            app.ReviewGrid.RowHeight = {'1x'};
            app.ReviewGrid.Padding = [8 8 8 8];
            app.ReviewGrid.ColumnSpacing = 10;

            leftReviewGrid = uigridlayout(app.ReviewGrid, [2 1]);
            leftReviewGrid.Layout.Row = 1;
            leftReviewGrid.Layout.Column = 1;
            leftReviewGrid.RowHeight = {'1x', 42};
            leftReviewGrid.Padding = [0 0 0 0];
            leftReviewGrid.RowSpacing = 8;

            app.ReviewTabGroup = uitabgroup(leftReviewGrid);
            app.ReviewTabGroup.Layout.Row = 1;
            app.ReviewTabGroup.Layout.Column = 1;
            app.ReviewTabGroup.SelectionChangedFcn = @(src, event) app.updateMoundDetectionSummaryFromSelectedTab();

            app.TierButtonGrid = uigridlayout(leftReviewGrid, [1 6]);
            app.TierButtonGrid.Layout.Row = 2;
            app.TierButtonGrid.Layout.Column = 1;
            app.TierButtonGrid.ColumnWidth = {85, 120, 130, 100, 110, '1x'};
            app.TierButtonGrid.RowHeight = {'1x'};
            app.TierButtonGrid.Padding = [0 0 0 0];

            app.DoneButton = uibutton(app.TierButtonGrid, 'push', 'Text', 'Save');
            app.DoneButton.ButtonPushedFcn = @(src, event) app.onDone(src, event);
            app.TooFewButton = uibutton(app.TierButtonGrid, 'push', 'Text', 'Too Few Mounds');
            app.TooFewButton.ButtonPushedFcn = @(src, event) app.onTooFew(src, event);
            app.TooManyButton = uibutton(app.TierButtonGrid, 'push', 'Text', 'Too Many Mounds');
            app.TooManyButton.ButtonPushedFcn = @(src, event) app.onTooMany(src, event);
            app.ManualCountField = uieditfield(app.TierButtonGrid, 'numeric', ...
                'Limits', [1 Inf], 'RoundFractionalValues', true, 'Value', 100);
            app.ManualCountButton = uibutton(app.TierButtonGrid, 'push', 'Text', 'Manual Count');
            app.ManualCountButton.ButtonPushedFcn = @(src, event) app.onManualCount(src, event);

            rightReviewGrid = uigridlayout(app.ReviewGrid, [3 1]);
            rightReviewGrid.Layout.Row = 1;
            rightReviewGrid.Layout.Column = 2;
            rightReviewGrid.RowHeight = {190, '1x', 145};
            rightReviewGrid.Padding = [0 0 0 0];
            rightReviewGrid.RowSpacing = 8;

            summaryPanel = uipanel(rightReviewGrid, 'Title', 'Summary');
            summaryPanel.Layout.Row = 1;
            summaryGrid = uigridlayout(summaryPanel, [1 1]);
            summaryGrid.Padding = [6 6 6 6];
            app.ReviewSummaryTable = uitable(summaryGrid);
            app.ReviewSummaryTable.Data = table();

            app.ReviewInfoTextArea = uitextarea(rightReviewGrid, 'Editable', 'off');
            app.ReviewInfoTextArea.Layout.Row = 2;
            app.ReviewInfoTextArea.Value = {'Analysis information panel reserved for future details.'};

            app.StatusTextArea = uitextarea(rightReviewGrid, 'Editable', 'off');
            app.StatusTextArea.Layout.Row = 3;
            app.StatusTextArea.Layout.Column = 1;
            app.setTierControlsEnabled(false);
        end

        function createLegacyLoadingAreaContent(app, inputPath, outputDir)
            app.stopLegacyPointerCallbacks();
            delete(app.ReviewPanel.Children);

            loadingGrid = uigridlayout(app.ReviewPanel, [1 1]);
            loadingGrid.Padding = [12 12 12 12];
            app.StatusTextArea = uitextarea(loadingGrid, 'Editable', 'off');
            app.StatusTextArea.Value = {
                'Preparing embedded legacy roughness tool...'
                ['Input: ' inputPath]
                ['Output: ' outputDir]
                'Loading the height surface directly from the selected VK4 file.'
                };
        end

        function tf = hasCachedLegacySurface(app, inputPath)
            tf = ~isempty(app.LegacyZ) && strcmp(app.LegacyImagePath, inputPath);
        end

        function loadLegacySurface(app, inputPath)
            if ~app.hasCachedLegacySurface(inputPath)
                [Z, xy_um_per_px] = readVK4(inputPath);
                app.LegacyZ = double(Z);
                app.LegacyXyUmPerPx = double(xy_um_per_px);
            end
            app.LegacyImagePath = inputPath;
            [~, app.LegacyImageName, ~] = fileparts(inputPath);
            app.LegacySurfaceInput = struct( ...
                'Z', app.LegacyZ, ...
                'xy_um_per_px', app.LegacyXyUmPerPx, ...
                'imagePath', app.LegacyImagePath, ...
                'source_label', 'direct VK4 load');
            app.LegacyRois = struct('type', {}, 'x1', {}, 'x2', {}, 'y1', {}, 'y2', {});
            app.LegacyRoiGraphics = gobjects(0);
            app.LegacyPreviewGraphic = gobjects(1);
            app.LegacyClickStage = 0;
            app.LegacyAnchorPoint = [NaN NaN];
            app.LegacyActiveMode = '';
        end

        function createLegacyRoughnessAreaContent(app, outputDir)
            legacyGrid = uigridlayout(app.ReviewPanel, [1 2]);
            legacyGrid.ColumnWidth = {'1x', 330};
            legacyGrid.RowHeight = {'1x'};
            legacyGrid.Padding = [8 8 8 8];
            legacyGrid.ColumnSpacing = 10;

            app.LegacyAxes = uiaxes(legacyGrid);
            app.LegacyAxes.Layout.Row = 1;
            app.LegacyAxes.Layout.Column = 1;
            imagesc(app.LegacyAxes, app.LegacyZ);
            axis(app.LegacyAxes, 'image');
            axis(app.LegacyAxes, 'ij');
            colormap(app.LegacyAxes, jet(256));
            set(app.LegacyAxes, 'XLim', [0.5, size(app.LegacyZ, 2) + 0.5], ...
                'YLim', [0.5, size(app.LegacyZ, 1) + 0.5], 'YDir', 'reverse');
            title(app.LegacyAxes, sprintf('%s | Legacy roughness ROI tool', app.LegacyImageName), ...
                'Interpreter', 'none');
            xlabel(app.LegacyAxes, sprintf('x (px) | %.4f um/px', app.LegacyXyUmPerPx));
            ylabel(app.LegacyAxes, 'y (px)');
            hold(app.LegacyAxes, 'on');

            sideGrid = uigridlayout(legacyGrid, [12 3]);
            sideGrid.Layout.Row = 1;
            sideGrid.Layout.Column = 2;
            sideGrid.RowHeight = {30, 30, 24, 30, 8, 24, 120, '1x', 105, 1, 1, 1};
            sideGrid.ColumnWidth = {'1x', '1x', '1x'};
            sideGrid.Padding = [4 4 4 4];
            sideGrid.RowSpacing = 6;

            app.LegacyAllButton = uibutton(sideGrid, 'push', 'Text', 'All areas');
            app.LegacyAllButton.Layout.Row = 1; app.LegacyAllButton.Layout.Column = 1;
            app.LegacyAllButton.ButtonPushedFcn = @(src, event) app.onLegacyAllAreas();
            app.LegacyRectButton = uibutton(sideGrid, 'push', 'Text', 'Rect.');
            app.LegacyRectButton.Layout.Row = 1; app.LegacyRectButton.Layout.Column = 2;
            app.LegacyRectButton.ButtonPushedFcn = @(src, event) app.setLegacyMode('rect');
            app.LegacySquareButton = uibutton(sideGrid, 'push', 'Text', 'Square');
            app.LegacySquareButton.Layout.Row = 1; app.LegacySquareButton.Layout.Column = 3;
            app.LegacySquareButton.ButtonPushedFcn = @(src, event) app.setLegacyMode('square');

            app.LegacyClearButton = uibutton(sideGrid, 'push', 'Text', 'Clear');
            app.LegacyClearButton.Layout.Row = 2; app.LegacyClearButton.Layout.Column = 2;
            app.LegacyClearButton.ButtonPushedFcn = @(src, event) app.onLegacyClear();
            app.LegacyDoneButton = uibutton(sideGrid, 'push', 'Text', 'Save', 'FontWeight', 'bold');
            app.LegacyDoneButton.Layout.Row = 2; app.LegacyDoneButton.Layout.Column = 1;
            app.LegacyDoneButton.ButtonPushedFcn = @(src, event) app.onLegacyDone();

            areaLabel = uilabel(sideGrid, 'Text', 'Fixed area size (um)', 'FontWeight', 'bold');
            areaLabel.Layout.Row = 3; areaLabel.Layout.Column = [1 3];
            app.LegacyAreaWidthField = uieditfield(sideGrid, 'numeric', 'Value', 10.00, 'Limits', [eps Inf]);
            app.LegacyAreaWidthField.Layout.Row = 4; app.LegacyAreaWidthField.Layout.Column = 1;
            app.LegacyAreaHeightField = uieditfield(sideGrid, 'numeric', 'Value', 10.00, 'Limits', [eps Inf]);
            app.LegacyAreaHeightField.Layout.Row = 4; app.LegacyAreaHeightField.Layout.Column = 2;
            app.LegacyAreaButton = uibutton(sideGrid, 'push', 'Text', 'Area');
            app.LegacyAreaButton.Layout.Row = 4; app.LegacyAreaButton.Layout.Column = 3;
            app.LegacyAreaButton.ButtonPushedFcn = @(src, event) app.onLegacyAreaMode();

            summaryLabel = uilabel(sideGrid, 'Text', 'Summary', 'FontWeight', 'bold');
            summaryLabel.Layout.Row = 6; summaryLabel.Layout.Column = [1 3];
            app.LegacySummaryTextArea = uitextarea(sideGrid, 'Editable', 'off');
            app.LegacySummaryTextArea.Layout.Row = 7; app.LegacySummaryTextArea.Layout.Column = [1 3];

            app.LegacyTable = uitable(sideGrid);
            app.LegacyTable.Layout.Row = 8; app.LegacyTable.Layout.Column = [1 3];
            app.LegacyTable.ColumnName = {'ROI', 'Type', 'Rp (um)', 'Rv (um)', 'Rz (um)', 'SA/A'};
            app.LegacyTable.RowName = {};

            app.LegacyStatusTextArea = uitextarea(sideGrid, 'Editable', 'off');
            app.LegacyStatusTextArea.Layout.Row = 9; app.LegacyStatusTextArea.Layout.Column = [1 3];

            app.StatusTextArea = app.LegacyStatusTextArea;
            app.UIFigure.WindowButtonDownFcn = @(src, event) app.onLegacyMouseDown();
            app.UIFigure.WindowButtonMotionFcn = @(src, event) app.onLegacyMouseMove();
            app.setLegacyStatus({['Output folder: ' outputDir]; 'Ready for ROI placement.'});
        end

        function stopLegacyPointerCallbacks(app)
            app.UIFigure.WindowButtonDownFcn = [];
            app.UIFigure.WindowButtonMotionFcn = [];
        end

        function onLegacyAllAreas(app)
            app.cancelLegacyPlacement();
            app.clearLegacyRois();
            [imgH, imgW] = size(app.LegacyZ);
            app.addLegacyRoi(struct('type', 'all_areas', 'x1', 1, 'x2', imgW, 'y1', 1, 'y2', imgH));
            outputDir = app.getLegacyRoughnessExportDir(char(app.OutputEditField.Value), app.LegacyImageName);
            app.setLegacyStatus({'Stored ROI 1 as the full image.'; ['Output folder: ' outputDir]});
        end

        function onLegacyAreaMode(app)
            [imgH, imgW] = size(app.LegacyZ);
            maxWidthUm = imgW * app.LegacyXyUmPerPx;
            maxHeightUm = imgH * app.LegacyXyUmPerPx;
            if app.LegacyAreaWidthField.Value > maxWidthUm || app.LegacyAreaHeightField.Value > maxHeightUm
                uialert(app.UIFigure, 'Width and height must fit inside the image bounds.', 'Area Too Large');
                return;
            end
            app.setLegacyMode('area');
        end

        function setLegacyMode(app, modeName)
            app.LegacyActiveMode = modeName;
            app.LegacyClickStage = 0;
            app.LegacyAnchorPoint = [NaN NaN];
            app.deleteLegacyPreview();
            app.setLegacyButtonStates();
            switch modeName
                case 'rect'
                    app.setLegacyStatus({'Rectangle mode armed.'; 'First click sets a corner. Second click sets the opposite corner.'});
                case 'square'
                    app.setLegacyStatus({'Square mode armed.'; 'First click sets a corner. Second click sets the opposite corner with equal sides.'});
                case 'area'
                    app.setLegacyStatus({
                        sprintf('Area mode armed: %.2f um x %.2f um.', app.LegacyAreaWidthField.Value, app.LegacyAreaHeightField.Value)
                        'First click centers the preview. Second click places the ROI.'
                        });
            end
        end

        function setLegacyButtonStates(app)
            buttons = [app.LegacyAllButton, app.LegacyRectButton, app.LegacySquareButton, app.LegacyAreaButton];
            for k = 1:numel(buttons)
                buttons(k).FontWeight = 'normal';
            end
            switch app.LegacyActiveMode
                case 'rect'
                    app.LegacyRectButton.FontWeight = 'bold';
                case 'square'
                    app.LegacySquareButton.FontWeight = 'bold';
                case 'area'
                    app.LegacyAreaButton.FontWeight = 'bold';
            end
        end

        function onLegacyClear(app)
            hadRois = ~isempty(app.LegacyRois);
            app.clearLegacyRois();
            app.refreshLegacyDisplay();
            app.LegacyClickStage = 0;
            app.LegacyAnchorPoint = [NaN NaN];
            app.deleteLegacyPreview();
            if hadRois
                app.markAnalysisDirty('legacyRoughness');
            end
            app.setLegacyStatus({'All ROIs cleared.'; 'Ready for new placement.'});
        end

        function onLegacyDone(app)
            outputDir = char(app.OutputEditField.Value);
            if strlength(outputDir) == 0
                uialert(app.UIFigure, 'Choose an output folder before saving legacy roughness results.', 'Missing Output');
                return;
            end
            if ~exist(outputDir, 'dir')
                mkdir(outputDir);
            end
            app.OutputEditField.Value = outputDir;
            outputDir = app.getLegacyRoughnessExportDir(outputDir, app.LegacyImageName);
            if ~exist(outputDir, 'dir')
                mkdir(outputDir);
            end
            results = app.buildLegacyResults(true, '', '');
            matPath = fullfile(outputDir, sprintf('%s_legacy_surface_roughness.mat', app.LegacyImageName));
            csvPath = fullfile(outputDir, sprintf('%s_legacy_surface_roughness.csv', app.LegacyImageName));
            results.saved = true;
            results.saved_files = struct('mat', matPath, 'csv', csvPath);
            results.gui_settings = struct( ...
                'colormap', 'jet', ...
                'roi_color', app.LegacyRoiColor, ...
                'max_rois', app.LegacyMaxRois, ...
                'default_area_width_um', app.LegacyAreaWidthField.Value, ...
                'default_area_height_um', app.LegacyAreaHeightField.Value, ...
                'done_timestamp', char(datetime('now', 'TimeZone', 'local', 'Format', 'yyyy-MM-dd HH:mm:ss Z')));
            save(matPath, 'results');
            writecell(app.buildLegacyCsvExport(results), csvPath);
            app.markAnalysisClean('legacyRoughness');
            app.setLegacyStatus({'Saved legacy roughness outputs.'; ['Output folder: ' outputDir]; matPath; csvPath});
        end

        function onLegacyMouseDown(app)
            if isempty(app.LegacyActiveMode) || isempty(app.LegacyAxes) || ~isvalid(app.LegacyAxes)
                return;
            end
            point = app.getLegacyAxesPoint();
            if isempty(point)
                return;
            end
            switch app.LegacyActiveMode
                case {'rect', 'square'}
                    app.handleLegacyRectLikeClick(point, app.LegacyActiveMode);
                case 'area'
                    app.handleLegacyAreaClick(point);
            end
        end

        function onLegacyMouseMove(app)
            if isempty(app.LegacyActiveMode) || app.LegacyClickStage == 0 || isempty(app.LegacyAxes) || ~isvalid(app.LegacyAxes)
                return;
            end
            point = app.getLegacyAxesPoint();
            if isempty(point)
                return;
            end
            app.updateLegacyPreview(point, app.LegacyActiveMode);
        end

        function point = getLegacyAxesPoint(app)
            cp = app.LegacyAxes.CurrentPoint;
            x = cp(1, 1);
            y = cp(1, 2);
            [imgH, imgW] = size(app.LegacyZ);
            if x < 0.5 || x > imgW + 0.5 || y < 0.5 || y > imgH + 0.5
                point = [];
                return;
            end
            point = [min(max(x, 1), imgW), min(max(y, 1), imgH)];
        end

        function handleLegacyRectLikeClick(app, point, modeName)
            if numel(app.LegacyRois) >= app.LegacyMaxRois
                uialert(app.UIFigure, sprintf('A maximum of %d ROIs can be stored.', app.LegacyMaxRois), 'ROI Limit Reached');
                return;
            end
            if app.LegacyClickStage == 0
                app.LegacyAnchorPoint = point;
                app.LegacyClickStage = 1;
                app.updateLegacyPreview(point, modeName);
                return;
            end
            roi = app.legacyRectLikeRoiFromPoints(app.LegacyAnchorPoint, point, modeName);
            app.addLegacyRoi(roi);
            app.LegacyClickStage = 0;
            app.LegacyAnchorPoint = [NaN NaN];
            app.deleteLegacyPreview();
        end

        function handleLegacyAreaClick(app, point)
            if numel(app.LegacyRois) >= app.LegacyMaxRois
                uialert(app.UIFigure, sprintf('A maximum of %d ROIs can be stored.', app.LegacyMaxRois), 'ROI Limit Reached');
                return;
            end
            if app.LegacyClickStage == 0
                app.LegacyClickStage = 1;
                app.updateLegacyPreview(point, 'area');
                return;
            end
            roi = app.legacyAreaRoiFromCenter(point);
            app.addLegacyRoi(roi);
            app.LegacyClickStage = 0;
            app.deleteLegacyPreview();
        end

        function addLegacyRoi(app, roi)
            app.LegacyRois(end + 1) = roi;
            app.drawLegacyRoiGraphic(roi);
            app.refreshLegacyDisplay();
            app.markAnalysisDirty('legacyRoughness');
            app.setLegacyStatus({
                sprintf('Stored ROI %d/%d (%s).', numel(app.LegacyRois), app.LegacyMaxRois, strrep(roi.type, '_', ' '))
                'Metrics and summary updated.'
                });
        end

        function roi = legacyRectLikeRoiFromPoints(app, pt1, pt2, modeName)
            [imgH, imgW] = size(app.LegacyZ);
            x1 = pt1(1); y1 = pt1(2); x2 = pt2(1); y2 = pt2(2);
            if strcmp(modeName, 'square')
                dx = x2 - x1; dy = y2 - y1;
                sx = app.signWithDefault(dx); sy = app.signWithDefault(dy);
                side = min([max(abs(dx), abs(dy)), app.maxSquareDelta(x1, sx, imgW), app.maxSquareDelta(y1, sy, imgH)]);
                x2 = x1 + sx * side; y2 = y1 + sy * side;
            end
            roi = struct('type', modeName, ...
                'x1', round(max(1, min(imgW, min(x1, x2)))), ...
                'x2', round(max(1, min(imgW, max(x1, x2)))), ...
                'y1', round(max(1, min(imgH, min(y1, y2)))), ...
                'y2', round(max(1, min(imgH, max(y1, y2)))));
        end

        function roi = legacyAreaRoiFromCenter(app, point)
            [imgH, imgW] = size(app.LegacyZ);
            fixedAreaWidthPx = max(1, round(app.LegacyAreaWidthField.Value / app.LegacyXyUmPerPx));
            fixedAreaHeightPx = max(1, round(app.LegacyAreaHeightField.Value / app.LegacyXyUmPerPx));
            halfW = (fixedAreaWidthPx - 1) / 2;
            halfH = (fixedAreaHeightPx - 1) / 2;
            x1 = round(point(1) - halfW);
            y1 = round(point(2) - halfH);
            x1 = min(max(x1, 1), imgW - fixedAreaWidthPx + 1);
            y1 = min(max(y1, 1), imgH - fixedAreaHeightPx + 1);
            roi = struct('type', 'area', 'x1', x1, 'x2', x1 + fixedAreaWidthPx - 1, ...
                'y1', y1, 'y2', y1 + fixedAreaHeightPx - 1);
        end

        function updateLegacyPreview(app, point, modeName)
            if strcmp(modeName, 'area')
                roi = app.legacyAreaRoiFromCenter(point);
            else
                roi = app.legacyRectLikeRoiFromPoints(app.LegacyAnchorPoint, point, modeName);
            end
            pos = app.legacyRoiToRectanglePosition(roi);
            if ~isgraphics(app.LegacyPreviewGraphic)
                app.LegacyPreviewGraphic = rectangle(app.LegacyAxes, 'Position', pos, ...
                    'EdgeColor', app.LegacyRoiColor, 'LineStyle', '--', 'LineWidth', 1.25);
            else
                app.LegacyPreviewGraphic.Position = pos;
            end
        end

        function drawLegacyRoiGraphic(app, roi)
            app.LegacyRoiGraphics(end + 1) = rectangle(app.LegacyAxes, ...
                'Position', app.legacyRoiToRectanglePosition(roi), ...
                'EdgeColor', app.LegacyRoiColor, 'LineWidth', 1.3);
        end

        function pos = legacyRoiToRectanglePosition(~, roi)
            pos = [roi.x1 - 0.5, roi.y1 - 0.5, roi.x2 - roi.x1 + 1, roi.y2 - roi.y1 + 1];
        end

        function clearLegacyRois(app)
            app.LegacyRois = struct('type', {}, 'x1', {}, 'x2', {}, 'y1', {}, 'y2', {});
            if ~isempty(app.LegacyRoiGraphics)
                delete(app.LegacyRoiGraphics(isgraphics(app.LegacyRoiGraphics)));
            end
            app.LegacyRoiGraphics = gobjects(0);
        end

        function cancelLegacyPlacement(app)
            app.LegacyActiveMode = '';
            app.LegacyClickStage = 0;
            app.LegacyAnchorPoint = [NaN NaN];
            app.deleteLegacyPreview();
            app.setLegacyButtonStates();
        end

        function deleteLegacyPreview(app)
            if isgraphics(app.LegacyPreviewGraphic)
                delete(app.LegacyPreviewGraphic);
            end
            app.LegacyPreviewGraphic = gobjects(1);
        end

        function refreshLegacyDisplay(app)
            currentResults = app.buildLegacyResults(false, '', '');
            app.updateLegacySummary(currentResults);
            app.updateLegacyTable(currentResults.roi_table);
        end

        function results = buildLegacyResults(app, savedFlag, matPath, csvPath)
            results = legacySurfaceRoughnessMeasureROIs(app.LegacyZ, app.LegacyXyUmPerPx, ...
                app.LegacyImagePath, app.LegacyRois);
            results.saved = savedFlag;
            results.saved_files = struct('mat', matPath, 'csv', csvPath);
        end

        function updateLegacySummary(app, currentResults)
            lines = {
                sprintf('Surface source: %s', app.LegacySurfaceInput.source_label)
                sprintf('Image size: %.2f um x %.2f um', currentResults.image_size_um(1), currentResults.image_size_um(2))
                sprintf('Ref plane: %.4f um', currentResults.refPlane_um)
                sprintf('Global Rp / Rv / Rz: %.4f / %.4f / %.4f um', currentResults.Rp_global, currentResults.Rv_global, currentResults.Rz_global)
                sprintf('Global SA/A: %.4f', currentResults.SA_to_A_ratio_global)
                sprintf('ROI count: %d / %d', currentResults.n_rois, app.LegacyMaxRois)
                };
            if currentResults.n_rois > 0
                lines = [lines; {
                    sprintf('Mean Rp +/- std: %.4f +/- %.4f um', currentResults.mean_Rp_um, currentResults.std_Rp_um)
                    sprintf('Mean Rv +/- std: %.4f +/- %.4f um', currentResults.mean_Rv_um, currentResults.std_Rv_um)
                    sprintf('Mean Rz +/- std: %.4f +/- %.4f um', currentResults.mean_Rz_um, currentResults.std_Rz_um)
                    sprintf('Mean SA/A +/- std: %.4f +/- %.4f', currentResults.mean_SA_to_A_ratio, currentResults.std_SA_to_A_ratio)
                    }];
            else
                lines = [lines; {'No ROIs placed yet.'}];
            end
            app.LegacySummaryTextArea.Value = lines;
        end

        function updateLegacyTable(app, roiTable)
            if isempty(roiTable)
                app.LegacyTable.Data = cell(0, 6);
                return;
            end
            app.LegacyTable.Data = [num2cell(roiTable.ROI_Index), ...
                cellstr(roiTable.ROI_Type), ...
                num2cell(round(roiTable.Rp_um, 4)), ...
                num2cell(round(roiTable.Rv_um, 4)), ...
                num2cell(round(roiTable.Rz_um, 4)), ...
                num2cell(round(roiTable.SA_to_A_ratio, 4))];
        end

        function setLegacyStatus(app, lines)
            if ischar(lines) || isstring(lines)
                lines = cellstr(lines);
            end
            app.LegacyStatusTextArea.Value = lines;
        end

        function csvCell = buildLegacyCsvExport(~, results)
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

        function s = signWithDefault(~, v)
            if v >= 0
                s = 1;
            else
                s = -1;
            end
        end

        function sideMax = maxSquareDelta(~, anchorCoord, directionSign, maxCoord)
            if directionSign >= 0
                sideMax = maxCoord - anchorCoord;
            else
                sideMax = anchorCoord - 1;
            end
        end
    end

    methods (Access = public)
        function app = SOLFAnalysisApp()
            createComponents(app);
            registerApp(app, app.UIFigure);
            runStartupFcn(app, @(~,~)startup(app));
            if nargout == 0
                clear app
            end
        end

        function delete(app)
            if isvalid(app.UIFigure)
                delete(app.UIFigure);
            end
        end
    end
end
