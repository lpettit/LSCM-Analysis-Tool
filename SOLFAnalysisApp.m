classdef SOLFAnalysisApp < matlab.apps.AppBase
    properties (Access = public)
        UIFigure matlab.ui.Figure
        Grid matlab.ui.container.GridLayout
        InputEditField matlab.ui.control.EditField
        OutputEditField matlab.ui.control.EditField
        RunModule1CheckBox matlab.ui.control.CheckBox
        RunModule2CheckBox matlab.ui.control.CheckBox
        RunModule3CheckBox matlab.ui.control.CheckBox
        FillDeepPitsCheckBox matlab.ui.control.CheckBox
        FillThresholdField matlab.ui.control.NumericEditField
        PickFillThresholdButton matlab.ui.control.Button
        ShowAutoTunePlotsCheckBox matlab.ui.control.CheckBox
        UseRefineMoundsCheckBox matlab.ui.control.CheckBox
        AutoTuneEvalsField matlab.ui.control.NumericEditField
        DilateRadiusField matlab.ui.control.NumericEditField
        MinObjectAreaField matlab.ui.control.NumericEditField
        MinDepthField matlab.ui.control.NumericEditField
        StatusTextArea matlab.ui.control.TextArea
    end

    methods (Access = private)
        function startup(app)
            app.StatusTextArea.Value = {
                'SOLF VK4 Analysis App'
                '1. Choose a .vk4 file'
                '2. Choose an output folder'
                '3. Select modules and options'
                '4. If using reflection correction, pick a fill threshold'
                '5. Click Run Analysis'
                };
        end

        function onBrowseInput(app, ~, ~)
            [f, p] = uigetfile('*.vk4', 'Choose VK4 file');
            if isequal(f, 0), return; end
            app.InputEditField.Value = fullfile(p, f);
            if strlength(app.OutputEditField.Value) == 0
                app.OutputEditField.Value = p;
            end
        end

        function onBrowseOutput(app, ~, ~)
            p = uigetdir(pwd, 'Choose output folder');
            if isequal(p, 0), return; end
            app.OutputEditField.Value = p;
        end

        function config = buildConfig(app)
            config = struct( ...
                'inputPath', char(app.InputEditField.Value), ...
                'outputDir', char(app.OutputEditField.Value), ...
                'runModule1', logical(app.RunModule1CheckBox.Value), ...
                'runModule2', logical(app.RunModule2CheckBox.Value), ...
                'runModule3', logical(app.RunModule3CheckBox.Value), ...
                'fillDeepPits', logical(app.FillDeepPitsCheckBox.Value), ...
                'fillThreshold', app.getFillThresholdValue(), ...
                'showAutoTunePlots', logical(app.ShowAutoTunePlotsCheckBox.Value), ...
                'useRefineMounds', logical(app.UseRefineMoundsCheckBox.Value), ...
                'autoTuneMaxEvals', double(app.AutoTuneEvalsField.Value), ...
                'dilateRadius', double(app.DilateRadiusField.Value), ...
                'minObjectArea', double(app.MinObjectAreaField.Value), ...
                'minDepthUm', double(app.MinDepthField.Value));
        end

        function fillThreshold = getFillThresholdValue(app)
            if ~logical(app.FillDeepPitsCheckBox.Value)
                fillThreshold = [];
                return;
            end

            fillThreshold = double(app.FillThresholdField.Value);
            if isnan(fillThreshold) || fillThreshold <= 0 || fillThreshold >= 1
                fillThreshold = [];
            end
        end

        function onFillDeepPitsChanged(app, ~, ~)
            isEnabled = logical(app.FillDeepPitsCheckBox.Value);
            if isEnabled
                app.FillThresholdField.Editable = 'on';
                app.PickFillThresholdButton.Enable = 'on';
            else
                app.FillThresholdField.Editable = 'off';
                app.PickFillThresholdButton.Enable = 'off';
            end
        end

        function onPickFillThreshold(app, ~, ~)
            inputPath = char(app.InputEditField.Value);
            if strlength(string(inputPath)) == 0
                uialert(app.UIFigure, ...
                    'Choose an input .vk4 file before picking a fill threshold.', ...
                    'Missing Input');
                return;
            end
            if ~exist(inputPath, 'file')
                uialert(app.UIFigure, sprintf('Input file not found:\n%s', inputPath), ...
                    'Missing Input', 'Interpreter', 'none');
                return;
            end

            app.StatusTextArea.Value = {
                'Picking fill threshold...'
                ['Input: ' inputPath]
                'Adjust the helper window, then click Confirm.'
                };
            drawnow;

            fillThreshold = pickFillThreshold(inputPath);
            app.FillDeepPitsCheckBox.Value = true;
            app.FillThresholdField.Value = fillThreshold;
            app.onFillDeepPitsChanged();

            app.StatusTextArea.Value = {
                'Fill threshold selected.'
                ['Input: ' inputPath]
                sprintf('fillThreshold = %.3f', fillThreshold)
                };
        end

        function onRun(app, ~, ~)
            try
                config = app.buildConfig();
                if strlength(config.inputPath) == 0
                    uialert(app.UIFigure, 'Choose an input .vk4 file first.', 'Missing Input');
                    return;
                end
                if strlength(config.outputDir) == 0
                    uialert(app.UIFigure, 'Choose an output folder first.', 'Missing Output');
                    return;
                end
                if ~(config.runModule1 || config.runModule2 || config.runModule3)
                    uialert(app.UIFigure, 'Select at least one module to run.', 'No Modules Selected');
                    return;
                end

                app.StatusTextArea.Value = {
                    'Running analysis...'
                    ['Input: ' config.inputPath]
                    ['Output: ' config.outputDir]
                    sprintf('fillDeepPits = %d', config.fillDeepPits)
                    };
                drawnow;

                runResults = runSOLFAnalysis(config); %#ok<NASGU>

                app.StatusTextArea.Value = {
                    'Analysis complete.'
                    ['Input: ' config.inputPath]
                    ['Output: ' config.outputDir]
                    'Saved outputs to disk and opened module figures.'
                    };
            catch ME
                app.StatusTextArea.Value = {
                    'Analysis failed.'
                    ME.message
                    };
                uialert(app.UIFigure, ME.message, 'SOLF Analysis Error', 'Interpreter', 'none');
            end
        end

        function createComponents(app)
            app.UIFigure = uifigure('Name', 'SOLF VK4 Analysis App', 'Position', [100 100 900 680]);
            app.Grid = uigridlayout(app.UIFigure, [12 4]);
            app.Grid.RowHeight = {26, 26, 26, 26, 26, 26, 26, 26, 26, 26, '1x', 40};
            app.Grid.ColumnWidth = {150, '1x', 120, 150};
            app.Grid.Padding = [12 12 12 12];

            lbl = uilabel(app.Grid, 'Text', 'Input .vk4 file', 'HorizontalAlignment', 'right');
            lbl.Layout.Row = 1; lbl.Layout.Column = 1;
            app.InputEditField = uieditfield(app.Grid, 'text');
            app.InputEditField.Layout.Row = 1; app.InputEditField.Layout.Column = [2 3];
            btnIn = uibutton(app.Grid, 'push', 'Text', 'Browse...');
            btnIn.Layout.Row = 1; btnIn.Layout.Column = 4;
            btnIn.ButtonPushedFcn = @(src, event) app.onBrowseInput(src, event);

            lbl = uilabel(app.Grid, 'Text', 'Output folder', 'HorizontalAlignment', 'right');
            lbl.Layout.Row = 2; lbl.Layout.Column = 1;
            app.OutputEditField = uieditfield(app.Grid, 'text');
            app.OutputEditField.Layout.Row = 2; app.OutputEditField.Layout.Column = [2 3];
            btnOut = uibutton(app.Grid, 'push', 'Text', 'Browse...');
            btnOut.Layout.Row = 2; btnOut.Layout.Column = 4;
            btnOut.ButtonPushedFcn = @(src, event) app.onBrowseOutput(src, event);

            app.RunModule1CheckBox = uicheckbox(app.Grid, 'Text', 'Run Module 1', 'Value', true);
            app.RunModule1CheckBox.Layout.Row = 3; app.RunModule1CheckBox.Layout.Column = 2;
            app.RunModule2CheckBox = uicheckbox(app.Grid, 'Text', 'Run Module 2', 'Value', false);
            app.RunModule2CheckBox.Layout.Row = 3; app.RunModule2CheckBox.Layout.Column = 3;
            app.RunModule3CheckBox = uicheckbox(app.Grid, 'Text', 'Run Module 3', 'Value', true);
            app.RunModule3CheckBox.Layout.Row = 3; app.RunModule3CheckBox.Layout.Column = 4;

            app.FillDeepPitsCheckBox = uicheckbox(app.Grid, 'Text', 'Use reflection correction', 'Value', false);
            app.FillDeepPitsCheckBox.Layout.Row = 4; app.FillDeepPitsCheckBox.Layout.Column = 2;
            app.FillDeepPitsCheckBox.ValueChangedFcn = @(src, event) app.onFillDeepPitsChanged(src, event);

            app.FillThresholdField = uieditfield(app.Grid, 'numeric', ...
                'Value', 0.50, ...
                'Limits', [0 1], ...
                'LowerLimitInclusive', false, ...
                'UpperLimitInclusive', false);
            app.FillThresholdField.Layout.Row = 4; app.FillThresholdField.Layout.Column = 3;
            app.FillThresholdField.Tooltip = 'fillThreshold used when reflection correction is enabled';

            app.PickFillThresholdButton = uibutton(app.Grid, 'push', 'Text', 'Pick fill threshold...');
            app.PickFillThresholdButton.Layout.Row = 4; app.PickFillThresholdButton.Layout.Column = 4;
            app.PickFillThresholdButton.ButtonPushedFcn = @(src, event) app.onPickFillThreshold(src, event);

            app.ShowAutoTunePlotsCheckBox = uicheckbox(app.Grid, 'Text', 'Show auto-tune plots', 'Value', true);
            app.ShowAutoTunePlotsCheckBox.Layout.Row = 5; app.ShowAutoTunePlotsCheckBox.Layout.Column = [2 3];

            lbl = uilabel(app.Grid, 'Text', 'Max optimization evaluations', 'HorizontalAlignment', 'right');
            lbl.Layout.Row = 6; lbl.Layout.Column = 1;
            app.AutoTuneEvalsField = uieditfield(app.Grid, 'numeric', ...
                'Value', 60, 'Limits', [1 Inf], 'RoundFractionalValues', true);
            app.AutoTuneEvalsField.Layout.Row = 6; app.AutoTuneEvalsField.Layout.Column = 2;
            lbl = uilabel(app.Grid, 'Text', 'Dilate radius', 'HorizontalAlignment', 'right');
            lbl.Layout.Row = 6; lbl.Layout.Column = 3;
            app.DilateRadiusField = uieditfield(app.Grid, 'numeric', ...
                'Value', 3, 'Limits', [1 Inf], 'RoundFractionalValues', true);
            app.DilateRadiusField.Layout.Row = 6; app.DilateRadiusField.Layout.Column = 4;

            lbl = uilabel(app.Grid, 'Text', 'Min object area', 'HorizontalAlignment', 'right');
            lbl.Layout.Row = 7; lbl.Layout.Column = 1;
            app.MinObjectAreaField = uieditfield(app.Grid, 'numeric', ...
                'Value', 20, 'Limits', [1 Inf], 'RoundFractionalValues', true);
            app.MinObjectAreaField.Layout.Row = 7; app.MinObjectAreaField.Layout.Column = 2;
            lbl = uilabel(app.Grid, 'Text', 'Min cavity depth (um)', 'HorizontalAlignment', 'right');
            lbl.Layout.Row = 7; lbl.Layout.Column = 3;
            app.MinDepthField = uieditfield(app.Grid, 'numeric', 'Value', 2.0, 'Limits', [0 Inf]);
            app.MinDepthField.Layout.Row = 7; app.MinDepthField.Layout.Column = 4;

            app.UseRefineMoundsCheckBox = uicheckbox(app.Grid, ...
                'Text', 'Use refineMounds after autoTune if more control is needed', ...
                'Value', false);
            app.UseRefineMoundsCheckBox.Layout.Row = 8;
            app.UseRefineMoundsCheckBox.Layout.Column = [2 4];

            lbl = uilabel(app.Grid, 'Text', 'Status', 'HorizontalAlignment', 'left', 'FontWeight', 'bold');
            lbl.Layout.Row = 9; lbl.Layout.Column = 1;
            app.StatusTextArea = uitextarea(app.Grid, 'Editable', 'off');
            app.StatusTextArea.Layout.Row = 10; app.StatusTextArea.Layout.Column = [1 4];

            btnRun = uibutton(app.Grid, 'push', 'Text', 'Run Analysis', 'FontWeight', 'bold');
            btnRun.Layout.Row = 12; btnRun.Layout.Column = [3 4];
            btnRun.ButtonPushedFcn = @(src, event) app.onRun(src, event);

            app.onFillDeepPitsChanged();
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
