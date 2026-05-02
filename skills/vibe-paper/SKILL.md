---
description: "学术论文写作助手（Vibe Paper）：默认使用 Microsoft Tech Report 模板，也支持用户指定自定义模板（ICLR/NeurIPS/CVPR等）。帮助初始化项目、填写内容、编译 PDF。Trigger: 用户提到 写论文、LaTeX、模板、paper、tech report、vibe paper、新建论文、学术写作。"
---

# Vibe Paper — 学术论文写作助手

> **语言**：始终使用用户的语言回复。以下指令仅供 Claude 内部参考。

---

## 一、概述

本 Skill 帮助用户从零开始撰写学术论文。内置 Microsoft Tech Report 模板作为默认模板，同时支持用户指定任意 LaTeX 模板。

**核心能力：**
1. 自动检测并引导安装 LaTeX 环境
2. 初始化论文项目（scaffold 模板文件）
3. 按照顶会写作规范（ICLR/ICML/NeurIPS）辅助填写各章节内容
4. 编译 LaTeX 生成 PDF

---

## 二、环境安装

初始化项目前，**必须先检查 LaTeX 环境**。按以下流程执行：

```bash
# 检查 pdflatex 是否可用
which pdflatex
```

如果 `pdflatex` 不存在，根据操作系统**自动执行安装**（需要用户确认）：

### macOS
```bash
# 推荐：安装完整版 MacTeX（约 4GB，包含所有宏包）
brew install --cask mactex

# 安装后刷新 PATH（新终端自动生效）
eval "$(/usr/libexec/path_helper)"

# 验证
pdflatex --version
bibtex --version
```

如果用户希望轻量安装：
```bash
# BasicTeX（约 100MB），需要手动安装缺失宏包
brew install --cask basictex
eval "$(/usr/libexec/path_helper)"

# 安装本模板需要的额外宏包
sudo tlmgr update --self
sudo tlmgr install collection-fontsrecommended collection-latexrecommended \
  tcolorbox environ etoolbox pgf xcolor listings algorithm2e ifoddpage \
  relsize titletoc placeins cleveref microtype booktabs enumitem \
  mathtools amscls amsmath natbib xstring
```

### Ubuntu / Debian
```bash
sudo apt update
sudo apt install -y texlive-full
```

轻量安装：
```bash
sudo apt install -y texlive-base texlive-latex-recommended texlive-latex-extra \
  texlive-fonts-recommended texlive-science texlive-bibtex-extra
```

### Windows
提示用户下载安装：
- **TeX Live**: https://www.tug.org/texlive/
- **MiKTeX**: https://miktex.org/download

### 验证安装成功
```bash
pdflatex --version && bibtex --version && echo "LaTeX environment ready!"
```

---

## 三、初始化流程

### 3.1 默认模板（Microsoft Tech Report）

当用户要求新建论文项目且未指定模板时：

```bash
# 复制模板到目标目录
cp -r <SKILL_DIRECTORY>/template/* <目标目录>/
```

### 3.2 自定义模板

当用户提供了模板路径（如 "用 ICLR 模板" 或指定一个目录）：

1. 读取目标目录下的 `main.tex`（或类似主文件）
2. 识别所有 `\input{}` / `\include{}` 的子文件
3. 逐一读取，理解每个文件的用途（abstract、intro、method 等）
4. 检测使用的编译器（pdflatex / xelatex / lualatex）
5. 按相同逻辑辅助用户编写内容，但遵循该模板的结构和格式

---

## 四、默认模板文件结构

```
project/
├── main.tex                     # 主文件（所有 <-- Replace 标记为可定制字段）
├── microsoft-tech-report.sty    # 微软样式文件（勿修改）
├── fancyhdr.sty                 # 页眉页脚（勿修改）
├── reference.bib                # 参考文献（BibTeX 格式）
├── figures/                     # 图片目录
│   └── microsoft.pdf            # 微软 logo（勿删除）
└── sections/
    ├── 0_abstract.tex           # 摘要
    ├── 1_introduction.tex       # 引言
    ├── 2_related_works.tex      # 相关工作
    ├── 3_method.tex             # 方法
    ├── 4_experiment.tex         # 实验
    ├── 5_conclusion.tex         # 结论
    └── 6_appendix.tex           # 附录（含 TOC 开关）
```

### 各文件说明

| 文件 | 内容 | 编辑要点 |
|------|------|----------|
| `main.tex` | 文档结构、包导入、标题、作者 | 搜索 `<-- Replace` 找到所有需要替换的字段 |
| `0_abstract.tex` | 摘要 | 按 [Background] → [Problem] → [Method] → [Results] → [Impact] 结构 |
| `1_introduction.tex` | 引言 | 含引用示例、交叉引用、contributions 列表 |
| `2_related_works.tex` | 相关工作 | 用 `\noindent\textbf{Topic.}` 段落式组织 |
| `3_method.tex` | 方法 | 公式、图片、伪代码示例 |
| `4_experiment.tex` | 实验 | Setup / Main Results / Ablation 结构，表格和子图 |
| `5_conclusion.tex` | 结论 | 含 Limitations and Future Work |
| `6_appendix.tex` | 附录 | TOC 开关、补充实验、Prompt 框、理论证明 |
| `reference.bib` | 参考文献 | BibTeX 格式，含 5 个示例条目 |

