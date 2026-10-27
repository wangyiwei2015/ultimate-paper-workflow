#!/usr/bin/env bash
# =============================================================
#  Ultimate Paper Workflow - macOS environment bootstrap
#  Toolchain: MacTeX / TeX Live (pdflatex, latexmk, biber), Typst,
#             GNU make, Git (Xcode CLT), VS Code + extensions,
#             MATLAB (manual)
#
#  Usage:  bash setup/macos.sh
#          LATEX=texlive bash setup/macos.sh     # lighter, no GUI apps
#  After:  open a new Terminal, then run:  make check-env
# =============================================================
set -uo pipefail

LATEX="${LATEX:-mactex-no-gui}"      # mactex-no-gui | texlive
EXTENSIONS=(
    "ms-vscode.makefile-tools"       # Makefile Tools (Microsoft, official)
    "myriad-dreamin.tinymist"        # Tinymist Typst (Typst language server)
    "james-yu.latex-workshop"        # LaTeX Workshop
    "MathWorks.language-matlab"      # MATLAB (MathWorks, official)
)

C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
C_RED=$'\033[31m';  C_OFF=$'\033[0m'

info() { printf "${C_CYAN}%s${C_OFF}\n" "$*"; }
ok()   { printf "  [${C_GREEN}OK${C_OFF}]      %s\n" "$*"; }
warn() { printf "  [${C_YELLOW}WARN${C_OFF}]    %s\n" "$*"; }
miss() { printf "  [${C_RED}MISSING${C_OFF}]  %s\n" "$*"; }

[[ "$(uname -s)" == "Darwin" ]] || { echo "This script is for macOS only."; exit 1; }

printf "\n"
printf "============================================================\n"
printf " Ultimate Paper Workflow  /  macOS setup\n"
printf " LaTeX distribution : %s\n" "${LATEX}"
printf "============================================================\n\n"

# -------------------------------------------------------------
# 0. Homebrew
# -------------------------------------------------------------
info "--- Homebrew --------------------------------------------"
if command -v brew >/dev/null 2>&1; then
    ok "brew $(brew --version | head -1)"
else
    warn "brew not found, installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
fi
command -v brew >/dev/null 2>&1 || { miss "brew - install from https://brew.sh then re-run"; exit 1; }

# -------------------------------------------------------------
# 1. Core CLI tools
# -------------------------------------------------------------
info "--- Core toolchain --------------------------------------"

install_formula() {           # <bin> <formula> <label>
    if command -v "$1" >/dev/null 2>&1; then
        ok "$3 already installed"
    else
        printf "  [INSTALL] %s  (brew install %s)\n" "$3" "$2"
        brew install "$2" || warn "$2 install failed, do it manually"
    fi
}

# "Is VS Code usable?" -- deliberately independent of the installer:
# /Applications/*.app can come from a manual .dmg/.zip download, not
# from brew, and a per-user install lands in ~/Applications instead.
vscode_present() {
    command -v code >/dev/null 2>&1 && return 0
    [ -x "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" ] && return 0
    [ -d "/Applications/Visual Studio Code.app" ] && return 0
    [ -d "$HOME/Applications/Visual Studio Code.app" ] && return 0
    return 1
}

install_cask() {              # <probe-func> <cask> <label>
    if "$1"; then
        ok "$3 present (any install method, not necessarily brew)"
        return 0
    fi
    printf "  [INSTALL] %s  (brew install --cask %s)\n" "$3" "$2"
    brew install --cask "$2" || warn "$2 install failed, do it manually"
}

install_formula typst  typst                 "Typst"
install_formula gmake  make                  "GNU make (gmake)"
install_cask vscode_present visual-studio-code "VS Code"

# Git ------------------------------------------------------------
# macOS ships a git shim, but it only works once the Xcode Command
# Line Tools are installed; without them `git` prints an install
# dialog instead of running.  Probe the real binary, not the shim.
git_present() {
    command -v git >/dev/null 2>&1 || return 1
    git --version >/dev/null 2>&1 || return 1
    return 0
}
if git_present; then
    ok "git $(git --version | head -1 | awk '{print $3}')"
else
    printf "  [INSTALL] Xcode Command Line Tools (provides git)\n"
    xcode-select --install 2>/dev/null || warn "run 'xcode-select --install' manually"
