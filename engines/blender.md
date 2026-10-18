# Blender 引擎指南（实验性）

> **部分验证（partly verified）**：2026-10-01 维护者的 Mac（M3 Max，macOS 15）装上了 Blender 5.2.2 LTS，风格库的 `tabletop-miniature` 样片（`styles/_swatch/` 的 Blender 场景）是在它上面做的。"首次冒烟"里做过的几项已经写回本文，标【实测 5.2.2】；没做的几项和其余的 Blender 命令、API 和数字仍来自官方文档、release notes 和 issue。ffmpeg、色彩、alpha、EXR 和 `sandbox-exec` 相关的结论标【实测】。**渲染时间先渲 3–5 帧校准，把结果写进 BRIEF**（见"渲染时间"）。
>
> 标记：【实测】在维护者的 Mac（macOS 15，ffmpeg 8.0.1）上跑过；【实测 5.2.2】用 Blender 5.2.2 跑过；【二手】只读到搜索摘要或第三方转述，没能打开原文；【推测】没有证据的推断。引用编号 `[n]` 见文末"来源"。`bin/vh` 里没有项目用的 Blender 子命令，下文都是直接调用 `blender`；风格样片走 `bin/vh style <slug>`，做法见 `styles/_swatch/README.md` 的"Blender 场景"，那里的 `blender_render.py` 是一个能跑的逐帧渲染器。

## 要点

1. **路线**：`blender -b` 两段式：`build`（`timeline.json` → `scene.blend`）和 `render`（`scene.blend` → PNG 序列）。合成走 HyperFrames 或 ffmpeg。MCP 只在探索阶段用，不进管线，而且要在沙箱里用。
2. **版本**：固定 **5.2 LTS**（2026-07-14 发布，维护到 2028-07）[1][2]。5.0 起只支持 Apple Silicon，macOS ≥ 13 [3]，Python API 有破坏性改动，凭 2.8–4.x 的记忆写的脚本多半会报错。
3. **引擎分工**：分镜和 draft 用 EEVEE（或 Workbench），final 用 Cycles（Metal）加 OIDN，风格化镜头可以直接 EEVEE final。
4. **确定性**：只承诺"同一台机器、同一 Blender 构建、同一设置"下，按硬规则 1 的口径（无损 PNG，PSNR ≥ 45 dB）乱序渲染一致。渲好的 PNG 序列是带哈希的素材，合成时不重渲。
5. **纯函数**：时间线用我们自己的缓动、样条和节拍函数，逐帧采样成关键帧；不用 Python handler，不靠实时模拟。
6. **合成与颜色**：默认交 PNG（straight alpha，视图变换已烘进去）；EXR 是 scene-linear，进 ffmpeg 要显式 `-apply_trc iec61966_2_1`；最后一步 H.264 要写 BT.709 矩阵和四个标签，否则饱和色偏 20 个色阶左右。
7. **安全**：官方 MCP 自己警告，它会直接执行 LLM 生成的代码，没有任何防护 [16]。**没有沙箱，就不要让 LLM 生成的 bpy 代码经过任何 MCP 执行**；管线里跑 agent 写的脚本同理。
8. **许可**：输出归自己，但公开发布的、调用 bpy 的脚本要以 GPL 兼容协议发布 [17]。本仓库的做法（维护者 2026-10-01 决定）：import bpy 的文件标 `SPDX-License-Identifier: GPL-3.0-or-later`，按 GPL 分发，其余仍是 MIT（见"许可证"）。

## 什么时候用 Blender

| 需求 | 首选 | 原因 |
|---|---|---|
| 3D 世界里的文字、节点标签、UI，一镜到底 | HyperFrames + Three.js | 文字和相机是同一份代码，实时；样板已有（`showcase/04-intro-film`） |
| 玻璃、水、皮肤（SSS）、焦散、体积光的产品镜头 | Blender（Cycles） | 路径追踪的光传输 |
| 布料、液体、烟 | Blender + 烘焙（缓存当素材） | Three.js 没有 |
| 非写实的 3D（toon、平涂、线稿） | Three.js 或 Blender（EEVEE） | 看有没有模型、要不要真运动模糊和景深 |
| 公式曲面、向量场、几何对象 | ManimGX 的 `ThreeDScene` | 精确 |
| 超过 30 秒、4K、大量镜头 | 先算渲染账 | 见"渲染时间" |

Blender 的增量只在路径追踪的光传输、物理模拟、真实运动模糊和景深、导入真实 3D 资产这几件事上。按类型：03 产品宣传收益最高（英雄镜头 1–3 个交给 Blender，UI 镜头仍是 HyperFrames；只用用户自己的模型，视图变换选 PBR Neutral）；01 讲解和 04 MV 可以做少量插页（公式和几何仍用 Manim，歌词和字仍在 HyperFrames）；02 短片最多 1–2 个 3D 镜头；05、07、08 不建议。风格里 `product-keynote`、`clockwork-map`、`monumental-scifi` 最可能受益，`blueprint` 和 `silhouette-papercut` 的 `STYLE.md` 明令不做 3D。reviewer 看 3D 镜头时，额外给它"为什么这个镜头需要 Blender（一句话）"，说不出来就降级成 Three.js 或 2D。

## 版本与安装

| 版本 | 发布日期 | 与我们相关的点 |
|---|---|---|
| 4.5 LTS | 2025-07-15 | 最后支持 Intel Mac 的版本 [1][3] |
| 5.0 | 2025-11-18 | 要求 Apple Silicon，macOS ≥ 13；新增 ACES 1.3/2.0 与 AgX HDR 视图、可选工作色彩空间；Python API 破坏性改动 [1][3][4] |
| 5.1 | 2026-03-17 | `bpy` 轮子从 cp311 换到 cp313；官方 MCP 要求 5.1+ [1][18][16] |
| **5.2 LTS** | **2026-07-14** | LTS 到 2028-07；EEVEE 大改；Cycles 纹理缓存；后台模式新增 `gpu.init()` [2][4] |

- **安装**：`brew install --cask blender`，装到 `/Applications/Blender.app` 并把 `blender` 链进 `$(brew --prefix)/bin` [18]。cask 永远跟最新版走；要钉住点版本，从 download.blender.org 取固定的 dmg（5.2.0、5.2.1、5.2.2 都在，约 346 MB [2a]），把它的 sha256 记进 `blender.lock`。
- **`bpy` 模块**：PyPI 上 5.0.x 是 cp311，5.1.x、5.2.x 是 cp313 [18]；要用就 `uv venv --python 3.13`。参数顺序、`-f` 列表、`--cycles-device` 这些官方文档描述的行为都是 CLI 的，所以**默认走 `blender -b`**，模块只留给单元测试。
- **`blender.lock`**：记 `bpy.app.version_string`、`bpy.app.build_hash`、dmg 的 sha256、设备类型、预设名、OIDN 开关。5.2 的 EEVEE 做了能量守恒修复，部分场景比 5.1 更暗 [4]，版本之间输出本来就不一致。