---

## 五、`main.tex` 可定制字段

用户需要替换的字段（搜索 `<-- Replace`）：

| 字段 | 位置 | 说明 |
|------|------|------|
| `pdftitle` | `\hypersetup` | PDF 元数据标题 |
| `\method` | `\newcommand` | 方法名缩写（用于正文中 `\method` 命令） |
| `\techreportshorttitle` | preamble | 页眉短标题 |
| 标题 | `\msfttitlefont` 行 | 论文标题 |
| 日期 | `\msftdatefont` 行 | 发布日期（出现两处） |
| 作者列表 | `\rmfamily\color{msftdark}` 块 | 作者姓名及标注 |
| 机构 | `\color{msftgray}` 块 | 机构名称 |
| Project Page | `\msftmetalabel` | 项目链接（可注释掉） |
| Correspondence | `\msftmetalabel` | 通讯邮箱 |
| 脚注说明 | `\itshape\color{msftgray}` | Equal contribution / Internship / Corresponding |

### 作者标注系统
- `$^{数字}$` — 机构编号
- `$^{*}$` — Equal contribution
- `$^{\dagger}$` — 实习等特殊说明
- `$^{\ddagger}$` — Corresponding author
- 多行作者用 `\\[-0.1em]` 换行

### 附录目录开关
在 `main.tex` 的 preamble 中：
- `\appendixtoctrue` — 显示附录目录页
- `\appendixtocfalse` — 不显示

---

## 六、写作规范（顶会风格）

**这些规范在帮用户写内容时必须严格遵守。**

### 5.1 Introduction
- 开头描述问题背景和动机（1-2 段）
- 可以引用 overview figure（`\cref{fig:*}`）
- **绝不**前向引用实验表格（`\cref{tab:*}`）——这不符合顶会惯例
- Contributions 用 `\begin{itemize}[leftmargin=2em]` 列表，通常 3 条
- 引用格式：`~\cite{key}` 或 `~\cite{key1,key2,key3}`

### 5.2 Related Work
- 用 `\noindent\textbf{Topic Name.}` 作为段落小标题
- 每个 topic 1-2 段，总结该方向的主要工作并指出与本文的区别
- 不使用 `\subsection`

### 5.3 Method
- 通常分为 Problem Formulation / Architecture / Training 等子节
- 单行公式用 `equation`
- **多行公式用 `equation` + `aligned`**（一个编号）；仅当每行需要独立编号时才用 `align`
- 图片浮动用 `[t]`，伪代码浮动用 `[t]`

### 5.4 Experiments
- 标准结构：Experimental Setup → Main Results → Ablation Study
- Setup 含 Datasets / Baselines / Implementation Details（各用 `\noindent\textbf{}`）
- 表格用 `booktabs`（`\toprule` / `\midrule` / `\bottomrule`）
- 最佳结果加粗：`\textbf{82.1}`
- 消融表如内容较晚出现，用 `[h!]` 防止浮动到 References 后面

### 5.5 Conclusion
- 1 段总结 + 1 段 Limitations and Future Work
- 用 `\noindent\textbf{Limitations and Future Work.}` 起头

### 5.6 页面布局规则
- 第一页：`\suppressfloats[t]` 阻止浮动体出现在 Abstract 之上
- References 前：`\FloatBarrier` 确保所有浮动体在 References 之前输出
- References **紧跟** Conclusion，不另起页（顶会标准做法）
- Appendix **从新页开始**（`\newpage`）

### 5.7 Appendix
- Prompt 框和详细 System Prompt 放附录
- 补充实验、可视化放附录
- 理论证明（如有）放附录

---

## 七、可用 LaTeX 环境速查

### 6.1 彩色定理框

所有定理环境**全局编号**（不跟 section），语法：`\begin{环境}{标题}{label}`

| 环境 | 用途 | 框颜色 | 引用方式 |
|------|------|--------|----------|
| `theorem` | 定理 | 蓝色 | `\cref{thm:label}` |
| `proposition` | 命题 | 绿色 | `\cref{prop:label}` |
| `lemma` | 引理 | 蓝色 | `\cref{lem:label}` |
| `corollary` | 推论 | 绿色 | `\cref{cor:label}` |
| `definition` | 定义 | 黄色 | `\cref{def:label}` |
| `assumption` | 假设 | 黄色 | `\cref{asm:label}` |
| `remark` | 备注 | 灰色 | `\cref{rem:label}` |

