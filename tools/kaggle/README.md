# 在 Kaggle（2×T4）上渲染 HyperFrames 片子

Kaggle 的免费 2×T4 实例（4 核 CPU、29 GB 内存）是这个仓库能用的最快的免费渲染机，但开箱什么都缺：Node 版本不对、ffmpeg 不一定带 NVENC、Chrome 要现下载，渲染命令本身还有几个不设就慢 3 倍的开关。这个文件夹是**一次 setup + 一条渲染命令**，长片还可以**两块卡同时画一支片子**。

在 notebook 里（Settings → Internet 打开，每个 `!` cell 都是新 shell，所以 `source` 写在命令行里）：

```bash
!git clone --depth 1 https://github.com/coreselfmastery/OpenVideoHarness.git /kaggle/working/OpenVideoHarness
%cd /kaggle/working/OpenVideoHarness
!bash tools/kaggle/setup.sh                    # 每个会话一次（首次 5–10 分钟，重启会话后秒级：缓存在 /kaggle/working）
!source .kaggle/env.sh && bin/vh new promo my-film        # 照常建项目（自动 bin/vh hf-init：GSAP 本地化、字体 local()）
# …写合成，source .kaggle/env.sh && npx hyperframes lint 到 0 error…
!bash tools/kaggle/render.sh projects/<date>-my-film --tier draft              # 评审稿（快）
!bash tools/kaggle/render.sh projects/<date>-my-film --tier draft --res 720p    # 结构稿更快的说法（画面不变、像素减半）
!bash tools/kaggle/render.sh projects/<date>-my-film --tier final              # 成片（引擎自己的渲染器）
!bash tools/kaggle/render-split.sh projects/<date>-my-film --tier final       # 或：两块卡各画半支（最快出成片）
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
| fps | **30 是默认**（提速清单里最大的单项杠杆，约省一半的帧）。合成写了 `data-fps` 且 ≤ 30 → 保留（24 fps 的片子不会被动到）；写了 > 30 → **仍然渲 30** 并说明（要保住 60 fps 的每一帧，自己传 `--fps 60`） | 降帧率是最大的单项提速（约 48%）；声明得更低的规格照读照留，默认值定在这里而不是靠每个人的手指 |
| workers | **< 240 s：`--workers 1`**。≥ 240 s 且硬件 GPU：**不传 `--workers`**——并行快速捕获路由器只在 worker 数留给 auto 时才接手，把它钉在 3 个 worker 的并行流式捕获上；显式传了反而把路由器关掉。≥ 240 s 且软件渲染：**实测内存**说了算——min(空核数, 空闲 GB / 6 GB 一个浏览器, 6)，空闲内存从 cgroup（Kaggle）或 /proc/meminfo 读 | 短片多 worker 会把每一帧先落到盘上再编码（最长慢 8 倍）；长片的 3-worker 并行 DE 流是实测最快的路径；内存快满的机器要的是少开浏览器，不是 OOM |
| 编码 | NVENC 探测通过 → `--gpu`：编码钉在第二块 T4；带 `--tier` 时再由 `.kaggle/ffmpeg-gpu.sh` 重调（见下节） | CPU 那部分负载整个卸到 GPU 1；`bin/vh deliver` 的平台成片仍然 CPU libx264 CRF 16 重编码，交付质量不变 |
| 捕获 | 硬件 WebGL **且合成过引擎自己的四个编译门**才加 `--experimental-fast-capture`：CSS 3D 上下文、`mix-blend-mode`、合成根的祖先带 background-image、shader 转场（`HyperShader.init` / `__hf.transitions`）——0.8.82 的编译器检测到任何一个都会**悄悄**退回截屏，这里用同一套模式先扫一遍（祖先是真走 DOM 的，不是猜 html/body），命中就说明是哪一个、环境变量怎么覆盖（`HF_FAST_CAPTURE_3D` / `_BLEND` / `_ANCESTOR_BG` / `PRODUCER_EXPERIMENTAL_FAST_CAPTURE`） | 快速捕获（drawElement）长片最高 5×，但要了却用不上只是浪费一个开关；扫不出结果时保守走截屏 |
| 流式上限 | 永远把 `PRODUCER_STREAMING_ENCODE_MAX_DURATION_SECONDS` 设在**片长 + 60 s** | 引擎的流式编码有个时长上限，任何东西把它压到片长以下都会**静默**切到逐帧落盘（慢路径）；设到片长之上，就没有东西能在底下关掉流式 |
| 帧提取缓存 | `HYPERFRAMES_EXTRACT_CACHE_DIR` 指到项目里（`renders/.hf-extract-cache`） | 有 `<video>` 素材的合成只在第一次渲染时切帧，重渲（含 Kaggle 下一个会话）直接复用；`renders/` 本来就是 `bin/vh clean` 的地盘，项目收尾时缓存跟着走 |
| 磁盘 | 开画前估算峰值（帧数 × 分辨率 × 经验码率），不够就说；连平片都放不下直接拒（exit 2） | `/kaggle/working` 上限 20 GB，别让渲染跑一半才死 |

`--detach` 把渲染放进后台（`HYPERFRAMES_RENDER_DETACHED=1`），打日志路径、pid 文件和停止命令；**只留最近 5 个日志**，旧的自动清掉。长渲染建议用它，notebook 的 cell 立刻返回。

### 出片后的「held」回读卡

渲染结束不是终点：render.sh 用 ffprobe 把**刚写出来的片子本身**读回来，对照刚才要的东西——帧数、尺寸、帧率、编码器。要了 NVENC 而文件里是 libx264 → 一句「`--gpu` 没站住，引擎回退了（原因在上面的日志里）」；要 30 fps 而文件里是 60 → 「要的 30，文件说的 60」。**标志是请求，文件才是事实**，这张卡说的是事实。带上 `--output-resolution` / `--width` / `--height` 时尺寸不对照（引擎自己会超采样），其余照查。

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

## --res：分辨率分层草稿（480p → 720p → 1080p）

HyperFrames 的 `--output-resolution` 只会**向上**超采样（1080p、4K），没有 480p/720p 的档；这条工具链自己补上了：`tools/film/render.mjs --res <N>p`（以及 `render-split.sh --res`）把页面按**分数 deviceScaleFactor** 画——布局不动、每个元素还是它自己的位置，只是像素少了。

- `--res 720p` 在 1080×1920 的片子上是 dpr 0.667 → 720×1280（44% 的像素）；`--res 480p` 是 dpr 0.444（20% 的像素）。
- 实测阶梯（leo 片 0–6 s、SwiftShader 软渲、含浏览器启动与编码的墙钟）：**1080p 16.2 s → 720p 10.5 s（1.55×）→ 540p 8.1 s（2.0×）→ 480p 7.5 s（2.15×）**。帧数一样、画面一样（720p 对母片降采样的 PSNR 43 dB，远超 patch 的 40 dB 门），480p 更适合看节奏和构图（文字抗锯齿在 0.44 的分数比例下会更糙）。
- 两条护栏：**dpr < 0.25 拒**（1080p 的页面最低 270p，再低 Chrome 自己都不稳）；**dpr > 1 拒**（`--res` 说的是草稿档、更少的像素——要**更多**像素是 `--dpr`（精确倍数）或引擎的 `--output-resolution`（超采样），混了会静默出 4× 的图，这不是它干的事）。
- `render-split.sh --res` 两半同一个 dpr、接缝照旧是关键帧上的 stream copy（实测 90p 切分：160×90、960 帧一个不少）。

评审循环里的用法：`--tier draft --res 720p` 出结构稿（两个杠杆叠乘），定稿再全尺寸 `--tier final`。

## 简化贵 CSS：bake 把静态场景冻成一张 PNG

提速清单的「简化贵 CSS」原来只是写作纪律（少叠大 `backdrop-filter` / `filter: blur()`）；现在是**工具 + 样板 + 数字**：

- `bin/vh bake <project|page> [--out scene.png] [--at t] [--hide sel,sel…]`：把页面标记的动画层（`[data-bake-hide]`）藏起来，t 时刻截一张**无损 PNG**（默认 `assets/scene.png`）。合成器每一帧都要重跑、但内容永远不变的东西——玻璃面板背后的模糊、叠起来的阴影——冻成一张图。
- 样板：`tools/kaggle/fixture/css-cost/` 是同一画面的一对双胞胎——`index.html` 是贵的那种（两层叠着的 `backdrop-filter`，卫星一动整块玻璃跟着重滤），`baked.html` 用 bake 出来的 PNG 加同样的两个动元素。
- 实测（960×540、6 s、同参数 x264 crf 16）：**活模糊 11.4 s → 烘焙 6.5 s，快 1.75×**（去掉固定开销后画帧侧约 2.3×）；两支片子互 PSNR **58.4 dB**（同一画面，远超 40 dB 门），新鲜烘焙与已提交的 PNG 逐位相同（PSNR ∞）。
- 平台诚实条款（CI 在 macOS 上跑出来的，run 39123478825）：Chrome 的栅格化是**平台方言**——同一页面，macOS 的 Chrome 烘出来与 Linux 烘的那张 `scene.png` 只有 29.7 dB（SF 与 DejaVu 的字形差异就够这个数了），所以「新鲜 bake = 提交的 PNG」只在烘它的平台上成立。测试套件随之改口径：**本平台的参照是第二次 bake**（同一页面连烘两次必须同图），双胞胎片子的 `scene.png` 换成本平台刚烘的那张（比较的永远是「活滤 vs 冻图」，不是「本平台 vs 参照的平台」），提交的 PNG 只在 Linux 上对（它就是在 Linux 烘的）。
- 测试套件把这些都钉住了：连烘两次同图（本平台参照）、双胞胎片子互 PSNR ≥ 40 dB（带本平台自己的 scene）、`--res` 档真的出 480×270；提交的 PNG 只在 Linux 上比对，别的平台明说跳过的原因。

写作侧的规矩没变（engines/README.md）：动画元素别垫在玻璃下面（bake 藏不掉它）、文字要跟着动画走的就别进 PNG。

## 字体全声明：local @font-face（以 leo 片为例）

`bin/vh hf-init` 给新项目做了 local() 字体；showcase 02 这支老片子是后补的示范——从 Google Fonts 的 CDN `<link>` 换成本地 `@font-face`：

- 只留**覆盖片子实际用字**的 unicode-range 子集（Noto Sans SC 500/800，37 个 face、2 MB，woff2 是 Google 自己的那几份文件，只是提前拿进来）；Δ（U+0394，`Δf ≈ (v/c)·f` 那个公式）Noto Sans SC 没有，补了一个 Noto Sans 的 greek 子集同族声明——**以前它悄悄落到本机有什么字体就用什么**（Linux 上是 Liberation Sans，每台机器不一样），现在是声明的、每台机器相同的字形。
- 验证三件套：页面可绘的 173 个字符全部落在本地声明的 unicode-range 里；页面**零**跨源请求（`performance.getEntriesByType("resource")` 过一遍）；CDN 版与本地版互 PSNR——除 Δ 之外逐位相同（Δ 是有意修的那个字形，37 dB 的差全在公式那一行）。
- 引擎自己的配合：编译器把本地字体嵌成 data URI（大文件保持 file-backed），所以离线渲染不缺字。

## lambda.sh：AWS Lambda 上的分布式渲染

`tools/kaggle/lambda.sh` 把这套的项目约定映射到引擎自己的 lambda 命令上（`deploy` 一次 → `render` 切块并行画 → MP4 落在栈的 S3 桶里）。**前提在动手前点名**：aws CLI（带可用凭证）、AWS SAM CLI、bun（打 handler 的 ZIP）、`@hyperframes/aws-lambda`——缺哪个就说哪个怎么装，而不是死在 Step Functions 深处；Kaggle 上一个都没有，那也没关系（同一台机器上 `--workers` 和 render-split 就是并行，这条路是给有云账号的机器的）。

- 决定与 render.sh 同源：宽高用合成自己的（`lambda render` 必须要，缺了拒）、fps 24/30 保留其余渲 30（lambda 只收 24|30|60）、`--tier draft` → `--quality draft`、`final` → `--quality high`（lambda 的质量档是 draft|standard|high）、块大小与并行度留给引擎（240 帧一块、16 块并行）。
- 诚实的话：Lambda worker **没有 GPU、没有 NVENC**——赢在块并行（强 vCPU × 16 块在飞），不是单帧速度；成本是每次渲染把项目 tar 上传 S3。`--dry-run` 打印将执行的完整命令，什么都不碰。
- 测试套件用桩引擎 + 桩 AWS 工具把参数映射和每一条拒绝都钉死（fps 25 拒、`--tier`+`--quality` 拒、无尺寸拒、无 aws 拒……）。

## render-split.sh：一支片子两半同时画（F6）

`tools/kaggle/render-split.sh <project> [--tier draft|final] [--res 480p|720p…] [--at 秒] [--gpu-a N --gpu-b N] [--workers N] [render.mjs 的其余参数] [--dry-run] [--keep] [--skip-determinism]`

**计划**：从 index.html 读片长、fps 和**合成自己声明的场景切点**（各 clip 的 `data-start`），在中间 ±¼ 片长的窗口里挑离中点（或 `--at`）最近的切点下刀——每一镜都完整地落在某一半里；没有切点就切正中帧。两半各由一个浏览器按仓库的页契约**逐帧精确**画出（`tools/film/render.mjs --frames`，就是 `bin/vh patch` 重渲镜用的同一条路），各配一个 ffmpeg：**半支 A 的 NVENC 在 GPU 0、半支 B 的 NVENC 在 GPU 1**，两个浏览器留在 GPU 0。画完三重校验后 **stream copy 拼接**（无重编码）：

1. 两半的编解码参数一致（codec/profile/level/尺寸/像素格式，不一致说明哪一半被重编码过）；
2. 半支 B 从关键帧开始（接缝是码流里真实的切点）；
3. 拼好的文件帧数 = 两半之和 = 全片帧数，字节数 ≈ 两半之和（stream copy 的直接证据）。

**安全性**：开画前先跑 `bin/vh determinism`——帧依赖它前面帧的页面（粒子、累积状态）会在切分下画出不同的帧，这个门把它拒掉（`--skip-determinism` 强行跳过，但别）。每半的 GOP 钉在 2 s，接缝正好落在关键帧上，所以拼好的片子 `bin/vh patch` 照常按关键帧补镜、`bin/vh mux` 照常套声音——sidecar 记录了切点、两半和各自的卡，patch 直接接着用（实测：split 成片上 patch 21–22 s，接缝外像素逐位相同，PSNR 门全过）。

**诚实的注意**（写在这里而不是脚注里）：两半是页契约画的，不是 `npx hyperframes render` 画的（那个渲染器渲染不了半支——0.8.82 与 0.8.169 都验证过没有跨中间态的入口）。仓库对这条路的信任有先例：`bin/vh patch` 每次补镜都这样画帧、PSNR ≥ 40 才拼回去，而补过的片子是交付过的片子。对照实测（32 s 测试片、同参数整渲 vs 切分）：**全片 PSNR 65.3 dB、接缝前后 ±0.3 s 55.3 dB**——远高于 patch 自己的 40 dB 门，视觉上无从分辨。所以：**交付的母片用 render.sh 的引擎渲染**（引擎注入的虚拟时间、GSAP 补间缓冲与页契约略有差异，见 hf-adapter.js 头注）；**墙钟时间要紧的长片（配额压力、赶评审）用 split**，或一轮评审两档同时出。

`--dry-run` 打印切点和两条半支命令不画一格；`--keep` 保留两半和日志；Ctrl-C（或 Kaggle 的 Interrupt）无论落在哪个阶段都带走该阶段的一切、一个文件都不留——落在确定性门上就带走门自己的浏览器（门在后台跑着，停止陷阱才够得着它），落在两半上就经 `exec node` 直达 render.mjs 的停止清理，各自删掉自己的分块。

## monitor.sh：整台机器一眼看尽（GPU/CPU/RAM/磁盘）

`tools/kaggle/monitor.sh [--once] [--watch N] [--json] [--log FILE] [--no-cpu-sample]`

渲染时另开一格跑它，看的就是"没浪费机器钱"这件事：两块 T4 各自的利用率/显存/温度/功耗、**哪支进程占着哪张卡**（blender? chrome? manimgx?）、CPU 核数与负载、RAM 余量、以及最要命的 `/kaggle/working` 磁盘余量——渲染会在磁盘写满时停，而 12 小时会话上限把剩下的一切都带走。健康的样子（GPU 分工表）：Blender split 时两行都近 100%；网页片渲染时 GPU 0（Chrome）忙、GPU 1 在 NVENC 编码瞬间脉冲；CPU 负载明显低于核数说明浏览器没饿着。

`--watch 5`（默认 5 s 一照）每照整印——不用屏幕刷新技巧，Kaggle 笔记本单元格里照样读；`--json` 出 JSONL（和人类表同字段）；`--log FILE` 把每一照追加成 JSONL（配 `--watch` 用，事后画图/写 NOTES.md）；`--no-cpu-sample` 跳过算 CPU 忙闲百分比的 1 秒采样，一照只要毫秒。桩验证 10 项断言（表、JSON 有效性、日志追加、拒绝路径、无 nvidia-smi 时仍 0 退出并说明原因）。

## 提速清单的落地情况

对照 HyperFrames 自己的调优表，在这套里各自落在哪：

| 手段 | 落地 |
|---|---|
| fps 30（或 24） | **30 是默认**：声明 ≤ 30 照读照留，声明 > 30 仍渲 30 并说明（`--fps` 可覆盖）；出片后的 held 卡把文件里真实的帧率读回来对账 |
| `HF_DE_PARALLEL_ROUTER=true` | env.sh 常备（忘了它长渲染慢 3 倍；设成环境变量还躲开 HyperFrames 的“失败一次就静默关掉”熔断） |
| GPU 编码 `--gpu` | NVENC 探测通过自动加，钉在第二块 T4；held 卡从文件里确认 h264_nvenc 真的站住了 |
| 浏览器 GPU `--browser-gpu` | WebGL 硬件探测通过自动加 |
| 两块卡画一支片子 | render-split.sh（≥ 30 s 长片；render.sh 打印提示） |
| worker 数 | render.sh 按片长和实测内存定（上面）；软渲小机器上实测过 1/2/6 的权衡（见研究一节） |
| 两级渲染 `--tier` | draft = `--quality draft` + NVENC p4/cq 28；final = `--quality delivery` + NVENC p7/cq 19 |
| 流式编码不被时长上限关掉 | render.sh 永远设上限 = 片长 + 60 s |
| 简化贵 CSS | **bin/vh bake**：静态场景（叠着的 backdrop-filter、静态模糊）冻成一张无损 PNG，动画层照常画；css-cost 样板实测 1.75×（见上节） |
| MP4 不用 WebM | 默认就是 MP4（VP9 编码在 CPU 上） |
| Chrome 缓存 | setup.sh 的 `browser ensure`，会话间留在 /kaggle/working |
| CDNs 本地化 | `bin/vh hf-init` 已经做（GSAP 进 node_modules）；引擎对缺失的本地 gsap 还会自动改写为 CDN（反方向也有究底） |
| 字体全声明 | `bin/vh hf-init` 给新项目做 local()；老片子照 showcase 02 的样子补（unicode-range 子集 + 希腊 Δ 补齐，见上节） |
| lambda / cloudrun 分布式 | tools/kaggle/lambda.sh（要有 AWS 账号：aws/SAM/bun 齐才动手，缺什么点名什么）；Kaggle 上同机的 `--workers` 和 render-split 就是并行 |
| HTML-in-canvas 快速捕获 | 硬件 GPU 且过引擎四个编译门时 render.sh 显式开（Linux 上默认关）；软渲机器上引擎自己也会拒（实测两道门：browserGpuMode=software 直接强制截屏、SwiftShader 探测再拒一次——与 render.sh 的门控同一个判断） |
| 分辨率分层 480p/720p/1080p | **render.mjs / render-split.sh 的 `--res`**：分数 dpr 保布局降像素（引擎的 `--output-resolution` 只会向上超采样）；实测 720p 1.55×、480p 2.15×（见上节） |
| 预计算共享素材 | **bin/vh bake**（静态场景）；`HYPERFRAMES_EXTRACT_CACHE_DIR`（`<video>` 切帧缓存进项目）；setup.sh 的 Chrome/npm 缓存；字体子集本地化 |
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
- **workers 在软渲小机器上的实测反转**（本沙箱 2 核 / 4 GB、同一支 8 s 真片子过真引擎）：`--workers 1`（流式）13.0 s、`--workers 2` 9.1 s、`--workers 6`（逐帧落盘）7.1 s——软光栅是瓶颈时，多开浏览器赢过流式的串行等待，尽管多付了落盘的往返。render.sh 的 ≤ 240 s → 1 是按 Kaggle（快光栅 + 29 GB）调的，在那里流式照旧占优；在纯软渲的小机器上要快就用 `--workers N` 明说。同一次实测还看到：**≤ 8 GB 内存的机器引擎自己进 low-memory profile**（强制截屏、跳过 worker 校准，日志明说），`--no-low-memory-mode` / `PRODUCER_LOW_MEMORY_MODE=false` 可关。

## 排查

- **`browser GPU` 一行说 CPU/SwiftShader**：容器里 EGL 到不了 GPU（驱动库没挂全）。浏览器负载回到 CPU，`--browser-gpu` 和快速捕获自动不请求。渲染还是能出片，只是慢。
- **`encode` 一行说 CPU（libx264）**：ffmpeg 没有 NVENC，或 NVENC 在容器里被挡（探测失败）。`apt-get install ffmpeg`（Ubuntu 源里的构建带 NVENC）后重跑 setup.sh。
- **`capture` 一行说 screenshots（合成用了 …）**：不是故障——合成里有 3D / blend / 祖先背景 / shader 转场，引擎本来就会退回截屏；要强行用快速捕获，按提示设对应的环境变量（画面自负）。
- **render-split 说 determinism 不过**：页面有依赖历史的帧（粒子、累积状态）。要么修页面（把这些状态做成 t 的纯函数——engines/CONTRACT.md 本来就要求），要么整支用 render.sh，要么 `--skip-determinism` 自担。
- **渲染命令完成了但进程迟迟不退**：HyperFrames 0.8.82 在个别机器上收尾慢（浏览器池的关闭竞态）。输出文件在完成横幅出现时就已经写好；等它自然退出，或长渲染用 `--detach`。
- **磁盘**：`/kaggle/working` 上限 20 GB，缓存占约 1 GB；render.sh 开画前会估峰值并提醒，连平片都放不下会直接拒绝而不是跑一半死。
- **GPU 配额**：Kaggle 每周约 30 小时。draft 用 `--tier draft`、长片用 render-split 两块卡一起跑、只重渲改动的镜（canvas 片子有 `bin/vh patch`），把配额花在成片上。

## 测试

`tools/kaggle/test.sh`（`tools/ci.sh` 自动跑它）用**桩**验证 setup.sh 的每个探针、ffmpeg 包装器的 tier 重调（引擎真实参数形状的 12 种情况）、render.sh 的全部决定和错误路径、render-split 的计划数字；有 Chrome 的机器上再跑**真**的 32 s 切分渲染：determinism 门、两半并行、三重拼接校验、sidecar 落点、打断后一个文件都不留。

现在这一套还用桩钉住：render.sh **出片后的 held 回读卡**（要了 NVENC 文件却是 libx264、要 30 fps 文件却是 60——每个分支都驱动到）、`--fps 30 默认`（声明 60 → 渲 30，`--fps 60` 覆盖）、帧提取缓存落位、`render.mjs`/`render-split.sh` 的 `--res` 护栏（升采样拒、0.25 地板拒、`--dpr` 互斥）、lambda.sh 的参数映射与全部拒绝（桩引擎 + 桩 AWS 工具）、**monitor.sh 整机一照**（两卡计数、每卡一行、持卡进程行、JSON 有效性、日志追加、拒绝路径、无 nvidia-smi 时的诚实降级）。有 Chrome 的机器再跑**真**的：同一页面连烘两次必须同图（本平台参照，见 bake 一节的平台诚实条款）、双胞胎片子互 PSNR ≥ 40 dB（带本平台刚烘的 scene）、`--res` 档真的出 480×270，以及 **render.sh 过真引擎**的端到端（引擎自己的横幅说 30fps · draft · 1 workers，held 卡把真片子读回来对账）。共 **150 项**断言，全部绿才许过。

三个真渲染段（切分 E2E、bake 三件套、引擎 E2E）各带**时间预算**（600 / 240 / 480 秒，环境变量可覆盖）：租来的 CI 主机可能卡死（Chrome 不应答就把等待挂到天荒地老），预算把「慢/卡」变成一句诚实的 skip——`run 39127448500` 的 macOS 任务静默耗完最后 31 分钟，正是因为 bake 段的注释写了「同样有预算」而下面其实什么都没有。三项预算全触发的最坏情形 ≈ 25 分钟，加上前面 ~9 分钟的影片工具组，落在 40 分钟的天花板内。