## 两段式：build → render

### 目录与产物

```
projects/<date>-<slug>/blender/
├── timeline.json        # 唯一事实来源，单位秒
├── assets/              # glb/usd/blend/HDRI；每件在 NOTES.md 素材台账有来源、许可、sha256
├── build/scene.blend    # build 的产物，可删可重建
├── caches/              # 烘焙缓存（关键帧 JSON、点缓存/Alembic/VDB），带 sha256
├── out/draft/ out/plate/ out/alpha/    # PNG 序列
└── blender.lock         # version, build_hash, device, preset, denoiser, seed
```

### timeline.json（最小 schema）

```json
{
  "schema": "vh-blender-timeline/1",
  "fps": 30, "duration": 8.0, "resolution": [1920, 1080], "seed": 20261001,
  "look": { "view_transform": "Khronos PBR Neutral", "display": "sRGB", "exposure": 0.0 },
  "camera": { "fov_deg": 35, "path": [
    { "t": 0.0, "pos": [0, -6, 1.6], "look_at": [0, 0, 1.0] },
    { "t": 3.0, "pos": [2.5, -4, 1.4], "look_at": [0, 0, 1.0], "ease": "inOutCubic" } ] },
  "objects": [ { "id": "product", "asset": "assets/product.glb",
                 "xform": [ { "t": 0, "rot_z_deg": 0 }, { "t": 8, "rot_z_deg": 360 } ] } ],
  "lights":  [ { "id": "key", "type": "AREA", "size": 2.0, "energy": 600, "pos": [3, -3, 4], "color": "#fff4e5" } ],
  "events":  "audio/music.beats.json"
}
```

`events` 指向节拍表，`build` 按 `beats`、`hits` 给发光强度、镜头冲击之类的量采样，做法和 `playbook/08` 的 `k = exp(-(t-beat)/0.12)` 相同，不手填时间。

### build 阶段

命令（没跑过）：`blender -b --factory-startup --python-exit-code 1 -noaudio --python lib/build.py -- timeline.json build/scene.blend`。Blender 的参数按给出顺序执行，先读文件再改设置 [5]。`lib/build.py` 要做的事：

- 从 `bpy.ops.wm.read_factory_settings(use_empty=True)` 开始，不读用户偏好和启动场景。
- `frame_start = 0`，帧 n 对应 t = n / fps；每帧采样关键帧，不写 fcurve，不注册 handler（见"每帧是 t 的纯函数"）。
- Cycles：`seed` 取自 timeline，`use_animated_seed = True`，`time_limit = 0`；不写 `METAL+CPU`（见"确定性"）。
- 视图变换和显示设备来自 `look`。枚举值以当前版本 `view_settings.bl_rna.properties['view_transform'].enum_items` 为准，不凭记忆写字符串（Filmic 已弃用，新增 ACES）[7][4]；引擎 id 用 `bpy.app.version` 门控。
- 导入资产之后立刻写素材台账（来源、许可、sha256）；烘焙和缓存的产物写进 `caches/` 并登记哈希。
- `lib/` 里放一层 API shim 和一条 5 帧冒烟测试，升级版本时先跑冒烟。

这里不放可运行的 bpy 脚本（许可问题见"许可证"，维护者待定），循环的做法是：

```text
对每一帧 n，从 frame_start 到 frame_end：
    t = n / fps
    (pos, look) = 相机路径在 t 的值     # 我们自己的样条和缓动，与 HyperFrames 同一实现
    相机的位置和旋转 = pos，以及由 look 算出的朝向
    对相机的位置和旋转各打一个关键帧，帧号 = n     # bpy 里是 keyframe_insert(frame=n)
```

### 渲染预设与 render 命令

预设的数值是起点，全部【推测】，以 5 帧校准为准：

| 预设 | 引擎 | 关键设置 | 用途 |
|---|---|---|---|
| `draft` | EEVEE | 分辨率 50%，其余默认 | 分镜、animatic、联系表 |
| `final` | Cycles，Metal | 96–256 spp，OIDN 高质量，关自适应，`time_limit=0`，间接光 clamp | 定稿底片 |
| `final-eevee` | EEVEE | 100% 分辨率，采样按画质 | 风格化镜头 |
| `alpha` | 同 `final` | `film_transparent=True`，`color_mode=RGBA`，PNG 16 位 | 带 alpha 的合成路径 |

命令行顺序按官方手册：`-f`、`-a` 放最后，顺序错了设置会被静默忽略；Cycles 选项在 `--` 之后 [5]。`-o` 里的 `//` 是 `.blend` 所在的目录，这里是 `build/`，所以输出写 `//../out/…` 才落在 `out/` 下。没跑过：

```bash
# 分块渲染，可续跑；一个进程一块
blender -b build/scene.blend -E CYCLES -o //../out/plate/f_#### -F PNG -s 0 -e 59 -a -- --cycles-device METAL --cycles-print-stats
# 抽帧（联系表用）：-f 接逗号列表或 a..b
blender -b build/scene.blend -E BLENDER_EEVEE -o //../out/draft/f_#### -F PNG -f 0,60,120,180
```

render 要带看门狗（沿用 `playbook/02` 的做法）、检查退出码、核对帧数和每帧 YAVG、按块记录墙钟时间。

## 5.0 起的 Python API 破坏性改动

下面这些对着 5.0 的 release notes 原文核对过（2026-10-01）[4]：

| 旧 | 5.0 起 |
|---|---|
| 渲染引擎 id `BLENDER_EEVEE_NEXT` | `BLENDER_EEVEE` |
| `scene.node_tree`（合成器节点树） | 已删除，改用 `scene.compositing_node_group`；`scene.use_nodes` 已弃用（6.0 删除） |
| File Output 节点的 `file_slots`、`layer_slots`、`base_path` | 已删除，改用 `directory`、`file_name`、`file_output_items` |
| `ImageFormatSettings`：直接设 `file_format` | 要**先**设 `media_type`，再设 `file_format` |
| 渲染通道名 `DiffCol`、`Z` 等缩写 | 改成全称：`Diffuse Color`、`Depth` 等 |
| `Action.fcurves`、`Action.groups`、`Action.id_root`（旧 Action API） | 已删除，要走每个 slot 的 channelbag |

