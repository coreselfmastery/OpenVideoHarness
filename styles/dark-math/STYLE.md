# 暗底数学 · dark-math

一句话：纯黑底上，几何对象靠连续变换推出结论；每个数学实体一个颜色，公式里的符号和它的图形同色，全片不变。适合讲清一个原理、定理或算法。本仓库的 `video-types/01-math-science-explainer.md` 和 `showcase/03-math-fourier/` 已经是这个风格的完整实现，本预设把它们的规则收成可复用的一页。

样片：`media/swatch.mp4`（5 s，含 `score.json` 配乐）· 封面 `media/poster.jpg`（t = 3.0 s）

样片里：0–0.6 s 整张网格以原点为圆心扫开（一个带亮边的圆盘在 0.1 s 已盖住大半个画面，扫完后亮度约 25% 灰，轴 60%），同拍钢琴琶音起；0.4 s 起绿色 î、红色 ĵ 两个基向量从原点弹出（各一声 `tick`），2.0 s 母题出场前退掉；网格单位 160 px；标题先描轮廓再填充（手写式）；三元素以 x 轴（y = 800）为底、高约画面的 37%，中心约在 0.55H，标签在轴下方：蓝点（大纲）的一份拷贝拉成绿色向量（分镜），再扫成黄色平行四边形（初版），标签与对象同色，中文 58 px；2.6–4.0 s 整组慢推 4.5%，3.0 s 和 3.5 s 各一次 1.2× indicate 加黄色闪光，都配一声 `ding` 和一个钢琴和弦；4.0 s 三者一起变换成一个黄圆，落成证毕方块，名字随之写出。实际字体：STIX Two Text（网页里没有 CMU Serif）、Songti SC。配乐记成 120 BPM（60 BPM 的双倍网格），`meters` 让 3.0、3.5、4.0 s 都是小节线，C 大调，没有鼓：毡锤钢琴（`piano` 的 `felt`，踩延音踏板）在两个八度里上下弹琶音，每秒 3 个音（按 60 BPM 算是八分三连音），每换一个和弦在低音区点一个根音；下面一层很轻、偏暗的弦乐 pad；和弦走 Cmaj7 → Fmaj7 → Am7 → Gsus4 → Cadd9；3.0、3.5 s 的 indicate 各是一个和弦；4.0 s 证毕时钢琴放下一个开放的 Cadd9，钢片琴（`celesta`）在上面把 C–E–G–C 唱一遍。混响是大厅。

## 学习对象

| 作品 | 年份 · 作者 / 工作室 | 从它身上学什么 |
|---|---|---|
| 《Essence of Linear Algebra》系列 | 2016 起 · 3Blue1Brown（Grant Sanderson）；首集 2016-08-05 | 先几何后代数；整个坐标网格本身被变换，观众"看见"矩阵；基向量的颜色贯穿整个系列；每集只立一个直觉 |
| manim | 3Blue1Brown 自研的动画库，社区维护版为 Manim Community Edition（分叉时间未核实） | 动画就是对象之间的变换（Transform）：旧对象变成新对象，而不是淡出再淡入 |
| `showcase/03-math-fourier` | 2026 · OpenVideoHarness | 实体-颜色表、6×6 锚点网格、放大细节时父图缩小变暗但不删、包围盒审计 |

核实：系列名和首集日期来自 3blue1brown.com 与 TheTVDB 的集表。Manim CE 从原版分叉的具体日期没有查到可靠出处。

**不照搬**：不用 π 形小角色、频道片头和标志、原片配乐；不逐镜复刻某一集的推导（例如"整个网格被 2×2 矩阵剪切"的那几个镜头），也不把颜色约定当成原作的签名来模仿。

## 视觉语法

- **色板**：黑底，白色只给运算符和结构，其余颜色全部绑定实体。

  | token | hex | 语义（示例：写进项目 STYLE.md 的实体表） |
  |---|---|---|
  | bg | `#000000` | 背景（类型文档允许纯黑） |
  | fg | `#FFFFFF` | 运算符（=、+、括号）、标题 |
  | 蓝 | `#58C4DD` | 自变量、输入、第一个对象 |
  | 黄 | `#FFFF00` | 当前焦点、累积结果、结论（accent） |
  | 红 | `#FC6255` | 误差、反例、要警惕的量 |
  | 绿 | `#83C167` | 第二个基向量、对照组 |
  | 金 | `#F0AC5F` | 常数、参数 |
  | 灰 | `#888888` | 目标、旧层、上下文 |

  透明度分三层：主角 1.0、上下文 0.30–0.35、结构（坐标轴、网格）0.15–0.30。一个颜色一旦代表某个实体，全片不再换义。
