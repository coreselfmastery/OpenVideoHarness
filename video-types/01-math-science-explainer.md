# 01 数学 / 科学原理讲解（3Blue1Brown 式）

**适用**：讲清一个原理、定理、算法或物理过程，比如"为什么傅里叶变换能分解信号""注意力机制在算什么"。时长一般在 1–10 分钟，画幅 16:9。
**不适用**：
- 讲一篇论文的整体贡献，看 `06-paper-explainer.md`；
- 竖屏的碎片化科普，看 `02-knowledge-short.md`（可以把本类当画面风格借用）。

## 引擎

- **首选**：ManimGX（同一套 CE 的 Python API，Rust/wgpu GPU 核；公式用内置 Typst 排版，不装 LaTeX；`self.say` / `add_sound` 内置，能在某个词出现时触发动画）。公式、几何和坐标系都很精确，LLM 语料多。
- **备选**：
  - HyperFrames + KaTeX，适合公式少、排版多的讲解；
  - Remotion + KaTeX，社区案例 @dotey 的 Transformer 讲解就是用它做的。
- 安装方法见 `engines/README.md`。公式排版用 ManimGX 内置的 Typst（New Computer Modern），不需要装 MacTeX/LaTeX。

## 工作流

1. **确定受众层级**。高中、本科、研究生和业界的写法差别很大，读 `references/repos/3brown1blue/src/three_b1b/skill/audiences/` 下对应的文件。
2. **写 SCRIPT.md**：
   - 从具体的问题或例子切入，再引出一般规律；
   - 开头 30 秒内讲清为什么要关心这件事；
   - 用 `{cue}` 标出"说到这个词时画面要出现"的位置；
   - 长于 90 秒的，先按 `playbook/09-narrative.md` 选骨架（默认起承转合）、写节拍表，再写 CURRICULUM。
3. **写 CURRICULUM**：写进 STORYBOARD.md，每个场景只讲一个 insight，并写明对应的视觉模式（变换、分解、对比、放大）。
4. **写 STYLE.md**：
   - **实体-颜色映射表**：每个数学对象一个颜色，全片不变；
   - 在动画区定义 6×6 锚点网格（Code2Video 的做法），只通过网格放置元素。有讲义栏时，动画区是讲义栏旁边的那块；没有讲义栏时，就是整个安全框。坐标轴内部的点仍然用 `axes.c2p()` 定位，网格只管对象的整体摆放。
5. **音频先行（有旁白时）**：用 TTS 生成旁白；ManimGX 里 `self.say("…[这个词]…", anim1, anim2)` 把动画对到方括号里的词上（本仓库自己的音频管线 `tools/build_audio.sh` + timeline 照旧）。**静音版**跳过这一步，时长由 STORYBOARD 的 reads 决定，画面和少量标签必须在静音下读得懂。
6. **逐个场景搭建**：
   - 先用 `manimgx render -r 854x480 --fps 15` 快速渲染，`manimgx inspect` 过布局检查（exit 1 = 有问题）；报错按 ScopeRefine 的顺序修（`playbook/06-research-mechanisms.md`）；
   - 渲染后先打印所有对象的包围盒，检查有没有重叠，再看联系表（网格和包围盒审计的现成实现：`showcase/03-math-fourier/scenes/style.py`；`manimgx inspect` 的 storyboard 也会标出重叠）；
   - 最终用 `-r 1920x1080 --fps 30` 出片（4K `-r 3840x2160`；输出在场景文件旁边，`-o` 可改路径）。
7. **写代码前先读**：`3brown1blue/src/three_b1b/skill/SKILL.md` 开头的 Gotchas，里面是 Manim CE 最常见的崩溃原因（GX 同一套 API，同样适用），比如 `MathTex` 里不要写 `$`、`Transform` 之后要换成 `ReplacementTransform`。

## 审美要点

- **靠连续变换推进，不靠剪辑。** 每 5–15 秒一个视觉观点。每个 `play()` 持续 1–3 秒，之后停 0.5–2 秒。30 秒以内的短版可以压缩到每个动作 0.6–1.5 秒、停 0.3–0.8 秒，但每个 read 仍要至少 0.5 秒。
- **先几何，后代数。** 标注贴在对象上。放大看细节时，父对象不删，只是变暗、缩小到画面的 30–40%。
- **逐层增加复杂度。** 旧层变暗，但在论证中途不删除。
- **方程的出场方式**：先整体显示 2 秒，再整体变暗到 30%，然后逐项点亮讲解并上色。
- **问题卡出现后停 2–3 秒**，让观众先自己想一想。
- **3b1b 的实际配置**：
  - 背景纯黑，文字用 CMU Serif；
  - 常用色：蓝 `#58C4DD`、黄 `#FFFF00`、红 `#FC6255`、绿 `#83C167`、金 `#F0AC5F`。
- 3b1b 在 SoME 竞赛里的评审四条是：motivation、clarity、novelty、memorability。

**可在 prompt 里点名的参考**：3Blue1Brown《Essence of Linear Algebra》、Reducible、Mathologer。
**风格关键词**：semantic color、TransformMatchingTex、dim-and-highlight、persistent context。

## 禁止

- 一次把整屏 LaTeX 铺满；
- 对每个对象都用 `Write()`；
- 没有语义的彩虹配色；
- 辉光、粒子；
- 弹跳；
- 用要点清单收尾；
- CE 和 GL 的 API 混用。