所以只用 `keyframe_insert`，不去改 fcurve 的插值类型；引擎 id、视图变换枚举、通道名都用 `bpy.app.version` 门控或枚举查询，不写死字符串。

## 每帧是 t 的纯函数：关键帧与物理

关键帧，不用 handler：时间线里的相机路径、物体变换、灯光、材质参数，用我们自己的缓动、样条、节拍函数（和 HyperFrames 里同一套）**每帧采样一次**，用 `keyframe_insert(frame=n)` 写进去。理由：Blender 的运动模糊是在快门区间内对动画曲线做子帧插值，`frame_change` handler 不会在每个子帧里被调用【推测：Cycles 运动模糊读的是求值后的动画系统】，用 handler 驱动的运动没有运动模糊。逐帧密采样加默认的 Bezier 插值，整数帧上的值精确等于我们的函数，子帧上平滑。

**物理，三级选法**

| 级别 | 做法 | 什么时候选 | 状态 |
|---|---|---|---|
| L0 解析式 | 用公式算：弹跳、阻尼弹簧、轨道、齿轮（转角 = 齿数比 × 主动轮角度），写成 t 的函数再采样成关键帧 | 默认，大多数"看起来有物理"的镜头够用 | 纯函数 |
| L1 烘焙成关键帧 | 刚体模拟一次，`bpy.ops.rigidbody.bake_to_keyframes(frame_start, frame_end, step)` 转成关键帧，再删掉 rigid body world [14] | 需要碰撞、堆叠、倒塌 | 烘焙后是纯函数；烘焙本身跨机器是否一致【推测：否】，所以把烘出的关键帧 JSON 入项目并记哈希 |
| L2 缓存当素材 | 布料、软体、流体、烟、毛发：烘焙到磁盘（point cache、Alembic、VDB），渲染只按帧读缓存 | 必须要这类效果时 | 缓存文件带 sha256 进素材台账，换种子或参数才重烘。乱序渲染烘焙缓存要单独测：有 issue 说烘焙过的刚体缓存乱序渲染时行为异常【二手】[14] |

不在渲染时现算模拟，不用没烘焙的粒子系统和 Geometry Nodes Simulation zone，不用带状态的 `frame_change` handler 和 `bpy.app.timers`。

## 确定性：种子、采样数、降噪

官方手册说明 `Seed` 决定噪声图案，`Animated Seed` 让种子逐帧变化，动画里推荐开，因为变化的噪声不那么显眼 [6]。种子随帧变化，机制应是按帧号偏移【推测：手册没写实现】，画面仍是（帧号, seed）的纯函数。

| 来源 | 影响 | 对策 |
|---|---|---|
| Cycles `Time Limit` | 到时限就停，哪怕没到目标采样数 [6]，结果随机器速度变化 | 固定为 0（关） |
| 自适应采样 | 像素是否停止取决于噪声估计；同设备是否逐位一致【推测：没找到官方说法】 | final 预设默认关自适应，固定 spp；要开就先做下面的验收 |
| 设备 | 同一场景在 CPU、CUDA、OptiX 上渲出的像素不同（#101561）；Cycles 开发者回复：设备之间总会有差异，不算 bug，归因于硬件精度差异 [12] | 一个项目只用一种设备（Metal），不用 `METAL+CPU` |
| OIDN 降噪 | 官方文档称不同设备之间可能有小的数值差异；RT 滤波器不具备时间稳定性 [10] | final 用默认（高质量）模式；降噪是逐帧的，可能闪 |
| 版本 | 5.2 EEVEE 输出与 5.1 不同 [4] | `blender.lock` 钉死 |
| Python | `random`、时间、`os.urandom` 会破坏纯函数 | 用带种子的 `hash(name, i)`，和硬规则 1 一致 |
| 文件哈希 | PNG 元数据可能含渲染时间等字段【推测】 | 比较像素，不比文件哈希 |

- **闪烁**：逐帧降噪的残余噪声在相邻帧之间不对齐，静态区域会"沸腾"。OIDN 3 已在 2026-01 宣布带时间降噪，Blender 合成器里的时间降噪节点还是一个未合并的 PR（#151020）[10]，先不用。现在的办法：提高 spp；开 albedo 和 normal 辅助通道；静态镜头可以固定 `seed`、关 animated seed（噪声"粘"在画面上，但不闪）【推测：要做 A/B】。
- **验收**：`blender -b scene.blend -f N` 单独渲第 N 帧，与整段 `-a` 渲出来的第 N 帧，比无损 PNG：`ffmpeg -i a.png -i b.png -lavfi psnr -f null -`，要求 ≥ 45 dB。预期同机同设置下逐像素相同【推测】。

## 渲染时间：先用 5 帧校准

M3 Max 上介绍片开场的实测见下文"Metal"一节的"速度"（1080p 每帧约 2–39 s，4K 约 4 倍）；新场景照样先校准，不要套用。**校准协议**（写进 BRIEF 的费用预算）：挑最重的镜头，渲 t=0、⅓、⅔、末尾各 1 帧，再加一帧最重的特写，记下每帧墙钟时间和 `--cycles-print-stats` 的内存；预算 = 帧数 × 中位数 × 1.5（重试）。结果写进 `LOCAL.md` 的渲染速度一行，和 `engines/README.md` 里 ClaudeAnimationBase 的"1080p 约 0.13 秒/帧（Metal）"并列。超过预算 1.5 倍就停下告诉用户。

### 出 4K

和 1080p 用同一份场景：只把 `render.resolution_percentage` 从 100 改成 200（介绍片的 `galaxy.py --pct 200`），相机、焦距、景深都不动。星点、卡片、光带这些东西要按世界尺寸摆（米），不要按像素，这样 4K 下大小自然对；以像素为单位的参数要逐个换算，例如 Freestyle 的绝对线宽、合成器里 Blur 的像素尺寸、像素滤波宽度【推测，没逐个验证】；Glare 的 Size 是 0–1 的相对值，跟着画面走。每帧约是 1080p 的 4 倍：介绍片 475 帧的开场约 6 小时。渲出来的帧编码成视频后，和 1080p 那一版一起过 `bin/vh check <4K> --against <1080p>`（`engines/README.md`"出 4K"）。

## Metal 上的 Cycles 与 EEVEE

