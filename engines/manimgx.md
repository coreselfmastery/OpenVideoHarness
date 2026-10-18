# ManimGX 引擎指南（数学/科学讲解的首选）

[ManimGX](https://github.com/academa-labs/manimgx)（Academa，2026-10 开源，MIT 源码）把 Manim CE 的 Python API 搬到 Rust/wgpu GPU 核心上：同一套 `Scene`/`MathTex`/`self.play` 写法，逐帧用 GPU 画，Typst 排公式，x264 在进程内直接出 MP4。本仓库的 math、paper 两类视频（`bin/vh new math|paper`）从 2026-10-18 起都用它；安装、四类画幅、迁移注意在 [`README.md`](README.md) 的 ManimGX 一节，本页讲引擎本身的用法、GPU、回退和排障。

## 要点

| | |
|---|---|
| 版本（实测） | manimgx 0.1.1，Python ≥ 3.13（3.13/3.14；uv 会自己下载） |
| 依赖 | 无：不装 LaTeX、ffmpeg、cairo、pango；Linux 无 GPU 时 wheel 自带 lavapipe（CPU 画） |
| 速度 | 官方基准 1080p60 比 CE 快 90.6 倍（M4 Pro，从启动到 MP4）；本仓库 Fourier 片在 2 核 CPU 上：草稿 480p15 约 11 s、成片 1080p30 约 40 s（25 s 片长） |
| 检查 | `manimgx inspect` 自带 2D 布局检查（文字重叠/出画面/过小字），有问题 exit 1 |
| 确定性 | 同机同参重复渲染，输出逐字节相同（实测 4 连渲 md5 一致）；官方回归测试也要求逐像素相同 |
| 许可证 | 源码 MIT；**带 x264 的二进制 wheel 整体是 GPL-3.0-or-later**（见文末） |

## 什么时候用 ManimGX

- **math / paper 类**：3Blue1Brown 式原理动画、公式推导、论文讲解。它是这两类的默认引擎（`bin/vh new` 的路由表）。
- **agent 的迭代循环**：ManimGX 就是为 agent 设计的——`inspect` 不出视频先查布局，草稿 `-r 854x480 --fps 15` 十秒级出片，改一版渲一版，把"渲一次几分钟"变成"渲一次一轮单测"。写场景前读 `references/repos/3brown1blue/src/three_b1b/skill/SKILL.md` 开头的 Gotchas（CE 的坑大多还在，API 相同）。
- **3D**：每个场景的相机都能动（没有单独的 MovingCameraScene）；3D 光照来自 Filament 的移植（PBR 材质、环境光、AO、bloom、AgX 色调映射），mesh 可贴纹理。3D 场景 `inspect` 出分镜和时间线，但跳过 2D 布局检查。
- **配音和按词触发**：`self.say("…[x squared]…", anim1, anim2)` 把动画对到方括号里的词上（替代 manim-voiceover），`self.add_sound("click.wav")` 加音效，`self.next_section("name")` 分节后 `manimgx present` 当幻灯片放。本仓库自己的音频先行管线（`tools/build_audio.sh`、timeline、foley）照旧，两边不冲突。

不适合的场合见[什么时候还是用 CE](#什么时候还是用-manim-ce)。

## 写 → 查 → 渲

```bash
bin/vh new math <slug>          # 建项目（自动 uv init --bare --python 3.14 && uv add manimgx）
cd projects/<date>-<slug>

# 场景写在 scenes/*.py：import manimgx as m，一个 Scene 子类一个 construct
env -u UV_PYTHON uv run manimgx inspect scenes/x.py            # 分镜 + 时间线 + 布局检查，不渲染
env -u UV_PYTHON uv run manimgx render -r 854x480 --fps 15 scenes/x.py   # 草稿
env -u UV_PYTHON uv run manimgx render -r 1920x1080 --fps 30 scenes/x.py # 成片
```

（沙箱里全局 `UV_PYTHON` 指向旧 Python 时才需要 `env -u UV_PYTHON`；干净的机器和 Kaggle 上直接 `uv run manimgx`。）

`render` 的全部旗标（0.1.1 实测 `--help`）：

| 旗标 | 说明 |
|---|---|
| `-o, --output <path>` | 输出 MP4 路径；不写就放在**场景文件旁边** |
| `-r, --resolution WxH` | 像素；默认场景 config（1920×1080）。4K 用 `-r 3840x2160` |
| `--fps <int>` | 帧率；默认场景 config（60）。CE 的 `-ql/-qh` 没了，用 `-r` + `--fps` 组合 |
| `--preset <ultrafast…placebo>` | x264 预设，默认 medium；草稿可 veryfast 换速度 |
| `--crf <0..51>` | 质量，默认 23；成片 18–19 更接近本仓库的交付习惯 |

- 文件里有多个 Scene 时，命令行给名字：`manimgx render scenes/x.py MyScene`。
- `render` 也会在视频旁边写分镜 PNG（每个 play 的结束帧、布局问题圈号标注），场景说话或带字幕时再写 `.srt`。
- `inspect -t 1.5,end` 只查指定时刻；`-o detail.png` 命名输出图。没给 `end` 就在最后一个请求时刻后停。
- 从 Python 调：`film = MyScene().render(video="out.mp4", preset="veryfast", crf=23)`，返回的 `film.export` 有引擎实测数：`seconds`（起渲到写完）、`x264`（编码线程耗时）、`converted`（16×16 块真正转换的比例，其余跳过）、`bytes`。基准脚本 `tools/manimgx_bench.sh` 用它出数。
- 出错时报出场景里出错的那一行；名字写错有提示（`ShowCreation` → "is Create in ManimGX"）。

## 与 Manim CE 的差异（写代码前读一遍）

大部分 CE 代码把 `manim` 换成 `manimgx` 就能跑；行为差异和改名（`MovingCameraScene`→`Scene`、`ApplyMethod`→`.animate`、`arrange_submobjects`→`arrange` 等）见官方 "Coming from Manim CE"。本仓库实测踩过的：

- `from manim import *` → `from manimgx import *`（或 `import manimgx as m`）；**`import numpy as np` 要显式写**（CE 是 manim 带进来的）。
- `manimgx` 导出一个 `Path` mobject 类，会把 `pathlib.Path` 盖掉：场景文件里 `from pathlib import Path as FsPath` 起别名。
- `rate_functions.smooth` 这类模块路径没了，函数都在包上：`m.smooth`、`m.ease_in_out_sine`。
- 没有 `manim.cfg`：画幅、帧率在场景里 `m.config.pixel_width/pixel_height/frame_rate` 或命令行 `-r/--fps`。
- **竖屏的 frame 不一样**：ManimGX 的短边恒为 8 个单位（竖屏 8 宽 × ~14.2 高；CE 竖屏是 4.5 宽）。横屏场景只要内容在中间 8×8 方块里，竖屏直接能用。
- `Tex`/`MathTex` 走内置 mitex → Typst（New Computer Modern，与 CE 的 CMU 同源）：**LaTeX 宏包和 `\def` 不支持**，报错带 TypstError。
- 每个关键字参数都有类型，用 [ty](https://docs.astral.sh/ty/) 能在渲染前查出拼错的参数（运行时大多静默忽略不认识的关键字）。
- 公式分部（part-splitting）用双花括号：`MathTex("{{a^2}} + {{b^2}}")`；CE 老代码里 `isolated_substrings` 一类的写法按这个改。

## GPU：Linux、Kaggle T4×2

**它怎么选 GPU**：Linux 上走 Vulkan，wgpu 自动拿"高性能 adapter"（macOS Metal、Windows D3D12）。adapter 必须支持 float32 渲染目标混合 + `depth32float-stencil8` 深度模板，缺一样就拒收，然后落到 wheel 自带的 lavapipe（CPU 画，不用装任何东西）。每个进程一个 GPU，在进程确定要画时于自己的线程上起来（`--version`、纯计数这类永远不碰 GPU）。

**要让 Kaggle 的 T4 真正被用上**（默认镜像里 Vulkan loader 不一定在）：

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh   # uv（Kaggle 镜像没有）
sudo apt-get install -y libvulkan1 vulkan-tools    # Vulkan loader + vulkaninfo
vulkaninfo --summary | grep -A2 -i "GPU id"        # 能看到 Tesla T4 即成功
# 万一 nvidia_icd.json 不在默认位置：
export VK_ICD_FILELIST=/usr/share/vulkan/icd.d/nvidia_icd.json
```

验证（A 类任务的做法，脚本化在 `tools/manimgx_probe_gpu.sh`）：渲染时另开一格跑 `nvidia-smi`，看到 python 进程挂在 GPU 0 上、利用率有起伏，就是真用了 T4；只看耗时不可靠，CPU lavapipe 慢但能跑完。

**怎么把渲染钉在某一块 T4 上（G3 的结论，实测过）**：

- **钉不了，0.1.1 没有 adapter 旗标**（`render --help` 只有 `-o/-r/--fps/--preset/--crf`）。
- **`CUDA_VISIBLE_DEVICES` 对 Vulkan 无效**：它只过滤 CUDA 设备，NVIDIA 的 Vulkan ICD 不读它（llama.cpp 的 Vulkan 维护者在 ggml-org/llama.cpp#5259 里明确说过，为此他们才做了 `GGML_VK_VISIBLE_DEVICES`）。拿它当 ManimGX 的 GPU 开关是白设。
- 两块 T4 一样快，wgpu 每次都选第一块：**多个 ManimGX 进程都会落在 GPU 0**。这不是问题——1080p 渲染吃不满一块 T4，T4 有 16 GB 显存，实测两个进程并发渲染互不干扰、输出仍逐字节相同（详见 [`manimgx-advanced.md`](manimgx-advanced.md) 的 H6）。
- **GPU 1 留给 CUDA 活**：PyTorch/扩散模型这类认 `CUDA_VISIBLE_DEVICES=1` 的负载放第二块卡，和 ManimGX 的渲染并行。
- 真要"每容器一块卡"的隔离，得靠设备节点掩蔽（Docker `--gpus device=N`），Kaggle 笔记本里用不上。

## 什么时候还是用 Manim CE

本仓库不再随装 CE，math/paper 一律 ManimGX；下面几种情况按需给**单个项目**配一个 CE venv（`uv venv --python 3.12 && uv pip install manim`，CE 要系统里有 cairo/pango），场景代码按上面的差异表把 import 换回去即可：

- **许可**：ManimGX 的 wheel 因为内置 x264 整体是 GPL-3.0-or-later。如果你的片子/管线在法律上不能引入 GPL 二进制（公司合规、某些商业交付），CE（MIT）是替代——先读文末许可证一节，多数"发布成片"的场合并不触发。
- **API 还没实现**：0.1.x 很年轻，个别 CE 类/参数没有（`inspect`/`render` 的报错会点名缺什么）。等上游补，或这一支临时用 CE。
- **环境锁死旧 Python**：机器只有 <3.13 且装不了新解释器时，CE 支持 3.9–3.13。
- **要和 CE 的像素逐位对齐**：跨引擎对拍（旧片复刻、回归基线）没有意义，两家连抗锯齿模型都不同；真需要 CE 的历史输出就留在 CE 里渲。

路由原则：**默认 ManimGX；上面四条命中一条，才在项目 NOTES.md 里记下"此支用 CE"并写明原因**。不要因为"CE 更熟"回退——迁移成本只有差异表那几行。

## Kaggle 故障排查（G5）

| 症状 | 原因 | 处理 |
|---|---|---|
| 渲染速度像 CPU（1080p30 一分钟级），`nvidia-smi` 里没有进程 | `libvulkan1` 没装，wgpu 枚举不到 NVIDIA，静默落到自带 lavapipe | `sudo apt-get install -y libvulkan1`；`vulkaninfo --summary` 看到 T4 后重渲 |
| `vulkaninfo` 有 T4，还是慢 | `nvidia_icd.json` 不在 loader 默认路径 | `export VK_ICD_FILELIST=/usr/share/vulkan/icd.d/nvidia_icd.json`（先 `dpkg -L libnvidia-gl-* \| grep icd` 找到它） |
| `no GPU adapter` 报错 | 命令跑在把 GPU 藏起来的沙箱里 | 在沙箱外跑（Docker 加 `--gpus all`；agent 的沙箱配置放行 GPU） |
| `uv run manimgx` 报 Python 版本不符 | 全局 `UV_PYTHON`/`VIRTUAL_ENV` 指向 3.12 | `env -u UV_PYTHON uv run …`，或 `uv python pin 3.14` |
| 带材质的 3D 场景 GPU 校验失败 | 0.1.0 的 bug，材质 mesh 和普通 mesh 混用时触发 | 升到 ≥ 0.1.1（`uv lock --upgrade-package manimgx`） |
| 每次 session 首渲都偏慢、Typst 首排版卡 | 布局/字体缓存在 `~/.cache/manimgx`，Kaggle 重启即失 | `export MANIMGX_CACHE_DIR=/kaggle/working/mgx-cache` 持久化 |
| 两个渲染进程同时跑报错 | 0.1.1 已知问题已修（透明重试期间的资源回收，上游 #16） | 升到 ≥ 0.1.1；并发输出路径别写同一个文件 |
| 渲染中 OOM 被杀 | Kaggle 13 GB RAM，不是显存问题（T4 16 GB 够用） | 关掉别的 notebook 会话；4K 草稿改 1080p 草稿 |

第一格先跑 `tools/manimgx_probe_gpu.sh`（见下），它把上面前五行一次性查完并给出结论。

## 渲染缓存与提速工具

| 工具 | 干什么 |
|---|---|
| `tools/manimgx_probe_gpu.sh` | GPU 确认：nvidia-smi / libvulkan1 / ICD / vulkaninfo / 渲染时 GPU 利用率采样，给出 "T4 VULKAN OK / LAVAPIPE 回退" 结论 |
| `tools/manimgx_bench.sh` | 测速：草稿 + 成片（可选 4K）各 N 轮，解析 `(rendered in X s)`，出 markdown 表（Kaggle 上跑完贴回来） |
| `tools/manimgx_render.sh` | 场景级渲染缓存：场景源码 + 旗标 + 版本取哈希，没变就跳过重渲（草稿迭代省时间） |

深入的话题——引擎缓存了什么、Vulkan 队列能不能调、显存怎么管、渲染和编码是否已并行、多进程并发实测——在 [`manimgx-advanced.md`](manimgx-advanced.md)，改性能前先读它。

## 与本仓库管线的接法

- **音频先行**照旧：`tools/build_audio.sh` 出 mix，ManimGX 的 `say`/`add_sound` 不用就不和它冲突；要按词触发时用 `say`（它自己配音）或按 timeline 的时间写 `self.play(..., run_time=)` 对拍。
- **交付重编码不变**：GX 输出是 limited-range 带标签（matrix smpte170m / transfer sRGB / primaries bt709）；混音那步本来就要重编码，按 playbook/10 交付编码到 BT.709 的规则照走。CE 时代"无标签被当 BT.709 读、黄色变 (255,240,0)"的坑不再出现。
- **数学核对**：`showcase/03-math-fourier/tools/verify_math.py` 用 `uv run --with scipy python …`（scipy 不是 manimgx 的依赖）。
- **画面审计**：锚点网格和包围盒审计抄 `showcase/03-math-fourier/scenes/style.py`；像素抽查用 ffprobe/ffmpeg 按 NOTES.md 的做法。

## 流程与验证

1. 写完先 `manimgx inspect`：布局问题（文字叠字、出画面、小字）修到 exit 0，分镜图肉眼过一遍。
2. 草稿 `-r 854x480 --fps 15 --preset veryfast`，看节奏和构图（字体、接缝以渲出的 mp4 为准，别只看分镜）。
3. bbox 审计（style.py 的锚点网格）+ 关键帧像素抽查（对照色值）。
4. 成片 `-r 1920x1080 --fps 30`（或 4K）；确定性抽查：重渲一次比 md5，应逐字节相同（同机同参）。
5. 混音、交付编码走 `bin/vh mux`/`bin/vh deliver`。

## 许可证

ManimGX 源码 MIT；但 PyPI 的 wheel 里编进了 x264（GPL-2.0-or-later），**发行的二进制整体按 GPL-3.0-or-later**，还带 Typst 字体（Noto，OFL）和 lavapipe（Mesa，MIT）的 notices。用自己的场景渲染、把成片发布到平台，都不构成对 GPL 二进制的再分发；把 wheel 打进你再分发的产品里才需要按 GPL 办（和 Blender 指南里 bpy 的情况同类，见 [`blender.md`](blender.md) 的许可证一节）。上游在 `LICENSE-THIRD-PARTY`、`LICENSE-LAVAPIPE` 里给了完整清单。
