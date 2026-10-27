# =============================================================
#  Ultimate Paper Workflow  --  Academic Figure & Paper Toolchain
#
#  MATLAB (*.m)  --svg-->  Typst (*.typ)  --pdf-->  LaTeX (main.tex)
#                    matlab/svg_out/          figs_output/
#
#  Cross-platform: run from Git Bash (Windows) or Terminal (macOS).
#  On Windows, Git for Windows is a hard requirement: the recipes are
#  POSIX sh and make needs a shell, so start "Git Bash" (or a VS Code
#  terminal with the Git Bash profile) before running any target.
#  POSIX-sh compatible recipes (no bashisms) and no GNU-only make
#  features, so BSD make on macOS works as well.
# =============================================================

SHELL := sh
.DEFAULT_GOAL := help

# ---------------------- Layout ----------------------
MATLAB_DIR      := matlab
MATLAB_ENTRY    := build_all_figs
MATLAB_SVG_DIR  := $(MATLAB_DIR)/svg_out

TYP_SRC_DIR     := figs_src
FIG_OUT_DIR     := figs_output
FONTS_DIR       := fonts

REF_DIR         := latex_refs
TMPL_DIR        := latex_templates
PAPER_DIR       := latex_paper
MAIN_TEX        := $(PAPER_DIR)/main.tex
MAIN_PDF        := $(PAPER_DIR)/main.pdf
PREAMBLE        := $(TMPL_DIR)/preamble.tex

# Journal-template demos in latex_paper/ (one per class in latex_templates/):
#   example_ieee_jmems.tex  IEEEtran        biblatex/biber
#   example_ieee_edl.tex    ieeecolor       biblatex/biber
#   example_nature.tex      sn-jnl          biblatex/biber
#   example_apl.tex         revtex4-2       BibTeX (REVTeX hard-codes natbib)
# They are buildable but not part of "make all": they exist to show how a
# class is wired to ../latex_templates, ../figs_output and ../latex_refs.
EXAMPLES  := $(wildcard $(PAPER_DIR)/example_*.tex)

# Which .tex "make paper" compiles.  Override on the command line:
#   make paper                         -> latex_paper/main.tex   (default)
#   make paper SRC=example_apl         -> latex_paper/example_apl.tex
#   make paper SRC=example_apl.tex     -> same (".tex" is optional)
#   make paper SRC=other/draft.tex     -> used verbatim (any path)
# Resolution happens in the recipe (POSIX sh), not with GNU-make-only
# functions, so BSD make on macOS behaves identically.
#
# DON'T rename this to TEX: "TEX" is a GNU make BUILT-IN variable whose
# default value is "tex" (the TeX binary), so it is always already
# defined and "TEX ?= ..." never fires -- every plain "make paper" would
# then look for "tex.tex".  Same trap for LATEX.  "SRC" is not built in.
SRC ?= $(MAIN_TEX)