- **Cycles**：Metal 只支持 Apple Silicon，macOS ≥ 13 [5a]。4.0 release notes 写明 M3 支持硬件光追，Cycles 默认使用（MetalRT 设为 Auto）；M1、M2 默认关闭 [9a]。OIDN 的 GPU 加速从 4.1 起在 Apple Silicon 上可用 [10]。
- **EEVEE**：4.2 起新的 EEVEE 走 Metal，4.2 有两个已记录的坑 [11]：命令行渲染动画时内存不释放，渲到一半卡死（#125333，修复在 4.3 并回溯到 4.2.4，有用户反馈 4.3 上仍然出现，没有核实）；同一个含体积的场景明显变慢（#128253：4.1.1 每帧 1–3 s，4.2.2 约 75 s，关体积或把体积分辨率降到 1:16 后约 14–17 s，单个场景）。5.x 是否还有残留，要用 5.2 跑一次 300 帧的耐久测试并监控内存；稳妥的做法是分块渲染，每个进程不超过 60 帧，崩了只重跑那一块。
- **电源**：M4 Pro 上开"低电量模式"，Cycles 性能降到正常的 65–71% [13]。渲染前确认插电、关低电量模式，长任务外面包 `caffeinate -i`。
- **后台模式**：5.2 新增 `gpu.init()`，用来在 `--background` 下初始化 GPU 后端 [4]。EEVEE 在无头脚本里拿不到 GPU 上下文时，先试这个【推测】。

## 与 HyperFrames、ffmpeg 合成：alpha、EXR、色彩管理

| 路径 | 什么时候 | 格式 | 注意 |
|---|---|---|---|
| A 不透明底片 | Blender 出整个背景或英雄镜头，HTML 叠字和 UI | PNG 序列 → mp4（BT.709 tv，CRF 12–16），当 `<video>` 底层 | 最常用，最省事 |
| B 带 alpha 的 PNG 序列 | 3D 物体要和 HTML 图层前后穿插 | RGBA PNG，页面里按 `floor(t × fps)` 取帧，和 `playbook/05` 的绿幕接法同一种 | 1080p RGBA 单帧约 1–3 MB【推测】，300 帧到 GB 级；HyperFrames 的 `<video>` 是否保留输入视频的 alpha，文档没写，未验证 |
| C ffmpeg `overlay` | 代码层和 Blender 层各渲成文件再叠 | PNG 序列或 ProRes 4444 | 见下面 alpha 一段 |
| D 夹心 | 字要夹在 3D 物体之间 | 渲两层：背景（不含英雄物体）和前景（英雄物体 + 阴影，透明底），字放中间 | Cycles 的 Shadow Catcher（`is_shadow_catcher`）可以把 3D 物体的影子落到 HTML 背景上 [15]；手册没有提到 EEVEE，第三方教程说 EEVEE 要手搭材质【二手】 |
| E Blender 里合成 | 需要景深、AO、Cryptomatte 遮罩 | 多层 EXR，在 Blender 合成器里出 PNG | 5.0 起合成器接口变了（`compositing_node_group`） |
| F 深度遮挡 | 要让 HTML 或 Three.js 里的字按 3D 深度躲到物体后面 | 导出 Depth 通道，浮点 EXR 或归一化后的 16 位 PNG，在 WebGL 层比较深度【推测：没有做过】 | 深度要和相机的近远裁剪面一起存，否则没法还原 |

**视图变换**（手册的枚举：Standard、Khronos PBR Neutral、AgX、Filmic、ACES 1.3/2.0、Raw、False Color；Filmic 已标注 deprecated）[7]：
- 和 HTML 的扁平图形、品牌色无缝拼，或者非写实、平涂：Standard（只做显示转换），或自发光材质平涂；
- 产品镜头要品牌色准：Khronos PBR Neutral（4.2 起有），让输出的 sRGB 颜色尽量贴近材质里的基色 [7][19]；
- 电影感、强光源、自发光：AgX（新文件默认），高光去饱和、更像胶片，但它改整片的色彩性格，HTML 层要么补同样的 look，要么整片统一再调一次色 [19]；
- Raw 和 False Color 只用来检查，不用来出片 [7]。

**PNG 与 EXR**：PNG 的视图变换和显示变换已经烘进像素，8 位按 straight alpha 存，这是合成默认值；EXR 存 scene-linear、premultiplied alpha，AgX 之类的 look **不在里面** [8][7]。ffmpeg 读 EXR 时不会自动做 sRGB 编码【实测】：6 个 scene-linear 值 `0, 0.0031308, 0.05, 0.18, 0.5, 1.0`，sRGB 公式应得 `0, 10, 63, 118, 188, 255`；ffmpeg 默认得到 `0, 1, 13, 46, 128, 255`（中灰 0.18 → 46，画面发黑）；加 `-apply_trc iec61966_2_1` 后与公式完全一致。`-apply_trc` 标了 deprecated，但 8.0.1 上仍然有效。维护者的 Mac 上的 ffmpeg 没有 zscale、libplacebo、OCIO，做不了更精细的转换。多层 EXR 用 `-layer` 选层。

**alpha 与 ffmpeg**：Blender 内部 premultiplied，存 8 位格式（PNG）时转成 straight，存浮点格式（EXR）保持 premultiplied，这是 2.66 起的约定 [8]；5.x 没看到改动说明，出片前用一张半透明边缘的测试图确认一次【推测】。ffmpeg `overlay=format=auto` 把 RGBA 输入当 straight，合成到白底上最大误差 0.9 个色阶；输入是 premultiplied 时要写 `overlay=format=auto:alpha=premultiplied`（误差 1.0），漏写则边缘最大偏 57 个色阶（暗边）【实测】。

**最后一步的 YUV 矩阵**：PNG 序列编成 H.264 时，如果不指定矩阵，swscale 默认用 BT.601，又不写标签；浏览器和手机按 BT.709 解码，饱和色就偏了。8 个色块实测：不写任何参数，最大偏 21 个色阶；只写 `-colorspace/-color_primaries/-color_trc`，最大偏 3，但 ffprobe 里 primaries 和 trc 仍是 unknown；下面的写法最大偏 3，四个标签齐全【实测】。

```bash
ffmpeg -framerate 30 -i out/plate/f_%04d.png \
  -vf "scale=out_color_matrix=bt709:out_range=tv,format=yuv420p,setparams=colorspace=bt709:color_primaries=bt709:color_trc=bt709:range=tv" \
  -c:v libx264 -crf 14 plate.mp4
# 检查：应显示 yuv420p / tv / bt709 / bt709 / bt709
ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt,color_range,color_space,color_transfer,color_primaries -of default=nw=1 plate.mp4
```

## 安全：MCP 与 LLM 生成的 bpy

