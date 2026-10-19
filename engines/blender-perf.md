# Blender 性能层：Cycles 的速度与画质预设（Kaggle 2×T4）

> **全部实测（fact-locked）**：本页的每一个属性名、枚举值和默认值都在 2026-10-18 对着真的 `blender -b`（Blender 5.2.2 LTS Linux x64，官方 tarball）读回验证过——`tools/blender_perf.py` 的 `check` 子命令在任何机器上重放同一断言。渲染验证（tabletop-miniature 样片、乱序 PSNR、4K@200%）也在同一环境跑通。三个本页要回答的"经典参数"在 5.2.2 里**已经不存在**：`render.tile_x/tile_y`（Cycles 从 2.90 起整帧渲染）、`cycles.use_spatial_splits`（BVH 布局自动）、`simplify` 的纹理上限（4.0 移除）——【实测 5.2.2】。别再找它们，下面"三个不存在的旋钮"有真相。

标记沿用 `blender.md`：【实测】维护者的 Mac；【实测 5.2.2】本 Linux 沙箱（2 核 Xeon，无 GPU——所有 GPU 路径走 mock 设备测试 + `check` 断言验证，CPU 路径全链路实测）；【二手】只读到文档；【推测】无证据推断。

## 要点

| | |
|---|---|
| 是什么 | `tools/blender_perf.py`：三档 Cycles 画像（draft / final / final-cpu）+ 设备选择（Linux 上 CUDA 优先）+ GPU 绑定 + `check` 自审计。一条命令把整套设置落到场景上，漏一个都过不了 `check` |
| 为什么 | T4 没有 RT 核，OptiX 失去唯一的固定功能 BVH 优势，**CUDA 才是正确后端**；同时 OIDN（RGB+Albedo+Normal，Accurate）让 32–128 spp 出 2048 spp 的观感。组合是数倍的提速，且画质不妥协（AgX、反弹预算、间接 clamp 都在） |
| 确定性 | 三档各表态：final-cpu 是锚（CPU、固定 spp、无时限、无 persistent data，乱序逐像素相同——实测 PSNR=inf）；final/draft 用速度杠杆，同机同设置逐位一致，跨机不承诺（见"哪个设置拿走了确定性"） |
| GPU 分工 | Kaggle 2×T4：**GPU 0 归 ManimGX**（Vulkan 不能绑：`CUDA_VISIBLE_DEVICES` 不滤 NVIDIA 的 Vulkan 设备，见 `manimgx.md`），**Blender 用 GPU 1**（`tools/blender_run.sh --gpu 1`）。纯 Blender 管线两卡一起用有三条路：单进程不绑卡（Cycles 多卡同帧交织）、每镜头一卡（OpenHarness 的 RenderQueue 就是这么干的）、`tools/blender_split.sh` 按帧区间切给每张卡（每帧仍是单卡整帧，见下节） |
| 层级 | CLI `--device` > 场景 `build()` 的艺术参数（反弹、clamp、曝光——风格属于场景）> profile 地板（设备、合成器、降噪通道、种子策略——场景不该逐风格手调的项） |

## 三档画像（`tools/blender_perf.py` 的 PROFILES）

