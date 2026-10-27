% =============================================================
%  fig1_overview.m  --  template for a "bare" paper sub-plot
% -------------------------------------------------------------
%  CONTRACT (keep this identical for every fig*.m script):
%    * Export ONLY the data canvas: no title, no legend, no colorbar,
%      no axis labels, no annotations.  All of that is added later in
%      Typst (figs_src/*.typ) so the whole paper shares one typeface.
%    * Exact physical size in millimetres, zero outer margin,
%      opaque WHITE background -> the SVG bounding box matches the
%      panel box in Typst exactly.
%    * Output: matlab/svg_out/<script_name>.svg
%    * Font:   leave at MATLAB default (Helvetica/Arial); Typst re-labels.
%    * Colors: use RGB triplets / hex so they survive re-labelling.
% =============================================================

function fig1_overview()
    clc;

    % ---- 1. Canvas geometry (mm) ---------------------------
    % 85 mm  = single column of an A4 two-column article
    % 170 mm = full text width; pick the one matching the Typst panel.
    figW = 85;
    figH = 60;

    outDir = fullfile(fileparts(mfilename('fullpath')), 'svg_out');
    if ~exist(outDir, 'dir'); mkdir(outDir); end
    outFile = fullfile(outDir, 'fig1_overview.svg');

    % ---- 2. Figure window (off-screen, exact size) ----------
    hFig = figure('Visible', 'off', ...
                  'Units', 'millimeters', ...
                  'Position', [0 0 figW figH], ...
                  'Color', 'w', ...
                  'MenuBar', 'none', ...
                  'ToolBar', 'none', ...
                  'NumberTitle', 'off', ...
                  'Name', 'fig1_overview', ...
                  'PaperUnits', 'millimeters', ...
                  'PaperSize', [figW figH], ...
                  'PaperPosition', [0 0 figW figH], ...
                  'PaperPositionMode', 'manual', ...
                  'InvertHardcopy', 'off');

    % ---- 3. Axes filling the whole canvas, no decoration ----
    hAx = axes('Parent', hFig, ...
               'Units', 'normalized', ...
               'Position', [0 0 1 1], ...
               'Color', 'w', ...
               'Box', 'on', ...
               'XTick', [], 'YTick', [], ...
               'XColor', 'k', 'YColor', 'k', ...
               'LineWidth', 0.6, ...
               'TickDir', 'out', ...
               'Layer', 'top');
    hold(hAx, 'on');

    % ---- 4. YOUR DATA GOES HERE -----------------------------
    %   plot(hAx, x, y, 'LineWidth', 1.0, 'Color', [0 0.4470 0.7410]);
    %   scatter(hAx, x, y, 12, 'filled', 'MarkerFaceColor', [0.85 0.33 0.10]);
    %   imagesc / contourf / errorbar ...
    % (Nothing is drawn yet: this is an intentionally empty canvas.)

    xlim(hAx, [0 1]);
    ylim(hAx, [0 1]);

    % ---- 5. Export true vector SVG on a white background ----
    try
        % R2023b+ : preferred, preserves exact paper size
        exportgraphics(hFig, outFile, ...
                       'ContentType', 'vector', ...
                       'BackgroundColor', 'white');
    catch
        % Fallback for older releases
        set(hFig, 'PaperPositionMode', 'manual');
        print(hFig, outFile, '-dsvg', '-painters');
    end

    close(hFig);
    fprintf('  [fig1_overview] %g x %g mm  ->  %s\n', figW, figH, outFile);
end