**默认关。** 用 Blender MCP 之前先问用户，而且只在虚拟机或单独的 macOS 用户下用。MCP 会话本身不可复现，不算产物：每次会话结束，把确认有用的操作固化成 `build.py`。

- **官方 MCP**（Blender Lab，`projects.blender.org/lab/blender_mcp`，GPL-3.0；v1.0.3 于 2026-09-11，要求 Blender 5.1+）：页面明确警告，服务器会直接执行 LLM 生成的代码，没有任何措施防止数据被删除或外发，建议用虚拟机或不含敏感信息的系统（2026-10-01 对着页面核对）[16]。开发者论坛的讨论里，官方仓库只附了一个承认不足以当安全边界的 `weak_sandbox.py` [16]。
- **社区 `ahujasid/mcp-for-blender`**（原名 `blender-mcp`，MIT，约 2.98 万星）：`execute_blender_code` 用 `exec()` 执行任意 Python；通过一个无认证、无加密的本地 TCP socket 通信；已有 CVE（CVE-2026-10661，评分低，`input_image_url` 注入）；新版有 `BLENDER_MCP_SAFE_MODE=1`，拦截文件读写、网络、起子进程、持久化代码 [16]。它集成的 Poly Haven（CC0）、Sketchfab、Poly Pizza（约 69% 是 CC-BY，需署名）等素材源，每一项都要进素材台账。
- **威胁面**：模型自己写出破坏性代码；间接提示注入（`.blend` 里的对象名、文本块、网页素材都能带指令）；`.blend` 里的自动执行脚本（Python 驱动器、启动脚本），命令行默认 `-Y` 禁用，不要加 `-y` [5]。

**管线里跑 agent 写的 `build.py`**：① 静态检查：AST 扫描，禁 `os`、`subprocess`、`socket`、`urllib`、`shutil`、`eval/exec`、`__import__`，`open` 只许写输出目录；② `--factory-startup`、不加 `-y`；③ 套 `sandbox-exec` 和 `env -i`（下）。第三方 `.blend` 和素材当不可信输入：先 `--disable-autoexec`（默认已是）打开，扫描文本块和驱动器再用。要联网取素材，单独做一步，显式 URL、记来源和许可，不在渲染进程里取。

**`sandbox-exec`**（手册标注 DEPRECATED，但在 macOS 15 上可用）。下面的 profile 在 `sh`、`curl`、`python3`、`ffmpeg` 上验证过：输出目录可写；其他位置（包括 `/tmp` 和真实的 home）写入得到 `Operation not permitted`；网络被拒（`curl` 返回 000，不加沙箱时是 200）【实测】。套 Blender 本体还要补几行，见下面的"首次冒烟"和 `styles/_swatch/render.sh` 的 `bl_profile`（一份在 Blender 5.2.2 上跑通的完整 profile）。

```scheme
(version 1)
(allow default)
(deny network*)
(deny file-write*)
(allow file-write* (subpath "/ABS/PATH/TO/PROJECT/blender/out"))
(allow file-write* (literal "/dev/null") (literal "/dev/dtracehelper"))
```

**沙箱里的进程要用 `env -i`，只放行几个变量。** 只写 `sandbox-exec … env TMPDIR=… blender`，整个环境都会传给 LLM 写的脚本，其中有 `FAL_KEY`、`GEMINI_API_KEY`、`ELEVENLABS_API_KEY` 这类 key（在子进程里打印环境变量验证过）。`HOME` 和 `TMPDIR` 指进白名单：否则 Python 的 `tempfile` 在沙箱里找不到可写的临时目录【实测】。

```bash
mkdir -p blender/out/.tmp blender/out/.home
sandbox-exec -f vh_blender.sb env -i PATH="$PATH" HOME="$PWD/blender/out/.home" TMPDIR="$PWD/blender/out/.tmp" LANG=en_US.UTF-8 \
  blender -b --factory-startup ...
```

沙箱不是安全边界的终点：`(allow default)` 只挡了网络和写入，读取 `~/.ssh`、`~/.zsh_secrets` 这类文件仍然放行（验证过）。要更严，在 profile 的 `(allow default)` 之后加一行拒读，例如 `(deny file-read* (subpath "/Users/<you>/.ssh") (literal "/Users/<you>/.zsh_secrets"))`（路径写绝对路径；实测读被拒，python 照常运行）；或者整个家目录拒读，再放行项目和字体目录（样片的正式渲染就是这样）。用 Metal 渲染时整个家目录拒读会崩，见"首次冒烟"。

## 许可证（2026-10-01 已定：选项 (2)）

以下是官方原文的要点，不是法律意见；许可页和 FAQ 的原文 2026-10-01 对着页面核对过 [17]。

| 问题 | 官方说法 | 结论 |
|---|---|---|
| Blender 本体 | GNU GPL v2 或更新；个别模块用 Apache 2.0 等更宽松协议 [17] | — |
| **输出**（图片、视频、`.blend`） | 用 Blender 做出的作品完全归创作者所有；`.blend` 被视为程序输出，版权归用户，可用于任何闭源产品 [17] | **不受 GPL 影响** |
| **调用 bpy 的 Python 脚本** | FAQ：分享或发布的、用了 Blender Python API 的脚本，必须以 GNU GPL 提供；许可页的措辞是"符合 GPL 的协议" [17] | **只在分享或发布时触发**，纯自用不触发；MIT 是 GPL 兼容协议，但 FAQ 字面写的是按 GPL |
| 完全在 Blender 之外、不调 API 的工具 | 可以闭源、可以卖 [17] | 不 import bpy 的封装属于此类 |
| 官方 MCP、`bpy` PyPI 包 | 元数据都标 GPL-3.0 [16][18] | 只读参考 |
| 素材 | 各自许可：Poly Haven 等为 CC0，Poly Pizza 多为 CC-BY，Sketchfab 逐件不同 [16] | 一律记素材台账 |

本仓库是 MIT。调用 bpy 的脚本放进仓库时，许可怎么写，原有三个选项：(1) 仓库里不放 `import bpy` 的文件，`build.py` 由 agent 在项目目录里生成（`projects/` 不入库），仓库只放不 import bpy 的封装和模板 JSON；(2) `import bpy` 的文件标 `SPDX-License-Identifier: GPL-3.0-or-later`，这部分文件按 GPL 分发；(3) 保持 MIT，承担 FAQ 字面要求和 MIT 之间的差距。**维护者 2026-10-01 选了 (2)**：现在仓库里 import bpy 的文件是 `styles/_swatch/blender_render.py` 和 `styles/tabletop-miniature/swatch.py`，文件头都有 SPDX 标注，`README.md` 的 License 一节写明了；不 import bpy 的封装（`blender_prep.py`、`render.sh`）仍是 MIT。以后加 import bpy 的文件，照样标。项目里 agent 生成的 `build.py` 在 `projects/` 下，不入库，不受影响。Blender 的名称和 logo 受单独的商标政策约束，片子里出现 Blender 界面截图前先看一眼 [17]。