- **字体**：ManimGX 公式走内置 Typst（New Computer Modern，和 CE 时代的 CMU Serif 同源）；网页引擎里没有 CMU 系统字体，用 STIX Two Text（本机自带，最接近）或 Times New Roman。变量用斜体，运算符和数字用正体。中文用 Songti SC，和衬线数学字体同一气质。等宽标签用 Menlo。
- **构图**：动画区划 6×6 锚点网格（A1–F6），元素只通过网格放置；公式放顶行，图形占中下部；标签离对象不超过一格。放大看细节时，父图缩到画面的 30–40% 放在一角，变暗但不删。
- **质感**：无。不发光、不加颗粒、不做粒子。

## 运动语法

帧数按 30 fps 计。

- **缓动**：Manim 的 `smooth`，网页里用 `cubic-bezier(0.65,0,0.35,1)`；强调用 there-and-back（亮一下再回去）；不用 overshoot、bounce 和弹簧。
- **时长**：每个 `play()` 1–3 s（30–90 帧），之后停 0.5–2 s；第一次出现的新概念后停 ≥ 1 s；问题卡出现后停 2–3 s。短版可以压到每个动作 0.6–1.5 s、停 0.3–0.8 s，但每个 read 至少 0.5 s。每 5–15 s 立一个新的视觉观点。
- **公式出场**：整体出现并停 2 s → 整体变暗到 30% → 逐项点亮，并染上它对应图形的颜色。代数变形用 TransformMatchingTex，相同的符号从旧位置滑到新位置。
- **转场**（只用这 3 种）：
  - 连续变换（transform）：对象变成下一个对象，点对点插值；
  - 放大进细节（zoom-into-detail）：父图缩小变暗，细节面板展开；
  - 章节之间淡到黑（fade-to-black），只在章节分界用，0.5 s。
- **镜头**：固定机位为主；放大用 MovingCamera，三维对象慢速旋转，不做手持和推拉特技。
- **文字动画**：手写式（handwrite）。先描出字形轮廓，轮廓画到 60% 时填充渐入；每个字形约 0.3 s，错开 40–60 ms。标签用淡入（0.4–0.6 s），不要每个对象都"写"。

## 声音语法

- **配乐**：旁白是主角，音乐只垫底，是 3Blue1Brown 那种安静的钢琴：C 大调，60 BPM（30 fps 下一拍 30 帧；2 s 和 4 s 都落在拍上）。签名是毡锤钢琴的琶音（`piano` 的 `tone: "felt"` 加延音踏板，八分三连音，在两个八度里上下走），每换一个和弦低音区点一个根音；下面一层很轻、偏暗的弦乐 pad（`strings`，低通）；结论出现时钢片琴（`celesta`）唱一个上行琶音。大厅混响，没有鼓。
- **音效**：几乎没有。结论落定时可以有一声 −18 dB 的 `ding`。不用 whoosh。
- **声画关系**：旁白先行，动画比 cue 词早 0.3–0.5 s 开始；问题卡之后的 2–3 s 只留 pad；每句话说完后画面停约 1 s。
- **样片拟音**：`events.json` 只有 8 个事件，由 `swatch.js` 导出的 `FOLEY` 经 `node styles/_swatch/foley.mjs <slug>` 生成，落点全部引用动作所用的同一张时间表，声像取发声物体的屏幕 x（`(2x/W − 1)·0.7`），按 `profile=swatch` 混在配乐下：î、ĵ 弹出各一声 `tick`；标题中英两次落笔各一声很轻的 `tick`；点出现一声 `pop`；3.0、3.5 s 两次 indicate 各一声 `ding`；证毕方块落定 `click`。两次 TransformFromCopy 和最后的合并都不配声，守住"不用 whoosh"。
- **样片的转场音效**：没有转场音效：两次 TransformFromCopy 变形保持安静（风格本来就不用 whoosh）。

## 适合与不适合

