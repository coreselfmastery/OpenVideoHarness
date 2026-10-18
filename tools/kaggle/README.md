# 在 Kaggle（2×T4）上渲染 HyperFrames 片子

Kaggle 的免费 2×T4 实例（4 核 CPU、29 GB 内存）是这个仓库能用的最快的免费渲染机，但开箱什么都缺：Node 版本不对、ffmpeg 不一定带 NVENC、Chrome 要现下载，渲染命令本身还有几个不设就慢 3 倍的开关。这个文件夹是**一次 setup + 一条渲染命令**，长片还可以**两块卡同时画一支片子**。

在 notebook 里（Settings → Internet 打开，每个 `!` cell 都是新 shell，所以 `source` 写在命令行里）：

```bash
!git clone --depth 1 https://github.com/coreselfmastery/OpenVideoHarness.git /kaggle/working/OpenVideoHarness
%cd /kaggle/working/OpenVideoHarness
!bash tools/kaggle/setup.sh                    # 每个会话一次（首次 5–10 分钟，重启会话后秒级：缓存在 /kaggle/working）
!source .kaggle/env.sh && bin/vh new promo my-film        # 照常建项目（自动 bin/vh hf-init：GSAP 本地化、字体 local()）
# …写合成，source .kaggle/env.sh && npx hyperframes lint 到 0 error…
!bash tools/kaggle/render.sh projects/<date>-my-film --tier draft    # 评审稿（快）
!bash tools/kaggle/render.sh projects/<date>-my-film --tier final    # 成片（引擎自己的渲染器）
!bash tools/kaggle/render-split.sh projects/<date>-my-film --tier final   # 或：两块卡各画半支（最快出成片）
!source .kaggle/env.sh && bin/vh mux projects/<date>-my-film/renders/<成片>.mp4 <混音> <输出>.mp4   # 声音照常套上
```

在终端里（Kaggle 的 Terminal、或任何 Linux 机器）更简单：`source .kaggle/env.sh` 一次，之后所有命令都在。

也适用于任何 Linux GPU 机器；没有 GPU 时它同样工作（Chrome 走 SwiftShader、编码走 libx264），只是快不起来。开 Kaggle 笔记本时记得把 **Internet** 开关打开（Settings → Internet），`npx` 和 Chrome 下载都要联网。

## 两块 T4 怎么都用上

HyperFrames 一次渲染是两种负载：**Chrome 画帧**（DOM、CSS、GPU 光栅化、shader 转场）和 **ffmpeg 编码**（H.264）。有两条路把两块卡都用上，按片长选：

| 路 | 怎么用两块卡 | 适合 |
|---|---|---|
| `render.sh`（一支片子一个引擎渲染） | GPU 0 = 所有 Chrome worker（EGL 默认第一块卡）；GPU 1 = h264_nvenc 编码（`.kaggle/ffmpeg-gpu.sh` 给每条 NVENC 命令插入 ffmpeg 自己的 `-gpu 1`） | 一切片子；短片的唯一选择 |
| `render-split.sh`（一支片子两半同时画） | 每半各一个浏览器、各一个编码器：半支 A 的 NVENC 在 GPU 0、半支 B 的 NVENC 在 GPU 1，两个浏览器都留在 GPU 0 | ≥ 30 s 的长片，墙钟时间差不多减半 |

`nvidia-smi -l 1` 能看到：render.sh 时 GPU 0 画帧、GPU 1 编码；render-split.sh 时两块卡都各有一个 NVENC 会话，CPU 上两个浏览器并行画帧。Chrome 用不了第二块卡是 Chrome 的 EGL 设备选择没有命令行开关（`CUDA_VISIBLE_DEVICES` 到不了它——EGL 枚举设备在 Chrome 内部完成，不走 CUDA）；好在编码正是从渲染里卸下来的那部分负载，而且 T4 的 NVENC 是独立的硬件块，和光栅化不抢同一个 SM 时间片。

## setup.sh：探针，不是假设

`tools/kaggle/setup.sh [--no-persist] [--force-browser]` 每一步用的都是 HyperFrames 0.8.82 自己会做的同一个探测，所以**这里探不过的，渲染时也不会突然能用**；探过的才写进 `.kaggle/env.sh`：

