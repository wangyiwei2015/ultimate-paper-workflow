#Requires -Version 5.1
<#
.SYNOPSIS
    Ultimate Paper Workflow - Windows environment bootstrap.

.DESCRIPTION
    Two-phase design:

      Phase 1  (no elevation)   detect every tool, print what is missing,
                                then wait for a key press.
      Phase 2  (elevated)       a NEW Administrator console installs the
                                DEPENDENCIES only, because winget and choco
                                both need admin rights.
      Extensions                installed by THIS, non-elevated process,
                                because VS Code extensions are per-user: an
                                admin token would put them in the admin
                                profile where they can never be updated.

    "Is it installed?" is decided by BINARY PROBING (Get-Command plus a
    look at the usual install folders), never by the winget/choco database:
    a manually installed VS Code must be recognised too.

.PARAMETER LatexId
    winget id of the LaTeX distribution.  Default: TeXLive.TeXLive.
    Pass MiKTeX.MiKTeX to use MiKTeX instead.

.PARAMETER Install
    Internal: the elevated dependency pass.  Only useful by hand if you
    are already in an Administrator console.

.PARAMETER Extensions
    Install the VS Code extensions only, from a normal (non-elevated) shell.

.PARAMETER ParentPid
    Internal: pid of the non-elevated launcher.  When > 0 this elevated
    window does not pause before exiting, because the launcher waits for it.

.EXAMPLE
    setup\windows.ps1
    setup\windows.ps1 MiKTeX.MiKTeX
    setup\windows.ps1 -Extensions
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$LatexId = 'TeXLive.TeXLive',

    [switch]$Install,
    [switch]$Extensions,
    [int]$ParentPid = 0
)

# Deliberately NOT 'Stop': native installers write progress to stderr, and
# with ErrorActionPreference='Stop' PowerShell 5.1 turns that into a
# terminating NativeCommandError.  Exit codes are checked explicitly instead.
$ErrorActionPreference = 'Continue'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SelfPath  = $MyInvocation.MyCommand.Path

# ---- well-known folders, bound to plain variables ----------------------
# "$Pf86\Git\cmd" is safe, while "$env:ProgramFiles(x86)\Git\cmd" inside a
# double-quoted string parses as $env:ProgramFiles followed by the literal
# text "(x86)" and yields "C:\Program Files(x86)" -- a path that never exists.
$Pf     = $env:ProgramFiles
$Pf86   = ${env:ProgramFiles(x86)}
$Lad    = $env:LOCALAPPDATA
$SysDrv = $env:SystemDrive

# Repo root, so every later path is absolute and the script never depends
# on the caller's working directory.
$RepoRoot = Split-Path -Parent $ScriptDir
$Preamble = Join-Path $RepoRoot 'latex_templates\preamble.tex'

# ---- LaTeX packages this pipeline needs --------------------------------
# The winget package "TeXLive.TeXLive" installs scheme-basic: pdflatex is
# there, but latexmk / biber / biblatex / graphicx are NOT, and "make paper"
# dies on the first \includegraphics.  tlmgr ships its own perl, so no
# system perl is required.
# The list mirrors latex_templates/preamble.tex exactly -- when a \usepackage
# is added there, add its package here too.  textcomp.sty is the exception:
# it ships inside the LaTeX kernel (tex/latex/base), so it needs no entry.
$TexPackages = @(
    'latexmk', 'biber'                      # build driver + biblatex backend
    'biblatex', 'logreq'                    # bibliography
    'geometry', 'lm'                        # page layout + lmodern fonts
    'graphicx', 'xcolor', 'caption'         # figures
    'subcaption', 'float'
    'microtype', 'setspace'                 # typography
    'amsmath', 'amssymb', 'mathtools'       # math
    'siunitx'                               # \SI{30}{\percent}
    'booktabs', 'multirow', 'tabularx'      # tables
    'enumitem', 'cleveref', 'hyperref'
) -join ' '

