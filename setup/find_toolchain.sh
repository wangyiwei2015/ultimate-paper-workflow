#!/bin/sh
# =============================================================
#  setup/find_toolchain.sh -- put the paper toolchain on PATH
#
#  Why this exists
#  ---------------
#  Windows installers (TeX Live, MiKTeX, winget, chocolatey) only
#  extend PATH for NEW processes -- the terminal that ran the
#  installer keeps its old environment block -- and the winget /
#  choco shims frequently never land on PATH at all.  A tool that
#  IS installed therefore still answers "command not found".
#
#  Every make recipe runs in a fresh sh process, so the lookup has
#  to be repeated on every single invocation.  That is why the
#  Makefile calls this script instead of patching PATH once.
#
#  Search order, per tool:
#     1. PATH                           -> already usable, nothing to do
#     2. known install folders on disk  -> prepended to PATH
#     3. neither                        -> FATAL, exit 1
#
#  Usage
#  -----
#    sh setup/find_toolchain.sh <cmd> [args...]    resolve, then exec <cmd>
#    sh setup/find_toolchain.sh --check <tool>...  report; exit 1 if any missing
#    sh setup/find_toolchain.sh --check-sty <preamble.tex>
#                                                  every \usepackage resolves?
#                                                  exit 1 if any is missing
#
#  On macOS / Linux none of the Windows folders exist, so this
#  degenerates to a plain PATH check plus exec.
# =============================================================

# -------------------------------------------------------------
#  _try <dir> -- prepend <dir> to PATH when it holds $_tool
# -------------------------------------------------------------
_try() {
    [ -n "${1:-}" ] || return 1
    [ -d "$1" ] || return 1
    if [ -x "$1/$_tool" ] || [ -x "$1/$_tool.exe" ]; then
        PATH="$1:$PATH"
        export PATH
        printf '  [fix] %-8s not on PATH -> using %s\n' "$_tool" "$1" >&2
        return 0
    fi
    return 1
}

# -------------------------------------------------------------
#  resolve <tool> -- make <tool> reachable.  0 = ok, 1 = nowhere
#  Runs in the CURRENT shell (no pipe into a while loop), so the
#  PATH change survives for the command that is exec'd later.
# -------------------------------------------------------------
resolve() {
    _tool=$1
    command -v "$_tool" >/dev/null 2>&1 && return 0

    # (a) glob patterns.  "$HOME" is quoted so a space inside it is
    #     safe, while the trailing * stays unquoted and still expands.
    for d in /c/texlive/*/bin/windows \
             /c/texlive/*/bin/win32 \
             "$HOME"/AppData/Local/Microsoft/WinGet/Packages/Typst.Typst_*; do
        _try "$d" && return 0
    done

    # (b) fixed paths that contain spaces -- quoted, one word each
    for d in "/c/Program Files/MiKTeX/miktex/bin/x64" \
             "/c/Program Files/MiKTeX 2.9/miktex/bin/x64" \
             "/c/Program Files (x86)/GnuWin32/bin" \
             "/c/ProgramData/chocolatey/bin" \
             "/c/Program Files/Git/bin" \
             "/c/Program Files/Git/usr/bin" \
             "/c/Program Files (x86)/Git/bin" \
             "/c/Program Files (x86)/Git/usr/bin" \
             "$HOME/AppData/Local/Microsoft/WinGet/Links" \
             "$HOME/AppData/Local/Programs/Git/bin" \
             "$HOME/AppData/Local/Programs/Git/usr/bin"; do
        _try "$d" && return 0
    done

    return 1
}

# -------------------------------------------------------------
#  hint_for <tool> -- what the user should do about a FATAL
# -------------------------------------------------------------
hint_for() {
    case "$1" in
        matlab)
            printf '       MATLAB is licence-gated: install it manually, then add\n'
            printf '       <matlabroot>\\bin to PATH.\n'
            ;;
        *)
            printf '       Run setup\\windows.ps1 (Windows) or setup/macos.sh (macOS),\n'
            printf '       then open a NEW terminal so the updated PATH takes effect.\n'
            ;;
    esac
}

