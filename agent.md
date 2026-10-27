# AGENT GUIDE — Ultimate Paper Workflow

> 面向 AI Agent 的项目操作手册。动手改任何文件之前先读完本文件的
> **§2 职责边界** 和 **§8 硬规则**。

---

## 1. 项目定位

一个"图—文分离"的学术流水线：**数据**由 MATLAB 产出，**版式与标注**由 Typst 统一排版，
**正文**由 LaTeX 编译。目标是一套图件字体/线宽/标注风格全域一致、可一键重建的稿件工程。

```
matlab/figN_*.m                    MATLAB：只画数据，导出无标注 SVG
        │  make matlab
        ▼
matlab/svg_out/figN_*.svg          中间产物（不入 LaTeX）
        │  make figs   (figs_src/figN_*.typ 引用它)
        ▼
figs_src/figN_*.typ                Typst：多 panel 组版 + (a)(b) 标签 + 图内标注
        │
        ▼
figs_output/figN_*.pdf             终态图件，LaTeX 直接 \includegraphics
        │  make paper
        ▼
latex_paper/main.tex + ../latex_templates/ + ../latex_refs/refs.bib
        │                                    →  latex_paper/main.pdf
```

**路径约定（改动前必读）**：正文只有一个入口 `latex_paper/main.tex`，
`make paper` 用 `latexmk -cd` 把编译工作目录切到 `latex_paper/`，所以

- 指向仓库其他目录的路径一律带 `../`：`\input{../latex_templates/preamble.tex}`、
  `\addbibresource{../latex_refs/refs.bib}`、`{../figs_output/fig1_overview}`；
- 所有辅助文件与 PDF 都落在 `latex_paper/` 内，**根目录永远干净**；
- 别改成 `cd latex_paper && latexmk`：`FIND_TOOL` 是相对路径，`cd` 之后会解析失败
  （见 §4.1 的 INVARIANT），`-cd` 是 latexmk 内部 chdir，不破坏这个前提。

---

## 2. 三段式的职责边界（最重要）

| 阶段 | 允许 | **禁止** |
|---|---|---|
| **MATLAB** (`matlab/figN_*.m`) | 数据曲线/曲面/散点；坐标轴框；颜色 | 标题 `title`、图例 `legend`、colorbar、`xlabel/ylabel`、任何文字标注、面板字母 (a)(b) |
| **Typst** (`figs_src/figN_*.typ`) | 面板排布、`(a)(b)` 标签、箭头/文字/比例尺等图内标注、字体 | 放数据、改数据、直接编辑 SVG |
| **LaTeX** (`latex_paper/main.tex`) | `\includegraphics` + `\caption` + `\label`、正文、参考文献 | 直接引用 `matlab/svg_out/*.svg`、在图里写标注、用 `subfig` 手工拼图 |

**判据**：图里出现的任何一个字符，都应该能在 `figs_src/*.typ` 里被 `grep` 到；
MATLAB 产出的 SVG 用文本编辑器打开应当**不含任何文本节点**。

---

## 3. 目录结构

| 路径 | 用途 | 是否入库 |
|---|---|---|
| `Makefile` | 唯一构建入口 | ✅ |
| `latex_paper/main.tex` | 稿件主文件（正文只放这里） | ✅ |
| `latex_paper/main.pdf` | 编译产物，与正文同目录（`make clean` 保留） | ❌ 见 `.gitignore` |
| `latex_paper/example_*.tex` | 四个期刊模板的接入示例（IEEEtran / ieeecolor / sn-jnl / revtex4-2），`make examples` 构建 | ✅ |
| `latex_templates/IEEE-T/`<br>`latex_templates/IEEE-LED/`<br>`latex_templates/Nature/`<br>`latex_templates/AIP_Publishing/` | 四套期刊类文件；**只留 `.cls/.sty/.rtx/.bst`**，模板自带的示例图片与示例 `.bib` 已删除（示例 tex 统一引用 `../figs_output/fig1_overview` 与 `../latex_refs/refs.bib`） | ✅ |
| `agent.md` | 本文件 | ✅ |
| `setup/windows.ps1` | Windows 环境安装（PowerShell，自提权，两阶段） | ✅ |
| `setup/macos.sh` | macOS 环境安装（brew） | ✅ |
| `setup/find_toolchain.sh` | **每次 make 调用**：PATH → 磁盘安装目录 → 报错，解析工具链 | ✅ |
| `.gitattributes` | 行尾统一 LF | ✅ |
| `latex_templates/preamble.tex` | 宏包与全局设置 | ✅ |
| `latex_templates/macros.tex` | 自定义宏（`\figref` `\paperfigure` …） | ✅ |
| `latex_templates/section_template.tex` | 新章节骨架（**不参与编译**） | ✅ |
| `latex_refs/refs.bib` | 参考文献库 | ✅ |
| `figs_src/*.typ` | Typst 图源文件 | ✅ |
| `figs_src/_lib.typ` | Typst 公共函数（下划线开头，不单独编译） | ✅ |
| `figs_output/*.pdf` | Typst 产出的终态图 | ✅ |
| `matlab/figN_*.m` | 单个图的 MATLAB 脚本 | ✅ |
| `matlab/build_all_figs.m` | 批量运行所有 `fig*.m` | ✅ |
| `matlab/svg_out/*.svg` | MATLAB 中间产物 | ✅ |
| `fonts/` | Typst/LaTeX 引用的字体（.ttf/.otf） | 空目录，按需添加 |