$VSCodeExtensions = @(
    @{ Id = 'ms-vscode.makefile-tools'; Label = 'Makefile Tools - Microsoft official' }
    @{ Id = 'myriad-dreamin.tinymist';  Label = 'Tinymist Typst - Typst language server' }
    @{ Id = 'james-yu.latex-workshop';  Label = 'LaTeX Workshop' }
    @{ Id = 'MathWorks.language-matlab'; Label = 'MATLAB - MathWorks official' }
)

$script:PkgMgr    = $null
$script:NotOnPath = New-Object System.Collections.ArrayList

# =====================================================================
#  Output helpers
# =====================================================================
function Write-Info      { param([string]$m) Write-Host $m -ForegroundColor Cyan }
function Write-Ok        { param([string]$m) Write-Host "  [OK]        $m" -ForegroundColor Green }
function Write-ToInstall { param([string]$m) Write-Host "  [TO INSTALL] $m" -ForegroundColor Yellow }
function Write-Warn      { param([string]$m) Write-Host "  [WARN]      $m" -ForegroundColor Yellow }
function Write-Fatal     { param([string]$m) Write-Host "  [FATAL]     $m" -ForegroundColor Red }
function Write-Skip      { param([string]$m) Write-Host "  [SKIP]      $m" -ForegroundColor DarkGray }

function Wait-AnyKey {
    param([string]$Message = 'Press any key to continue . . .')
    if ([Console]::IsInputRedirected) { return }
    Write-Host $Message -ForegroundColor Yellow
    try {
        [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    }
    catch {
        # No RawUI (e.g. the VS Code terminal in some hosts): fall back to Enter.
        [void][Console]::ReadLine()
    }
}

# =====================================================================
#  Locators -- answer "is it installed?", looking on PATH *and* on disk,
#  because a freshly installed tool is invisible to THIS process: the
#  PATH change made by the installer only reaches new processes.
#  On success with the tool OFF PATH, Dir holds its bin folder.
# =====================================================================
function Find-Tool {
    param(
        [Parameter(Mandatory)][string]$Command,
        [string[]]$Dirs = @()
    )
    if (Get-Command -Name $Command -ErrorAction SilentlyContinue) {
        return [pscustomobject]@{ Present = $true; Dir = $null; Source = 'PATH' }
    }
    foreach ($d in $Dirs) {
        if (-not $d) { continue }
        foreach ($name in @("$Command.exe", $Command)) {
            if (Test-Path -LiteralPath (Join-Path $d $name)) {
                return [pscustomobject]@{ Present = $true; Dir = $d; Source = 'disk' }
            }
        }
    }
    return [pscustomobject]@{ Present = $false; Dir = $null; Source = $null }
}

function Get-TexLiveBinDirs {
    # <root>\texlive\<year>\bin\{windows,win32}\latexmk.exe
    # Only names that look like a year: C:\texlive also holds texmf-local,
    # which sorts AFTER "2026" descending and would otherwise win.
    $dirs = @()
    $roots = @("$Pf\texlive", "$SysDrv\texlive", "$Pf86\texlive") |
             Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    foreach ($root in $roots) {
        $years = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -match '^\d{4}$' } |
                 Sort-Object -Property Name -Descending
        foreach ($y in $years) {
            foreach ($sub in @('bin\windows', 'bin\win32')) {
                $dirs += (Join-Path $y.FullName $sub)
            }
        }
    }
    return $dirs
}

function Get-LatexBinDirs {
    # Built with @() + '+=' on purpose: a function that RETURNS an ArrayList
    # has it unrolled by the pipeline, so the caller receives a fixed-size
    # Object[] and .Add() would throw "collection size is fixed".
    $dirs = @(Get-TexLiveBinDirs)
    # MiKTeX: <root>\miktex\bin\x64\latexmk.exe
    foreach ($m in @("$Pf\MiKTeX\miktex\bin\x64",
                     "$Pf\MiKTeX 2.9\miktex\bin\x64",
                     "$Lad\Programs\MiKTeX\miktex\bin\x64")) {
        if ($m) { $dirs += $m }
    }
    return $dirs
}