| 设置 | draft | final | final-cpu | 5.2.2 事实 |
|---|---|---|---|---|
| 设备 | auto（CUDA 优先） | auto（CUDA 优先） | cpu | `compute_device_type` 枚举：NONE/CUDA/OPTIX/HIP/ONEAPI（Linux）；METAL 只在 macOS【实测 5.2.2】 |
| 采样上限 | 32 spp | 128 spp | 128 spp 固定 | `cycles.samples` |
| 自适应 | 开，阈值 0.1 | 开，阈值 0.02 | **关**（固定 spp=最强确定性） | `use_adaptive_sampling` / `adaptive_threshold` / `adaptive_min_samples=0` |
| 每帧时限 | 120 s | 600 s | **0（关）** | `time_limit`；时限只裁采样阶段，不含降噪/编码【实测 5.2.2：4K@200% 一帧总 288.8 s，其中采样被 120 s 截住】 |
| 降噪 | OIDN，RGB+Albedo+Normal，prefilter ACCURATE，quality HIGH | 同左 | 同左 | `denoising_input_passes` 枚举 RGB/RGB_ALBEDO/RGB_ALBEDO_NORMAL；`denoising_prefilter` NONE/FAST/ACCURATE；`denoising_quality` HIGH/BALANCED/FAST【实测 5.2.2】 |
| `denoising_use_gpu` | 跟设备（GPU 时开） | 同左 | 关 | OIDN 的 GPU 模式走 CUDA/Metal，无 OpenGL 依赖，headless 安全 |
| 反弹 | 6 / 3 / 3 / 4 / 2 / 4（max/diffuse/glossy/transmission/volume/transparent） | 同左 | 同左 | 工厂默认 12/4/4/12/0/8——transmission 12→4、transparent 8→4 是净省；volume 0→2 只在有体积时才花钱【实测 5.2.2】 |
| clamp | 间接 10.0，直接 0.0 | 同左 | 同左 | 工厂默认恰好也是 10/0；显式写死防用户文件改过 |
| persistent data | 开 | 开 | **关** | `render.use_persistent_data`；见"茶杯事件" |
| Simplify | 开（subdiv 2、child 0.5） | 关（`--simplify` 应急开） | 同 final | `simplify_subdivision(_render)=2`、`simplify_child_particles(_render)=0.5`【实测 5.2.2；纹理上限旋钮已不存在】 |
| 合成器 | CPU（含 `compositor_denoise_device='CPU'`） | 同左 | 同左 | `compositor_device` 枚举 CPU/GPU，工厂默认 GPU；headless 下 GPU 合成会栽在无 GL 上下文，CPU 可靠【实测 5.2.2】 |
| 色彩 | AgX + "AgX - Medium High Contrast" | 同左 | 同左 | **先设 `view_transform` 再设 `look`**（look 列表依赖前者，顺序反了 look 会落空）【实测 5.2.2】 |
| 种子 | 0，animated seed 开 | 同左 | 同左 | 噪点随帧号变，仍是 t 的函数（`blender.md`"确定性"） |

## 17 点清单 → 5.2.2 落点

1. **CUDA 不 Optix 不 CPU**：`select_device` 的 auto 顺序 Linux=CUDA>OPTIX>HIP>ONEAPI（macOS=METAL）。T4=图灵无 RT 核，OptiX 只剩软件 BVH；有 RT 核的卡自己传 `--device optix`。CPU 仅显式 `--device cpu` 或回退，且打印原因。
2. **绑 GPU 1**：物理绑定只有 `CUDA_VISIBLE_DEVICES`（驱动层，Blender 进程只见那一张卡，进程内索引从 0 重排）——`tools/blender_run.sh --gpu 1`。进程内绑定是 `--device cuda:1`（cycle 偏好里的设备 use 位，适合改不了环境的场合）。两个都给了，别叠着用。
3. **合成器 CPU**：`compositor_device='CPU'` + `compositor_denoise_device='CPU'`。
4. **OIDN + 低采样**：denoiser=OPENIMAGEDENOISE，passes=RGB_ALBEDO_NORMAL，prefilter=ACCURATE（draft 也用 ACCURATE：预过滤成本远小于采样，画质不妥协）。
5. **自适应采样**：见上表；`adaptive_min_samples=0` 让自适应自己决定。
6. **每帧时限**：draft 120 s / final 600 s；final-cpu 关。这是保险丝，不是目标——一帧卡死不会吃掉整个 Kaggle 会话。
7. **反弹预算**：6/3/3/4/2/4（见上表）。
8. **clamp**：间接 10、直接 0——间接 clamp 压萤火虫，直接不 clamp 保高光，从而敢用更低采样。
9. **Simplify**：draft 常开；final 默认关，`--simplify` 是 16 GB 显存的应急闸（ subdivision≤2、child 0.5）。纹理上限旋钮 4.0 起不存在。
10. **persistent data**：管线开（几何/BVH/贴图留在显存，免每帧重建，重场景省 20–40 s/帧）；**swatch 渲染器永远关**（茶杯事件，下节）。开它要盯显存（T4 16 GB）。
11. **时间稳定性（动画降噪）**：OIDN 3 的时间降噪未进 5.2.2 的 Cycles；合成器时间降噪还是未合并 PR（#151020，`blender.md` 已记录）。现行对策照旧：animated seed + albedo/normal 通道；静态镜头可固定 seed（噪点粘住不闪）。
12. **瓦片尺寸**：**不存在的旋钮**——Cycles 2.90 起整帧渲染，`render.tile_x/tile_y` 已删除（合成器也是全帧，chunk 旋钮同样没了）【实测 5.2.2：`RenderSettings` 无此属性】。
13. **空间分割 BVH**：**不存在的旋钮**——`use_spatial_splits` 已删，BVH 布局自动。别照旧博客抄。
14. **persistent + BVH 复利**：真正活下来的旋钮是 `use_persistent_data`（BVH 建一次跨帧复用）——就是第 10 条。
15. **色彩管理**：AgX + Medium High Contrast（顺序：transform 先、look 后）。`tabletop-miniature` 的 `build()` 早就是这个组合——性能层把最佳实践固化成了地板。
16. **PBR**：Principled BSDF 是仓库铁律（反 blockout，`AGENTS.md`）；`check` 顺带报告没有 Principled 的材质（advisory，不算失败）。
17. **降噪质量**：= 第 4 条（HIGH + ACCURATE + albedo/normal）。