# Files in figs_src whose name starts with "_" are shared includes
# (e.g. _lib.typ) and are never compiled into a standalone PDF.
TYP_ALL   := $(wildcard $(TYP_SRC_DIR)/*.typ)
TYP_SRCS  := $(filter-out $(TYP_SRC_DIR)/_%.typ,$(TYP_ALL))
FIG_PDFS  := $(patsubst $(TYP_SRC_DIR)/%.typ,$(FIG_OUT_DIR)/%.pdf,$(TYP_SRCS))

# ---------------------- Tools ----------------------
MATLAB_BIN := matlab
TYPST_BIN  := typst
LATEXMK    := latexmk
PDFLATEX   := pdflatex
BIBER      := biber
BIBTEX     := bibtex
VSCODE_BIN := code

# Toolchain resolver.  Windows installers only extend PATH for NEW
# processes (and winget/choco shims often never do), so a freshly
# installed tool can be invisible to the shell that is running make.
# Every recipe runs in a fresh sh process, so the lookup -- PATH, then
# the known install folders on disk, then FATAL -- is repeated on every
# invocation by this helper.  The folder list lives in the script only,
# so there is exactly one place to update when a tool moves.
# "sh <script>" is used instead of executing it directly so a lost
# executable bit after a git checkout cannot break the build.
#
# INVARIANT: the path below is RELATIVE, so a recipe must never change
# the shell's working directory before using it -- "cd matlab && $(FIND_TOOL)"
# resolves to matlab/setup/find_toolchain.sh and dies with
# "No such file or directory".  When a tool needs to run in another
# folder, give it that folder as an argument instead (see the matlab
# target, which uses "matlab -sd matlab" rather than "cd matlab").
FIND_TOOL := sh setup/find_toolchain.sh

# ---------------------- Colors ----------------------
CYAN   := \033[36m
GREEN  := \033[32m
YELLOW := \033[33m
RED    := \033[31m
BOLD   := \033[1m
RESET  := \033[0m

.PHONY: help check-env matlab figs sync tex-deps paper examples all clean distclean dirs

# =============================================================
#  0. Help / environment check
# =============================================================
help: check-env
	@printf "\n"
	@printf "$(CYAN)Available targets:$(RESET)\n"
	@printf "  $(GREEN)make help$(RESET)       - verify toolchain + print this help (default)\n"
	@printf "  $(GREEN)make matlab$(RESET)     - run $(MATLAB_DIR)/$(MATLAB_ENTRY).m -> regenerate raw SVG plots\n"
	@printf "  $(GREEN)make figs$(RESET)       - compile $(TYP_SRC_DIR)/*.typ -> $(FIG_OUT_DIR)/*.pdf\n"
	@printf "  $(GREEN)make sync$(RESET)       - full figure chain (matlab + figs)\n"
	@printf "  $(GREEN)make tex-deps$(RESET)   - verify every preamble \\\\usepackage resolves (auto-run by 'paper')\n"
	@printf "  $(GREEN)make paper$(RESET)      - latexmk $(MAIN_TEX) -> $(MAIN_PDF)\n"
	@printf "                         add $(BOLD)SRC=x$(RESET) to compile another source. 'x' resolves as:\n"
	@printf "                         x.tex (cwd) -> $(PAPER_DIR)/x.tex -> path/to/x.tex\n"
	@printf "                         e.g. $(BOLD)make paper SRC=example_apl$(RESET)\n"
	@printf "  $(GREEN)make examples$(RESET)   - build every $(PAPER_DIR)/example_*.tex (journal-template demos)\n"
	@printf "  $(GREEN)make all$(RESET)        - matlab -> figs -> paper\n"
	@printf "  $(GREEN)make clean$(RESET)      - delete every LaTeX aux file (.aux/.log/.bbl/.bcf/...),\n"
	@printf "                         keep the .tex sources and the PDFs\n"
	@printf "  $(GREEN)make distclean$(RESET)  - clean + delete all generated figures and PDFs\n"
	@printf "\n"
	@printf "$(CYAN)Windows note:$(RESET) run every target from $(BOLD)Git Bash$(RESET) -- the recipes\n"
	@printf "              are POSIX sh, and make itself needs a shell.\n"
	@printf "$(CYAN)Figure sources found:$(RESET) $(TYP_SRCS)\n"
	@printf "$(CYAN)Figure targets:      $(RESET) $(FIG_PDFS)\n"

check-env:
	@printf "$(CYAN)=== Toolchain verification ===$(RESET)\n"
	@printf "  Resolving PATH -> install folders -> FATAL for each tool:\n"
	@$(FIND_TOOL) --check make sh typst latexmk pdflatex || exit 1
	@$(FIND_TOOL) --check-sty $(PREAMBLE) || exit 1
	@printf "$(CYAN)=== Optional ===$(RESET)\n"
	@command -v $(BIBER) >/dev/null 2>&1 \
		&& printf "  [$(GREEN)OK$(RESET)]      biber    : $$(command -v $(BIBER))\n" \
		|| printf "  [$(YELLOW)OPTIONAL$(RESET)] biber    : needed by biblatex (or switch to bibtex)\n"
	@command -v $(BIBTEX) >/dev/null 2>&1 \
		&& printf "  [$(GREEN)OK$(RESET)]      bibtex   : $$(command -v $(BIBTEX))\n" \
		|| printf "  [$(YELLOW)OPTIONAL$(RESET)] bibtex   : classic bibliography backend\n"
	@command -v $(MATLAB_BIN) >/dev/null 2>&1 \
		&& printf "  [$(GREEN)OK$(RESET)]      matlab   : $$(command -v $(MATLAB_BIN))\n" \
		|| printf "  [$(YELLOW)OPTIONAL$(RESET)] matlab   : no CLI matlab; 'make matlab' will fail\n"
	@command -v $(VSCODE_BIN) >/dev/null 2>&1 \
		&& printf "  [$(GREEN)OK$(RESET)]      vscode   : $$(command -v $(VSCODE_BIN))\n" \
		|| printf "  [$(YELLOW)OPTIONAL$(RESET)] vscode   : editor CLI not on PATH\n"
	@printf "$(CYAN)=== Layout ===$(RESET)\n"
	@for d in $(MATLAB_DIR) $(MATLAB_SVG_DIR) $(TYP_SRC_DIR) $(FIG_OUT_DIR) $(FONTS_DIR) $(REF_DIR) $(TMPL_DIR) $(PAPER_DIR); do \
		if [ -d "$$d" ]; then printf "  [$(GREEN)OK$(RESET)]      $$d/\n"; \
		else printf "  [$(RED)MISSING$(RESET)]  $$d/\n"; fi; \
	done
	@if [ -f "$(MAIN_TEX)" ]; then printf "  [$(GREEN)OK$(RESET)]      $(MAIN_TEX)\n"; \
		else printf "  [$(RED)MISSING$(RESET)]  $(MAIN_TEX)\n"; fi
	@printf "  $(CYAN)Note:$(RESET) a \"[fix]\" line above means the tool is installed\n"
	@printf "        but was not on PATH; it was resolved from disk for this\n"
	@printf "        run.  Open a NEW terminal to make that permanent.\n"

dirs:
	@mkdir -p $(MATLAB_SVG_DIR) $(FIG_OUT_DIR) $(FONTS_DIR)

# =============================================================
#  1. MATLAB -> SVG (raw, unannotated plots)
# =============================================================
matlab:
	@mkdir -p $(MATLAB_SVG_DIR)
	@printf "$(CYAN)--> Running MATLAB: $(MATLAB_DIR)/$(MATLAB_ENTRY).m$(RESET)\n"
	@$(FIND_TOOL) $(MATLAB_BIN) -sd $(MATLAB_DIR) -batch "$(MATLAB_ENTRY)"
	@printf "$(GREEN)--> MATLAB raw SVGs are in $(MATLAB_SVG_DIR)/$(RESET)\n"

# =============================================================
#  2. Typst -> PDF (multi-panel composition + in-figure labels)
# =============================================================
figs: $(FIG_PDFS)
	@printf "$(GREEN)--> Typst panels updated in $(FIG_OUT_DIR)/$(RESET)\n"

# NB: no order-only prerequisites ("| ...") -- BSD make on macOS does
# not support them. Each recipe creates its own output directory.
# NB: FIND_TOOL must sit on the SAME logical line as the command it
# protects -- every recipe line is a separate sh process, so a PATH
# fix on its own line would be thrown away.
# NB: and that line must not start with "cd" -- FIND_TOOL is a relative
# path, see the INVARIANT note where it is defined.
$(FIG_OUT_DIR)/%.pdf: $(TYP_SRC_DIR)/%.typ
	@mkdir -p $(FIG_OUT_DIR)
	@printf "  $(CYAN)typst$(RESET): $< -> $@\n"
	@$(FIND_TOOL) $(TYPST_BIN) compile --root . --font-path $(FONTS_DIR) "$<" "$@"

# =============================================================
#  3. Figure chain sync
# =============================================================
sync: matlab figs
	@printf "$(GREEN)--> Figure chain synced (MATLAB -> SVG -> Typst -> PDF).$(RESET)\n"

# =============================================================
#  4. LaTeX -> main.pdf
# =============================================================
# Gate: every \usepackage of the preamble must resolve BEFORE latexmk
# starts.  Without this, a missing .sty surfaces as
# "File `x.sty' not found" buried in main.log, and latexmk leaves a
# poisoned .fdb_latexmk behind -- so the NEXT run only says
# "gave an error in previous invocation" instead of the real cause.
# The check prints the exact tlmgr command to paste, then we abort.
tex-deps:
	@$(FIND_TOOL) --check-sty $(PREAMBLE) || { \
		printf "\n$(RED)--> make paper aborted: LaTeX packages missing (see list above).$(RESET)\n"; \
		printf "$(RED)    After installing them, run: make clean && make paper$(RESET)\n"; \
		exit 1; }

# -cd (NOT "cd $(PAPER_DIR) &&"): latexmk chdirs into the directory of
# the .tex file itself, so latex_paper/*.tex reaches the rest of the repo
# as ../latex_templates/... and ../figs_output/... while every aux file
# and the PDF land next to the source instead of cluttering the repo root.
# Doing it inside latexmk also keeps the FIND_TOOL invariant: that path
# is RELATIVE and must be resolved before any chdir happens.
#
# SRC= resolution lives in the recipe (POSIX sh) on purpose: the whole
# block runs in ONE shell, so "$$t" survives from the normalisation to
# the latexmk call, and FIND_TOOL is expanded before any chdir happens.
paper: tex-deps
	@t="$(SRC)"; \
	case "$$t" in *.tex) ;; *) t="$$t.tex" ;; esac; \
	if [ ! -f "$$t" ] && [ -f "$(PAPER_DIR)/$$t" ]; then t="$(PAPER_DIR)/$$t"; fi; \
	if [ ! -f "$$t" ]; then \
		printf "\n$(RED)--> make paper aborted: no such file '$$t'.$(RESET)\n"; \
		printf "$(RED)    Sources available in $(PAPER_DIR)/:$(RESET)\n"; \
		for x in $(PAPER_DIR)/*.tex; do printf "      %s\n" "$$x"; done; \
		exit 1; \
	fi; \
	printf "$(CYAN)--> latexmk: $$t -> $${t%.tex}.pdf$(RESET)\n"; \
	$(FIND_TOOL) $(LATEXMK) -cd -pdf -interaction=nonstopmode -synctex=1 -file-line-error "$$t" \
		|| { printf "\n$(RED)--> Build failed. Re-run with 'make clean' first if the log\n"; \
		     printf "$(RED)    says \"gave an error in previous invocation\".$(RESET)\n"; exit 1; }; \
	printf "$(GREEN)--> PDF: $${t%.tex}.pdf$(RESET)\n"

# Journal-template demos.  Same -cd trick, so every example resolves the
# rest of the repo as ../latex_templates, ../figs_output, ../latex_refs.
# One shell, one loop: FIND_TOOL is a relative path, so the cwd must not
# change between resolving the tool and running it.
examples: tex-deps
	@for f in $(EXAMPLES); do \
		printf "$(CYAN)--> latexmk: $$f$(RESET)\n"; \
		$(FIND_TOOL) $(LATEXMK) -cd -pdf -interaction=nonstopmode -file-line-error $$f || exit 1; \
	done
	@printf "$(GREEN)--> Examples built: $(patsubst %.tex,%.pdf,$(EXAMPLES))$(RESET)\n"

# =============================================================
#  5. Everything
# =============================================================
all: matlab figs paper
	@printf "$(GREEN)============================================$(RESET)\n"
	@printf "$(GREEN)  Done: MATLAB -> Typst -> LaTeX$(RESET)\n"
	@printf "$(GREEN)============================================$(RESET)\n"

# =============================================================
#  6. Cleaning
# =============================================================
# Why not "latexmk -c": by design -c KEEPS the .bbl (for journals that
# want it shipped with the source).  Here .bbl is a rebuildable artefact
# like any other, and a leftover .bbl is the classic reason a changed
# .bib does not show up.  So we delete by extension instead -- the list
# below is the full set latexmk/pdflatex/biber/BibTeX/REVTeX can emit.
AUX_EXTS = aux log bbl blg bcf out toc lof lot fls fdb_latexmk nav snm vrb
AUX_EXTRA = run.xml synctex.gz

clean:
	@printf "$(YELLOW)--> Removing LaTeX aux files (keeping .tex and .pdf)...$(RESET)\n"
	@for e in $(AUX_EXTS) $(AUX_EXTRA); do rm -f $(PAPER_DIR)/*."$$e"; done
	@for e in $(AUX_EXTS) $(AUX_EXTRA); do rm -f *."$$e"; done
	@rm -f $(PAPER_DIR)/*Notes.bib
	@printf "$(GREEN)--> Clean. $(PAPER_DIR)/ now holds only sources + PDFs.$(RESET)\n"

distclean: clean
	@printf "$(YELLOW)--> Removing generated figures and PDFs...$(RESET)\n"
	@rm -f $(FIG_OUT_DIR)/*.pdf
	@rm -f $(MATLAB_SVG_DIR)/*.svg
	@rm -f $(MAIN_PDF) $(patsubst %.tex,%.pdf,$(EXAMPLES))
	@printf "$(GREEN)--> Dist clean done.$(RESET)\n"
