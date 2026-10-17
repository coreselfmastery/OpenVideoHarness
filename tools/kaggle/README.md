# 在 Kaggle（2×T4）上渲染 HyperFrames 片子

Kaggle 的免费 2×T4 实例（4 核 CPU、29 GB 内存）是这个仓库能用的最快的免费渲染机，但开箱什么都缺：Node 版本不对、ffmpeg 不一定带 NVENC、Chrome 要现下载，渲染命令本身还有几个不设就慢 3 倍的开关。这个文件夹是**一次 setup + 一条渲染命令**。

在 notebook 里（Settings → Internet 打开，每个 `!` cell 都是新 shell，所以 `source` 写在命令行里）：

```bash
!git clone --depth 1 https://github.com/coreselfmastery/OpenVideoHarness.git /kaggle/working/OpenVideoHarness
%cd /kaggle/working/OpenVideoHarness
!bash tools/kaggle/setup.sh                    # 每个会话一次（首次 5–10 分钟，重启会话后秒级：缓存在 /kaggle/working）
!source .kaggle/env.sh && bin/vh new promo my-film        # 照常建项目（自动 bin/vh hf-init：GSAP 本地化、字体 local()）
# …写合成，source .kaggle/env.sh && npx hyperframes lint 到 0 error…
!bash tools/kaggle/render.sh projects/<date>-my-film --quality draft     # 评审稿（render.sh 自己会 source env.sh）
!bash tools/kaggle/render.sh projects/<date>-my-film --quality delivery  # 成片
!source .kaggle/env.sh && bin/vh mux projects/<date>-my-film/renders/<成片>.mp4 <混音> <输出>.mp4   # 声音照常套上
```

在终端里（Kaggle 的 Terminal、或任何 Linux 机器）更简单：`source .kaggle/env.sh` 一次，之后所有命令都在。

也适用于任何 Linux GPU 机器；没有 GPU 时它同样工作（Chrome 走 SwiftShader、编码走 libx264），只是快不起来。开 Kaggle 笔记本时记得把 **Internet** 开关打开（Settings → Internet），`npx` 和 Chrome 下载都要联网。

## 两块 T4 怎么都用上

HyperFrames 一次渲染是两种负载：**Chrome 画帧**（DOM、CSS、GPU 光栅化、shader 转场）和 **ffmpeg 编码**（H.264）。本方案把两种负载钉在两块卡上：

| GPU | 干什么 | 怎么钉上去 |
|---|---|---|
| GPU 0 | 所有 Chrome worker（WebGL / GPU 光栅化 / 页内 shader 合成） | EGL 默认用第一块卡，不用干预 |
| GPU 1 | h264_nvenc 硬件编码 | `HYPERFRAMES_FFMPEG_PATH` 指到 `.kaggle/ffmpeg-gpu.sh`，它给每条 NVENC 编码命令插入 ffmpeg 自己的 `-gpu 1`（`ffmpeg -h encoder=h264_nvenc`），其余调用原样放行 |

渲染时开 `nvidia-smi -l 1` 能看到两块卡都有负载。Chrome 用不了第二块卡是 Chrome 的 EGL 设备选择没有命令行开关；好在编码正是从渲染里卸下来的那部分负载，两块卡都不闲着。

## setup.sh：探针，不是假设

`tools/kaggle/setup.sh [--no-persist] [--force-browser]` 每一步用的都是 HyperFrames 0.8.82 自己会做的同一个探测（它的 gpuEncoder 探测、它的浏览器 GPU 探测），所以**这里探不过的，渲染时也不会突然能用**；探过的才写进 `.kaggle/env.sh`：

- **Node ≥ 22**：Kaggle 镜像里的 Node 太旧或没有 → 从 nodejs.org 解一个 22 LTS 到缓存里（不用 sudo、不动 apt）。
- **ffmpeg**：按 `PATH` 和常见 bin 目录找第一个**同时有** `h264_nvenc` 和 `psnr` 滤镜的（Ubuntu 自带的都有；conda 的 ffmpeg 常常两个都没有）。找不到带 NVENC 的就落回 CPU 编码并说明。
- **Chrome**：`npx hyperframes browser ensure`（仓库钉的 0.8.82）把 chrome-headless-shell 提前下好——否则第一次渲染要现场下载 5–10 分钟。
- **浏览器 GPU**：用 HyperFrames 自己的硬件参数（`--use-angle=gl-egl` 等）拉起 Chrome 问 WebGL renderer。看到 NVIDIA → `--browser-gpu` 和快速捕获都安全；看到 SwiftShader / 没有上下文 → 一律不要求硬件。
- **NVENC 逐卡探测**：每块卡上跑一次 320×240 的 `h264_nvenc` 测试编码（从最后一块卡往下试）。两块 T4 时编码钉在 GPU 1；只有 GPU 0 应答时退回 GPU 0 并说明。

`--no-persist` 不把缓存挪进 `/kaggle/working/.cache`（默认挪：npm、Chrome、hyperframes、uv 四个缓存换成软链，**保存的笔记本**重启会话后还在，省掉每个会话重新下载）。`.kaggle/` 里的生成物不进 git。

## render.sh 的四个决定

`tools/kaggle/render.sh <project> [options]`（其余参数原样传给 `hyperframes render`）：