> 根目录只放**目录**与入口文件（`Makefile` / `agent.md` / `README.md`）。
> LaTeX 的 `.aux/.log/.fls/.bbl/main.pdf` 全部落在 `latex_paper/`，
> 不会污染根目录。

---

## 4. 环境安装

```powershell
# Windows（PowerShell / VS Code 终端均可；脚本会自己弹管理员窗口）
powershell -NoProfile -ExecutionPolicy Bypass -File setup\windows.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File setup\windows.ps1 MiKTeX.MiKTeX   # 改用 MiKTeX

# macOS
bash setup/macos.sh               # 默认 mactex-no-gui
LATEX=texlive bash setup/macos.sh # 轻量版
```

安装内容：**Git for Windows**（不只是 git，还提供 Makefile 依赖的 POSIX `sh`）、
TeX Live / MiKTeX（`pdflatex`、`latexmk`、`biber`）、Typst、GNU make、
VS Code 及以下四个扩展：

| 扩展 ID | 名称 |
|---|---|
| `ms-vscode.makefile-tools` | Makefile Tools（微软官方） |
| `myriad-dreamin.tinymist` | Tinymist Typst（Typst 语言服务器） |
| `james-yu.latex-workshop` | LaTeX Workshop |
| `MathWorks.language-matlab` | MATLAB（MathWorks 官方，勿装第三方同名插件） |

**Windows 两阶段设计**（winget / choco 都需要管理员权限）：

1. **Phase 1 不提权**：二进制探测 VS Code / Git / LaTeX / Typst / GNU make，
   逐项打印 `[OK]` 或 `[TO INSTALL]`，汇总缺失清单，然后等你按任意键。
2. **Phase 2 提权**：`Start-Process -Verb RunAs` 打开**新的管理员窗口**，
   **只装依赖**（winget/choco）。
3. **插件在普通进程装**：VS Code 扩展是 per-user 的，管理员 token 会把它们装进
   admin 配置目录且以后无法被普通 VS Code 更新。所以普通窗口开完管理员窗口后
   **继续在本进程**装插件（非静默，能看到每个插件的安装状态）；
   若当前 shell 已是管理员则 `[SKIP]` 插件并提示去普通终端重跑；
   也可事后单独跑 `setup\windows.ps1 -Extensions` 只装插件。
4. **等管理员窗口结束**（`WaitForExit`），再从注册表重读 PATH
   （`[Environment]::GetEnvironmentVariable('Path','Machine'/'User')`），
   最后才做验证——因为安装器只对**新进程**写 PATH，这样验证结果才是准的。

"是否已安装"由**二进制探测**判定（`Get-Command` 或检查 `Code.exe` 是否存在），
不信任 winget/choco 的已装数据库——手动安装的 VS Code 同样能被正确识别。
winget 找不到时自动降级 choco；两者都没有则 Phase 1 直接报错。