- **Node ≥ 22**：Kaggle 镜像里的 Node 太旧或没有 → 从 nodejs.org 解一个 22 LTS 到缓存里（不用 sudo、不动 apt）。
- **ffmpeg**：按 `PATH` 和常见 bin 目录找第一个**同时有** `h264_nvenc` 和 `psnr` 滤镜的（Ubuntu 自带的都有；conda 的 ffmpeg 常常两个都没有）。
- **Chrome**：`npx hyperframes browser ensure`（仓库钉的 0.8.82）把 chrome-headless-shell 提前下好——否则第一次渲染要现场下载 5–10 分钟。
- **浏览器 GPU**：用 HyperFrames 自己的硬件参数（`--use-angle=gl-egl` 等）拉起 Chrome 问 WebGL renderer。
- **NVENC 逐卡探测**：每块卡上跑一次 320×240 的 `h264_nvenc` 测试编码（从最后一块卡往下试）。两块 T4 时编码钉在 GPU 1；只有 GPU 0 应答时退回 GPU 0 并说明。

`--no-persist` 不把缓存挪进 `/kaggle/working/.cache`（默认挪：npm、Chrome、hyperframes、uv 四个缓存换成软链，**保存的笔记本**重启会话后还在，省掉每个会话重新下载）。`.kaggle/` 里的生成物不进 git。

### 探针输出怎么读（A9/A10）

setup.sh 的每一行输出都是一个决定，照着读：

| 输出行 | 意思 | 接下来 |
|---|---|---|
| `✓ Node v22.x` / `✓ Node … from /kaggle/working/.cache/node/…` | Node 版本够（自带或现场解包） | 无 |
| `✓ ffmpeg version … — has h264_nvenc and psnr` | 编码器和快速捕获的检查滤镜都在 | 无 |
| `! … has no h264_nvenc: renders encode on the CPU` | ffmpeg 编了但没编 NVENC（conda 的常见） | `apt-get install ffmpeg` 后重跑 setup.sh；或接受 CPU 编码 |
| `✓ h264_nvenc works on GPU 1` | 两块卡的 NVENC 都应答；编码钉在 GPU 1 | 无——这正是两块 T4 的期望行 |
| `✓ h264_nvenc works on GPU 0 only …` | 高编号的卡没应答（容器只挂了一块） | 浏览器和编码共用 GPU 0，仍比 CPU 快 |
| `! h264_nvenc is compiled in but encodes on no GPU` | 驱动/容器挡住了硬件编码 | 检查 nvidia-smi；或接受 CPU 编码 |
| `✓ Chrome's WebGL renderer is hardware: NVIDIA T4 …` | 浏览器 GPU 探针的 GL_RENDERER 是 NVIDIA——**2×T4 上的期望输出**；`--browser-gpu` 和快速捕获都会被请求 | 无 |
| `! Chrome's WebGL renderer is software (…)` | GL_RENDERER 报了 SwiftShader / llvmpipe：浏览器走 CPU 光栅 | 见「排查」第一节 |
| `! Chrome gets no WebGL context through EGL` | 容器里 EGL 到不了 GPU | 同上 |

在真实的 Kaggle 2×T4 上，setup.sh 的结尾摘要应该是：`browser : GPU 0, hardware WebGL (NVIDIA T4…)`、`encode : GPU 1 (h264_nvenc)`、`both cards: render-split.sh … draws two halves at once`。任何一行不是这样，对应上表处理；**探针说过不行的，render.sh 不会再去要**（它只带探过的标志），渲染仍然出片，只是走的安全路径。

## render.sh 的决定

`tools/kaggle/render.sh <project> [options]`（其余参数原样传给 `hyperframes render`）：

