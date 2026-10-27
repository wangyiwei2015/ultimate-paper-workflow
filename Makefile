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
MAIN_TEX        := main.tex
MAIN_PDF        := main.pdf
PREAMBLE        := $(TMPL_DIR)/preamble.tex

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

.PHONY: help check-env matlab figs sync paper all clean distclean dirs

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
	@printf "  $(GREEN)make paper$(RESET)      - latexmk -> $(MAIN_PDF)\n"
	@printf "  $(GREEN)make all$(RESET)        - matlab -> figs -> paper\n"
	@printf "  $(GREEN)make clean$(RESET)      - remove LaTeX aux files (keeps PDFs)\n"
	@printf "  $(GREEN)make distclean$(RESET)  - remove aux files + all generated figures\n"
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
	@for d in $(MATLAB_DIR) $(MATLAB_SVG_DIR) $(TYP_SRC_DIR) $(FIG_OUT_DIR) $(FONTS_DIR) $(REF_DIR) $(TMPL_DIR); do \
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
paper:
	@printf "$(CYAN)--> latexmk: $(MAIN_TEX) -> $(MAIN_PDF)$(RESET)\n"
	@$(FIND_TOOL) $(LATEXMK) -pdf -interaction=nonstopmode -synctex=1 -file-line-error $(MAIN_TEX)
	@printf "$(GREEN)--> Paper built: $(MAIN_PDF)$(RESET)\n"

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
clean:
	@printf "$(YELLOW)--> Removing LaTeX aux files...$(RESET)\n"
	@$(FIND_TOOL) $(LATEXMK) -c $(MAIN_TEX) 2>/dev/null || true
	@rm -f *.synctex.gz *.bcf *.run.xml *.fls *.fdb_latexmk
	@printf "$(GREEN)--> Clean (PDFs kept).$(RESET)\n"

distclean: clean
	@printf "$(YELLOW)--> Removing generated figures...$(RESET)\n"
	@rm -f $(FIG_OUT_DIR)/*.pdf
	@rm -f $(MATLAB_SVG_DIR)/*.svg
	@rm -f $(MAIN_PDF)
	@printf "$(GREEN)--> Dist clean done.$(RESET)\n"