## 流程与验证

和 `playbook/01` 的阶段对齐：

| 阶段 | 做什么 | 通过条件 |
|---|---|---|
| 0–1 | 判断是否需要 Blender；BRIEF 里写渲染账：帧数 × 校准时间 × 1.5 | 用户同意预算（关卡 ①） |
| 2–3 | `STYLE.md` 选视图变换和灯光语言；分镜里标出 3D 镜头；blockout animatic（EEVEE 或 Workbench，50% 分辨率，几何块代替资产，`bin/vh sheet` 出联系表） | 节奏和构图通过（关卡 ②） |
| 4 | 有声音就先定音频和 `beats.json`，时间线的时间从这里读 | 时长由音频决定 |
| 5 | 搭 `lib/`，先做 5 帧冒烟：build → 渲 5 帧 → 对比；写 `blender.lock`，记录每帧耗时 | 确定性验收（下表第 6 行）通过 |
| 6–7 | 写场景，每个镜头一个块；联系表、strip、crop、色彩、alpha、降噪检查 | 见下表 |
| 8–9 | 分块渲染 final 底片，合成，编码，`bin/vh check`；交付底片、`blender.lock`、素材台账（含许可） | 帧数、YAVG、时长；关卡 ③ |

| # | 检查 | 做法 | 通过条件 | effort |
|---|---|---|---|---|
| 1 | 能不能跑 | `--python-exit-code 1`；`build.py` 静态扫描；5 帧冒烟；日志里没有 `Traceback` | 退出码 0 | quick |
| 2 | 结构 | 帧数 = 时长 × fps；输出 mtime 是新的；PNG 尺寸；每帧 `signalstats` 的 YAVG 没有突降（5.x API 变了会出空帧）；没有 NaN 或全黑帧 | 与 `playbook/02` 的"静默失败"同口径 | quick |
| 3 | 联系表 | 全片 draft 渲成 mp4（EEVEE，50%），`bin/vh sheet <mp4>`；final 只在关键时刻渲全分辨率抽帧 | 构图、光、材质读得出 | quick |
| 4 | strip 和 crop | 关键动作每 0.1–0.15 s 一格；100% 裁切高光、暗部、边缘、玻璃、头发，每镜头至少 2 处 | 运动不抖不漂，无 fireflies，alpha 边缘干净 | standard |
| 5 | 色彩合约 | 场景里放一块品牌色平涂块，走完整条链路（Blender PNG → ffmpeg → mp4 → 解码），和 HTML 里同色块的截图比较；`ffprobe` 看四个标签 | 最大色阶差 ≤ 3（基线：BT.709 + tv 的 8 位往返最大差 3） | standard |
| 6 | 确定性 | (a) 单帧 `-f N` 对整段 `-a` 的第 N 帧；(b) 一个进程渲 0–59 对两个进程各渲 0–29、30–59；(c) 重启后重渲同一帧。比无损 PNG 的 PSNR | 最小值 ≥ 45 dB（预期逐像素相同【推测】） | studio；冒烟时先做 (a) |
| 7 | alpha 边缘 | RGBA 分别合成到黑、白、品牌色上，裁边缘放大；`premultiplied` 选项对不对 | 无黑边或亮边 | standard（用到带 alpha 的路径时） |
| 8 | 降噪与闪烁、缓存 | 静态区域的帧间差，OIDN 开、关各一版；缓存 sha256 和 `blender.lock` 一致，关键帧 JSON 的哈希不变 | 静态区域的时间噪声不高于同片其他图层；哈希一致 | studio（有模拟时加缓存） |

## 首次冒烟（装上 Blender 之后）

2026-10-01 用 5.2.2（Homebrew cask，M3 Max）做过的【实测 5.2.2】：

- **同一帧、同一设置、新进程渲两次**（一个简单场景：木纹桌面、一个方块、一行中文、两盏灯，1920×1080，64 spp + OIDN）：CPU 上的 Cycles 逐像素相同；Metal 上的 Cycles 不同，PSNR 92 dB；EEVEE 不同，85 dB。都在 45 dB 线以上，但只有 CPU 能做到逐像素相同。风格样片的正式版因此走 CPU；草稿走 Metal。
- **乱序、多进程**：`tabletop-miniature` 的 12 帧倒序分给 3 个新进程重渲，和整片按顺序渲出来的同一帧比（`styles/_swatch/determinism.sh`），结果见 `styles/_swatch/README.md`。
- **速度**：上面那个简单场景每帧 CPU 21 s、Metal 4.5 s、EEVEE 1.1 s（含启动）。`tabletop-miniature`（约 70 个物体、文字、景深、4 盏灯）CPU 64 spp 每帧 32–43 s，32 spp 每帧 15–19 s，两者并排放大看不出差别；Metal 20 spp 每帧约 1.6 s。
- **`sandbox-exec` 套 Blender**（完整的 profile 见 `styles/_swatch/render.sh` 的 `bl_profile`）：
  - 只放行输出目录时，Metal 不能写着色器缓存，每帧都重编（2 s 变成 13 s）。再放行本用户缓存目录里 Blender 自己的子目录（`$(getconf DARWIN_USER_CACHE_DIR)org.blenderfoundation.blender`）就正常了；临时目录不用放行。日志里仍有几行无害的 "Error creating directory"。
  - 冷启动时 Metal 编译内核要静默约 110 s，日志一行不动：看门狗的静默阈值要放宽（样片用 300 s）。
  - 整个家目录拒读（只放行项目、Blender 安装目录和 `~/Library/Fonts`）：CPU 渲染照常，和不加这条时逐像素相同。Metal 在内核已经缓存好时会崩溃（SIGSEGV，崩在 `-[_MTLDevice recordBinaryArchiveUsage:]`），放行 `~/Library` 也不行。所以样片只在正式渲染（CPU）上加这条，草稿（Metal）仍然断网、只写输出目录，但不禁读。
  - `env -i` 只带 `PATH`、`LANG`，`HOME` 和 `TMPDIR` 指进输出目录，Blender 照常运行，Cycles 的内核缓存写到 `$HOME/.cache/cycles`。
