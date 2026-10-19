# HyperFrames 渲染提速（GPU 路径、硬件编码、分段并行）

HyperFrames 0.8.82 是本仓库 Remotion 层的渲染器（HTML + GSAP 合成 → Chrome 逐帧截取 → ffmpeg 编码）。本页是它的速度层：**哪些开关真的提速、快多少、什么代价**，以及一条命令的封装 [`tools/hf_speed.sh`](../tools/hf_speed.sh)。速度不换画质、不换创意：快的是**草稿迭代**（GPU 路径），**交付成片**仍走本仓库已验证的确定性软件路径——两档都是完整画面，只是帧的来路不同。

> **实测口径（2026-10-19，Linux 沙箱 headless）**：下文标【实测】的是在沙箱里真实跑过的（HyperFrames 0.8.82，Node 24，2 核 CPU、无 GPU——所以 GPU 分支验证的是**探测与回退**的确定性，GPU 命中分支标【Kaggle 待验证】并给出应看到的日志行）；标【源码】的是拆包核过 `dist/cli.js` 的行为（0.8.82 的事实，不是文档许诺）；标【二手】的只有引用来源。沙箱里的五次真渲：`--browser-gpu --gpu` 草稿、分段捕获（5 段/30 帧每段）、`--keep-segments`、`--resume`（0.6 s 复用全部 5 段）、`tools/hf_speed.sh` 三档各一次，全部 exit 0。

## 要点

| | |
|---|---|
| 工具 | `tools/hf_speed.sh <项目> --tier draft\|final\|4k`（下文"两档渲染"） |
| GPU 草稿 | `--browser-gpu`：Linux 上 Chrome 以 `--use-gl=angle --use-angle=gl-egl --enable-gpu-rasterization` 启动（Remotion `--gl=angle-egl` 的同路）【源码】；`--gpu`：编码器按 nvenc→vaapi→qsv→amf 探测，320×240 实探 2 s 超时，命中即 `h264_nvenc -preset p4 -cq/-b:v -bf 0`【源码】 |
| 交付成片 | `--no-browser-gpu --experimental-fast-capture=false --quality delivery`：软件 Chrome + 截屏捕获 + 软件 x264——本仓库的既有口径（engines/README.md"浏览器 GPU"一节的坏帧教训、`styles/_swatch/determinism.sh` 的逐字节契约），速度层不改它 |
| 分段并行 | `HF_SEGMENTED_CAPTURE=true`（两档都开）：默认 3000 帧一段（30 fps 即 100 s），多 worker 并行吃段，每 3 段回收浏览器（ANGLE/Chrome 长渲染内存增长的对症解），`--keep-segments` + `--resume` 断点续渲只补缺段【实测：全渲 11.6 s → resume 0.6 s】 |
| Workers | Kaggle 4 vCPU 上**显式 `--workers 2`**：auto 解析为 `max(6, cores/8)`，小机器上过量订阅【源码】；每个 worker 一个 Chrome（约 256 MB） |
| Chrome 旗标 | 全部原生且常开：`--no-sandbox --disable-setuid-sandbox --disable-dev-shm-usage --disable-background-timer-throttling --disable-backgrounding-occluded-windows --disable-renderer-backgrounding --disable-background-media-suspend --force-color-profile=srgb --font-render-hinting=none`【源码】——不需要也不接受自定义 Chrome 旗标 |
| 中间帧 | 默认 JPEG（draft 质量 80、其余 95）【源码】；源视频抽帧 `--video-frame-format auto\|jpg\|png`，屏幕录制/对色彩敏感才用 png |
| 测量 | `hyperframes benchmark`（原生对比 fps/quality/workers 预设）、`--debug` 全量诊断、Render:trace 每阶段毫秒、【实测】`HYPERFRAMES_DEBUG_GPU_PROBE=1` 打印编码器探测明细 |
| 版本 | 全部事实按 0.8.82 锁定（本仓库固定版本；doctor 提示 0.8.174 只是"有新版"，升级要按 engines/README.md 的流程先冒烟） |

## 一条渲染命令的四段

