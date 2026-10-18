# 开源项目清单（2026-09-28）

所有项目都通过 GitHub API 核实过存在性；⭐ 是约数，日期是最近一次 push。

已拉到本地的仓库都在 `references/repos/`（运行 `references/fetch.sh` 更新），包括：
- PDoomVideo、functional-emotions-video、hyperframes-launches、remotion-skills；
- HyperFrames 的 skills（部分检出）、Code2Video 的 prompts 和 src（部分检出）、3brown1blue 的 skill（部分检出）；
- 2026-09-29 补：Battle-of-Austerlitz-Film、claude-animation-skill、product-film-skill、procedural-film，以及两份 Opus 5.5 作品目录（athemeroy、zhuyansen）。社区 skill 和目录的完整清单见 `community-skills.md`。

ClaudeAnimationBase 在 `engines/` 下，依赖已装好。清单里的其他项目需要时再装。

**CC 适配**：A = 代码优先、有 CLI、渲染确定、文档好，Claude Code 可直接驱动；B = 能驱动，但要配 API/GPU 或是固定流水线；C = 以 GUI 为主或难以自动化。
**标记**：[停更] 超过 12 个月没有 push；[NC] 非商用；[自定义] 自定义许可证，用前细读。

---

## 如果只选 5 个

1. **HyperFrames**：主力渲染器。纯 HTML + GSAP，Claude 最擅长写；Apache-2.0；自带 lint、snapshot、check 自检；官方 skills 直接覆盖产品宣传、科普竖屏、歌词 MV。偏好 React 就换 Remotion + `remotion-dev/skills`，思路相通。
2. **ManimGX**（manimgx 0.1.1，Rust/wgpu GPU 核，实现的就是 Manim CE 的 Python API）：公式、几何、算法、论文机制需要精确，没有替代品。公式用内置 Typst 排版（不装 LaTeX）；`self.say`/`add_sound` 能按词触发动画、加声音，不再需要 manim-voiceover。
3. **ClaudeAnimationBase**（配 PDoomVideo 当范例）：手绘质感，已在本机跑通；流程在 Claude 上验证过。PDoomVideo 没有 license，只能参考。
4. **mlx-audio 跑 Qwen3-TTS**：在 Apple Silicon 上本地做中文配音，Apache-2.0。
5. **whisper.cpp 或 FunASR 做时间戳 + librosa 或 beat_this 做节拍**：导出成 `timeline.json`，前三个渲染器都从这里读时间。中文字幕用 FunASR 更准；已有讲稿或歌词用 ctc-forced-aligner。

没有选 MoneyPrinterTurbo 这类，是因为它们是固定流水线加素材拼接，风格难控；在 Claude Code 里自己编排上面这些组件更灵活。中文平台需要可编辑工程时，加 `pyJianYingDraft` 导出剪映草稿。

---

## 1. 程序化视频 / 动效框架