function Get-TypstDirs {
    # winget Links shim, then the per-version package folder
    $dirs = @("$Lad\Microsoft\WinGet\Links")
    $pkgRoot = "$Lad\Microsoft\WinGet\Packages"
    if (Test-Path -LiteralPath $pkgRoot) {
        $dirs += Get-ChildItem -LiteralPath $pkgRoot -Directory -Filter 'Typst.Typst_*' -ErrorAction SilentlyContinue |
                 ForEach-Object { $_.FullName }
    }
    return $dirs
}

function Get-PackageManager {
    # winget first, choco as the fallback; $null when neither exists.
    if (Get-Command -Name winget -ErrorAction SilentlyContinue) { return 'winget' }
    if (Get-Command -Name choco  -ErrorAction SilentlyContinue) { return 'choco'  }
    return $null
}

# =====================================================================
#  Package table -- single source of truth for ids and probes
# =====================================================================
function Get-Packages {
    @(
        [pscustomobject]@{
            Key = 'vscode'; Label = 'VS Code'
            Id = 'Microsoft.VisualStudioCode'; Choco = 'visualstudiocode'
            Cmd = 'code'
            Dirs = @("$Lad\Programs\Microsoft VS Code",
                     "$Pf\Microsoft VS Code",
                     "$Pf86\Microsoft VS Code") | Where-Object { $_ }
        }
        [pscustomobject]@{
            Key = 'git'; Label = 'Git for Windows'
            Id = 'Git.Git'; Choco = 'git'
            Cmd = 'git'
            Dirs = @("$Pf\Git\cmd", "$Pf86\Git\cmd",
                     "$Lad\Programs\Git\cmd", "$SysDrv\Git\cmd") | Where-Object { $_ }
        }
        [pscustomobject]@{
            Key = 'latex'; Label = 'LaTeX distribution'
            Id = $LatexId
            Choco = $(if ($LatexId -eq 'MiKTeX.MiKTeX') { 'miktex' } else { 'texlive' })
            Cmd = 'latexmk'
            Dirs = (Get-LatexBinDirs)
        }
        [pscustomobject]@{
            Key = 'typst'; Label = 'Typst'
            Id = 'Typst.Typst'; Choco = 'typst'
            Cmd = 'typst'
            Dirs = (Get-TypstDirs)
        }
        [pscustomobject]@{
            Key = 'make'; Label = 'GNU make'
            Id = 'GnuWin32.Make'; Choco = 'make'
            Cmd = 'make'
            Dirs = @("$Pf86\GnuWin32\bin", "$Pf\GnuWin32\bin",
                     "$env:ProgramData\chocolatey\bin",
                     "$SysDrv\ProgramData\chocolatey\bin") | Where-Object { $_ }
        }
    )
}

# =====================================================================
#  Phase 1 : detection
# =====================================================================
function Get-Detection {
    Get-Packages | ForEach-Object {
        $r = Find-Tool -Command $_.Cmd -Dirs $_.Dirs
        $_ | Add-Member -NotePropertyName Present  -NotePropertyValue $r.Present -Force
        $_ | Add-Member -NotePropertyName FoundDir -NotePropertyValue $r.Dir    -Force
        $_
    }
}

function Show-Detection {
    param($Detected)
    Write-Info '--- Detection (nothing is installed yet) ---'
    foreach ($p in $Detected) {
        if (-not $p.Present) {
            Write-ToInstall $p.Label
            continue
        }
        if ($p.FoundDir) {
            Write-Ok "$($p.Label)  (at $($p.FoundDir))"
            Write-Host '           installed, but NOT on PATH of this shell.'
            Add-NotOnPath $p.FoundDir
            $env:Path = "$($p.FoundDir);$env:Path"
        }
        else {
            Write-Ok $p.Label
        }
    }
    # Deliberately returns nothing: a function that returns a collection has
    # it unrolled by the pipeline, so the caller would receive a scalar (or
    # $null when empty) and .Count would be unreliable.  The caller derives
    # the missing list itself with @(...), which is always a real array.
}