`hyperframes render` 内部是 compile →（视频源抽帧）→ capture → encode → assemble【源码】。提速前先知道时间花在哪：草稿渲染的日志末尾直接给分段耗时（`compile 0.0s · capture 8.1s · encode 2.0s · assemble 0.1s`【实测】），`--debug` 保留全部中间产物再查。四个环节里 GPU 能碰的只有两个：**capture**（Chrome 画帧——GPU 光栅化、WebGL、drawElement 快速截帧）和 **encode**（ffmpeg——NVENC）。compile/assemble 是 CPU 的 Node 侧编排，视频源抽帧是 ffmpeg 的 CPU 活。所以"给 Remotion 上 CUDA/OptiX/TPU"是无的放矢：Chrome 的排版和 GSAP 的时间线根本不在 GPU 上跑。

## 两档渲染（tools/hf_speed.sh）

```bash
tools/hf_speed.sh projects/<date>-<slug> --tier draft   # 草稿：GPU 浏览器 + NVENC + JPEG80 + 分段，迭代用
tools/hf_speed.sh projects/<date>-<slug> --tier final   # 交付：软件 Chrome + 截屏 + 软件 x264 + 并行流 + 分段可续
tools/hf_speed.sh projects/<date>-<slug> --tier 4k      # final + --resolution 4k + 8 GB Node 堆（engines/README.md 的 4K 一节）
```

| | draft | final / 4k |
|---|---|---|
| 画质 | `--quality draft`（JPEG 80 中间帧 + 草稿 CRF） | `--quality delivery`（= high） |
| 浏览器 | `--browser-gpu`：探测有 GPU 就走 gl-egl 硬件光栅 + drawElement 快截（约 2×，仅硬件 GPU 时启用【源码】） | `--no-browser-gpu`：SwiftShader 软件，强制截屏捕获 |
| 编码 | `--gpu`：nvenc 命中即 `h264_nvenc`；文件比同观感 x264 大，配 `--bitrate 8M` 控体积 | 软件 x264（CRF 可 `--crf` 覆盖） |
| 分段 | 默认开（`--segment-frames 3000`） | 默认开，`--keep-segments` 后可 `--resume` |
| 确定性 | **无**：GPU 光栅的文字边缘逐进程不同，NVENC 逐机不同（HyperFrames 自己在分布式渲染里禁 GPU 编码、要求逐字节可重放【源码】） | **有**：同机同参数逐字节可重放（determinism.sh 的契约口径） |
| 用途 | 看构图、节奏、接缝、字体——创意判断够用，**不出仓** | 唯一交付路径 |

为什么交付不走 GPU（这不是妥协，是三条实测依据）：① 本仓库的坏帧教训——浏览器 GPU 开着时长片偶发单帧坏帧（闪进别的场景、字成乱码），软件路径 7 连渲干净（engines/README.md"浏览器 GPU"）；② 逐字节确定性——GPU 文字光栅逐进程有几十像素一级的差异，x264 会把它放大成不同的 mp4（`styles/_swatch/render.sh` 头注释）；③ HyperFrames 0.8.82 源码里分布式模式直接拒绝 GPU 编码，理由写明"NVENC/QSV/VAAPI 跨机器输出不同"。GPU 档换来的迭代速度（下面 Kaggle 一节估 3–6×）让**每一版草稿更快出来**，成片的画质标准一点没动。

draft 档还想更快：`--fps 15`（帧数减半，动效半采样，只判构图/时间）、`--workers 2`、短段 `--segment-frames 1500`。要"和成片完全同帧率同节奏"的审片，用 final 档渲一次中间产物即可——两档都是完整合成，不是缩水版。

## 速度清单：原版 Remotion 建议 → HyperFrames 0.8.82 的现实