| 决定 | 规则 | 为什么 |
|---|---|---|
| fps | 合成写了 `data-fps` 且 ≤ 30 → 保留（24 fps 的片子不会被动到）；没写 → 显式 `--fps 30`；写了 > 30 → 保留并提示一句（加 `--fps 30` 可以砍一半帧数，前提是片子的规格允许） | 降帧率是最大的单项提速（约 48%），但片子自己的规格不该被工具悄悄改 |
| workers | **< 240 s：`--workers 1`**。≥ 240 s 且硬件 GPU：**不传 `--workers`**——并行快速捕获路由器（parallel router）只在 worker 数留给 auto 时才接手，把它钉在 3 个 worker 的并行流式捕获上；显式传了反而把路由器关掉。≥ 240 s 且软件渲染：每空一个核一个 worker，至多 6（Kaggle 4 核 → 3）。`--workers N` 永远可以覆盖 | 短片多 worker 会把每一帧先落到盘上再编码（最长慢 8 倍）；单 worker 保持流式编码。长片的 3-worker 并行 DE 流是实测最快的路径 |
| 编码 | NVENC 探测通过 → `--gpu`：HyperFrames 用 `h264_nvenc` 按 `--quality` 自己的恒定质量档（looks = `-cq 16`）编码，钉在第二块 T4 上 | CPU 那部分负载整个卸到 GPU 1；`bin/vh deliver` 的平台成片仍然 CPU libx264 CRF 16 重编码，交付质量不变 |
| 捕获 | 硬件 WebGL → `--browser-gpu --experimental-fast-capture`（drawElement 读 DOM 画录，长片最高 5×）。软件 → 两个都不要：软件 GPU 上它比截屏还慢 | Linux 上快速捕获默认不开（HyperFrames 只在 macOS/Windows 默认启用），要显式要；`HF_DE_PARALLEL_ROUTER/…_STREAM/…` 三个环境变量由 env.sh 常备 |

`--detach` 把渲染放进后台（`HYPERFRAMES_RENDER_DETACHED=1`，engines/README.md 讲过这个坑），打日志路径和停止命令。长渲染建议用它，notebook 的 cell 立刻返回。

## 提速清单的落地情况

对照 HyperFrames 自己的调优表，在这套里各自落在哪：

| 手段 | 落地 |
|---|---|
| fps 30（或 24） | render.sh 按上面的规则；`--fps` 可覆盖 |
| `HF_DE_PARALLEL_ROUTER=true` | env.sh 常备（忘了它长渲染慢 3 倍；设成环境变量还躲开 HyperFrames 的"失败一次就静默关掉"熔断） |
| GPU 编码 `--gpu` | NVENC 探测通过自动加，钉在第二块 T4 |
| 浏览器 GPU `--browser-gpu` | WebGL 硬件探测通过自动加 |
| worker 数 | render.sh 按片长定（上面） |
| draft 评审 | `--quality draft` 照常传（2–4× 迭代提速） |
| 简化贵 CSS | 仍是写作时的事：少叠大 `backdrop-filter` / `filter: blur()`，静态模糊预渲成 PNG（engines/README.md） |
| MP4 不用 WebM | 默认就是 MP4（VP9 编码在 CPU 上） |
| Chrome 缓存 | setup.sh 的 `browser ensure`，会话间留在 /kaggle/working |
| CDNs 本地化 | `bin/vh hf-init` 已经做（GSAP 进 node_modules） |
| 字体全声明 | `bin/vh hf-init` 已经做（local() @font-face） |
| lambda / cloudrun 分布式 | 不适用于 Kaggle（要云账号）；同一台机器上 `--workers` 就是并行 |
| HTML-in-canvas 快速捕获 | 硬件 GPU 时 render.sh 显式开（Linux 上默认关） |
| 分辨率分层 480p/720p/1080p | HyperFrames 的 `--resolution` 只接受整数倍预设（1080p、4K），没有 480p/720p；迭代提速靠 `--quality draft`，4K 靠 `--resolution 4k` |
| 预计算共享素材 | 写作时的事（logo、背景、字体一次画好），engines/README.md 的规则不变 |

## 质量没有让步的地方

- fps、worker、捕获路径只影响**速度**，不影响画面内容；唯一动画面的杠杆（帧率）保留给合成作者。
- NVENC 母片按 `--quality` 的恒定质量档编码（Turing NVENC 与 libx264 视觉上接近）；要上传的平台成片由 `bin/vh deliver` 照常 CPU libx264 CRF 16 重编码，交付链路没变。
- `bin/vh check`、`textcheck`、readcheck 等一切检查照常工作（Chrome 的缓存路径没挪出 `~/.cache` 的查找范围，只是换成了软链）。

## 排查

- **`browser GPU` 一行说 CPU/SwiftShader**：容器里 EGL 到不了 GPU（驱动库没挂全）。浏览器负载回到 CPU，`--browser-gpu` 和快速捕获自动不请求。渲染还是能出片，只是慢。
- **`encode` 一行说 CPU（libx264）**：ffmpeg 没有 NVENC，或 NVENC 在容器里被挡（探测失败）。`apt-get install ffmpeg`（Ubuntu 源里的构建带 NVENC）后重跑 setup.sh。
- **渲染命令完成了但进程迟迟不退**：HyperFrames 0.8.82 在个别机器上收尾慢（浏览器池的关闭竞态）。输出文件在完成横幅出现时就已经写好；等它自然退出，或长渲染用 `--detach`。
- **磁盘**：`/kaggle/working` 上限 20 GB，缓存占约 1 GB；4K 多 worker 截屏渲染的临时帧可能要几十 GB——env.sh 已把多 worker 流式编码常开（不落盘），仍然紧张时把 `--output` 指到空间够的盘。
- **GPU 配额**：Kaggle 每周约 30 小时。draft 用 `--quality draft`、只重渲改动的镜（canvas 片子有 `bin/vh patch`；HyperFrames 片子重渲整支），把配额花在成片上。