fi

# LaTeX distribution --------------------------------------------
# Probe the actual binaries, so an existing MacTeX (installer, brew
# texlive, or manual) is recognised whatever its origin.
if command -v pdflatex >/dev/null 2>&1 && command -v latexmk >/dev/null 2>&1; then
    ok "LaTeX already on PATH: $(command -v pdflatex)"
else
    printf "  [INSTALL] LaTeX distribution: %s  (large download, several GB)\n" "${LATEX}"
    if [[ "${LATEX}" == "texlive" ]]; then
        brew install texlive || warn "texlive install failed"
    else
        brew install --cask mactex-no-gui || warn "mactex-no-gui install failed"
    fi
    # MacTeX installs into /Library/TeX/texbin (not linked into /usr/local/bin)
    if [[ -d /Library/TeX/texbin ]]; then
        case ":${PATH}:" in
            *:/Library/TeX/texbin:*) ok "/Library/TeX/texbin already on PATH" ;;
            *) warn "add to ~/.zprofile:  export PATH=\"/Library/TeX/texbin:\$PATH\""
               grep -q 'Library/TeX/texbin' "$HOME/.zprofile" 2>/dev/null \
                 || echo 'export PATH="/Library/TeX/texbin:$PATH"' >> "$HOME/.zprofile"
               export PATH="/Library/TeX/texbin:$PATH"
               warn "appended to ~/.zprofile; open a NEW terminal to apply" ;;
        esac
    fi
fi

# -------------------------------------------------------------
# 2. VS Code extensions
#    macOS runs everything in user scope: brew installs into the
#    user's Homebrew prefix and "code --install-extension" writes
#    to ~/.vscode/extensions, so no elevation is involved here.
# -------------------------------------------------------------
info "--- VS Code extensions ----------------------------------"
vscode_cli() {
    if command -v code >/dev/null 2>&1; then
        command -v code
        return 0
    fi
    local c
    for c in "/Applications/Visual Studio Code.app" "$HOME/Applications/Visual Studio Code.app"; do
        if [ -x "$c/Contents/Resources/app/bin/code" ]; then
            echo "$c/Contents/Resources/app/bin/code"
            return 0
        fi
    done
    return 1
}

CODE_BIN="$(vscode_cli || true)"

if [[ -z "${CODE_BIN}" ]]; then
    warn "VS Code CLI not found - install extensions manually (IDs in agent.md)"
else
    for ext in "${EXTENSIONS[@]}"; do
        printf "  [EXT]     %s\n" "${ext}"
        # output is NOT redirected, so the install status is visible
        "${CODE_BIN}" --install-extension "${ext}" --force || warn "failed: ${ext}"
    done
fi

# -------------------------------------------------------------
# 3. Verification
# -------------------------------------------------------------
info "--- Verification ----------------------------------------"
check() {                     # <bin> <label>
    if command -v "$1" >/dev/null 2>&1; then ok "$2 -> $(command -v "$1")"
    else miss "$2"; fi
}
check typst    "typst"
check latexmk  "latexmk"
check pdflatex "pdflatex"
check biber    "biber   (biblatex backend)"
check bibtex   "bibtex  (classic backend)"
check make     "make    (system, BSD make is fine here)"
check gmake    "gmake   (GNU make from brew)"
check git      "git     (Xcode Command Line Tools)"
printf "             note: the Makefile avoids GNU-only features,\n"
printf "             so the BSD make shipped with macOS works as well.\n"

info "--- MATLAB ---------------------------------------------"
if command -v matlab >/dev/null 2>&1; then
    ok "matlab -> $(command -v matlab)"
else
    warn "MATLAB cannot be installed by a script (license required)."
    printf "            1. Install MATLAB R2020a+ (R2023b+ recommended for SVG export).\n"
    printf "            2. sudo ln -sf /Applications/MATLAB_R2025b.app/bin/matlab /usr/local/bin/matlab\n"
    printf "            3. Verify:  matlab -batch \"disp(version)\"\n"
    printf "            Without MATLAB, keep SVGs in matlab/svg_out/ and run \"make figs paper\".\n"
fi

printf "\n============================================================\n"
printf " Setup finished. Open a NEW terminal and run:\n\n"
printf "     make check-env\n"
printf "     make all\n"
printf "============================================================\n\n"