> **已装但不在 PATH**：winget/choco 包甚至完全不写 PATH。所以探测除了 PATH 还会翻常见
> 安装目录（`C:\texlive\<年>\bin\windows`、`%PROGRAMFILES%\MiKTeX\miktex\bin\x64`、
> winget 的 `Links` 目录、`GnuWin32\bin`、`chocolatey\bin`）。
> 命中时报 `[OK] ... (at <目录>) installed, but NOT on PATH of this shell`，
> 并**不会重复安装**；同时把该目录临时加进本进程 PATH，并在结尾汇总
> "Installed but NOT on PATH" 提示你加 Path 或开新终端。

> macOS 全程用户态（brew 装在用户 Homebrew 前缀，`code --install-extension`
> 写 `~/.vscode/extensions`），不存在提权问题，插件同样是可视输出。

MATLAB 需 License，**脚本不会自动安装**；装完后把 `matlab` 加入 PATH
（Windows：`C:\Program Files\MATLAB\R20xx\bin`；macOS：软链到 `/usr/local/bin/matlab`）。

### 4.1 工具链解析：`setup/find_toolchain.sh`（每次 make 都会跑）

因为"PATH 只对新进程生效"这个问题无法靠装完一次解决，**每个 recipe 都会重新解析**。
Makefile 里所有真正调用工具的指令都写成：

```make
$(FIND_TOOL) <工具> <参数>       # 例如：sh setup/find_toolchain.sh typst compile ...
```

解析顺序（每个工具独立判定）：

1. **PATH 上已有** → 什么都不做；
2. **PATH 上没有，但磁盘上有** → 把该目录插到 PATH 最前面，同时打印
   `[fix] <工具> not on PATH -> using <目录>`，然后正常执行；
3. **两者都没有** → **直接 FATAL 退出 1**，并提示去跑 `setup\windows.ps1` /
   `setup/macos.sh`，然后开新终端。

验证与编译两条路都走这套逻辑：

```bash
make check-env     # 对 make sh typst latexmk pdflatex 逐个解析，缺一个就 exit 1
make figs          # typst 解析失败 => 不编译，报 FATAL
make paper         # latexmk + pdflatex 都要能解析到，否则 FATAL
```

> `latexmk` 额外要求 `pdflatex` 也在（它只是个驱动，没有引擎跑不了）。
> `matlab` 是唯一例外：它给的是 License 提示而不是"去跑 setup"。

**安装目录清单只有 `setup/find_toolchain.sh` 一处**（`/c/texlive/*/bin/{windows,win32}`、
MiKTeX、`chocolatey\bin`、`GnuWin32\bin`、winget `Links`、`Typst.Typst_*`、
Git 的 `bin`/`usr\bin`）。**要加目录就改脚本，不要在 Makefile 里另写一份**——
两处清单必然漂移。脚本用 POSIX sh 写（`sh -n` 干净，dash 下实测通过），
不依赖可执行位，所以 git 检出丢权限也不会坏。

### 4.2 Windows 必须在 Git Bash 里跑 make

Makefile 的 `SHELL := sh`，而 cmd / PowerShell **没有 `sh`**——make 会以
`sh: not found` 直接死掉，连 `check-env` 都进不去。所以：

- **每个 target 都要从 Git Bash 启动**（或在 VS Code 终端里选 Git Bash profile）；
- Git for Windows 默认只把 `...\Git\cmd` 加进 PATH，那里有 `git.exe` 但**没有
  `sh.exe`**（在 `...\Git\bin` 和 `...\Git\usr\bin`）。这是故意的：把 Git 的
  `usr\bin` 塞进系统 PATH 会用 MSYS 的 `find`/`sort` 覆盖 Windows 同名命令。
  所以脚本**不会**把这两个目录加进 PATH，只告诉你 Git Bash 在哪。

### 4.3 坑：winget 的 TeXLive 包装的是 scheme-basic

`winget install TeXLive.TeXLive` 装出来是 **scheme-basic**（约 144 个包）：
有 `pdflatex`，但**没有 `latexmk`、没有 `biber`、没有 `biblatex`，连 `graphicx` 都没有**。
`make paper` 会在第一个 `\includegraphics` 就挂。

`windows.ps1` 的安装阶段会自动用 tlmgr 补齐这些包（tlmgr 自带 perl，不需要系统 perl；
MiKTeX 跳过这步，它按需自动装包）：

```
latexmk biber biblatex logreq geometry lm graphicx xcolor caption subcaption float
microtype setspace amsmath amssymb mathtools siunitx booktabs multirow tabularx
enumitem cleveref hyperref
```