| # | Remotion 的建议 | 这里的事实 | 状态 |
|---|---|---|---|
| 1 | `--gl=angle-egl` | `--browser-gpu`（Linux 硬件模式 = `--use-gl=angle --use-angle=gl-egl`） | 原生 |
| 2 | NVENC `--hardware-acceleration if-possible --codec h264` | `--gpu`（探测链 + 自动回退 libx264；`-cq` 代替 CRF） | 原生 |
| 3 | 两档渲染（draft/final） | `--quality draft/delivery` + `tools/hf_speed.sh` 三档 | 原生+封装 |
| 4 | 分块并行渲染 + ffmpeg concat | `HF_SEGMENTED_CAPTURE` 分段捕获：段内流式编码、段间 concat、浏览器按段回收、`--resume` 复用 | 原生（更安全） |
| 5 | `--concurrency=2` | `--workers 2`（auto 在小机器上过量） | 原生，需显式 |
| 6 | 并行编码 | 流式编码默认开（`PRODUCER_ENABLE_STREAMING_ENCODE`，240 s 上限可调）；`PRODUCER_ENABLE_CHUNKED_ENCODE=true` 让超长渲染分块喂 ffmpeg | 原生 |
| 7 | Chrome 旗标 | 全部原生常开（见要点表），不接受自定义 | 原生 |
| 8 | H.264 + JPEG 中间帧 | mp4=x264 默认；中间帧默认 JPEG（80/95）；避免 WebM（libvpx-vp9 慢，`--vp9-cpu-used` 只是止损） | 原生 |
| 9 | 避开昂贵 CSS（blur/阴影/渐变动画） | 写法约束（下文"合成侧"）；着色器转场走 `--page-side-compositing`（约 6×，SDR mp4 默认开，drawElement 时自动关）【源码】 | 写法+原生 |
| 10 | `<Video>` 用 @remotion/media | HyperFrames 的媒体层：`hyperframes.json` 的 `media.autoProxy` 代理、内容寻址抽帧缓存（默认 2 GB，`HYPERFRAMES_EXTRACT_CACHE_DIR` 可挪盘）、`--video-frame-format` | 原生等价 |
| 11 | useMemo/数据缓存 | 合成是纯 HTML+GSAP：重计算放 timeline 回调外、常量提升到模块层（硬规则 1 本来就要求画面是 t 的纯函数） | 写法 |
| 12 | `--log=verbose` 找慢帧 | `--debug` 全量诊断；Render:trace 逐阶段毫秒【实测】；`hyperframes benchmark` 对比预设 | 原生 |

## GPU 路径细节

**浏览器（capture）**【源码+实测回退】：`--browser-gpu` 把 browserGpuMode 定为 hardware，Linux 上 Chrome 带硬件 GL 旗标启动；无 GPU 时 0.8.82 会打探测结论并**安全回退**（实测日志：`browserGpuMode probe → software (WebGL unavailable)` + Docker GPU 直通指引）。auto 模式（默认）先探 WebGL vendor/renderer，探到 SwiftShader/lavapipe 也回软件。注意：软件模式下 0.8.82 **强制截屏捕获**（`PRODUCER_FORCE_SCREENSHOT=false` 可关），drawElement 快截只在硬件 GPU 时启用——这是"无 GPU 的机器上 draft 档不会更快"的原因，不是 bug。

**编码器（encode）**【源码+实测回退】：`--gpu` 时先 `ffmpeg -encoders` 过滤出编译进去的候选（顺序 nvenc→videotoolbox→vaapi→qsv→amf），再对每个候选跑 320×240 实探（2 s 超时），第一个可用的胜出；全败回 libx264（实测：`[gpuEncoder] nvenc probe failed … Cannot load libcuda.so.1`）。NVENC 命中时：`-preset p4`（medium 的 NVENC 档）+ 有 `--video-bitrate` 用 `-b:v`、没有用 `-cq`（quality 映射，**不是 CRF**——NVENC 文件偏大时就用 `--bitrate 8M` 控体积）+ `-bf 0`。`HYPERFRAMES_DEBUG_GPU_PROBE=1` 打印每步探测【实测】。

## 分段捕获与断点续渲【实测】

```bash
HF_SEGMENTED_CAPTURE=true HF_SEGMENT_FRAMES=3000 HF_SEGMENT_BROWSER_RECYCLE=3 \
  hyperframes render . --keep-segments --output out/final.mp4     # 崩了/断了再来一次：
HF_SEGMENTED_CAPTURE=true … hyperframes render . --resume --output out/final.mp4
```