- **适合**：01 数学、物理、算法原理；06 论文里的机制部分；02 横屏科普（节奏压缩后）。
- **不适合**：情绪化的品牌片、数据新闻（用 `editorial-data`）、竖屏 3 秒 hook 类快剪。
- **容易被误用成**：黑底 + 发光公式 + 粒子的"科技感 PPT"，或者满屏 LaTeX 的板书。

## 禁止项

1. 一次把整屏 LaTeX 铺满；对每个对象都用 Write。
2. 没有语义的彩虹配色，或者同一个颜色在不同场景代表不同东西。
3. 辉光、粒子、弹跳、渐变背景。
4. 放大细节时把父图删掉，观众失去上下文。
5. 用要点清单收尾；结尾应该停在"观众现在多懂了什么"的那个画面上。

## Prompt 块

```text
Visual style: dark mathematical explainer. Pure black background, no glow, no particles, no bounce. Every mathematical entity has one colour for the whole film, shared by its symbol in the equation and its geometry: blue #58C4DD for the input, yellow #FFFF00 for the current focus and the result, red #FC6255 for error or counterexamples, green #83C167, gold #F0AC5F for parameters, grey #888888 for context; white only for operators and titles. Text is a Computer Modern style serif (LaTeX; STIX Two Text on the web) with italic variables; Chinese in Songti SC. Geometry first, then algebra: equations appear whole, hold 2 s, dim to 30%, then light up term by term in their entity colours. Change is shown by continuous transformation (one object morphs into the next, matching symbols slide to their new places), never by fade-out/fade-in. Zooming into a detail keeps the parent diagram on screen, dimmed and shrunk to a corner. Each move 1–3 s with smooth in-out easing, then a 0.5–2 s hold; objects placed on a 6×6 anchor grid. Titles are hand-written: outlines trace, then fill. Quiet 60 BPM major-key felt-piano arpeggios over a soft string pad under the narration, a celesta on the conclusion, no drums.
```

## 引擎做法

- **首选 ManimGX**（CE 的同一套 API）。直接复用 `showcase/03-math-fourier/scenes/style.py`（已迁移）：`Grid`（6×6 锚点、`at()`、`area()`）、包围盒审计，以及修 `always_redraw` 丢 `z_index` 的 `live()` 包装。颜色只从一个 palette 模块取，代码里 grep 不到 palette 以外的 hex。
- **网页引擎**（HyperFrames + KaTeX 或 Canvas）：公式用 `\textcolor` 按实体上色；形状统一重采样成 N 个点（例如 64 个），变换就是逐点 `lerp`，点、线段、面都能互相变。
- **手写字**：Canvas 里 `strokeText` 配 `setLineDash([L, L])`，`lineDashOffset = L·(1 − u)` 让轮廓逐渐画出，u > 0.6 后填充渐入。
- 样片 `swatch.js`：逐段做法见开头"样片里"。实现要点：点、向量、平行四边形都重采样成 64 个点的多边形，变换就是逐点插值；indicate 是一个 sin 脉冲的缩放，外加一圈向外扩散的短射线。

## 自查重点

- 同一个实体在全片是否始终同一个颜色？抽 3 个场景对照实体表。
- 放大细节时，父对象是否还在画面里？
- 公式是否超出安全区，或和图形重叠？（打印包围盒）
- 每个场景是否只讲了一个 insight？
- 结论文字至少完整可读 2.5 s（风格节拍：结论要留时间想；比读时底线长）；放大或转场的中途，有没有不透明底色盖住被放大的部分？
- Manim 陷阱（GX 同样适用）：`self.play(..., rate_func=…)` 会覆盖每个子动画自己的缓动；`always_redraw` 会丢 `z_index`（见 `video-types/01`）。

## 相关资源

- `video-types/01-math-science-explainer.md`（审美要点、禁止项、Prompt 增量块都以它为准）；`showcase/03-math-fourier/`（STYLE.md、`scenes/style.py`、成片）。
- `references/repos/3brown1blue/src/three_b1b/skill/` 的 `rules/`（动画设计、公式推导、视觉原则）。
- lemo-opuscar 没有暗底数学风格；亮底的替代口味是 `references/repos/lemo-opuscar/styles/whiteboard/STYLE.md`（LemoLab，CC BY 4.0），一块白板一镜到底。
- `playbook/06-research-mechanisms.md`（Code2Video 的锚点网格和 ScopeRefine）。