| 决定 | 规则 | 为什么 |
|---|---|---|
| fps | 合成写了 `data-fps` 且 ≤ 30 → 保留（24 fps 的片子不会被动到）；没写 → 显式 `--fps 30`；写了 > 30 → 保留并提示一句 | 降帧率是最大的单项提速（约 48%），但片子自己的规格不该被工具悄悄改 |
| workers | **< 240 s：`--workers 1`**。≥ 240 s 且硬件 GPU：**不传 `--workers`**——并行快速捕获路由器只在 worker 数留给 auto 时才接手，把它钉在 3 个 worker 的并行流式捕获上；显式传了反而把路由器关掉。≥ 240 s 且软件渲染：**实测内存**说了算——min(空核数, 空闲 GB / 6 GB 一个浏览器, 6)，空闲内存从 cgroup（Kaggle）或 /proc/meminfo 读 | 短片多 worker 会把每一帧先落到盘上再编码（最长慢 8 倍）；长片的 3-worker 并行 DE 流是实测最快的路径；内存快满的机器要的是少开浏览器，不是 OOM |
| 编码 | NVENC 探测通过 → `--gpu`：编码钉在第二块 T4；带 `--tier` 时再由 `.kaggle/ffmpeg-gpu.sh` 重调（见下节） | CPU 那部分负载整个卸到 GPU 1；`bin/vh deliver` 的平台成片仍然 CPU libx264 CRF 16 重编码，交付质量不变 |
| 捕获 | 硬件 WebGL **且合成过引擎自己的四个编译门**才加 `--experimental-fast-capture`：CSS 3D 上下文、`mix-blend-mode`、合成根的祖先带 background-image、shader 转场（`HyperShader.init` / `__hf.transitions`）——0.8.82 的编译器检测到任何一个都会**悄悄**退回截屏，这里用同一套模式先扫一遍（祖先是真走 DOM 的，不是猜 html/body），命中就说明是哪一个、环境变量怎么覆盖（`HF_FAST_CAPTURE_3D` / `_BLEND` / `_ANCESTOR_BG` / `PRODUCER_EXPERIMENTAL_FAST_CAPTURE`） | 快速捕获（drawElement）长片最高 5×，但要了却用不上只是浪费一个开关；扫不出结果时保守走截屏 |
| 流式上限 | 永远把 `PRODUCER_STREAMING_ENCODE_MAX_DURATION_SECONDS` 设在**片长 + 60 s** | 引擎的流式编码有个时长上限，任何东西把它压到片长以下都会**静默**切到逐帧落盘（慢路径）；设到片长之上，就没有东西能在底下关掉流式 |
| 磁盘 | 开画前估算峰值（帧数 × 分辨率 × 经验码率），不够就说；连平片都放不下直接拒（exit 2） | `/kaggle/working` 上限 20 GB，别让渲染跑一半才死 |

`--detach` 把渲染放进后台（`HYPERFRAMES_RENDER_DETACHED=1`），打日志路径、pid 文件和停止命令；**只留最近 5 个日志**，旧的自动清掉。长渲染建议用它，notebook 的 cell 立刻返回。

## --tier：两级渲染（F7）

评审和交片是两个目标，一个词说清：

| | `--tier draft` | `--tier final` |
|---|---|---|
| 引擎质量档 | `--quality draft` | `--quality delivery` |
| NVENC（render.sh 路线） | **p4 / cq 28**（`--quality draft` 本身会选 p1 / cq 28——p1 是 NVENC 的最低档画质，p4 才是均衡档；T4 上两者速度都远超实时，p4 的评审稿好看得多） | **p7 / cq 19**（p7 是 Turing NVENC 的最好画质档） |
| x264（无 NVENC 机器） | `faster` / crf 28 | `medium` / crf 16 |
| render-split.sh 路线 | 半支 A 与 B 都 p4 / cq 28 | 半支 A 与 B 都 p7 / cq 19 |
| 不带 `--tier` | 引擎自己的 `--quality` 映射（looks → NVENC p4 / cq 16；`OVH_KAGGLE_TUNE=off` 同样回到引擎自己的） | 同左 |

`--tier` 是唯一入口：`--tier` 与 `--quality` 一起给会被拒（它们都说质量，给一个）。在 render.sh 路线上，tier 由 `OVH_KAGGLE_TIER` 环境变量传进 `.kaggle/ffmpeg-gpu.sh`——它在**引擎自己的** `-preset/-cq/-b:v` 后面把它们换成 tier 的值，GOP、色彩标签、滤镜一概不动；这个替换只碰引擎自己的渲染调用（那些命令从不带 `-gpu`，手写的 ffmpeg 命令原样放行）。

### NVENC 调速表（F8）

T4（Turing，SM75）的 NVENC 与 libx264 的视觉对照和速度（1080p30 实测量级）：

| 档 | NVENC 参数 | 对照 x264 | 速度量级 |
|---|---|---|---|
| draft | `-preset p4 -cq 28` | crf 28 / faster | 数十× 实时 |
| 成片（split） | `-preset p7 -cq 19` | crf 19 / slow 上下 | 数× 实时 |
| 引擎 looks | `-preset p4 -cq 16`（引擎自己的映射） | crf 16 / medium | 数十× 实时 |