装完还会**验证一遍**：从 `latex_templates/preamble.tex` 里解析出所有
`\usepackage`，逐个 `kpsewhich` 对应的 `.sty`。这一步是必需的——`tlmgr install`
可能 exit 0 但清单本身不全，之前就是这样漏掉了 `setspace mathtools float
multirow cleveref` 五个包，直到 `make paper` 才炸。

解析而非硬编码清单，所以**永远不会和 preamble 脱节**：在 preamble 里加一行
`\usepackage{...}`，检查自动跟上。老机器上已装好的 scheme-basic 手动补一次
（管理员 PowerShell）：

```powershell
"C:\texlive\2026\bin\windows\tlmgr.bat" install latexmk biber biblatex logreq geometry lm graphicx xcolor caption subcaption float microtype setspace amsmath amssymb mathtools siunitx booktabs multirow tabularx enumitem cleveref hyperref
```

或者直接让 `make check-env` 告诉你缺什么（它内部走
`sh setup/find_toolchain.sh --check-sty latex_templates/preamble.tex`，
缺包会 exit 1，**并把缺失名单直接拼进 `tlmgr install ...` 命令**，连
`sudo` 版和 `--usermode` 版各给一条，复制即用）。`make paper` 会先跑同一个
检查（`make tex-deps` 门禁），缺包时立刻中止、不启动 latexmk —— 否则错误会
埋进 `main.log`，latexmk 还会留下坏掉的 `.fdb_latexmk`，下次只说
`gave an error in previous invocation`。

**macOS 的 BasicTeX 是同一个坑。** `brew install --cask basictex`（或 pkg 装的
BasicTeX）也是 scheme-basic，同样缺 `siunitx / biblatex / cleveref / enumitem /
multirow`，`make paper` 报 `File 'siunitx.sty' not found`。而
`/usr/local/texlive/<year>basic` 属主是 `root`，系统级 `tlmgr install` 需要 sudo。
没有 sudo 时走 **usermode**（装到 `~/Library/texmf`，即 `TEXMFHOME`，pdflatex
立即可见，无需改 PATH）：

```sh
tlmgr init-usertree                     # 只需一次
tlmgr --usermode install siunitx biblatex cleveref enumitem multirow logreq
```

注意 `biblatex` 会连锁要求 `logreq`（还有 `etoolbox`/`url`/`ifthen`），
`latexmk` 只报第一个缺的包，所以补完要再跑一次 `make check-env` 直到
`N LaTeX packages ... resolve`。之后**所有 tlmgr 操作都要带 `--usermode`**
（包括 `tlmgr --usermode update --all`），否则会去动只读的系统树而报权限错。

### 4.4 文献后端：biblatex/Biber 为主，BibTeX 是唯一例外

四份 `latex_paper/example_*.tex` 里三份用 **biblatex + Biber**，只有
`example_apl.tex` 用 **BibTeX**：

| 示例 | 模板类 | 文献方案 | 原因 |
|---|---|---|---|
| `example_ieee_jmems.tex` | IEEEtran | biblatex (biber) | 类本身不加载 natbib |
| `example_ieee_edl.tex` | ieeecolor | biblatex (biber) | 同上 |
| `example_nature.tex` | sn-jnl | biblatex (biber) | 需伪 `ver@natbib.sty` 抑制类里硬编码的 natbib 加载 |
| `example_apl.tex` | revtex4-2 | **BibTeX** | REVTeX 硬编码 `\RequirePackage[sort&compress]{natbib}` 且自带 `\@bibitem` 体系，biblatex 会撞 `\bibhang / \citename / \textcite`；官方支持的就是 `aipnum4-2.bst` |

**`latex_refs/refs.bib` 因此必须同时被 Biber 和 BibTeX 读通。** 有一条硬规则：

> **BibTeX 没有注释语法。** 以 `%` 开头的行只被跳过「直到下一个 `@`」为止。
> 所以注释行里出现 `@` + 条目类型名，BibTeX 会真的当成一个条目去解析，
> 报 `I was expecting a '{' or a '('` 或 `You're missing a field name`。
> 而 `@comment{...}` 也不是注释块——BibTeX 只跳到下一个 `@`，里面的条目照样入库。

因此：