function Add-NotOnPath {
    param([string]$Dir)
    if ($Dir -and -not $script:NotOnPath.Contains($Dir)) {
        [void]$script:NotOnPath.Add($Dir)
    }
}

# =====================================================================
#  Phase 2 : install the dependencies (elevated)
# =====================================================================
function Install-Package {
    param($Pkg)

    $r = Find-Tool -Command $Pkg.Cmd -Dirs $Pkg.Dirs
    if ($r.Present) {
        if ($r.Dir) {
            Write-Skip "$($Pkg.Label) already present at $($r.Dir)"
            Write-Host '             (not on PATH - add it, or open a new terminal)'
            Add-NotOnPath $r.Dir
            $env:Path = "$($r.Dir);$env:Path"
        }
        else {
            Write-Skip "$($Pkg.Label) is already present"
        }
        return
    }

    if (-not $script:PkgMgr) {
        Write-Fatal "no package manager available for $($Pkg.Label)."
        Write-Host '             Install "App Installer" (winget) from the Microsoft'
        Write-Host '             Store, or Chocolatey, then re-run this script.'
        return
    }

    if ($script:PkgMgr -eq 'winget') {
        & winget list --id $Pkg.Id -e 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Skip "$($Pkg.Label) ($($Pkg.Id)) already recorded by winget"
            return
        }
        Write-Host "  [INSTALL]   $($Pkg.Label)  (winget: $($Pkg.Id)) ..." -ForegroundColor Cyan
        & winget install -e --id $Pkg.Id --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "$($Pkg.Id) failed. Install it manually:  winget install -e --id $($Pkg.Id)"
        }
        return
    }

    # choco fallback.  -lo = local only (choco 1.x); choco 2.x is local by
    # default and simply fails the flag, which is a safe false negative.
    & choco list -e $Pkg.Choco --limit-output -lo 2>$null |
        Select-String -SimpleMatch -Pattern "$($Pkg.Choco)|" | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Skip "$($Pkg.Label) ($($Pkg.Choco)) already recorded by choco"
        return
    }
    Write-Host "  [INSTALL]   $($Pkg.Label)  (choco: $($Pkg.Choco)) ..." -ForegroundColor Cyan
    & choco install -y $Pkg.Choco
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "$($Pkg.Choco) failed. Check admin rights, then run manually:  choco install -y $($Pkg.Choco)"
    }
}

function Install-Dependencies {
    Write-Host ''
    Write-Info '--- Dependencies ---'
    foreach ($p in (Get-Packages)) { Install-Package $p }
}

# =====================================================================
#  tlmgr repair -- add the packages scheme-basic is missing
# =====================================================================
function Get-TexLiveRoot {
    $roots = @("$Pf\texlive", "$SysDrv\texlive", "$Pf86\texlive") |
             Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    foreach ($root in $roots) {
        $years = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -match '^\d{4}$' } |
                 Sort-Object -Property Name -Descending
        foreach ($y in $years) {
            if (Test-Path -LiteralPath (Join-Path $y.FullName 'bin\windows\tlmgr.bat')) {
                return $y.FullName
            }
        }
    }
    return $null
}

