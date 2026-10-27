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
%      NOTE: MATLAB has no 'millimeters' unit -- write figW/figH in mm,
%      but hand the figure/paper properties values in CENTIMETRES
%      (see mm2cm below).  'millimeters' makes figure() error out.
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

    % MATLAB 没有 'millimeters' 单位（只认 inches/centimeters/points/
    % pixels/normalized/characters），所以几何量仍按 mm 书写，交给下面
    % 的换算统一转成 cm 再赋给图窗属性。
    mm2cm = @(v) v / 10;
    figWcm = mm2cm(figW);
    figHcm = mm2cm(figH);

    outDir = fullfile(fileparts(mfilename('fullpath')), 'svg_out');
    if ~exist(outDir, 'dir'); mkdir(outDir); end
    outFile = fullfile(outDir, 'fig1_overview.svg');

    % ---- 2. Figure window (off-screen, exact size) ----------
    hFig = figure('Visible', 'off', ...
                  'Units', 'centimeters', ...
                  'Position', [0 0 figWcm figHcm], ...
                  'Color', 'w', ...
                  'MenuBar', 'none', ...
                  'ToolBar', 'none', ...
                  'NumberTitle', 'off', ...
                  'Name', 'fig1_overview', ...
                  'PaperUnits', 'centimeters', ...
                  'PaperSize', [figWcm figHcm], ...
                  'PaperPosition', [0 0 figWcm figHcm], ...
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
    % 用 print -dsvg 而非 exportgraphics：两者都按整数 pt 落盘，
    % 但 exportgraphics 会把内容外框（含边框线宽）一起算进去，
    % 实测 85x60 mm 的板子会输出成 86.08x61.38 mm；print 严格
    % 按 PaperSize/PaperPosition 出图（85.02x60.33 mm，仅差一个
    % 取整 pt），所以尺寸契约以 print 为准。
    set(hFig, 'PaperPositionMode', 'manual');
    print(hFig, outFile, '-dsvg', '-painters');

    close(hFig);
    fprintf('  [fig1_overview] %g x %g mm  ->  %s\n', figW, figH, outFile);
end
