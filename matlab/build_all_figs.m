% =============================================================
%  build_all_figs.m  --  run every figure script in this folder
% -------------------------------------------------------------
%  Discovers and executes all  fig*.m  scripts sitting next to this
%  file (itself excluded), so adding a new plot only requires
%  dropping a new  fig<name>.m  into  matlab/.
%
%  Command line:   matlab -batch "build_all_figs"
%  Or via make:    make matlab
%
%  Output:         matlab/svg_out/*.svg   (consumed by figs_src/*.typ)
% =============================================================

function build_all_figs()
    thisDir = fileparts(mfilename('fullpath'));
    outDir  = fullfile(thisDir, 'svg_out');
    if ~exist(outDir, 'dir'); mkdir(outDir); end

    listing = dir(fullfile(thisDir, 'fig*.m'));
    % keep only scripts (skip this file and any non-.m leftovers)
    names = {listing(~[listing.isdir]).name};

    if isempty(names)
        fprintf('  [build_all_figs] no fig*.m scripts found in %s\n', thisDir);
        return;
    end

    addpath(thisDir);
    fprintf('=== build_all_figs: %d script(s) ===\n', numel(names));

    tStart = tic;
    okCnt  = 0;
    for k = 1:numel(names)
        [~, funName, ~] = fileparts(names{k});
        fprintf('  -> %s\n', funName);
        try
            feval(funName);
            okCnt = okCnt + 1;
        catch ME
            fprintf(2, '  [FAILED] %s : %s\n', funName, ME.message);
        end
    end

    fprintf('=== done: %d/%d ok in %.2f s  ->  %s ===\n', ...
            okCnt, numel(names), toc(tStart), outDir);

    if okCnt < numel(names)
        error('build_all_figs: %d script(s) failed.', numel(names) - okCnt);
    end
end