function Repair-TexLive {
    if ($LatexId -eq 'MiKTeX.MiKTeX') {
        Write-Skip 'MiKTeX installs missing packages on demand'
        return
    }
    $tl = Get-TexLiveRoot
    if (-not $tl) {
        Write-Warn 'tlmgr not found - add the LaTeX packages by hand:'
        Write-Host "             tlmgr install $TexPackages"
        return
    }
    Write-Host "  [TLMGR]     $tl is scheme-basic; adding the packages the" -ForegroundColor Cyan
    Write-Host "              pipeline needs: $TexPackages"
    $tlmgr = Join-Path $tl 'bin\windows\tlmgr.bat'
    & $tlmgr install ($TexPackages -split ' ')
    if ($LASTEXITCODE -ne 0) {
        Write-Warn 'tlmgr failed. Run it manually from an Admin prompt:'
        Write-Host "             `"$tlmgr`" install $TexPackages"
        return
    }
    Test-TexPackages -TexRoot $tl
}

# -------------------------------------------------------------
#  Test-TexPackages -- prove every \usepackage in the preamble
#  actually resolves.  tlmgr can exit 0 while the package list
#  was still incomplete, which used to surface much later as
#  "LaTeX Error: File 'setspace.sty' not found" during make paper.
#  The package names are DERIVED from the preamble, so this check
#  can never drift out of sync with what the document loads.
# -------------------------------------------------------------
function Test-TexPackages {
    param([string]$TexRoot)
    if (-not (Test-Path -LiteralPath $Preamble)) {
        Write-Warn "preamble not found at $Preamble - cannot verify LaTeX packages"
        return
    }
    $kps = Join-Path $TexRoot 'bin\windows\kpsewhich.exe'
    if (-not (Test-Path -LiteralPath $kps)) {
        Write-Warn 'kpsewhich not found - cannot verify the LaTeX packages'
        return
    }
    # strip comments first, then join the lines: \usepackage may wrap
    # across several lines, as the biblatex block in the preamble does.
    $text = (Get-Content -LiteralPath $Preamble -Raw) -replace '(?m)%.*$', ''
    $names = [regex]::Matches($text, '\\usepackage(\[[^\]]*\])?\{([^}]*)\}') |
             ForEach-Object { $_.Groups[2].Value -split ',' } |
             ForEach-Object { $_.Trim() } |
             Where-Object { $_ } |
             Sort-Object -Unique
    $missing = @()
    foreach ($n in $names) {
        $hit = & $kps "$n.sty" 2>$null | Select-Object -First 1
        if (-not $hit) { $missing += $n }
    }
    if ($missing.Count -eq 0) {
        Write-Host "  [OK]        all $($names.Count) preamble packages resolve" -ForegroundColor Green
        return
    }
    $tlmgr = Join-Path $TexRoot 'bin\windows\tlmgr.bat'
    Write-Warn "still missing after tlmgr: $($missing -join ' ')"
    Write-Host "             re-run from an Admin prompt:"
    Write-Host "             `"$tlmgr`" install $($missing -join ' ')"
}

# =====================================================================
#  VS Code extensions -- user scope, output deliberately NOT redirected
#  so the install status of each extension stays visible.  --force only
#  suppresses the interactive "reinstall?" prompt, it hides nothing.
# =====================================================================
function Get-VSCodeCli {
    $c = Get-Command -Name code -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    foreach ($p in @("$Lad\Programs\Microsoft VS Code\bin\code.cmd",
                     "$Pf\Microsoft VS Code\bin\code.cmd",
                     "$Pf86\Microsoft VS Code\bin\code.cmd")) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    return $null
}

function Install-Extensions {
    Write-Host ''
    Write-Info '--- VS Code extensions ---'
    $code = Get-VSCodeCli
    if (-not $code) {
        Write-Warn 'VS Code CLI not on PATH - install extensions manually:'
        foreach ($e in $VSCodeExtensions) { Write-Host "             $($e.Id)" }
        return
    }
    foreach ($e in $VSCodeExtensions) {
        Write-Host "  [EXT]     $($e.Label)  ($($e.Id))"
        # 2>$null drops code.cmd's crashpad noise (it goes to stderr) while
        # the real progress messages stay on stdout and remain visible.
        & $code --install-extension $e.Id --force 2>$null
        if ($LASTEXITCODE -ne 0) { Write-Warn "failed: $($e.Id)" }
    }
}

# =====================================================================
#  Elevation
# =====================================================================
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-ElevatedSelf {
    # Quote only the -File argument; every other token is a plain switch or
    # a value without spaces, so a single ArgumentList string is safe here.
    $argString = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -LatexId {1} -Install -ParentPid {2}' -f $SelfPath, $LatexId, $PID
    try {
        return Start-Process -FilePath 'powershell.exe' -ArgumentList $argString `
                    -Verb RunAs -WorkingDirectory $ScriptDir -PassThru -ErrorAction Stop
    }
    catch {
        Write-Warn 'Could not open the elevated window (UAC declined?).'
        Write-Host '             Re-run this script from an Administrator prompt.'
        return $null
    }
}

# =====================================================================
#  PATH refresh -- installers only extend PATH for NEW processes, so the
#  registry has to be re-read once the elevated window is done.
# =====================================================================
function Update-ProcessPath {
    $m = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $u = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = $m
    if ($u) { $env:Path = "$env:Path;$u" }
    foreach ($d in ($script:NotOnPath | Select-Object -Unique)) {
        if ($d -and ($env:Path -notlike "*$d*")) { $env:Path = "$d;$env:Path" }
    }
}

# =====================================================================
#  Verification / closing message
# =====================================================================
function Check-Tool {
    param([string]$Label, [string]$Command)
    $c = Get-Command -Name $Command -ErrorAction SilentlyContinue
    if ($c) { Write-Ok "$Label -> $($c.Source)" } else { Write-Fatal $Label }
}

function Show-Verification {
    Write-Host ''
    Write-Info '--- Verification ---'
    Check-Tool 'typst'    'typst'
    Check-Tool 'latexmk'  'latexmk'
    Check-Tool 'pdflatex' 'pdflatex'
    Check-Tool 'make'     'make'
    Check-Tool 'git'      'git'
    Write-Host ''
    Write-Info '--- MATLAB ---'
    if (Get-Command -Name matlab -ErrorAction SilentlyContinue) {
        Write-Ok "matlab -> $((Get-Command matlab).Source)"
    }
    else {
        Write-Warn 'MATLAB cannot be installed by a script (license required).'
        Write-Host '             1. Install MATLAB R2020a+ (R2023b+ recommended for SVG export).'
        Write-Host '             2. Add to PATH:  C:\Program Files\MATLAB\R2025b\bin'
        Write-Host '             3. Verify with:  matlab -batch "disp(version)"'
        Write-Host '             Without MATLAB, keep the SVGs in matlab/svg_out/'
        Write-Host '             and run "make figs paper" only.'
    }
}

function Get-GitBashPath {
    foreach ($p in @("$Pf\Git\git-bash.exe", "$Pf86\Git\git-bash.exe",
                     "$Lad\Programs\Git\git-bash.exe")) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    return $null
}

function Show-Closing {
    Write-Host ''
    Write-Host '  --- PATH notes ------------------------------------------'
    Write-Host '    TeX Live : C:\texlive\2026\bin\windows  (year may differ)'
    Write-Host '    make     : C:\Program Files (x86)\GnuWin32\bin'
    Write-Host '               or  C:\ProgramData\chocolatey\bin'
    Write-Host '    Typst    : added automatically by the package manager'
    Write-Host '    Git      : C:\Program Files\Git\cmd'
    if ($script:NotOnPath.Count -gt 0) {
        Write-Host ''
        Write-Host '  Installed but NOT on PATH of this shell (added for this'
        Write-Host '  session only). Add them to Path permanently, or simply'
        Write-Host '  open a NEW terminal:'
        foreach ($d in ($script:NotOnPath | Select-Object -Unique)) { Write-Host "    $d" }
    }
    Write-Host ''
    Write-Host '  Add any missing folder to Path, then open a NEW terminal.'
    Write-Host '  The Makefile recipes are POSIX sh, so run every target from'
    Write-Host '  Git Bash (NOT from cmd or PowerShell).'
    $gb = Get-GitBashPath
    if ($gb) { Write-Host "  Git Bash : $gb" }
    Write-Host ''
    Write-Host '  ==========================================================='
    Write-Host '   Open a NEW Git Bash terminal and run:'
    Write-Host ''
    Write-Host '       make check-env'
    Write-Host '       make all'
    Write-Host '  ==========================================================='
}

function Show-Banner {
    param([switch]$InstallPass)
    Write-Host ''
    Write-Host '  ============================================================'
    Write-Host '   Ultimate Paper Workflow  /  Windows setup'
    Write-Host "   LaTeX distribution : $LatexId"
    Write-Host '   (pass "MiKTeX.MiKTeX" as an argument to use MiKTeX instead)'
    if ($InstallPass) {
        Write-Host '   Install pass (elevated) -- dependencies only,'
        Write-Host '   extensions are user scope and live in the original window.'
    }
    Write-Host '  ============================================================'
    Write-Host ''
}

# =====================================================================
#  Main
# =====================================================================
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

if ($Extensions) {
    Show-Banner
    Install-Extensions
    exit 0
}

if ($Install) {
    Show-Banner -InstallPass
    Install-Dependencies
    Repair-TexLive
    Show-Closing
    if ($ParentPid -le 0) { Wait-AnyKey }
    exit 0
}

# ---------------- normal run ----------------
Show-Banner
$script:PkgMgr = Get-PackageManager

if ($script:PkgMgr) {
    Write-Host "  Package manager : $($script:PkgMgr)"
    if ($script:PkgMgr -eq 'choco') {
        Write-Host '  NOTE: choco needs an elevated (Administrator) shell.'
    }
}
else {
    Write-Warn 'No winget and no choco found.'
    Write-Host '             Install "App Installer" from the Microsoft Store, or'
    Write-Host '             Chocolatey, then re-run this script.'
}
Write-Host ''

$detected = @(Get-Detection)
$missing  = @($detected | Where-Object { -not $_.Present })
Show-Detection $detected

Write-Host ''
if ($missing.Count -eq 0) {
    Write-Host '  Everything is already installed. Nothing to do.'
    Write-Host '  Skipping the install window.'
    Install-Extensions
    Show-Closing
    exit 0
}

Write-Host "  $($missing.Count) item(s) to install: $(($missing.Label) -join ', ')"
Write-Host ''
Write-Host '  Installation requires administrator rights, so a NEW elevated'
Write-Host '  window will be opened for the install pass.'
Write-Host ''

if (Test-IsAdmin) {
    Write-Host '  This shell is already elevated - installing here.'
    Install-Dependencies
    Repair-TexLive
    Write-Host ''
    Write-Warn 'VS Code extensions: this shell is elevated, and an admin token'
    Write-Host '             would install them into the admin profile (making'
    Write-Host '             them un-updatable).'
    Write-Host '             Re-run this script from a NORMAL terminal to install'
    Write-Host '             the four extensions listed in agent.md.'
    Update-ProcessPath
    Show-Verification
    Show-Closing
    exit 0
}

Write-Host '  This shell is NOT elevated - a new window will be opened.'
Write-Host '  VS Code extensions are installed HERE, in user scope.'
Write-Host ''
Wait-AnyKey

Write-Host ''
Write-Host '  Opening the elevated install window ...'
$child = Start-ElevatedSelf

Write-Host ''
Write-Host '  ============================================================'
Write-Host '   The elevated window now installs the dependencies.'
Write-Host '   VS Code extensions are installed HERE, in user scope.'
Write-Host '  ============================================================'
Write-Host ''

Install-Extensions

if ($child) {
    Write-Host ''
    Write-Host '  Waiting for the elevated install window to finish ...'
    try { $child.WaitForExit() } catch { }
    Update-ProcessPath
}

Show-Verification
Show-Closing
exit 0