# =============================================================
#  mode 1 : --check <tool>...
# =============================================================
if [ "${1:-}" = "--check" ]; then
    shift
    if [ $# -eq 0 ]; then
        printf 'usage: find_toolchain.sh --check <tool>...\n' >&2
        exit 2
    fi
    bad=0
    for t in "$@"; do
        if resolve "$t"; then
            printf '  [OK]      %-9s %s\n' "$t" "$(command -v "$t")"
        else
            printf '  [FATAL]   %-9s not on PATH and not in any known install folder\n' "$t"
            hint_for "$t"
            bad=1
        fi
    done
    if [ "$bad" -ne 0 ]; then
        printf '\n       Fix the items above, then run "make check-env" again.\n'
    fi
    exit "$bad"
fi

# =============================================================
#  mode 1b : --check-sty <preamble.tex>
#
#  Verify that every \usepackage in the preamble resolves on disk.
#  The names are DERIVED from the preamble, so this check can never
#  drift: add a \usepackage there and it is verified here too.
#
#  This is the failure "make paper" would otherwise hit one page
#  into the build: TeX Live scheme-basic ships pdflatex but NOT
#  setspace / mathtools / float / multirow / cleveref.
# =============================================================
if [ "${1:-}" = "--check-sty" ]; then
    preamble=${2:-}
    if [ -z "$preamble" ] || [ ! -f "$preamble" ]; then
        printf 'usage: find_toolchain.sh --check-sty <preamble.tex>\n' >&2
        exit 2
    fi
    if ! resolve kpsewhich; then
        printf '  [skip]    kpsewhich not found - LaTeX packages not verified\n'
        exit 0
    fi
    # strip comments first, then join the lines into one: \usepackage may
    # wrap across lines (the biblatex block in the preamble does), and a
    # line-based grep would silently miss it.
    names=$(sed 's/%.*//' "$preamble" | tr -d '\n' \
        | grep -oE '\\usepackage(\[[^]]*\])?\{[^}]*\}' \
        | sed -e 's/^[^{]*{//' -e 's/}.*//' \
        | tr ',' '\n' | tr -d ' \t' | grep -v '^$' | sort -u)
    if [ -z "$names" ]; then
        printf '  [skip]    no \\usepackage found in %s\n' "$preamble"
        exit 0
    fi
    bad=0
    missing=""
    for n in $names; do
        if ! kpsewhich "$n.sty" >/dev/null 2>&1; then
            printf '  [FATAL]   %s.sty not found - install it with tlmgr\n' "$n"
            missing="${missing}${missing:+ }$n"
            bad=1
        fi
    done
    if [ "$bad" -ne 0 ]; then
        # Print the exact command with the missing names filled in, so the
        # user never has to translate ".sty not found" into package names
        # by hand.  Two variants: system-wide (root) and usermode (no root,
        # needed on macOS BasicTeX where /usr/local/texlive is root-owned).
        printf '\n       Fix (pick the one that matches your TeX install):\n'
        printf '         sudo tlmgr install %s\n' "$missing"
        printf '         tlmgr init-usertree && tlmgr --usermode install %s\n' "$missing"
        printf '\n       sys = system tree (needs root); usermode = ~/Library/texmf on macOS\n'
        printf '       (.sty name != package name for a few: amssymb->amsfonts,\n'
        printf '        graphicx->graphics, lm->lmodern; see agent.md section 4.3)\n'
    else
        printf '  [OK]      %s LaTeX packages from %s resolve\n' \
               "$(printf '%s\n' $names | wc -l | tr -d ' ')" "$preamble"
    fi
    exit "$bad"
fi

# =============================================================
#  mode 2 : resolve, then exec
# =============================================================
cmd=${1:-}
if [ -z "$cmd" ]; then
    printf 'usage: find_toolchain.sh <cmd> [args...]  |  --check <tool>...\n' >&2
    exit 2
fi
shift

# latexmk cannot work without a TeX engine behind it.
required=$cmd
if [ "$cmd" = "latexmk" ]; then
    required="latexmk pdflatex"
fi

for t in $required; do
    if ! resolve "$t"; then
        printf 'FATAL: %s not found on PATH and not in any known install folder.\n' "$t" >&2
        hint_for "$t" >&2
        exit 1
    fi
done

exec "$cmd" "$@"