- **字体**：`bpy.data.fonts.load()` 只读 .ttc 的第一个字形：`Songti.ttc` 读出 Songti SC Black，`Hiragino Sans GB.ttc` 读出 W3。要别的字重，先把那一面写成单独的字体文件（`styles/_swatch/blender_prep.py` 用 fontTools 做）。
- **API**：5.2 里新建的材质和世界自带节点树，再设 `use_nodes` 会报 DeprecationWarning（6.0 删除）；Mix 节点有三组同名输入（float、vector、color 都叫 "A"），要按 identifier 取（`A_Color`、`Factor_Float`、`Result_Color`）；`view_transform` 和 `look` 是动态枚举，`bl_rna` 里查不到选项，直接设、失败再退（`AgX` 和 `AgX - Medium High Contrast` 都可用）；后台模式下 `stdout` 是块缓冲，Cycles 的进度行不会实时进日志，渲染器要自己 `print(..., flush=True)`，否则看门狗会以为卡住了。
- **persistent data 会留下跨帧状态**：一个进程里按顺序逐帧 `apply(t)` 再 `bpy.ops.render.render()`，开着 `render.use_persistent_data` 时，CPU 上的 Cycles 在一段帧里把一个物体（茶杯）渲成全黑，单独渲同一帧是正常的；乱序重渲 12 帧，有 1 帧对不上（24.5 dB）。关掉以后每帧时间几乎不变。逐帧改属性再渲的流程不要开它，开了就要做乱序比对。
- **job control**：在 `set -m` 打开的 shell 里把 Blender 放到后台，它会进另一个进程组，看门狗按组杀不到它；在起 Blender 的子 shell 里先 `set +m`。

## 大场景：numpy 逐帧驱动上百万个点（介绍片 v5 的开场）

2026-10-02 用 5.2.2、Cycles、Metal 做的介绍片开场（`showcase/04-intro-film/blender/galaxy.py`）【实测 5.2.2】：一个星系由 118 万颗星、1.6 万张会变成玻璃卡片的“片星”、体积光雾和尘埃带组成，镜头从一张卡片的特写拉远成整个星系，再螺旋下坠、坍缩、超新星、压平成一张影片之海。做法和坑：

- **全部是 t 的纯函数，但不用关键帧动画**：每帧在 Python 里用 numpy 算出所有点和卡片的位置，`mesh.vertices.foreach_set("co", …)` 一次写进去，再渲这一帧。118 万个点算加写约 0.5 s。只有相机逐帧打关键帧（`keyframe_insert`），这样相机的运动模糊来自关键帧插值。
- **这样写的几何没有运动模糊，要自己给速度**：Cycles 不知道上一帧点在哪。给网格加一个点属性 `velocity`（`FLOAT_VECTOR`，单位 m/s），值取快门两端位置的中心差分，Cycles 就按它拉出拖影（同一场景有无 `velocity` 对照过）。点云走 Geometry Nodes 的 Mesh to Points，半径来自一个属性。
- **星点不要降噪**：OIDN 会把星点抹成一团团糊。星空关降噪、靠采样数（这里 64 spp，特写 96 spp）；没有降噪就要接受一层细颗粒。
- **贴着镜头的体积发光会冲白画面**：镜头穿进星系的光雾里时整帧发白。用 Camera Data 节点的 View Distance 把镜头 4–60 m 内的体积发光压掉。
- **层层重叠的玻璃会吞掉光线**：几千张玻璃卡片压平叠在一起时，光线穿过的层数超过透射反弹上限，画面成了黑块。压平以后的卡片收起玻璃外壳（特写才需要玻璃）。
- **相机的上方向要自己给**：`Vector.to_track_quat("-Z", "Y")` 让 Y 轴尽量对着世界 Z 轴，镜头接近垂直俯视时这个方向不稳定，画面会扭和抖。改成自己算 forward 和 up，用 `Matrix((right, up, -forward)).transposed().to_quaternion()`，相邻两帧的四元数取同号（`q.dot(prev) < 0` 就取反），否则运动模糊会沿长弧插值。
- **数学式写成着色器节点**：旋臂、尘埃带、超新星的丝缕都是节点树。`blender/nodexpr.py` 把 `"exp(-r / 21) * smooth(80, 120, r)"` 这样的表达式编译成 Math、Map Range、Noise 节点，场景代码和 numpy 那一份读起来一样。它本身不 import bpy（MIT），由调用它的场景脚本传入节点树。
- **速度**（M3 Max，Metal，1080p，64 spp，不降噪）：按块实测：特写 28–39 s 一帧（96 spp），拉远到星系 7–14 s，螺旋下坠和坍缩 12–21 s，超新星之后约 6 s，压平以后约 2 s。15.8 s 的开场（475 帧）实际渲了 1 小时 28 分（2026-10-02，分 16 块）。4K 按像素数约 ×4。
- **Metal 的确定性**：新进程里打乱顺序重渲，和序列里的同一帧比。look-dev 那版底片 3 帧：一帧逐像素相同，另两帧 PSNR 95 dB 和 49 dB；正式底片 2 帧：71.3 dB 和 47.3 dB。最低的都是几千张卡片叠在一起的影片之海，都过 45 dB 的线；PNG 文件哈希不同，是元数据。
- **长渲染不要挂在 agent 的后台任务上**：Claude Code 的后台任务 30 分钟会被收掉，渲到一半就断。分块（每块 30 帧一个新进程）、可续渲（已存在的帧跳过），用 `nohup caffeinate -i … & disown` 脱离会话，再用 Monitor 盯日志。`showcase/04-intro-film/tools/bl_render.sh` 就是这样写的。
- **和网页引擎接力**：Blender 只渲到 15.8 s，之后的网格、片名和终端交给 HyperFrames 的 WebGL。接法是从同一份 `galaxy.py` 导出卡片的格位、片源和逐帧相机（`tools/export_state.py`，不启动 Blender），WebGL 按同一个相机重画同一批卡片，两边在 15.0–15.6 s 交叉溶解（Blender 底片渲到 15.8 s，留一点余量）。Blender 是 Z 朝上、水平视角，three.js 是 Y 朝上、垂直视角，换算是 (x, y, z) → (x, z, −y)。

还没做的：

1. 5.2 上 EEVEE 命令行渲 300 帧，看内存曲线（#125333 的后续）。
2. Cycles Metal 的确定性：`-f N` 对 `-a`、自适应采样开、关各一组（CPU 的乱序一致见上；Metal 新进程乱序重渲见“大场景”一节）。
3. OIDN 开、关的静态区域闪烁。
4. 刚体烘焙缓存乱序渲染是否一致。
5. HyperFrames 的 `<video>` 是否保留输入视频的 alpha（WebM VP9、ProRes 4444），PNG 序列方案是否够用。
6. PNG 元数据里是否含渲染时间等字段（影响"文件哈希"）。
7. 上文各条命令（`-o //../out/…`、`-E BLENDER_EEVEE`、`--cycles-device METAL`）在 5.2 上的实际行为（样片渲染器在一个进程里逐帧调 `bpy.ops.render.render`，没走这些参数）。