## 哪个设置拿走了确定性（哪档什么时候用）

| 杠杆 | 同机同设置 | 跨机 | 结论 |
|---|---|---|---|
| 自适应采样 | 逐位一致（噪声估计是确定性的）【实测 5.2.2：tabletop 第 30 帧，单独渲 vs 顺序渲，PSNR=inf】 | 不同（采样数随设备噪声估计走） | final 里没问题；要跨机复现就用 final-cpu |
| `time_limit>0` | 一致（同机速度稳定时） | **不可比**（慢机少采样） | 只当保险丝；final-cpu 关掉 |
| persistent data | 理论一致 | 理论一致 | **但有状态泄漏前科**——茶杯事件 |
| 设备 | 每设备一套像素（#101561，`blender.md` 已录） | — | 一个项目一种设备；验收线 45 dB（硬规则 1） |
| OIDN | 同输入同输出 | 官方称设备间可有微小差异 | 跨机不承诺，45 dB 线内 |
| `animated seed` | 仍是 (帧号, seed) 的纯函数 | 同 | 开着（`blender.md`"确定性"） |

**茶杯事件**（为什么 swatch 渲染器永远关 persistent data）：tabletop 的茶杯在 27–44 帧连渲时黑、单独渲时灰——Cycles 的 persistent data 让某帧依赖了"它前面渲过谁"，`determinism.sh` 抓到（24.5 dB）。所以 `styles/_swatch/blender_render.py` 在 profile 之后强制 `use_persistent_data=False`（`engines/blender.md` 的渲染管线、`tools/blender_run.sh --profile` 才是开 persistent 的地方）；开工前先跑 `tools/blender_bench.sh` 校准，渲完抽查 `determinism.sh`。

## 两块卡同时渲一支序列（blender_split.sh）

长序列的墙钟时间近乎减半：帧区间按 GPU 数切分，每半一个 Blender 进程，各自 `CUDA_VISIBLE_DEVICES` 绑一张卡（`blender_run.sh --gpu N` 链，画像照常先落）。**为什么选帧区间切而不是 Cycles 多卡**：多卡是同一帧内交织设备，噪声图案随设备组合变（#101561 的"每设备一套像素"）；帧区间切分下每帧都由单卡整帧渲出，与单卡逐帧渲的像素合同一致。**为什么安全**：本文的纯函数合同（物理 L0/L1/L2、种子策略、无渲染期模拟）保证第 N 帧不依赖第 N-1 帧——与 render-split.sh 的确定性门对网页片是同一条性质；违反合同的场景（未烘焙粒子、Simulation zone）不归这个工具管。

用法要点：`--resume` 只补缺帧（连续段走 `-s/-e/-a`，带洞的走 `-f` 列表）；`--bias 2:1` 在 GPU 0 还要给 Chrome/EGL 画帧时给第一张卡多分、第二张卡让份额；输出 PNG 序列到 `renders/blender-split/<场景>/`，`--encode` 直接出 MP4（libx264 CRF 18 slow，或 `--nvenc` p7/cq 19 对齐 Kaggle 的 final 档）。墙钟数写进项目 NOTES.md（预算照旧：帧数 × 中位数 × 1.5）。编排逻辑对着桩 Blender 验证过（`tools/blender_split_test.sh`，24 项断言）；真卡实测数在 Kaggle 上补。

