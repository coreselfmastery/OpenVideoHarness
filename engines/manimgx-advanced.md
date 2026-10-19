# ManimGX 进阶：速度实测与优化研究（H1–H6）

`engines/manimgx.md` 讲怎么用；本页是深入题——引擎到底缓存了什么、队列能不能调、显存怎么管、渲染与编码是否已经并行、多进程并发的真实行为——每条都标了**结论、依据、实测**。除标注外，实测都在本仓库的沙箱（2 vCPU、无 GPU、lavapipe 软件 Vulkan、manimgx 0.1.1 / Python 3.14）上做，探测脚本可复现；Kaggle T4×2 上的复测方法随每节给出。

## 速度数字（G2）

**本仓库 Fourier 片（25.0 s 成片，showcase/03）**

| 引擎 | 设置 | 墙钟 | 机器 | 出处 |
|---|---|---|---|---|
| Manim CE（迁移前） | `-ql`（480p15） | 22 s | 维护者的 Mac | 迁移前 NOTES.md 的记录（历史） |
| ManimGX 0.1.1 | `-r 854x480 --fps 15` | 10.9 s | **2 vCPU 沙箱，lavapipe（CPU 画）** | 迁移时实测 |
| ManimGX 0.1.1 | `-r 1920x1080 --fps 30` | 40.3 s（片长 0.62× 实时） | 同上 | 同上 |

沙箱连 GPU 都没有就已经和 CE 的 Mac 草稿同量级；**Kaggle T4 的数请用 `tools/manimgx_bench.sh` 现场测**，测完把表贴进项目 NOTES.md。