两个细节：`-cq` 和 x264 的 `-crf` 同为 0–51 恒定质量标尺（数值越小质量越高）；p1–p7 是 NVENC 自己的档（p1 最快最糙 → p7 最慢最好），ffmpeg 把 x264 风格的 preset 名字映射过去（medium→p4、slow→p5……）。`render.mjs --encoder nvenc` 直接走 `--crf`/`--preset`（NVENC 参数原生），`patch.mjs` 从 sidecar 里读回同一套参数重渲——NVENC 片子的补丁仍是 NVENC，SPS/PPS 的一致性检查会拒绝混编。

## render-split.sh：一支片子两半同时画（F6）

`tools/kaggle/render-split.sh <project> [--tier draft|final] [--at 秒] [--gpu-a N --gpu-b N] [--workers N] [render.mjs 的其余参数] [--dry-run] [--keep] [--skip-determinism]`

**计划**：从 index.html 读片长、fps 和**合成自己声明的场景切点**（各 clip 的 `data-start`），在中间 ±¼ 片长的窗口里挑离中点（或 `--at`）最近的切点下刀——每一镜都完整地落在某一半里；没有切点就切正中帧。两半各由一个浏览器按仓库的页契约**逐帧精确**画出（`tools/film/render.mjs --frames`，就是 `bin/vh patch` 重渲镜用的同一条路），各配一个 ffmpeg：**半支 A 的 NVENC 在 GPU 0、半支 B 的 NVENC 在 GPU 1**，两个浏览器留在 GPU 0。画完三重校验后 **stream copy 拼接**（无重编码）：

1. 两半的编解码参数一致（codec/profile/level/尺寸/像素格式，不一致说明哪一半被重编码过）；
2. 半支 B 从关键帧开始（接缝是码流里真实的切点）；
3. 拼好的文件帧数 = 两半之和 = 全片帧数，字节数 ≈ 两半之和（stream copy 的直接证据）。

**安全性**：开画前先跑 `bin/vh determinism`——帧依赖它前面帧的页面（粒子、累积状态）会在切分下画出不同的帧，这个门把它拒掉（`--skip-determinism` 强行跳过，但别）。每半的 GOP 钉在 2 s，接缝正好落在关键帧上，所以拼好的片子 `bin/vh patch` 照常按关键帧补镜、`bin/vh mux` 照常套声音——sidecar 记录了切点、两半和各自的卡，patch 直接接着用（实测：split 成片上 patch 21–22 s，接缝外像素逐位相同，PSNR 门全过）。

**诚实的注意**（写在这里而不是脚注里）：两半是页契约画的，不是 `npx hyperframes render` 画的（那个渲染器渲染不了半支——0.8.82 与 0.8.169 都验证过没有跨中间态的入口）。仓库对这条路的信任有先例：`bin/vh patch` 每次补镜都这样画帧、PSNR ≥ 40 才拼回去，而补过的片子是交付过的片子。对照实测（32 s 测试片、同参数整渲 vs 切分）：**全片 PSNR 65.3 dB、接缝前后 ±0.3 s 55.3 dB**——远高于 patch 自己的 40 dB 门，视觉上无从分辨。所以：**交付的母片用 render.sh 的引擎渲染**（引擎注入的虚拟时间、GSAP 补间缓冲与页契约略有差异，见 hf-adapter.js 头注）；**墙钟时间要紧的长片（配额压力、赶评审）用 split**，或一轮评审两档同时出。

`--dry-run` 打印切点和两条半支命令不画一格；`--keep` 保留两半和日志；Ctrl-C（或 Kaggle 的 Interrupt）无论落在哪个阶段都带走该阶段的一切、一个文件都不留——落在确定性门上就带走门自己的浏览器（门在后台跑着，停止陷阱才够得着它），落在两半上就经 `exec node` 直达 render.mjs 的停止清理，各自删掉自己的分块。

## 提速清单的落地情况

对照 HyperFrames 自己的调优表，在这套里各自落在哪：