- **不要**在 `refs.bib` 的 `%` 注释里写 `@`（尤其别写「`% @article{...}` 这样注释掉」）。
- **不要**在 `refs.bib` 里存注释掉的条目模板。模板放本节末尾，复制出去用。
- 字段只用 BibTeX 与 Biber 的交集：不要 `@string` / `@preamble` 宏，不要裸数字字段。
- 写完先跑 `bibtex` 看 `.blg` 是否 0 error/warning，再跑完整 `make paper`。

条目模板（复制到 `latex_refs/refs.bib` 里改）：

```bibtex
@article{key2024,
  author  = {Last, F. and Last, F.},
  title   = {Sentence case title with {PMUT} protected},
  journal = {Journal Name},
  volume  = {1},
  pages   = {1--10},
  year    = {2024},
  doi     = {10.xxxx/xxxxx},
}

@inproceedings{key2023,
  author    = {Last, F. and Last, F.},
  title     = {Design of a {PIMNT} transducer for pulse-echo imaging},
  booktitle = {IEEE International Ultrasonics Symposium (IUS)},
  pages     = {1--4},
  year      = {2023},
  doi       = {10.1109/IUS.2023.1234567},
}

@book{key2020,
  author    = {Last, F.},
  title     = {Fundamentals of piezoelectric micromachined ultrasonic transducers},
  publisher = {Springer},
  address   = {Berlin},
  year      = {2020},
}
```

---

## 5. 命令速查

| 命令 | 作用 |
|---|---|
| `make` / `make help` | 环境检查 + 帮助（默认）；**Windows 需在 Git Bash 里跑** |
| `make check-env` | 只做工具链与目录检查；**必需工具缺失会 exit 1**（PATH→磁盘→FATAL）。同时校验 preamble 里每个 `\usepackage` 是否装全 |
| `make matlab` | 运行 `matlab/build_all_figs.m` → 重生成 `matlab/svg_out/*.svg` |
| `make figs` | 把 `figs_src/*.typ` 编译为 `figs_output/*.pdf`（增量） |
| `make sync` | `make matlab && make figs` |
| `make tex-deps` | 只校验 preamble 里每个 `\usepackage` 是否都装全；缺包会打印可直接粘贴的 `tlmgr install ...` 并 exit 1（`make paper` 会自动先跑它） |
| `make paper` | `latexmk -cd -pdf` → `latex_paper/main.pdf`（前置 `tex-deps` 门禁，缺包直接中止，不启动 latexmk） |
| `make paper SRC=<x>` | 编**别的** `.tex`。`x` 解析顺序：`x.tex`（当前目录）→ `latex_paper/x.tex` → `路径/x.tex` 原样用；`.tex` 可省。典型：`make paper SRC=example_apl`。文件不存在会列出现有源并 exit 1 |
| `make examples` | 依次编译 `latex_paper/example_*.tex` → 同目录 `example_*.pdf`（四套期刊模板的接入示例，不属于 `make all`） |
| `make all` | 全链路：matlab → figs → paper |
| `make clean` | 按扩展名删掉**所有** LaTeX 辅助文件（`.aux/.log/.bbl/.blg/.bcf/.out/.fls/.fdb_latexmk/.run.xml/.synctex.gz/…` + REVTeX 的 `*Notes.bib`），`latex_paper/` 只剩源码与 PDF |
| `make distclean` | `clean` + 所有生成的图 + `latex_paper/main.pdf` + `example_*.pdf` |

> **`make paper` 的变量叫 `SRC` 而不是 `TEX`。** `TEX` 是 GNU make 的
> **内建变量**（默认值 `tex`，即 TeX 二进制名），它永远"已定义"，
> 所以 `TEX ?= ...` 永远不会生效——不带参数时会去找 `tex.tex`。
> `LATEX` 同理。`SRC` 没有内建冲突。

---

## 6. 新增一张图：SOP（按顺序打勾）

- [ ] **1. MATLAB**：新建 `matlab/figN_name.m`
  - 函数名 = 文件名；尺寸用 `figW/figH`（85 mm 单栏 / 170 mm 双栏）
  - **单位陷阱**：MATLAB 没有 `'millimeters'`，图窗/纸张属性只能用 `'centimeters'`
    → `Units/PaperUnits='centimeters'`、`Position=[0 0 figW/10 figH/10]`
  - `Position=[0 0 figW/10 figH/10]`、`Color='w'`、坐标轴 `Position=[0 0 1 1]`
  - `XTick/YTick` 置空，**不加** title/legend/xlabel/annot
  - 导出到 `matlab/svg_out/figN_name.svg`