## 来源

- [1] Blender 发布页 https://www.blender.org/download/releases/ （4.5 LTS 2025-07-15、5.0 2025-11-18、5.1 2026-03-17、5.2 LTS 2026-07-14）。
- [2] Blender 5.2 LTS https://www.blender.org/download/releases/5-2/ （2026-07-14 发布，LTS 到 2028-07；2026-10-01 核对）。[2a] 下载目录 https://download.blender.org/release/Blender5.2/ （5.2.0 于 2026-07-14、5.2.1 于 2026-08-25、5.2.2 于 2026-09-15；macOS arm64 的 dmg 约 346 MB；2026-10-01 核对）。
- [3] 系统要求 https://www.blender.org/download/requirements/ （macOS 13+，5.0 起需要 Apple Silicon，内存最低 8 GB、建议 32 GB；2026-10-01 核对）。
- [4] Blender 开发者文档 release notes：5.0 Python API 原文 https://projects.blender.org/blender/blender-developer-docs/raw/branch/main/docs/release_notes/5.0/python_api.md （2026-10-01 核对引擎 id、`scene.node_tree`、File Output、`media_type`、通道名、Action 各条）；5.0 色彩 https://developer.blender.org/docs/release_notes/5.0/color_management/ ；5.2 EEVEE https://developer.blender.org/docs/release_notes/5.2/eevee/ ；5.2 Python API https://developer.blender.org/docs/release_notes/5.2/python_api/ （`gpu.init()` 2026-10-01 核对）；5.2 Cycles https://developer.blender.org/docs/release_notes/5.2/cycles/ 。
- [5] 手册：命令行参数 https://docs.blender.org/manual/en/latest/advanced/command_line/arguments.html ，命令行渲染 https://docs.blender.org/manual/en/latest/advanced/command_line/render.html （页面是 JS 渲染，内容取自手册仓库的 rst：https://projects.blender.org/blender/blender-manual/raw/branch/main/manual/advanced/command_line/arguments.rst ）。[5a] GPU 渲染 https://docs.blender.org/manual/en/latest/render/cycles/gpu_rendering.html 。
- [6] 手册：Cycles 采样 https://docs.blender.org/manual/en/latest/render/cycles/render_settings/sampling.html （rst 原文）。
- [7] 手册：显示与视图变换 https://docs.blender.org/manual/en/latest/render/color_management/displays_views.html ；色彩空间 https://docs.blender.org/manual/en/latest/render/color_management/color_spaces.html ；图像格式 https://docs.blender.org/manual/en/latest/files/media/image_formats.html 。
- [8] Blender 2.66 发布说明 "Image Transparency" https://archive.blender.org/wiki/2015/index.php/Dev:Ref/Release_Notes/2.66/Image_Transparency/ （字节精度 straight、浮点 premultiplied；PNG 存 straight，EXR 存 premultiplied）。
- [9a] Blender 4.0 Cycles release notes https://developer.blender.org/docs/release_notes/4.0/cycles/ （M3 硬件光追，MetalRT 设为 Auto）。
- [10] OIDN 文档 https://www.openimagedenoise.org/documentation.html （设备间数值差异；RT 滤波器不具备时间稳定性）；Blender 4.1 Cycles https://developer.blender.org/docs/release_notes/4.1/cycles/ （OIDN GPU 加速，Apple Silicon、macOS 13.0+）；OIDN 3 时间降噪 https://www.cgchannel.com/2026/01/open-image-denoise-3-will-support-temporal-denoising/ ；合成器时间降噪 PR #151020 https://projects.blender.org/blender/blender/pulls/151020 。
- [11] EEVEE：内存问题 https://projects.blender.org/blender/blender/issues/125333 ，变慢 https://projects.blender.org/blender/blender/issues/128253 （网页 403，内容经 Gitea API 读到：https://projects.blender.org/api/v1/repos/blender/blender/issues/125333 及其 `/comments`）。
- [12] Cycles 设备差异 issue #101561（https://projects.blender.org/api/v1/repos/blender/blender/issues/101561/comments ，读到 Brecht 等人的回复）。
- [13] 低电量模式影响 https://eclecticlight.co/2025/01/06/power-modes-and-apple-silicon-gpus/ 。
- [14] 刚体：`bpy.ops.rigidbody.bake_to_keyframes` https://docs.blender.org/api/current/bpy.ops.rigidbody.html ；渲染农场与刚体烘焙 https://www.renderjuice.com/docs/rendering-with-blender/rigid-body-simulations 【二手】。
- [15] Shadow Catcher：手册（Cycles 物体设置）rst 原文 https://projects.blender.org/blender/blender-manual/raw/branch/main/manual/render/cycles/object_settings/object_data.rst 。
- [16] MCP：官方页面 https://www.blender.org/lab/mcp-server/ （2026-10-01 核对警告原文和 5.1+ 要求）；安全讨论 https://devtalk.blender.org/t/blender-mcp-server-after-claude-mcp-security-for-blender-scripting-3d-agent-notes/45131 ；社区实现 https://github.com/ahujasid/mcp-for-blender （原名 blender-mcp，旧链接会跳转；MIT）；CVE-2026-10661 https://github.com/advisories/GHSA-qqw9-95ww-prfm （2026-10-01 核对：低危，2026-06-03 发布）；官方仓库元数据与 release：https://projects.blender.org/api/v1/repos/lab/blender_mcp 及 `/releases`（2026-10-01 核对：GPL-3.0，v1.0.3 于 2026-09-11）。
- [17] 许可：https://www.blender.org/about/license/ ；FAQ https://www.blender.org/about/faq/ （2026-10-01 核对输出归属、脚本须按 GPL 或符合 GPL 的协议提供、Blender 之外的闭源工具）。
- [18] Homebrew cask https://formulae.brew.sh/api/cask/blender.json （2026-10-01 核对：5.2.2）；PyPI `bpy` https://pypi.org/simple/bpy/ 。
- [19] Khronos PBR Neutral：4.2 release notes https://developer.blender.org/docs/release_notes/4.2/rendering/ ；设计讨论 https://devtalk.blender.org/t/adding-pbr-neutral-tone-mapper/33602 ；AgX、Standard、PBR Neutral 的差别见手册 [7]。
