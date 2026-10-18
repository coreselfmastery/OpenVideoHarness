# 05 数据叙事 / 动画图表

**适用**：
- 用数据讲一个结论：趋势、对比、排名变化、分布；
- 实验结果展示；
- 市场或业务数据的短视频，比如把每日行情或业务指标做成 60 秒的数据短片。

## 引擎

- **首选**：HyperFrames，用 SVG 配合 GSAP 手写图表。需要现成组件时，可以用 `npx hyperframes add data-chart` 加入动画图表组件。
- **备选**：Remotion + D3 的比例尺；图表之间需要形变过渡时，可以看 vizzu-lib。
- **不要**直接用图表库的默认输出。

## 工作流

1. **先定结论，再画图**：列出 2–5 个 takeaway，每个 takeaway 对应一张图。图的标题就写成那个结论句。
2. **数据处理**：用 Python（pandas 或 duckdb）算好数据，导出 `data/*.json`，前端只负责画。每个上屏的数字，都在 `NOTES.md` 里记下出处和计算方式。
3. **图表语法**：
   - 直接在线上或柱子上标注，不用图例；
   - 只高亮 1 条系列，其他都是灰色、40% 透明；
   - 数字用 `tabular-nums`，并带单位；
   - 数据来源常驻在左下角，60% 透明。
4. **转场**：
   - 同一个概念的连续数据留在同一个视觉空间里，只变数值；
   - 转场分阶段进行：先变坐标轴，再变数值，约 1 秒（Heer & Robertson 2007）；
   - 同一个图形标记始终代表同一个实体。
5. **节奏**：
   - 数字计数不超过 1.5 秒，最终状态至少停 2 秒；
   - 时间序列的曲线线性地画出来，因为横轴就是时间；
   - 先出基线，再出"我们的"。

## 审美要点

- **可在 prompt 里点名的参考**：Hans Rosling / Gapminder、FT 的 John Burn-Murdoch、The Pudding、NYT 和 Bloomberg Graphics。
- **Gapminder 式动画的定位**：它做分析不如静态的小多图，但很适合讲故事。所以动画的每一步都要服务于那个结论。
- **数字要有视觉重量**：数字旁边配一个有分量的东西，比如填充条或圆环。

## 禁止

- 没有叙事的 bar chart race；
- 3D 饼图，或者任何饼图；
- 双轴；
- 满屏网格线；
- 彩虹分类色；
- 条形图的 y 轴不从 0 开始；
- 6 格仪表盘；
- 数字没有出处。

## Prompt 增量块

```text
+ TYPE: data story. {1920x1080 | 1080x1920} 30fps {45–90}s from {data.csv / data/*.json}; build charts with SVG + GSAP, not a chart library.
Each chart = one takeaway, written as its title sentence. Label lines directly; no legends, gridlines, dual axes, or pies.
Highlight series in accent {hex}; others #8A8F98 at 40%. Numbers use tabular-nums, with units; source line bottom-left at 60% opacity.
Transitions ~1s and staged: rescale axes first, then move values; the same mark always = the same entity; continuous data for one concept stays in one visual space.
Count-ups <=1.5s, then hold the final state >=2s. Time-series lines draw linearly. Baseline first, then ours.
Every on-screen number traced to its source row/calculation in NOTES.md.
```

## 自查重点

- 屏幕上的每个数字都能对上数据文件吗？可以抽 3 个数字手算核对。
- 轴刻度和单位对吗？
- 高亮的系列是不是就是标题结论里说的那个？
- 转场时，同一个实体是否始终是同一个标记？

## 可参考的案例与源码

- `references/repos/hyperframes/skills/hyperframes-creative/references/data-in-motion.md`（**必读**）。
- `references/repos/3brown1blue/src/three_b1b/skill/rules/graphs-plots.md`：用 Manim（CE；ManimGX 同一套 API）画图表的做法。
- `playbook/03-motion-design.md`：计数和 stagger 的数值参数。

## 社区 skill 参考

以下条目选自 183 个社区视频 skill，完整对照和许可证说明见 `references/community-skills.md`。只读参考；复用代码前，先确认它的许可证。

- **data-animation-skills / chart-animation**（MIT）：每个值都由当前帧计算，关掉图表库自带的动画；计数先取整再格式化，用 tabular-nums；排名也插值，超车时滑过去而不是跳过去。见 `references/repos/data-animation-skills/skills/chart-animation/SKILL.md`、`references/repos/data-animation-skills/skills/chart-animation/references/bar-chart-race.md`。
- **lemo-opuscar 的 `dataviz` 风格**（MIT）：图表本身就是镜头和节奏，手写批注钉在具体数字上。见 `references/repos/lemo-opuscar/styles/dataviz/STYLE.md`。
