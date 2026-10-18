# 00 范式与引擎选型

## video-as-code 是什么

模型不直接生成像素，而是写一个程序：给定时间 t，就画出那一帧。渲染器（headless Chrome、ManimGX、Blender）以 1/fps 为步长逐帧调用这个程序，最后由 ffmpeg 把帧和音轨合成 mp4。

这种做法带来三个性质，后面的工作流都依赖它们：

1. **确定性**：同一个 t 永远得到同一帧。因此可以并行渲染、断点续渲，也可以跳到任意时刻渲染。
2. **可自查**：任何时刻都能单独渲染出来，agent 可以拼一张联系表，"看"一眼自己的作品再改代码。这是整个质量闭环的基础。
3. **可 fork 和 remix**：视频就是代码，换歌词、换音轨、换风格都只是改代码。例如 YC 把英文 P(doom) MV 改成中文版，流程是重填歌词、用 Suno 翻唱，再让 Claude Code 把动画重新对齐到新音轨。

还有一个前提要记住：Claude 只接受文本和图像输入。所以它"看视频"其实是看抽出来的帧，"听音频"其实是读转写结果和时间戳。任何工作流都得先把音频变成时间表。

## 引擎选型

| 引擎 | 写什么 | 长处 | 短处 | 适合 |
|---|---|---|---|---|
| **HyperFrames**（HeyGen，Apache-2.0） | 纯 HTML/CSS + GSAP，可混用 Lottie、Three.js | Claude 最擅长写 HTML；有官方 Claude Code 插件和 21 个 skills；自带 lint、check、snapshot 自检；没有公司规模限制 | 2026 年 3 月才开源，还在快速迭代 | 宣传片、科普竖屏、字幕包装、排版类 MV、数据动画、梗视频 |
| **Remotion** | React 组件 | 生态最大；有官方 skills；有 Studio 预览；支持 Lambda 云渲染 | 超过 3 人的公司需要买授权；动画必须用 `useCurrentFrame()` 驱动 | 同上；偏好 React 或需要云端批量渲染时选它 |
| **ManimGX** | Python 场景类（CE 的 API，Rust/wgpu GPU 核） | 公式、几何、坐标系精确；LLM 语料多（就是 CE 的 API）；`self.say` 能按词触发动画；内置 Typst 排公式，不装 LaTeX | 不适合排版密集或 UI 类画面；无 GPU 时落到 CPU（lavapipe），仍比 CE 快 | 数学、物理、算法、论文机制讲解 |
| **p5.js + p5.brush**（ClaudeAnimationBase） | JS，每帧 `renderAt(t)` | 手绘、水彩、墨线质感；有现成角色和完整动画规范；仓库自带 | 纯 2D；没有 GPU 时水彩渲染慢（Apple Silicon 实测约 0.13 秒/帧） | 角色短片、手绘 MV、叙事型科普 |
| **自定义 WebGL/Canvas** | JS | 可做任意画风，例如 functional-emotions 的 6 万笔触渲染器 | 要从头搭 | 有明确风格追求的 MV |
| **Blender**（MCP 或 `blender -b` 脚本） | Python bpy | 真 3D、光照、物理 | 渲染慢；MCP 会直接执行 LLM 生成的代码 | 3D 产品展示、空间场景 |
| **生成式视频 + 代码叠加** | 调 API，再写叠加层 | 写实人物和物理效果 | 花钱多；跨镜头角色一致性差；结果不确定 | 见 `05-hybrid-genvideo.md` |

【综合】默认选法：
- 要精确的数学图形，用 ManimGX；
- 要手绘质感，用 ClaudeAnimationBase；
- 其余先用 HyperFrames；
- 需要真 3D，用 Blender；
- 需要真人或写实效果，走混合管线。

## 为什么大家最后都走到同一套流程

学术系统（Code2Video、TheoremExplainAgent、Paper2Video）和社区里做得好的案例（PDoom、Functional Emotions、Claude Pop），各自独立演化，最后都收敛到同一套骨架：

1. 先写脚本和分镜文件。
2. 音频先行，用音频决定时长。
3. 每个镜头写成确定性的 `f(t)` 代码。
4. 渲染静帧或联系表，让 agent 自己看。
5. 按看到的问题修改。
6. 并行渲染，最后用 ffmpeg 合成。

具体做法见 `01-pipeline.md`。