**官方基准**（[academa-labs/manimgx/benchmarks](https://github.com/academa-labs/manimgx/tree/main/benchmarks)，2026-10，Apple M4 Pro，1080p60，从启动到 MP4，各引擎都用最快编码档）：36.2 s 的片子 3.08 s 渲完——比 ManimCE 快 **90.6×**、比 ManimGL 快 **11.5×**、比 Blender Workbench 快 **18.7×**。这是上游自测，场景、设置、每轮数据都在仓库里；引用时注明出处。

**引擎内部数**（probe 场景 3 s，1920×1080@60，veryfast/CRF 23，`Film.export`）：`seconds` 7.27、`x264` 0.53（编码线程自己的耗时，只占总时长 7%，且与画帧重叠）、`converted` **6.8%**——平均只有 6.8% 的 16×16 块在帧间真的变了需要转换。静态为主、局部运动的讲题型画面，脏块编码的收益极大。

**同机对比 CE（可选）**：CE 要 cairo/pango（`sudo apt-get install -y libcairo2 libpango-1.0-0 libpangocairo-1.0-0`），然后在**另一个**项目目录 `uv venv --python 3.12 && uv pip install manim` 用同一场景渲 `-ql`。能跑通就得到同机数；跑不通（缺库、LaTeX）就只报 GX 数，别拿别的机器的 CE 数硬比。

## H1 · 着色器缓存：没有跨进程的持久缓存，但有别的缓存

**结论：ManimGX 0.1.1 没有持久化的着色器/管线缓存；每次进程起 GPU 时编译一次 WGSL 管线（在独立线程上，与 CLI 启动重叠），量级小到不值得优化。真正值得管的是文本布局缓存。**

依据（官方开发者指南）：着色器（`vector.wgsl`、`blend.wgsl`、`paint.wgsl`）编进引擎；GPU 在进程确定要画时于自己的线程上起来（`start_gpu`），首帧等它就绪。没有任何 `VkPipelineCache` 一类的落盘机制，也没有暴露相关旗标。

能持久化的是**文本排版和字体扫描**：按"源码 + 环境"做键写进用户缓存目录（默认 `~/.cache/manimgx/`，实测有 `fonts/`、`layouts/` 两个子目录，小场景 ~130 KiB），`MANIMGX_CACHE_DIR` 可以挪走。实测冷/热缓存对 3 s probe 场景只差 ~0.1 s（文本少）；MathTex 密集的长片收益更大。

**Kaggle 对策**：`export MANIMGX_CACHE_DIR=/kaggle/working/mgx-cache`，跨 session 保住布局缓存；着色器那点重编成本忽略。

## H2 · 场景级渲染缓存：引擎没有，我们补了

**结论：引擎不比较"场景变没变"；要跳过未改动的重渲，用 `tools/manimgx_render.sh`（对场景源码 + 目录里全部 .py + 渲染旗标 + manimgx 版本取 SHA-256，没变就跳过）。**

上游自己也是这个模式：ManimGX 文档站的影片构建对"代码 + 渲染设置 + 共享输入"取指纹，没变的影片不再渲。本仓库把同样的规则做成了包装脚本：缓存命令中在输出旁边 `<输出>.render.json` 里，`--force` 强制重渲。草稿迭代时改一处动画，只重渲真变了的那支场景。

## H3 · Vulkan 队列：没有可调的东西，别在这花时间

**结论：0.1.1 不暴露任何队列/设备参数（`render --help` 只有 `-o/-r/--fps/--preset/--crf`）；每进程一个 device + queue，wgpu 全权管理。**

官方文档通篇没有队列配置项；渲染器按"画帧 → 脏块转换 → 推给编码线程"单队列流水线工作。想在 T4 上提速，有效的杠杆是：`--preset`（编码在 CPU 侧，Kaggle 4 vCPU 上它是草稿吞吐的显性瓶颈之一）、分辨率/帧率（草稿 480p15）、以及进程数（H6）。

## H4 · 显存：引擎自管，进程边界就是回收边界

**结论：不需要人工防碎片。上传资源按内容哈希（xxh3）寻键，同形状同色自动去重共享，"连续若干帧没画到"的资源自动逐出；一个进程一个 GPU 上下文，进程退出显存全还。**

依据（官方）：GPU 内存按内容寻键（`add_path/add_mesh/add_rows` 存、`grow_path` 增、`evict` 弃），"equal shapes of the same kind share GPU memory; what no frame has shown for a while is freed"。0.1.1 修了一个相关的崩溃：透明重试期间资源被过早回收（上游 issue #16）——并发渲染报错先升级再排查。

多场景长片的工作法：**一场一进程**（`manimgx_render.sh` 循环），别在一个 Python 进程里连渲多场；显存峰值 = 单场峰值，回收最干净。T4 16 GB 对 1080p/4K 讲解片余量极大，实测无需关心。

## H5 · 异步渲染：已经是异步的，别再包一层

**结论：渲染与编码天然并行——x264 在自己的线程上收帧，引擎画帧/编码时释放 GIL；帧间没变的 16×16 块跳过转换（实测只转 6.8%），和上一帧完全相同的帧不重发、只把前一帧续长。**

依据（官方）：编码器"on a thread of its own"；"The GIL is released while the engine draws and encodes"；`Film.export` 的 `x264` 秒数就是那条线程的耗时（probe 实测占总时长 7%）。

所以：**不需要也不应该**在 Python 侧再套 asyncio/线程池——`Scene.render` 是同步语义，一个渲染进程就是一条完整的"画帧→编码→写 MP4"流水线；要"边渲边干别的"，开第二个进程（H6），那是引擎支持并发的正确粒度（一进程一 GPU，官方明说）。

## H6 · 多进程：可行、安全，T4×2 上都落在第一块卡

**结论：多个 ManimGX 渲染进程并发是官方支持的用法，实测输出与串行逐字节相同；但两块 T4 上它们都会用 GPU 0（没有 adapter 旗标，`CUDA_VISIBLE_DEVICES` 对 Vulkan 无效——详见 `manimgx.md` 的 GPU 一节）。第二块卡留给 CUDA 负载。**

实测（本沙箱，lavapipe）：两个进程并发渲同一场景（共享缓存目录 / 各自 `MANIMGX_CACHE_DIR` 两种姿势）全部 exit 0，六个输出文件全部 9,727 字节、与串行渲的完全一致；墙钟 6.33 s（串行两遍）→ 4.53 s（并发），2 核上 1.4×——瓶颈是 CPU 不是引擎。T4×2 上 GPU 侧毫无压力，**并发数按 vCPU 定：Kaggle 4 核建议 ≤ 2 个渲染进程**，再多就互相抢 CPU、编码线程先饿。

姿势：

```bash
# 两个项目（或草稿+成片）各一个进程，输出路径别写同一个文件
uv run manimgx render -r 854x480 --fps 15 scenes/a.py A -o out/a-draft.mp4 &
uv run manimgx render -r 854x480 --fps 15 scenes/b.py B -o out/b-draft.mp4 &
wait
```

## 复测与取数

- `tools/manimgx_probe_gpu.sh`——GPU 确认（nvidia-smi、libvulkan1、ICD、vulkaninfo、渲染时利用率采样），Kaggle 第一格跑它。
- `tools/manimgx_bench.sh`——草稿/成片/(可选 4K) 各 N 轮计时，出 markdown 表。
- 要引擎内部数（编码占比、脏块比例），从 Python 侧渲：`film = MyScene().render(video=…)`，读 `film.export.{seconds,x264,converted,bytes}`。

本页结论基于 manimgx 0.1.1（2026-10）；上游在快速迭代，升版本后把 H5/H6 的两条实测重跑一遍（脚本在 `scripts/` 的探测思路照抄即可），再更新本页。
