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

        ReviewPanel matlab.ui.container.Panel
        ReviewGrid matlab.ui.container.GridLayout
        ReviewTabGroup matlab.ui.container.TabGroup
        TierButtonGrid matlab.ui.container.GridLayout
        DoneButton matlab.ui.control.Button
        TooFewButton matlab.ui.control.Button
        TooManyButton matlab.ui.control.Button
        ManualCountField matlab.ui.control.NumericEditField
        ManualCountButton matlab.ui.control.Button
        StatusTextArea matlab.ui.control.TextArea
        LaunchLegacyRoughnessButton matlab.ui.control.Button
    end

    properties (Access = private)
        OutputWasAutoDefaulted logical = false
        BestParamsIsValid logical = false
        MoundGuiState struct = struct()
        MoundReviewResults cell = {}
        MoundResultCount double = 0
        IdleButtonColor double = [0.94 0.94 0.94]
        ActiveButtonColor double = [0.55 0.82 0.58]
        RunningButtonColor double = [0.30 0.68 0.35]
    end

    methods (Access = private)
        function startup(app)
            app.logStatus({
                'SOLF VK4 Analysis App'
                'Choose a .vk4 file to begin.'
                'Optional: choose a bestParams.mat file to unlock downstream analysis modules.'
                });
            app.updateModuleButtonStates();
        end

        function onBrowseInput(app, ~, ~)
            [f, p] = uigetfile('*.vk4', 'Choose VK4 file');
            if isequal(f, 0), return; end

            app.InputEditField.Value = fullfile(p, f);
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
            app.logStatus({'Output folder selected.'; ['Output: ' p]});
        end

        function onBrowseBestParams(app, ~, ~)
            [f, p] = uigetfile('*.mat', 'Choose bestParams MAT file');
            if isequal(f, 0), return; end

            candidatePath = fullfile(p, f);
            [isValid, msg] = app.validateBestParamsFile(candidatePath);
            if ~isValid
                app.BestParamsEditField.Value = '';
                app.BestParamsIsValid = false;
                app.logStatus({'Invalid bestParams file.'; msg});
                uialert(app.UIFigure, msg, 'Invalid bestParams File', 'Interpreter', 'none');
            else
                app.BestParamsEditField.Value = candidatePath;
                app.BestParamsIsValid = true;
                app.logStatus({'bestParams file selected.'; ['bestParams: ' candidatePath]});
            end
            app.updateModuleButtonStates();
        end

        function [isValid, msg] = validateBestParamsFile(~, matPath)
            isValid = false;
            if ~exist(matPath, 'file')
                msg = sprintf('File not found:\n%s', matPath);
                return;
            end
            try
                info = whos('-file', matPath);
                names = {info.name};
                if ~ismember('bestParams', names)
                    msg = 'The selected .mat file must contain a variable named bestParams.';
                    return;
                end
                loaded = load(matPath, 'bestParams');
                required = {'morphScale', 'contrastMethod', 'gaussSigma', 'openRadius', 'clipLimit'};
                if ~istable(loaded.bestParams)
                    msg = 'bestParams must be a MATLAB table.';
                    return;
                end
                missing = setdiff(required, loaded.bestParams.Properties.VariableNames);
                if ~isempty(missing)
                    msg = ['bestParams is missing required fields: ' strjoin(missing, ', ')];
                    return;
                end
                isValid = true;
                msg = 'bestParams file is valid.';
            catch ME
                msg = ME.message;
            end
        end

        function updateModuleButtonStates(app)
            hasVk4 = app.hasValidVk4();
            hasBestParams = app.BestParamsIsValid && exist(char(app.BestParamsEditField.Value), 'file') == 2;

            app.setButtonEnabled(app.MoundDetectionButton, hasVk4);
            app.setButtonEnabled(app.LegacyRoughnessButton, hasVk4);
            app.setButtonEnabled(app.CavityAnalysisButton, false);
            app.setButtonEnabled(app.MoundSurfaceButton, hasVk4 && hasBestParams);
            app.setButtonEnabled(app.SpatialAnalysisButton, hasVk4 && hasBestParams);
        end

        function tf = hasValidVk4(app)
            inputPath = char(app.InputEditField.Value);
            [~, ~, ext] = fileparts(inputPath);
            tf = strlength(string(inputPath)) > 0 && exist(inputPath, 'file') == 2 && strcmpi(ext, '.vk4');
        end

        function setButtonEnabled(~, btn, tf)
            if tf
                btn.Enable = 'on';
            else
                btn.Enable = 'off';
            end
        end

        function onMoundDetection(app, ~, ~)
            if ~app.hasValidVk4()
                uialert(app.UIFigure, 'Choose a valid .vk4 file before starting mound detection.', 'Missing Input');
                return;
            end
            app.MoundDetectionButton.BackgroundColor = app.ActiveButtonColor;
            app.showMoundSettings(true);
            app.showReviewPanel(false);
            app.logStatus({
                'Mound Detection selected.'
                'Set reflection-correction options, then run mound detection.'
                });
        end

        function showMoundSettings(app, isVisible)
            if isVisible
                app.MoundSettingsPanel.Visible = 'on';
                app.MainGrid.ColumnWidth = {280, 2, 235, '1x'};
            else
                app.MoundSettingsPanel.Visible = 'off';
                app.MainGrid.ColumnWidth = {280, 2, 0, '1x'};
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
            app.showReviewPanel(true);
            app.clearReviewTabs();
            app.setTierControlsEnabled(false);
            app.setMoundControlsEnabled(false);

            try
                inputPath = char(app.InputEditField.Value);
                outputDir = char(app.OutputEditField.Value);
                app.MoundGuiState = refineMoundsStableGuiCore('init', inputPath, ...
                    logical(app.FillDeepPitsCheckBox.Value), app.getFillThresholdValue(), ...
                    3, 20, outputDir, double(app.MaxEvalsField.Value), ...
                    @(msg) app.appendLog(msg));
                [app.MoundGuiState, result] = refineMoundsStableGuiCore('runInitial', app.MoundGuiState);
                app.addMoundReviewTab(result);
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
                app.updateModuleButtonStates();
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
            tabGrid = uigridlayout(tab, [1 2]);
            tabGrid.ColumnWidth = {'1x', '1x'};
            tabGrid.RowHeight = {'1x'};
            tabGrid.Padding = [8 8 8 8];
            tabGrid.ColumnSpacing = 10;

            axOverlay = uiaxes(tabGrid);
            axOverlay.Layout.Row = 1;
            axOverlay.Layout.Column = 1;
            imshow(result.I, [], 'Parent', axOverlay);
            hold(axOverlay, 'on');
            if ~isempty(result.centroids)
                plot(axOverlay, result.centroids(:,1), result.centroids(:,2), 'r+', ...
                    'MarkerSize', 6, 'LineWidth', 1.0);
            end
            hold(axOverlay, 'off');
            title(axOverlay, sprintf('%s | %d mounds | target %.0f', ...
                result.tierLabel, result.nCurrent, result.nMid), 'Interpreter', 'none');

            axHist = uiaxes(tabGrid);
            axHist.Layout.Row = 1;
            axHist.Layout.Column = 2;
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

            app.ReviewTabGroup.SelectedTab = tab;
            app.appendLog(sprintf('Review tab added: %s (%d mounds).', tabTitle, result.nCurrent));
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
            if ~exist(outputDir, 'dir')
                mkdir(outputDir);
            end

            [~, imageName] = fileparts(char(app.InputEditField.Value));
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

        function logStatus(app, lines)
            if ischar(lines) || isstring(lines)
                lines = cellstr(lines);
            end
            app.StatusTextArea.Value = lines;
        end

        function appendLog(app, msg)
            if isstring(msg), msg = char(msg); end
            current = app.StatusTextArea.Value;
            if ischar(current), current = {current}; end
            app.StatusTextArea.Value = [current; {msg}];
            drawnow;
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

                app.StatusTextArea.Value = {
                    'Preparing legacy roughness GUI...'
                    ['Input: ' inputPath]
                    ['Output: ' outputDir]
                    'Loading the height surface directly from the selected VK4 file.'
                    };
                drawnow;

                legacyResults = legacySurfaceRoughnessGUI(inputPath, outputDir); %#ok<NASGU>

                app.StatusTextArea.Value = {
                    'Legacy roughness GUI closed.'
                    ['Input: ' inputPath]
                    ['Output: ' outputDir]
                    'Saved legacy roughness outputs if you clicked Done in the GUI.'
                    };
            catch ME
                app.StatusTextArea.Value = {
                    'Legacy roughness GUI launch failed.'
                    ME.message
                    };
                uialert(app.UIFigure, ME.message, 'Legacy Roughness GUI Error', 'Interpreter', 'none');
            end
        end

        function createComponents(app)
            app.UIFigure = uifigure('Name', 'SOLF VK4 Analysis App');
            app.UIFigure.WindowState = 'maximized';

            app.MainGrid = uigridlayout(app.UIFigure, [1 4]);
            app.MainGrid.ColumnWidth = {280, 2, 0, '1x'};
            app.MainGrid.RowHeight = {'1x'};
            app.MainGrid.Padding = [10 10 10 10];
            app.MainGrid.ColumnSpacing = 10;

            app.createLeftColumn();
            app.createMoundSettingsColumn();
            app.createReviewArea();
        end

        function createLeftColumn(app)
            app.LeftPanel = uipanel(app.MainGrid, 'Title', '');
            app.LeftPanel.Layout.Row = 1;
            app.LeftPanel.Layout.Column = 1;

            app.LeftGrid = uigridlayout(app.LeftPanel, [18 1]);
            app.LeftGrid.RowHeight = {18, 28, 28, 18, 28, 28, 18, 28, 28, 30, 30, 30, 30, 30, '1x', 26, 26, 26};
            app.LeftGrid.Padding = [8 8 8 8];
            app.LeftGrid.RowSpacing = 7;

            uilabel(app.LeftGrid, 'Text', 'Input .vk4 file', 'FontWeight', 'bold');
            app.InputEditField = uieditfield(app.LeftGrid, 'text', 'Editable', 'off');
            btnIn = uibutton(app.LeftGrid, 'push', 'Text', 'Browse VK4...');
            btnIn.ButtonPushedFcn = @(src, event) app.onBrowseInput(src, event);

            uilabel(app.LeftGrid, 'Text', 'Output folder', 'FontWeight', 'bold');
            app.OutputEditField = uieditfield(app.LeftGrid, 'text', 'Editable', 'off');
            btnOut = uibutton(app.LeftGrid, 'push', 'Text', 'Browse Output...');
            btnOut.ButtonPushedFcn = @(src, event) app.onBrowseOutput(src, event);

            uilabel(app.LeftGrid, 'Text', 'bestParams .mat', 'FontWeight', 'bold');
            app.BestParamsEditField = uieditfield(app.LeftGrid, 'text', 'Editable', 'off');
            btnBest = uibutton(app.LeftGrid, 'push', 'Text', 'Browse bestParams...');
            btnBest.ButtonPushedFcn = @(src, event) app.onBrowseBestParams(src, event);

            app.MoundDetectionButton = uibutton(app.LeftGrid, 'push', 'Text', '1. Mound Detection');
            app.MoundDetectionButton.ButtonPushedFcn = @(src, event) app.onMoundDetection(src, event);
            app.CavityAnalysisButton = uibutton(app.LeftGrid, 'push', 'Text', '2. Cavity Analysis');
            app.MoundSurfaceButton = uibutton(app.LeftGrid, 'push', 'Text', '3. Mound/Surface Analysis');
            app.SpatialAnalysisButton = uibutton(app.LeftGrid, 'push', 'Text', '4. Spatial Analysis');
            app.LegacyRoughnessButton = uibutton(app.LeftGrid, 'push', 'Text', '5. Legacy Roughness Measurement');

            app.DividerPanel = uipanel(app.MainGrid, 'BorderType', 'none', 'BackgroundColor', [0.55 0.55 0.55]);
            app.DividerPanel.Layout.Row = 1;
            app.DividerPanel.Layout.Column = 2;
        end

        function createMoundSettingsColumn(app)
            app.MoundSettingsPanel = uipanel(app.MainGrid, 'Title', 'Mound Detection');
            app.MoundSettingsPanel.Layout.Row = 1;
            app.MoundSettingsPanel.Layout.Column = 3;
            app.MoundSettingsPanel.Visible = 'off';

            app.MoundSettingsGrid = uigridlayout(app.MoundSettingsPanel, [10 1]);
            app.MoundSettingsGrid.RowHeight = {30, 26, 26, 26, 26, 26, '1x', 30, 30, 42};
            app.MoundSettingsGrid.Padding = [8 10 8 10];
            app.MoundSettingsGrid.RowSpacing = 9;

            app.FillDeepPitsCheckBox = uicheckbox(app.MoundSettingsGrid, ...
                'Text', 'Use reflection correction', 'Value', false);

            uilabel(app.MoundSettingsGrid, 'Text', 'Fill threshold', 'FontWeight', 'bold');
            app.FillThresholdField = uieditfield(app.MoundSettingsGrid, 'numeric', ...
                'Value', 0.50, 'Limits', [0 1], ...
                'LowerLimitInclusive', false, 'UpperLimitInclusive', false);
            app.FillThresholdField.Tooltip = 'fillThreshold used when reflection correction is enabled';

            app.PickFillThresholdButton = uibutton(app.MoundSettingsGrid, 'push', ...
                'Text', 'Pick Fill Threshold...');
            app.PickFillThresholdButton.ButtonPushedFcn = @(src, event) app.onPickFillThreshold(src, event);

            uilabel(app.MoundSettingsGrid, 'Text', 'Max evals', 'FontWeight', 'bold');
            app.MaxEvalsField = uieditfield(app.MoundSettingsGrid, 'numeric', ...
                'Value', 60, 'Limits', [1 Inf], 'RoundFractionalValues', true);
            app.MaxEvalsField.Tooltip = 'Max Bayesian optimization evaluations for initial mound detection';

            uilabel(app.MoundSettingsGrid, 'Text', '');
            uilabel(app.MoundSettingsGrid, 'Text', '');

            app.RunMoundDetectionButton = uibutton(app.MoundSettingsGrid, 'push', ...
                'Text', 'Run Mound Detection', 'FontWeight', 'bold');
            app.RunMoundDetectionButton.ButtonPushedFcn = @(src, event) app.onRunMoundDetection(src, event);
        end

        function createReviewArea(app)
            app.ReviewPanel = uipanel(app.MainGrid, 'Title', 'Mound Detection Review');
            app.ReviewPanel.Layout.Row = 1;
            app.ReviewPanel.Layout.Column = 4;
            app.ReviewPanel.Visible = 'off';

            app.ReviewGrid = uigridlayout(app.ReviewPanel, [3 1]);
            app.ReviewGrid.RowHeight = {'1x', 42, 145};
            app.ReviewGrid.Padding = [8 8 8 8];
            app.ReviewGrid.RowSpacing = 8;

            app.ReviewTabGroup = uitabgroup(app.ReviewGrid);
            app.ReviewTabGroup.Layout.Row = 1;
            app.ReviewTabGroup.Layout.Column = 1;

            app.TierButtonGrid = uigridlayout(app.ReviewGrid, [1 6]);
            app.TierButtonGrid.Layout.Row = 2;
            app.TierButtonGrid.Layout.Column = 1;
            app.TierButtonGrid.ColumnWidth = {85, 120, 130, 100, 110, '1x'};
            app.TierButtonGrid.RowHeight = {'1x'};
            app.TierButtonGrid.Padding = [0 0 0 0];

            app.DoneButton = uibutton(app.TierButtonGrid, 'push', 'Text', 'Done');
            app.DoneButton.ButtonPushedFcn = @(src, event) app.onDone(src, event);
            app.TooFewButton = uibutton(app.TierButtonGrid, 'push', 'Text', 'Too Few Mounds');
            app.TooFewButton.ButtonPushedFcn = @(src, event) app.onTooFew(src, event);
            app.TooManyButton = uibutton(app.TierButtonGrid, 'push', 'Text', 'Too Many Mounds');
            app.TooManyButton.ButtonPushedFcn = @(src, event) app.onTooMany(src, event);
            app.ManualCountField = uieditfield(app.TierButtonGrid, 'numeric', ...
                'Limits', [1 Inf], 'RoundFractionalValues', true, 'Value', 100);
            app.ManualCountButton = uibutton(app.TierButtonGrid, 'push', 'Text', 'Manual Count');
            app.ManualCountButton.ButtonPushedFcn = @(src, event) app.onManualCount(src, event);

            app.StatusTextArea = uitextarea(app.ReviewGrid, 'Editable', 'off');
            app.StatusTextArea.Layout.Row = 3;
            app.StatusTextArea.Layout.Column = 1;
            app.setTierControlsEnabled(false);
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