示例：
```latex
\begin{theorem}{Convergence Rate}{convergence}
Under Assumption~1, the algorithm converges at $\mathcal{O}(1/\sqrt{T})$.
\end{theorem}

\begin{proof}
证明内容...
\end{proof}
```

### 6.2 伪代码（algorithm2e）

```latex
\begin{algorithm}[t]
  \caption{算法标题}
  \label{alg:label}
  \KwIn{输入}
  \KwOut{输出}
  初始化\;
  \For{$t = 1$ \KwTo $T$}{
    操作\;
    \If{条件}{
      \textbf{break}\;
    }
  }
  \Return{结果}
\end{algorithm}
```
引用：`\cref{alg:label}`

### 6.3 LLM Prompt 框

```latex
\begin{promptbox}[Prompt 标题]
\noindent\textbf{Role:} ...
\noindent\textbf{Task:} ...
\noindent\textbf{Output:} ...
\end{promptbox}
```

### 6.4 JSON 代码块（在 Prompt 框中使用）

```latex
\begin{promptbox}[API Response Format]
\begin{lstlisting}[style=json]
{
  "title": "Paper Title",
  "score": 8.5,
  "tags": ["tag1", "tag2"]
}
\end{lstlisting}
\end{promptbox}
```

### 6.5 图片

```latex
% 单图
\begin{figure}[t]
  \centering
  \includegraphics[width=\linewidth]{figures/your_figure.pdf}
  \caption{图片说明。}
  \label{fig:label}
\end{figure}

% 子图
\begin{figure}[t]
  \centering
  \begin{subfigure}[b]{0.48\linewidth}
    \centering
    \includegraphics[width=\linewidth]{figures/a.pdf}
    \caption{子图 A}
  \end{subfigure}
  \hfill
  \begin{subfigure}[b]{0.48\linewidth}
    \centering
    \includegraphics[width=\linewidth]{figures/b.pdf}
    \caption{子图 B}
  \end{subfigure}
  \caption{总标题。}
  \label{fig:label}
\end{figure}
```

### 6.6 表格

```latex
\begin{table}[t]
  \centering
  \caption{表格标题。}
  \label{tab:label}
  \begin{tabular}{lcc}
    \toprule
    Method & Metric ($\uparrow$) & Metric ($\downarrow$) \\
    \midrule
    Baseline & 75.3 & 0.42 \\
    Ours & \textbf{82.1} & \textbf{0.31} \\
    \bottomrule
  \end{tabular}
\end{table}
```

### 6.7 公式

```latex
% 单行
\begin{equation}
  \mathcal{L} = \mathbb{E}_{x} [f(x; \theta)]
  \label{eq:label}
\end{equation}

% 多行（单编号）
\begin{equation}
  \begin{aligned}
    \nabla \mathcal{L} &= \frac{1}{N} \sum_i \nabla \ell_i \\
                       &\approx \frac{1}{|\mathcal{B}|} \sum_{i \in \mathcal{B}} \nabla \ell_i
  \end{aligned}
  \label{eq:label}
\end{equation}
```

---

## 八、编译

```bash
pdflatex -interaction=nonstopmode main.tex
bibtex main
pdflatex -interaction=nonstopmode main.tex
pdflatex -interaction=nonstopmode main.tex
```

**注意：** 需要运行 3 次 pdflatex（第一次生成 aux，bibtex 处理引用，后两次解析交叉引用和目录）。

编译后检查：
- `grep "undefined" main.log` — 确保无未定义引用
- `grep "Warning" main.log | head` — 检查警告

---

## 九、示例 PDF

完整渲染示例见 `<SKILL_DIRECTORY>/example.pdf`，展示了模板的所有功能。

---

## 十、工作流程

当用户请求帮助时，按以下流程操作：

### 场景 A：新建论文
1. 询问用户目标目录（默认当前目录）
2. 询问是否使用默认模板还是自定义模板
3. Scaffold 模板文件
4. 检查 LaTeX 环境
5. 询问论文标题、作者等基本信息
6. 替换 `main.tex` 中的 `<-- Replace` 字段
7. 编译验证

### 场景 B：填写内容
1. 读取用户指定的 section 文件
2. 根据用户提供的素材（要点、数据、图片路径等）按顶会规范撰写内容
3. 用 Edit 工具修改对应文件
4. 编译验证

### 场景 C：使用自定义模板
1. 读取用户指定的模板目录
2. 分析 main.tex 结构（包、section 文件、编译器）
3. 按分析结果辅助编写，遵循同样的写作规范
4. 自动适配编译命令

---

## 十一、注意事项

1. **不要修改** `microsoft-tech-report.sty`、`fancyhdr.sty`、`figures/microsoft.pdf`
2. 图片建议放在 `figures/` 目录，使用 PDF/PNG 格式
3. 所有交叉引用使用 `\cref{}`（自动添加 "Figure"、"Table" 等前缀）
4. 引用文献使用 `~\cite{}`（波浪号防止断行）
5. 编译遇到错误时，先查看 `main.log` 定位问题