| 手段 | 落地 |
|---|---|
| fps 30（或 24） | render.sh 按上面的规则；`--fps` 可覆盖 |
| `HF_DE_PARALLEL_ROUTER=true` | env.sh 常备（忘了它长渲染慢 3 倍；设成环境变量还躲开 HyperFrames 的“失败一次就静默关掉”熔断） |
| GPU 编码 `--gpu` | NVENC 探测通过自动加，钉在第二块 T4 |
| 浏览器 GPU `--browser-gpu` | WebGL 硬件探测通过自动加 |
| 两块卡画一支片子 | render-split.sh（≥ 30 s 长片；render.sh 打印提示） |
| worker 数 | render.sh 按片长和实测内存定（上面） |
| 两级渲染 `--tier` | draft = `--quality draft` + NVENC p4/cq 28；final = `--quality delivery` + NVENC p7/cq 19 |
| 流式编码不被时长上限关掉 | render.sh 永远设上限 = 片长 + 60 s |
| 简化贵 CSS | 仍是写作时的事：少叠大 `backdrop-filter` / `filter: blur()`，静态模糊预渲成 PNG（engines/README.md） |
| MP4 不用 WebM | 默认就是 MP4（VP9 编码在 CPU 上） |
| Chrome 缓存 | setup.sh 的 `browser ensure`，会话间留在 /kaggle/working |
| CDNs 本地化 | `bin/vh hf-init` 已经做（GSAP 进 node_modules） |
| 字体全声明 | `bin/vh hf-init` 已经做（local() @font-face） |
| lambda / cloudrun 分布式 | 不适用于 Kaggle（要云账号）；同一台机器上 `--workers` 和 render-split 就是并行 |
| HTML-in-canvas 快速捕获 | 硬件 GPU 且过引擎四个编译门时 render.sh 显式开（Linux 上默认关） |
| 分辨率分层 480p/720p/1080p | HyperFrames 的 `--resolution` 只接受整数倍预设（1080p、4K），没有 480p/720p；迭代提速靠 `--tier draft`，4K 靠 `--resolution 4k` |
| 预计算共享素材 | 写作时的事（logo、背景、字体一次画好），engines/README.md 的规则不变 |
| 只重渲改动的镜 | canvas 片子 `bin/vh patch`（本仓库自己的）；见下面研究一节对 HyperFrames 片子的结论 |

## 质量没有让步的地方

- fps、worker、捕获路径、编码器只影响**速度或码率结构**，不影响画面内容；唯一动画面的杠杆（帧率）保留给合成作者。
- NVENC 母片按恒定质量档编码（Turing NVENC 与 libx264 视觉接近，见上表）；要上传的平台成片由 `bin/vh deliver` 照常 CPU libx264 CRF 16 重编码，交付链路没变。
- render-split 的切分只动“谁画哪一段”，每帧仍逐帧精确；切点落在场景切点上，接缝是关键帧上的 stream copy（三重校验见上）。它退回 render.sh 的条件（< 30 s、determinism 不过、无场景切点时也只在正中帧下刀）都写明在输出里。
- `bin/vh check`、`textcheck`、readcheck 等一切检查照常工作（Chrome 的缓存路径没挪出 `~/.cache` 的查找范围，只是换成了软链）。

## 研究结论（C7/C8/D8/H7–H10/I3/I4）

对着 hyperframes 0.8.82 的 dist（`styles/_swatch/node_modules/hyperframes`）和 0.8.169（写本文时验证过）逐条查过，结论和证据：