## Prompt 增量块

```text
+ TYPE: 3b1b-style explainer. ManimGX, 1920x1080 30fps (`render -r 1920x1080 --fps 30`), bg #000000, math in New Computer Modern (built-in Typst; no LaTeX install). Audience: {high-school | undergrad | graduate | industry}.
Bind one color per math entity for the whole video; symbol and its geometry share it: {x:#58C4DD, f(x):#FFFF00, error:#FC6255}.
Open on the concrete puzzle with the core object on screen; say why it matters within 30s. Concrete example before the general rule.
Geometry first, then the equation. Equations appear whole, dim to 30%, then light up and get colored term by term.
Keep the parent diagram visible (dimmed) when zooming into details; dim old layers, never delete them mid-argument.
After a question card, hold 2–3s so the viewer can think (longer than the reading floor). Each play() 1–3s, then a 0.5–2s hold. No bounce, glow, particles, or bullet-list ending.
Place objects only via a 6x6 anchor grid (A1–F6) in the animation area; print all bounding boxes and check overlaps before rendering.
{Narrated: ManimGX self.say, trigger visuals on [bracketed] words at {cue} | Silent: timing comes from the storyboard reads; short on-screen labels carry the meaning}. Final render: -r 1920x1080 --fps 30.
```

## 自查重点

在 `TASTE_CHECKLIST.md` 之外，另外检查：
- 同一个实体在全片是否始终同一个颜色？
- 放大细节时，父对象是否还在画面里？
- 公式有没有超出安全区或和图形重叠？
- 每个场景是否只讲了一个 insight？
- 结尾是否落在"观众现在多懂了什么"的那个画面上，而不是一张总结清单？
- 结论文字至少完整可读 2.5 秒；放大、转场的中途，有没有不透明的底色把被放大的部分盖住？（showcase 03 的评审就抓到过这一点）
- 画面在演示一个数学性质时，数据是不是脚本算出来、并且 assert 过的？坐标和数字不能凭记忆手填。abstract-algebra-promo 的 `e8.py` 从定义生成 E8 根系，断言正好 240 个根、8 个单根，再把投影坐标写成 JSON；`qr.py` 生成 H 级纠错的二维码，把画面上要撕掉的那块分别涂白、涂黑各渲一张，用 OpenCV 解码，断言两种情况都还读得出原文。脚本和它写出的数据一起放进项目，页面直接读这份数据（它是手工嵌进 `promo.html` 的，重跑脚本不会更新画面，这一步别学）；NOTES.md 记下断言了什么。见 `cases/opus55-gallery.md` §7。
- Manim 陷阱（GX 同样适用）：传给 `self.play(..., rate_func=...)` 的 `rate_func` 会覆盖其中每个动画自己的缓动函数。想让各个动画用不同的缓动，就分开 play，或者只在动画上设置（`x.animate(rate_func=…)`）。
- Manim 陷阱（GX 同样适用）：`always_redraw` 每次重绘都会丢失 `z_index`，因为 `Mobject.become()` 只复制点和样式。结果所有动态曲线都停在图层 0，不透明面板会盖住它们。需要包一层，每次重绘后把 `z_index` 设回去，实现见 `showcase/03-math-fourier/scenes/` 里的 `live()`。showcase 03 前三版的放大转场闪黑，根源就是这个。

## 可参考的案例与源码

- `cases/explainer-code2video.md`：Planner-Coder-Critic、锚点网格、ScopeRefine。
- `cases/opus55-gallery.md` §7：abstract-algebra-promo，一支 4 分 23 秒的抽象代数宣传片（Canvas/WebGL，没有许可证，只读）。可看它按小节排的场景表、不跨切点的子帧运动模糊、脚本算出并断言的数学数据，以及代码合成的配乐。
- `references/repos/3brown1blue/src/three_b1b/skill/`：
  - `rules/` 下的 `animation-design-thinking.md`、`explanation-design.md`、`equations.md`、`equation-derivations.md`、`visual-design-principles.md`、`pedagogy-checklist.md`、`voiceover.md`、`troubleshooting.md`；
  - `domains/`：数学、物理、算法、ML 各自的套路；
  - `references/repos/3brown1blue/src/three_b1b/skill/templates/equation_explainer.py`：公式讲解的场景模板。
- `references/repos/Code2Video/prompts/stage3.py`（锚点网格的 prompt）、`src/scope_refine.py`（报错修复）。

## 社区 skill 参考

以下条目选自 183 个社区视频 skill，完整对照和许可证说明见 `references/community-skills.md`。只读参考；复用代码前，先确认它的许可证。

- **MathLens**（README 声明 CC BY-NC 4.0，只读）：`wait_for_narration(keyword)` 让动画等旁白说出关键词才触发；`assert_geometry()` 在动画前先校验几何事实和画布范围。见 `references/repos/MathLens/SKILL.md`、`references/repos/MathLens/templates/script_scaffold.py`。
- **lemo-opuscar 的 `whiteboard` 风格**（MIT；2026-09-29 之前的快照为 CC BY 4.0）：一块白板一镜到底，逐笔写出，最后拉远看全板，是 3b1b 黑底之外的另一种画风。见 `references/repos/lemo-opuscar/styles/whiteboard/STYLE.md`。