## 工具

| 命令 | 用途 |
|---|---|
| `blender -b … --python tools/blender_perf.py -- check --profile final` | 落设置 + 逐项读回断言（28–32 行 PASS 表），退出码 1 = 有设置没落地 |
| `… -- probe` | 列各后端设备与 auto 顺序 |
| `tools/blender_run.sh --gpu 1 --profile final -- blender -b build/scene.blend … -a -- --cycles-device CUDA` | 物理绑卡 + 同进程"应用画像→渲"（`--python` 脚本先于 `-a/-f` 跑，实测验证）；成功不退出 Blender，失败带 `--python-exit-code 1` 停在渲染前 |
| `tools/blender_split.sh build/scene.blend --gpus 0,1 --profile final` | **两块卡同时渲一支序列**：帧区间按 GPU 数切分，每半一个进程、各绑一张卡（`blender_run.sh --gpu N` 链）；每帧都由单卡整帧渲出（比 Cycles 多卡同帧交织更贴确定性合同），断点续渲 `--resume` 只补缺帧，`--bias 2:1` 给共享卡留份额，`--encode` 直接出 MP4。前提即本文"纯函数"合同（L0/L1/L2 物理） |
| `tools/blender_bench.sh [--slug tabletop-miniature] [--frames 0,37,74,111,149] [--no-4k] [--out t.md]` | 校准协议的机器可读版：draft/final/fast/4K 各渲 5 帧取最好，环境戳（设备/GPU/构建/核数）随表走 |
| `tools/blender_mcp_setup.sh --headless --perf draft` | MCP 探索会话的起始场景带 draft 默认（启动链应用，不经 code_guard；实测 5 步往返全过） |
| `blender_render.py --quality fast --pct 200` | 样片渲染器的新档：GPU 上 final 画像（Kaggle 画质样片）、4K 校准（`--pct` 走 `resolution_percentage`，实测 3840×2160） |

## 层级与优先级

1. **CLI**（`--device cuda:1` / `blender_run.sh --gpu 1`）——最高，明确一次，全程生效。
2. **场景 `build()` 的艺术参数**——反弹、clamp、曝光、caustics 开关属于风格；`tabletop-miniature` 就自设 4/2/2/4 与 clamp 4（它要那件事的观感）。性能层在它之前应用，被它覆盖是**设计**。
3. **profile 地板**——设备、合成器、降噪通道/质量、种子策略、色彩变换。场景不该逐风格手调这些；它们是"机器怎么画"而不是"画什么"。

## 本机数字（校准样例，别当通用常数）

沙箱 2 核 Xeon CPU（无 GPU，draft/fast 回退 CPU），tabletop 第 30 帧、`--pct 33`：【实测 5.2.2】draft 12.4 s、final 18.9 s、fast 53.0 s（in-frames）；`--pct 50`：final 44.1 s；`--pct 200` draft 288.8 s（120 s 时限只裁采样段）。Kaggle T4 上的数字用 `tools/blender_bench.sh` 现场量，写进项目的 `NOTES.md`/`LOCAL.md`，预算按 `blender.md`"校准协议"：帧数 × 中位数 × 1.5。

## 来源

- [1] 属性与枚举：2026-10-18 对 Blender 5.2.2 LTS（官方 Linux tarball，headless）的活体探针——`check` 子命令即其可重放形式；三个"不存在"（tile/spatial splits/texture limit）为同日实测
- [2] `engines/blender.md`：两段式管线、5.0 API 破坏性改动、确定性合同（45 dB）、渲染时间校准协议、OIDN 时间降噪未合并（#151020）、#101561 设备间差异
- [3] `engines/manimgx.md`：GPU 0 归 ManimGX 的原因（`CUDA_VISIBLE_DEVICES` 不滤 Vulkan，ggml-org/llama.cpp#5259）
- [4] `engines/blender-mcp-ultra.md`：探索阶段规则与 `--perf` 的位置
- [5] 乱序/顺序 PSNR=inf 与 4K 尺寸验证：本页"实测"下的渲染记录（`/tmp` 证据随会话；`check` 与 `bench` 可随时重放）