- 段长默认 3000 帧（`MIN_SEGMENT_FRAMES=30` 下限）：30 fps 即 100 s 一段；多 worker 并行取段（实测日志里两个 worker 交错推进 segment 1/5 与 2/5）。
- **每 3 段回收浏览器**（`HF_SEGMENT_BROWSER_RECYCLE`）：长渲染内存增长的正解——Chrome/ANGLE 进程按段重启，不用整片重来。
- `--keep-segments` 把段留在 `renders/.hf-segments/<hash>/`（composition+设置的哈希）；`--resume` 逐段校验后复用，只补缺的段。实测：全渲 11.6 s → resume 0.6 s（5 段全命中）。
- 只在 mp4/mov、流式编码可用、非分层合成路径时启用【源码】；不满足时自动整片渲染，不报错。
- 一致性口径：分段渲染的段边界就是编码器的分块边界，**和整片渲染的字节不必相同**（同分段配置重复渲染仍逐字节一致）。要"无分段的原始字节"就 `--no-segments`；`styles/_swatch/determinism.sh` 走 PNG 序列，不受影响。

`tools/hf_speed.sh` 两档默认都带分段（`--no-segments` 关）；draft 崩了 `--resume` 直接续，final 长片建议常带 `--keep-segments`。

## Workers、内存、磁盘

- **`--workers 2`（Kaggle 4 vCPU）**：auto = `max(6, cores/8)`【源码】，4 核上给 6 个 Chrome 是过量订阅；仓库既有口径也是 2（swatch render.sh 默认 2、4K 大机器 4）。每个 worker 约 256 MB + Node 侧开销，堆不够时 0.8.82 自己会提醒，4K 用 `NODE_OPTIONS=--max-old-space-size=8192`（engines/README.md）。
- **低内存模式**：总内存 ≤ 8 GB 自动进（cgroup 限额也算——沙箱 4 GB 上实测触发：钉 1 worker + 截屏 + 跳过 worker 自适应）；`--no-low-memory-mode` 可关。Kaggle ~29 GB 不触发。
- **/dev/shm 64 MB**（doctor 会 ✗）：Chrome 恒带 `--disable-dev-shm-usage`，不用管【源码】；doctor 那行只是通用检查。
- **4K 磁盘**：多 worker 截屏默认先落 JPEG 再编码（每帧约 4 MB），长片几十 GB——`HF_CAPTURE_PARALLEL_STREAM=true` 让帧直接流进编码器不落盘（final/4k 档已带；engines/README.md"长片出 4K 先看磁盘"）。视频源抽帧缓存在内容寻址缓存里（默认 2 GB，`HYPERFRAMES_EXTRACT_CACHE_DIR` 挪盘，`--frames-cache-dir off` 关闭）。
- 超长渲染的 ffmpeg 单进程可能撞 10 分钟编码超时：`PRODUCER_ENABLE_CHUNKED_ENCODE=true`（360 帧一块，可 `PRODUCER_CHUNK_SIZE_FRAMES` 调）分块喂。

## 合成侧的提速（写法，不改引擎）

- **动画只动 transform 和 opacity**：blur/box-shadow/渐变背景的**逐帧动画**每帧都触发重光栅，是慢帧的头号来源；静态的昂贵视觉效果预渲染成 PNG 当 `<img>` 贴。GSAP tween 的 `x/y/scale/rotation/opacity` 走合成器，代价最低。
- **重计算提升到模块层**：数据表、路径、着色器常量算一次存常量；驱动 tween 的回调里只做 t → 画面的映射（硬规则 1 本来就这么要求）。
- **着色器转场**靠 `--page-side-compositing`（页内 WebGL 合成，约 6×）【源码】——SDR mp4 默认开，drawElement 硬件截帧时自动让位（两者的快速路径互斥，0.8.82 自己选）。
- **源视频**：`hyperframes.json` 的 `media.autoProxy` 保持开（重素材自动做快速 seek 的代理）；`--video-frame-format png` 只给屏幕录制/色彩敏感素材，默认 auto/jpg 快得多。
- **别用 WebM 交差**：libvpx-vp9 编码慢数倍；真要 WebM（透明通道）单独渲，别当日常路径。

## Kaggle 2×T4 实战

**前置**：容器要 GPU 直通（`--gpus all` + NVIDIA Container Toolkit；无驱动时 0.8.82 的回退警告原文就教这个【实测回退文案】）。T4 是 Turing，**有 NVENC**；Kaggle 的 apt ffmpeg 带 `h264_nvenc`（本沙箱同源构建实测可见）。先跑 `tools/hf_speed.sh <项目> --gpu-probe`（doctor + nvidia-smi + 编码器清单），再 `HYPERFRAMES_DEBUG_GPU_PROBE=1 … --tier draft` 看命中。