- [ ] **2. Typst**：新建 `figs_src/figN_name.typ`
  - `#import "_lib.typ": *`  +  `#show: doc => paper-figure(width: single-column, doc)`
  - `width` 必须与 MATLAB 的 `figW` 一致
  - `#panel[(a) ...][ #image("../matlab/svg_out/figN_name.svg", width: 100%) ]`
  - 多 panel 用 `#panels(columns: 2, gutter: 4mm)[...][...]`
  - 图内标注用 `#annot(dx: 55%, dy: 20%)[...]`
- [ ] **3. 构建**：`make figs`（会只重新编译改动过的 `.typ`）
- [ ] **4. LaTeX**：在 `latex_paper/main.tex` 中
      `\paperfigure{fig:name}{Caption.}{../figs_output/figN_name}`（注意 `../`）
- [ ] **5. 检查**：`make all` 零 error；PDF 中字体与正文一致，无重复标注

---

## 7. 命名规范

| 对象 | 规则 | 示例 |
|---|---|---|
| MATLAB 脚本 | `figN_name.m`，函数名同名 | `fig2_impedance.m` |
| Typst 源 | 与 MATLAB 脚本同名 | `fig2_impedance.typ` |
| 输出 PDF | 自动生成，同名 | `figs_output/fig2_impedance.pdf` |
| Typst 公共文件 | 下划线开头（Makefile 跳过） | `_lib.typ` |
| LaTeX label | `fig:` / `tab:` / `eq:` / `sec:` 前缀 | `fig:overview` |
| BibTeX key | `作者姓+年份+关键词` | `wang2023pmut` |

---

## 8. 硬规则（Do / Don't）

**Do**

- 改动 `.tex` / `.typ` / `.m` / `.bib` 时，**直接用编辑工具改文件**，不要用 Python/脚本批量改写文本。
- 用 VS Code diff 复查每一处修订再提交。
- `.bib` 标题一律 **Sentence case**；需要保留大写的词用双花括号：`{PMUT}`、`{Sc}`、`{AlN}`。
- 迭代用增量版本（V1→V2→…），重大改动前先备份当前可编译状态。
- 字体文件（`.ttf`/`.otf`）放 `fonts/`，Makefile 已通过 `--font-path fonts` 传给 Typst。
- 新增"某工具的安装目录" → 只改 `setup/find_toolchain.sh`，**不要**在 Makefile 里另写一份清单。
- 提交前跑 `make all` 并确认无 error。

**Don't**

- 不要把 `matlab/svg_out/*.svg` 直接 `\includegraphics` 进 LaTeX。
- 不要在 `latex_paper/main.tex` 里写不带 `../` 的仓库内路径（编译 cwd 是 `latex_paper/`）。
- 不要在 MATLAB 里写任何文字（含 `text()`、`annotation()`）。
- 不要在 Typst 里画数据。
- 不要手动编辑 `figs_output/*.pdf`——它是产物，永远由 `make figs` 重建。
- 不要往 `figs_src/` 放不带下划线的公共文件（会被误编译成图）。
- 不要提交 `*.aux *.log *.fls *.fdb_latexmk *.synctex.gz *.bbl *.bcf`、`latex_paper/main.pdf`（见 `.gitignore`）。
- 不要在 cmd / PowerShell 里跑 `make`——没有 `sh`，make 起不来；用 Git Bash。
- 不要把 Git 的 `usr\bin` 加进系统 PATH（会覆盖 Windows 的 `find`/`sort`）。

---

## 9. 故障排查