| 项目 | 说明 | ⭐ / push | License | CC | 适合 |
|---|---|---|---|---|---|
| [heygen-com/hyperframes](https://github.com/heygen-com/hyperframes) | HTML/CSS + 可 seek 动画（GSAP、Lottie、Three.js）写视频，headless Chrome + FFmpeg 出片；官方 Claude Code 插件和 21 个 skills；Node 22+ | 53.8k / 2026-09 | Apache-2.0 | A+ | 宣传片、讲解、歌词 MV、字幕包装 |
| [remotion-dev/remotion](https://github.com/remotion-dev/remotion) | 用 React 组件写视频 | 60.9k / 2026-09 | Remotion License（个人和 3 人以内公司免费） | A | 宣传片、数据动画、字幕短视频 |
| [motion-canvas/motion-canvas](https://github.com/motion-canvas/motion-canvas) | TS generator 写动画 | 19.2k / 2026-07 | MIT | B（渲染依赖编辑器） | 讲解、代码演示 |
| [midrender/revideo](https://github.com/midrender/revideo) | Motion Canvas 分支，有 headless 渲染 API（原 redotvideo/revideo） | 4.1k / 2026-07 | MIT | A- | 模板化批量出片 |
| [Zulko/moviepy](https://github.com/Zulko/moviepy) | Python 剪辑合成 | 14.9k / 2026-08 | MIT | A（复杂动效弱） | 拼接、加字幕 |
| [lucemia/typed-ffmpeg](https://github.com/lucemia/typed-ffmpeg) | 类型安全的 FFmpeg filtergraph | 1.2k / 2026-09 | MIT | A | 复杂滤镜 |
| [WyattBlue/auto-editor](https://github.com/WyattBlue/auto-editor) | 自动剪掉静音段，可导出 Premiere/Resolve 时间线 | 5.4k / 2026-09 | Unlicense | A | 口播粗剪 |
| [charmbracelet/vhs](https://github.com/charmbracelet/vhs) | 用脚本录终端 GIF/MP4 | 21.0k / 2026-09 | MIT | A | CLI 工具演示 |
| [OpenCut-app/OpenCut](https://github.com/OpenCut-app/OpenCut) | 开源 CapCut 替代，GUI 剪辑器 | 90.8k / 2026-09 | MIT | C | 手动精修 |
| [openfilm/openfilm](https://github.com/openfilm/openfilm) | 视频即网页：`film.html` 把页面（`window.film.frame(t)`）、素材和声音按轨道剪在一起；`look` 检查、`render` 出片；本地剪辑器 Studio 和带聊天的桌面版。加一小段包装就能打开我们的片子，见 `docs/proposals/01-client-and-workflow.md` | 未查 / 2026-10 | MIT（名称和 Logo 是商标） | A，跨进程的确定性未量（见提案 2.4） | 人工精修、给片子加剪辑器 |
| [alchaincyf/huashu-art-motion](https://github.com/alchaincyf/huashu-art-motion) | 艺术动画 skill：Canvas 引擎（按作者的文档，每帧是 t 的函数、随机带种子），每种风格是一个可运行的场景文件加一张配方卡，共用一套渲染器库；另有 9 种解说语法、qa（确定性、运动、静止帧对、跳变、每帧耗时）和 breakdown（拆参考片）脚本。见 `references/community-skills.md` 第 8 节 | 3.3k / 2026-10 | MIT（作者的卡通形象和角色帧、Clawd 形象除外） | A，按作者的文档；qa.py 的确定性检查没自己跑过 | 艺术史、名画、绘画质感；解说语法 |

已被取代：editly、ffmpeg-python、theatre.js、timecut、FFCreator（均 [停更]）。

## 2. 数学 / 科学 / 知识讲解

| 项目 | 说明 | ⭐ / push | License | CC | 适合 |
|---|---|---|---|---|---|
| [academa-labs/manimgx](https://github.com/academa-labs/manimgx) | Manim CE 的 Python API，Rust/wgpu GPU 核渲染；内置 Typst 排公式；本仓库现在用的数学引擎 | 1.6k / 2026-10 | MIT | A | 数学、算法、物理、论文 |
| [ManimCommunity/manim](https://github.com/ManimCommunity/manim) | Manim 社区版（CE），文档全，LLM 语料多；ManimGX 实现的就是它的 API | 41.1k / 2026-09 | MIT | A | 数学、算法、物理、论文（已被本仓库换为 ManimGX） |
| [3b1b/manim](https://github.com/3b1b/manim) | ManimGL，3b1b 原版；和 CE 不兼容，LLM 容易混用 | 94.3k / 2026-09 | MIT | B | 3b1b 风格 |
| [3b1b/videos](https://github.com/3b1b/videos) | 3b1b 各期场景源码 | 11.3k | CC BY-NC-SA [NC] | 参考语料 | — |
| [ManimCommunity/manim-voiceover](https://github.com/ManimCommunity/manim-voiceover) | 给 Manim 配音，按词触发动画 | 0.3k / 2026-06 | MIT | A | 带旁白讲解 |
| [jeertmans/manim-slides](https://github.com/jeertmans/manim-slides) | Manim 动画做成可翻页演示 | 0.9k / 2026-09 | MIT | A | 学术报告 |
| [adithya-s-k/manim_skill](https://github.com/adithya-s-k/manim_skill) | CE 和 GL 的 Agent Skills，`npx skills add` 安装 | 1.1k / 2026-01 | MIT | A | 直接给 Claude Code |
| [AmitSubhash/3brown1blue](https://github.com/AmitSubhash/3brown1blue) | 3b1b 风格的讲解 skill，含 paper-explainer 规则 | 36 / 2026-06 | MIT | A | 讲解、论文 |
| [showlab/Code2Video](https://github.com/showlab/Code2Video) | Planner/Coder/Critic 生成 Manim 教学视频 | 2.1k / 2026-08 | MIT | B（研究管线） | 教学视频 |
| [HarleyCoops/Math-To-Manim](https://github.com/HarleyCoops/Math-To-Manim) | 文本或图片生成数学物理动画（主线绑定 OpenAI） | 2.7k / 2026-09 | MIT | B | 数学科普 |
| [TIGER-AI-Lab/TheoremExplainAgent](https://github.com/TIGER-AI-Lab/TheoremExplainAgent) | 定理讲解视频 agent + benchmark | 1.5k / 2025-07 [停更] | MIT | B | 参考 |

## 3. 论文 → 视频

| 项目 | 说明 | ⭐ / push | License | CC |
|---|---|---|---|---|
| [showlab/Paper2Video](https://github.com/showlab/Paper2Video) | LaTeX → Beamer 幻灯片、字幕、光标、TTS、数字人；有不带数字人的快速模式 | 2.4k / 2026-03 | MIT | B（数字人要 NVIDIA GPU） |
| [icip-cas/PPTAgent](https://github.com/icip-cas/PPTAgent) | 论文或文档生成 PPT | 5.1k / 2026-09 | MIT | B |
| [souzatharsis/podcastfy](https://github.com/souzatharsis/podcastfy) | 论文或网页做成双人播客音频 | 6.6k / 2026-05 | Apache-2.0 | A |

对研究者更实用的做法：让 Claude Code 直接读 `.tex`，用 ManimGX 或 HyperFrames 出画面，再配 TTS。

## 4. 短视频自动化流水线

| 项目 | 说明 | ⭐ / push | License | CC |
|---|---|---|---|---|
| [harry0703/MoneyPrinterTurbo](https://github.com/harry0703/MoneyPrinterTurbo) | 给主题，自动文案、素材、TTS、字幕，出竖屏片 | 126.6k / 2026-09 | MIT | B（风格固定） |
| [ATH-MaaS/Pixelle-Video](https://github.com/ATH-MaaS/Pixelle-Video) | 文案 → ComfyUI 或 API 出图/视频 → TTS、BGM | 28.5k / 2026-06 | Apache-2.0 | B |
| [linyqh/NarratoAI](https://github.com/linyqh/NarratoAI) | 影视解说：文案、剪辑、配音、字幕 | 11.2k / 2026-09 | MIT | B |
| [HKUDS/ViMax](https://github.com/HKUDS/ViMax) | 导演、编剧、制片多 agent 生成叙事短片 | 12.5k / 2026-09 | MIT | B |
| [ArcReel/ArcReel](https://github.com/ArcReel/ArcReel) | 小说或剧本 → 分镜 → 视频 → 剪映草稿 | 5.2k / 2026-09 | AGPL-3.0 | B |
| [Huanshere/VideoLingo](https://github.com/Huanshere/VideoLingo) | 字幕翻译、对齐、配音 | 18.5k | Apache-2.0 | B |

## 5. Claude Code skills / 模板 / MCP

| 项目 | 说明 | ⭐ / push | License | CC |
|---|---|---|---|---|
| [remotion-dev/skills](https://github.com/remotion-dev/skills) | Remotion 官方 skills，`npx skills add remotion-dev/skills` | 4.8k / 2026-09 | 受 Remotion License 约束 | A |
| HyperFrames 自带 skills | `/faceless-explainer`、`/product-launch-video`、`/music-to-video`、`/pr-to-video`、`/embedded-captions` 等；[hyperframes-launches](https://github.com/heygen-com/hyperframes-launches) 是 HeyGen 发布会视频源码，可当范例 | — | Apache-2.0 | A+ |
| [JohnHeibel/ClaudeAnimationBase](https://github.com/JohnHeibel/ClaudeAnimationBase) | p5.js + p5.brush 手绘入门工程，含 `ANIMATION_GUIDE.md` 和自查渲染器 | 0.5k / 2026-09 | MIT | A |
| [JohnHeibel/PDoomVideo](https://github.com/JohnHeibel/PDoomVideo) | P(doom) MV 全部源码，含分镜和 subagent 指南 | 1.4k / 2026-09 | 无 license，仅参考 | 范例 |
| [WinterArc21/Battle-of-Austerlitz-Film](https://github.com/WinterArc21/Battle-of-Austerlitz-Film) | 5 分钟 WebGL2 历史长片的全部源码：真实 SRTM 地形、Kokoro 离线旁白决定镜头时长、从画面推导带距离和声像的音效、代码合成配乐；深读见 `cases/opus55-gallery.md` 第 6 节 | 12 / 2026-09 | 无 license，仅参考 | 范例 |
| [buildwithhanif/claude-animation-skill](https://github.com/buildwithhanif/claude-animation-skill) | 纯代码手绘 2D 动画：细节圣经、带解剖结构的角色骨架、毛笔水彩笔刷；`verify` 检查乱序渲染一致性，编码失败不覆盖旧文件；Node canvas + ffmpeg，不用浏览器和 GPU | 21 / 2026-09 | MIT | A |
| [Rieranthony/product-film-skill](https://github.com/Rieranthony/product-film-skill) | 产品片 skill：从设计系统写出 `BRAND.md`，先交 3 张风格帧，240 fps 母版做运动模糊，`verify.py` 解码检查成品 | 358 / 2026-09 | MIT（Remotion 另有许可） | A |
| [kuhnhomeuk-cell/procedural-film](https://github.com/kuhnhomeuk-cell/procedural-film) | 题材 → 30 秒竖屏片，纯 JS 绘制和合成声音，零素材；一镜一个 agent、评审波次、六项关卡 `check.cjs`；另有像素复古模式和一个可玩游戏 | 460 / 2026-09 | MIT | A（很耗额度） |
| [athemeroy/awesome-opus-5-5-videos](https://github.com/athemeroy/awesome-opus-5-5-videos) | Opus 5.5 视频的研究型目录：168 条逐条核对来源、7 条制作路径、配色模式研究、制作 brief 模板、视觉效果适配指南 | 318 / 2026-09 | CC BY 4.0 | 参考资料 |
| [zhuyansen/awesome-opus-5.5-video](https://github.com/zhuyansen/awesome-opus-5.5-video) | 962 支 Opus 5.5 作品的元数据目录（`cases.json`），prompt 原文在网页版上；见 `cases/opus55-gallery.md` 第 5 节 | 33 / 2026-09 | 无 license，仅参考 | 参考资料 |
| [digitalsamba/claude-code-video-toolkit](https://github.com/digitalsamba/claude-code-video-toolkit) | `/setup`、`/video` 命令加模板；TTS、图像、音乐模型部署在自己的云 GPU | 2.1k / 2026-09 | MIT | A |
| [geekjourneyx/hyperframes-motion-director](https://github.com/geekjourneyx/hyperframes-motion-director) | 中文优先的 HyperFrames 动效 skill | 0.45k / 2026-07 | AGPL-3.0 | A |
| [iart-ai/motion-skills](https://github.com/iart-ai/motion-skills) | 动效和 kinetic typography skills | 0.5k | MIT | A |
| [carlosh7/blender-mcp](https://github.com/carlosh7/blender-mcp) | blender-mcp-ultra：248 工具的 Blender MCP（token 认证 + AST 双侧拦截，headless 可用）；本仓库 Blender 引擎探索阶段的推荐，专页 `engines/blender-mcp-ultra.md` | 13 / 2026-08 | MIT | A- |
| [ahujasid/mcp-for-blender](https://github.com/ahujasid/mcp-for-blender) | 用 LLM 控制 Blender（原 blender-mcp）；无认证 socket + 裸 exec，仅作对照 | 29.5k / 2026-09 | MIT | B |
| [samuelgursky/davinci-resolve-mcp](https://github.com/samuelgursky/davinci-resolve-mcp) | DaVinci Resolve MCP（需 Studio 版） | 3.2k / 2026-09 | MIT | B |
| [GuanYixuan/pyJianYingDraft](https://github.com/GuanYixuan/pyJianYingDraft) | Python 生成剪映草稿，出草稿后手动精修 | 4.5k / 2026-09 | Apache-2.0 | A |

## 6. 配套组件

**TTS**

| 项目 | License | 说明 |
|---|---|---|
| [Blaizzy/mlx-audio](https://github.com/Blaizzy/mlx-audio) | MIT | Mac 首选，Apple Silicon 本地跑 Qwen3-TTS、Kokoro 等 |
| [QwenLM/Qwen3-TTS](https://github.com/QwenLM/Qwen3-TTS) | Apache-2.0 | 中文和方言，声音设计和克隆 |
| [QwenAudio/CosyVoice](https://github.com/QwenAudio/CosyVoice) | Apache-2.0 | 中文强，零样本克隆 |
| [RVC-Boss/GPT-SoVITS](https://github.com/RVC-Boss/GPT-SoVITS) | MIT | 1 分钟样本克隆，中文社区最成熟 |
| [index-tts/index-tts](https://github.com/index-tts/index-tts) | [自定义] | 情感和时长可控，适合卡时长 |
| [rany2/edge-tts](https://github.com/rany2/edge-tts) | LGPL-3.0 | 免费调微软中文音色；非官方接口，可能失效 |
| fish-speech、F5-TTS 权重、ChatTTS | [NC] | 商用避开 |

**时间戳 / 对齐**

| 项目 | 说明 |
|---|---|
| [ggml-org/whisper.cpp](https://github.com/ggml-org/whisper.cpp) | Mac 上 Metal 加速；Remotion 的 template-tiktok 用它 |
| [modelscope/FunASR](https://github.com/modelscope/FunASR) | 中文首选，字级时间戳和标点 |
| [m-bain/whisperX](https://github.com/m-bain/whisperX) | 词级对齐 + 说话人分离；Mac 上只能 CPU |
| [MahmoudAshraf97/ctc-forced-aligner](https://github.com/MahmoudAshraf97/ctc-forced-aligner) | 已知文本（歌词、讲稿）对齐到音频 |

**节拍 / 音乐分析**：[librosa](https://github.com/librosa/librosa)（ISC）、[beat_this](https://github.com/CPJKU/beat_this)（MIT，高精度 downbeat）、[demucs](https://github.com/adefossez/demucs)（MIT，分离人声和伴奏）。

**画风与动画库**：[p5.brush](https://github.com/acamposuribe/p5.brush)（水彩、笔刷）、[rough.js](https://github.com/rough-stuff/rough)（手绘风，稳定但停更）、[perfect-freehand](https://github.com/steveruizok/perfect-freehand)（压感笔迹）、[excalidraw-animate](https://github.com/dai-shi/excalidraw-animate)（白板逐笔）、[GSAP](https://github.com/greensock/GSAP)（免费含商用，非 OSI）、[anime.js](https://github.com/juliangarnier/anime)、[lottie-web](https://github.com/airbnb/lottie-web)、[three.js](https://github.com/mrdoob/three.js)。

**数据可视化**：[d3](https://github.com/d3/d3)、[echarts](https://github.com/apache/echarts)、[vizzu-lib](https://github.com/vizzuhq/vizzu-lib)（图表之间的形变过渡）。

## 7. 生成式视频与数字人（要 NVIDIA GPU 或云端）

- 生成式视频：[ComfyUI](https://github.com/Comfy-Org/ComfyUI)（有 API）、[Wan2.2](https://github.com/Wan-Video/Wan2.2)（Apache-2.0）、[LTX-2](https://github.com/Lightricks/LTX-2)（音视频一起生成，[自定义]）、[FramePack](https://github.com/lllyasviel/FramePack)。云端调用可走 fal 上的 Seedance 2.5、Veo 3.1、Kling。
- 数字人：[InfiniteTalk](https://github.com/MeiGen-AI/InfiniteTalk)（音频驱动，时长不限，Apache-2.0）、[LivePortrait](https://github.com/KlingAIResearch/LivePortrait)（依赖模型 [NC]）。SadTalker、Wav2Lip、LatentSync 已停更。