**三引擎的 GPU 分配**（engines/manimgx.md"GPU"、engines/blender.md 的 T4 教义）：

| 引擎 | 用途 | GPU | 说明 |
|---|---|---|---|
| ManimGX | 数学场景（Vulkan） | GPU 0（不可钉，两个进程都落第一张 T4） | 渲完就退，不长期占 |
| Blender | 3D 场景（CUDA） | GPU 1（`CUDA_VISIBLE_DEVICES=1`） | tools/blender_run.sh --gpu 1 |
| HyperFrames | 全片（Chrome/EGL + NVENC） | 默认 GPU 0（EGL 不认 CUDA_VISIBLE_DEVICES） | 和 ManimGX 同卡可共存（不同进程、不同 API），串行更快 |

Chrome/EGL 在 NVIDIA 上落默认卡（GPU 0），`CUDA_VISIBLE_DEVICES` 管不到它。三引擎并行的最稳排法：**数学场景先渲完 → 全片渲染独占 GPU 0 → Blender 在 GPU 1 随便并行**；真要 Chrome 和 ManimGX 同卡并行也能跑（速度分摊），别把三个都堆上去。

**预期收益**（按机制估，Kaggle 上用 benchmark 实测后回填）：

| 档 | 相对本仓库旧口径（软件草稿、单进程）| 依据 |
|---|---|---|
| draft GPU 全开 | 3–6× | capture 硬件光栅+drawElement 约 2×【源码】× NVENC 编码 2–2.7×（用户侧 T4 实测口径）× workers 2 并行 |
| 断点续渲 | 缺多少补多少（实测全命中 19×） | 段哈希复用【实测】 |
| final | 不提速也不变慢 | 走的是仓库原路径，只是多了分段可续和并行流 |

测量协议：`tools/hf_speed.sh <项目> --bench --runs 3`（原生 benchmark，对比 30fps×draft/standard/high×2w/4w）；渲一次 draft 看 Render:trace 的 capture/encode 分段耗时；`nvidia-smi dmon -s u` 盯 NVENC 列在不在动。**别拿一次 wall time 下结论**——首次渲染要下 chrome-headless-shell（约 200 MB）。

## 验证与排障

| 想知道 | 跑什么 | 看到 |
|---|---|---|
| 环境齐不齐 | `tools/hf_speed.sh <项目> --gpu-probe` | doctor 全表 + nvidia-smi + h264_nvenc 在不在 ffmpeg 里 |
| GPU 到底命中没有 | draft 渲染的日志 | 命中：banner `GPU: encoder GPU + browser GPU (forced)`、无 probe failed；未命中：`browserGpuMode probe → software` + `[gpuEncoder] nvenc probe failed`（都安全回退【实测】） |
| 分段在不在工作 | 日志 | `Streaming frame N/总 (segment k/m)`、`Segmented capture complete: m segment(s) concatenated`【实测】 |
| resume 复用了多少 | 日志 + wall time | 复用段的渲染跳过，总时长骤降（实测 11.6 s → 0.6 s） |
| 哪个阶段慢 | 日志末尾 / `--debug` | `compile X · capture Y · encode Z · assemble W`【实测】 |
| workers 选多少 | `--bench --runs 3` | 各预设的时长和文件大小对比表 |

## 反模式

- **给 Chrome 上 CUDA/OptiX/TPU/Vulkan 渲染器**：Chrome 的排版与 GSAP 在 CPU，GPU 只碰光栅和编码；换"渲染后端"没有对象。
- **workers 拉到 8+**：4 vCPU 上是内存压力 + GC 抖动，实测口径（用户清单）和 0.8.82 的 auto 公式都不支持。
- **`--crf` 配 NVENC**：0.8.82 把 quality 映射成 `-cq`，CRF 语义不存在；控体积用 `--bitrate`。
- **GPU 渲交付成片**：逐字节确定性没了 + 坏帧风险回来了（三条依据见"两档渲染"）。
- **把分段渲染的字节当整片字节**：段边界=编码分块边界，对比要用同一种渲染形态。