| 现象 | 原因 / 处理 |
|---|---|
| `make: command not found` | Windows：装 GnuWin32 make 并加 PATH，且在 Git Bash 中运行；macOS 用系统 make 即可 |
| `sh: not found` / make 一启动就死 | 你在 cmd 或 PowerShell 里跑 make；改用 **Git Bash**（或装 Git for Windows） |
| `FATAL: typst not found ...` | 真的没装：跑 `setup\windows.ps1` / `setup/macos.sh`，然后**开新终端**。若显示 `[fix] ... using <目录>` 说明是装了但没进 PATH，脚本已自动兜住 |
| `FATAL: latexmk ...` 但 `pdflatex` 是 OK 的 | TeX Live 装成 scheme-basic 了，缺 `latexmk` 包；见 §4.3 用 tlmgr 补 |
| LaTeX 报 `File 'xxx.sty' not found` | scheme-basic 缺包。**先跑 `make check-env`**，它会逐条列出缺哪个 `.sty`；再按 §4.3 的 tlmgr 命令补 |
| `make paper` 一开始就打印 `[FATAL] xxx.sty not found` + `make paper aborted` | 就是 `tex-deps` 门禁拦下来了。照它给的 `tlmgr install ...` 装完，再 `make clean && make paper` |
| latexmk 只说 `gave an error in previous invocation` / `Nothing to do`，不给真错误 | latexmk 记住了上次失败状态，不会自己重跑。先 `make clean` 再看 `main.log` 末尾；真实错误（通常是缺 `.sty`）会出现在那里 |
| `make check-env` 报一串 `[FATAL] xxx.sty not found` | 就是上面的缺包；`make check-env` 已经把答案直接给你了 |
| `make check-env` 直接 exit 1，不给看后面的检查 | 设计如此：必需工具（make/sh/typst/latexmk/pdflatex）缺一个就停，先修再跑 |
| Windows 脚本重复安装已装好的 VS Code | 已改为二进制探测；若仍复现，检查 `where code` 是否可用 |
| 插件看不到安装状态 | 已去掉输出重定向；`--force` 仅跳过交互确认，不影响可见性 |
| 刚装完 TeX Live，重跑脚本仍说未安装 | 安装器只对新进程写 PATH；已改为"PATH + 常见安装目录"双重探测，命中即跳过安装 |
| 插件装错用户 / VS Code 无法更新插件 | 别用管理员窗口装插件；在普通终端跑 `setup\windows.ps1 -Extensions` |
| 提权窗口没弹出来 / UAC 被拒 | 用管理员身份重跑 `setup\windows.ps1` |
| Typst 报 `font ... not found` | 把字体放进 `fonts/`；Makefile 已加 `--font-path fonts` |
| Typst 报 `path "../matlab/svg_out/..." would escape the project root` | Typst 默认把输入文件所在目录当 root；Makefile 已加 `--root .` 修掉。**新图照常写 `../matlab/svg_out/xxx.svg` 即可** |
| Typst 报 `file not found: matlab/svg_out/xxx.svg` | 还没跑 MATLAB；先 `make matlab`（或手动放好 SVG）再 `make figs` |
| `make matlab` 报 MATLAB 未找到 | 见 §4，确认 `matlab -batch "disp(version)"` 可用 |
| SVG 导出后有白边/尺寸不符 | 检查 `PaperPositionMode='manual'` 与 `PaperSize`；旧版 MATLAB 走 `print -dsvg` 分支 |
| LaTeX 报 `File ...fig not found` | 先 `make figs`；确认 `figs_output/` 中有对应 PDF |
| 编译后图/参考文献丢失，报 `File '../figs_output/x.pdf' not found` | 编译 cwd 是 `latex_paper/`（`latexmk -cd`），仓库内路径必须带 `../`；少了 `../` 就指到了 `latex_paper/figs_output/` |
| 根目录又冒出 `main.aux` / `main.pdf` | 有人直接在根目录跑了 `pdflatex main.tex`，或用的是旧布局；`make clean` 会连带清掉根目录残留 |
| 引用显示 `[?]` | `refs.bib` 为空或 key 拼错；跑 `make paper` 让 biber 参与 |
| 图内出现两套字体 | 说明 MATLAB 里写了文字，回到 §2 清掉 |

---

## 10. 扩展知识的落点

- 新增全局宏 → `latex_templates/macros.tex`
- 新增宏包 → `latex_templates/preamble.tex`
- 新增可复用的 Typst 绘图函数（比例尺、箭头、标注） → `figs_src/_lib.typ`
- 新增图的尺寸常数（如某期刊 90 mm 栏宽） → `figs_src/_lib.typ` 顶部常量区

改完上述位置后，记得在 `agent.md` 对应表格里补一行，保持手册与实现同步。