- **C7 · 切分到底快多少**：两个浏览器并行画帧 + 两个 NVENC 各在一块卡 = CPU 画帧侧近似减半，编码侧互不等待。32 s 测试片上实测：整渲 48 s → 切分 31 s（本沙箱 2 核）。真实瓶颈是画帧（每帧 ~50 ms）时接近 2×；瓶颈在编码或 GPU 0 光栅时收益小于 2×。**别期待超过 2×**：两半加起来就是全部工作量，只是不再排队。
- **C8 · 超过两块卡**：本脚本是 A/B 两段。多于两块卡时同构可扩（N 段 N 个 NVENC），但浏览器全部留在 GPU 0 会成为新瓶颈；Kaggle 就是 2×T4，两段是甜点，没有为不存在的机器做通用化。
- **D8 · 接缝在别的播放器上**：`-movflags +faststart` + 关键帧上的 stream copy + 两半参数一致 = 播放器看到的是一支普通 MP4（时间戳由 concat 复制，无负值无空洞）。帧数校验（拼接后 = 两半之和）排除丢帧/重复；`bin/vh check` 照常能读它的色彩标签。
- **H7 · Chrome 会话跨渲染复用**：0.8.82 每次渲染起自己的浏览器池、会话结束即拆（dist 里 browserPool 生命周期跟渲染走），跨渲染复用要改引擎本体。浏览器冷启动 ~2–5 s，对分钟级渲染占比 < 5%，收益配不上风险（会话残留状态正是 determinism 要防的东西）。**结论：不做**；Chrome 二进制本身已被 setup.sh 缓存（下载才是大头）。
- **H8 · 逐镜缓存（只重渲改动的镜）**：引擎没有场景级缓存；HyperFrames 片子的时间轴是连续 DOM/GSAP 状态，安全切分需要 determinism（render-split 已经这样门控）。对 canvas 页契约片子，`bin/vh patch` 已实现“只重画一段拼回去”；对 HyperFrames 片子，等价能力 = render-split 的半支重渲 + patch，已够用。**结论：不另做引擎级逐镜缓存**。
- **H9 · Skia GPU / EGL 路由 2D 矢量**：`--browser-gpu` 走的就是 ANGLE-over-EGL（`--use-angle=gl-egl --enable-gpu-rasterization`，setup.sh 探针用的同一组 flag）——2D canvas 的光栅化已经在 GPU 0 上。再往下（Skia Vulkan、`--use-gl=desktop`）在 headless 容器里稳定性陡降，收益没有实测依据。**结论：现有路由即是答案**。
- **H10 · `CUDA_VISIBLE_DEVICES` 能否隔离 Chrome**：**不能**。Chrome 的 GPU 选择走 EGL 设备枚举（ANGLE），不读 CUDA 的环境变量；NVENC 侧则可以用 ffmpeg 自己的 `-gpu`（本套用的）或 `CUDA_VISIBLE_DEVICES`。这就是“浏览器留在 GPU 0”的原因，也是为什么隔离两个 NVENC 用 `-gpu` 而不是环境变量。
- **I3 · 更激进的 Chrome flag**：dist 里引擎已带 `--disable-dev-shm-usage`、deterministic 模式等；再叠 `--disable-gpu-watchdog`、`--ignore-gpu-blocklist` 之类对吞吐无实测收益，且有的会在某些驱动组合下改变渲染路径（= 改变画面）。**结论：不加引擎没带的 flag**。
- **I4 · WebGL 纹理零拷贝进 NVENC**（Chrome 画到 GPU 面、ffmpeg 直接编码，不过 JPEG/管道）：Chrome headless 没有导出 GPU surface 给外部进程的通道（CDP screencast 是压缩帧，drawElement 是 DOM 读回）。引擎自己的快速捕获已经省掉了截屏路径里最贵的一步；零拷贝要 Chrome/ffmpeg 两边同时改。**结论：当前最快的可用路径就是快速捕获 + NVENC，零拷贝不在 0.8.x 的能力范围**。

## 排查

- **`browser GPU` 一行说 CPU/SwiftShader**：容器里 EGL 到不了 GPU（驱动库没挂全）。浏览器负载回到 CPU，`--browser-gpu` 和快速捕获自动不请求。渲染还是能出片，只是慢。
- **`encode` 一行说 CPU（libx264）**：ffmpeg 没有 NVENC，或 NVENC 在容器里被挡（探测失败）。`apt-get install ffmpeg`（Ubuntu 源里的构建带 NVENC）后重跑 setup.sh。
- **`capture` 一行说 screenshots（合成用了 …）**：不是故障——合成里有 3D / blend / 祖先背景 / shader 转场，引擎本来就会退回截屏；要强行用快速捕获，按提示设对应的环境变量（画面自负）。
- **render-split 说 determinism 不过**：页面有依赖历史的帧（粒子、累积状态）。要么修页面（把这些状态做成 t 的纯函数——engines/CONTRACT.md 本来就要求），要么整支用 render.sh，要么 `--skip-determinism` 自担。
- **渲染命令完成了但进程迟迟不退**：HyperFrames 0.8.82 在个别机器上收尾慢（浏览器池的关闭竞态）。输出文件在完成横幅出现时就已经写好；等它自然退出，或长渲染用 `--detach`。
- **磁盘**：`/kaggle/working` 上限 20 GB，缓存占约 1 GB；render.sh 开画前会估峰值并提醒，连平片都放不下会直接拒绝而不是跑一半死。
- **GPU 配额**：Kaggle 每周约 30 小时。draft 用 `--tier draft`、长片用 render-split 两块卡一起跑、只重渲改动的镜（canvas 片子有 `bin/vh patch`），把配额花在成片上。

## 测试

`tools/kaggle/test.sh`（`tools/ci.sh` 自动跑它）用**桩**验证 setup.sh 的每个探针、ffmpeg 包装器的 tier 重调（引擎真实参数形状的 12 种情况）、render.sh 的全部决定和错误路径、render-split 的计划数字；有 Chrome 的机器上再跑**真**的 32 s 切分渲染：determinism 门、两半并行、三重拼接校验、sidecar 落点、打断后一个文件都不留。89 项断言，全部绿才许过。
