# styles/_swatch · 风格样片渲染器

每个风格预设都要附一段用本仓库真渲出来的 5 秒样片，用样片证明风格之间确实不同。本目录负责把 `styles/<slug>/swatch.js`（或 Blender 场景 `swatch.py`，见"Blender 场景"）渲成：

- `styles/<slug>/media/swatch.mp4`：1280×720，H.264 High，yuv420p，faststart，≤ 1.5 MB；有 `score.json` 时带配乐，否则静音；
- `styles/<slug>/media/poster.jpg`：t = 3.0 s 那一帧，1280×720，≤ 200 KB。

引擎是固定在 0.8.82 的 HyperFrames。画面是一张 1920×1080 的 `<canvas>`，每一帧都是 `renderAt(t)` 的纯函数。这张 canvas 固定按 1 倍像素画：把样片的画法搬进要出 4K 的项目时，canvas 要按 `devicePixelRatio` 开大再 `ctx.scale`，以像素为单位的效果（颗粒、网点大小、用 `getImageData` 取的遮罩，例如 `scratched-type`、`pixel-16bit`）要跟着换算（`engines/README.md`"出 4K"）。需要路径追踪的光、真实景深的风格（目前是 `tabletop-miniature`）改用 Blender 的 Cycles，场景写成 `swatch.py`，渲出的帧走同一套检查、配乐、混音和编码。

## 快速开始

```bash
(cd styles/_swatch && npm ci)                    # 第一次：本地装 hyperframes@0.8.82（不装全局 skill）
styles/_swatch/render.sh demo --draft            # 冒烟：内置 demo → styles/_swatch/out/demo/media/
styles/_swatch/render.sh <slug>                  # 正式：styles/<slug>/ → styles/<slug>/media/
styles/_swatch/render.sh <slug> --draft --hud    # 自查用：角上烧 t / 帧号（不要交付）
styles/_swatch/determinism.sh <slug>             # 确定性检验（1 个 worker 对 3 个 worker，逐帧比对）
uv run --with pillow python styles/_swatch/gallery.py --mp4   # styles/gallery.jpg + gallery.mp4
```

本机实测（M3 Max；渲染走 CPU 软件光栅，原因见下面"确定性"）：正式渲染（`--quality delivery`、2 个 worker）单个 swatch 的 HyperFrames 部分约 15–45 s，整条流程（含音乐、音效、QA）约 20–50 s（走 GPU 时约 13–19 s，见下面"确定性"）；`determinism.sh` 要渲两遍无损 PNG，halftone-comic 约 40 s，fui-hud 约 50 s，有大面积颗粒的场景更久（PNG 编码变慢）。demo 的正式产物：swatch.mp4 0.91 MB（CRF 18），poster.jpg 111 KB。

`render.sh` 的参数：`--draft`（HyperFrames draft 画质；产物写到 `out/<slug>/media/`，不会覆盖 `styles/<slug>/media/` 里已发布的正式样片）、`--workers N`（默认 2；检测到别的 `hyperframes render` 在跑时自动降到 1；worker 数只影响速度，画面逐字节相同）、`--hud`、`--png`（只渲无损 PNG 序列到 `out/<slug>/png-w<N>/`）、`--stage-only`（只搭 stage，打印 snapshot / preview 命令）、`--timeout S`。`<slug>` 也可以是一个带 `/` 的路径，指向任意位置的场景文件夹（草稿、测试用），产物写进该文件夹的 `media/`。

## 目录

```
styles/_swatch/
├── README.md          本文件
├── index.html         唯一的 composition：5.0 s · 30 fps · 1920×1080 · 一张 canvas#c；变量 style / hud
├── boot.js            运行时：读变量 → 加载 tokens 和场景 → 预载字体 → setup → 预热 → 每次 seek 画一帧
├── lib.js             共享工具（传给场景的 lib）
├── fonts.css          生成文件：本机系统字体的 @font-face local() 目录（fonts.py 生成）
├── fonts.py           重新生成 fonts.css；--list 打印字体清单
├── render.sh          渲染 + 看门狗 + 检查 + 转码 + 封面 + 联系表
├── determinism.sh     确定性检验
├── blender_render.py  Blender 场景的渲染器（在 Blender 里运行；GPL-3.0-or-later，见"Blender 场景"）
├── blender_prep.py    Blender 场景渲染前的两步：静态检查 swatch.py、把它的 FONTS 解析成字体文件
├── gallery.py         styles/gallery.jpg（+ 带声音的 gallery.mp4）
├── demo/              中性示例场景：按统一内容规格走一遍 API，复制它起步
├── catalog/           lib.js 测试卡：每个纹理、滤镜、转场、WebGL 各一格（改 lib.js 后渲它看）
├── fontprobe/         字体探针：在渲染用的 Chrome 里逐个加载 fonts.css 的字体，红色 = 打不开
├── package.json · package-lock.json · hyperframes.json · meta.json   （hyperframes 0.8.82 精确版本）
└── out/               不入库：stage/、每个 slug 的中间文件（hf.mp4、render.log、sheet.png）
```

## 场景怎么被选中：stage，而不是 `current/`

HyperFrames 把项目根目录当网站根目录，而且根目录只能有一个 composition。`render.sh` 每次渲染都搭一个一次性的 stage：`styles/_swatch/out/stage/<slug>/`。

- 外壳文件（`index.html`、`boot.js`、`lib.js`、`fonts.css`、配置、内置场景）从 `_swatch/` 复制过去；
- `styles/<slug>/` 整个复制到 `scenes/<slug>/`，不带 `media/` 和 `*.md`；
- 场景由 HyperFrames 变量选：`--variables '{"style":"<slug>"}'`。`boot.js` 从 `./<slug>/`（内置场景）或 `./scenes/<slug>/` 加载 `tokens.json` 和 `swatch.js`；
- stage 里 `index.html` 的 `style` 默认值被改成 `<slug>`。这样 `hyperframes snapshot` / `preview` 这两个不接受 `--variables` 的命令，在 stage 上也能直接看到这个风格：`render.sh <slug> --stage-only` 会把命令打印出来（打印的 snapshot 命令带着 `--describe false`：设了 `GEMINI_API_KEY` 时，`snapshot` 默认会把帧发给 Gemini，见 `engines/README.md`）。

没有用共享的 `_swatch/current/`，原因是三个 agent 会并行渲染不同的风格，共享目录会互相覆盖。每个 slug 有自己的 stage，还有一个锁目录（`out/stage/<slug>.lock`），同一个 slug 不会被同时渲两次。也没有用软链接：软链接指回 `styles/` 会让目录树成环，HyperFrames 的 lint 或打包一旦跟随链接就会出问题。stage 在 `out/` 下，已被根目录 `.gitignore` 的 `out/` 规则忽略。

## 场景 API

`styles/<slug>/swatch.js` 是一个 ES module：

```js
export const fonts = ["Didot"];          // 可选：renderAt 里用到、但 tokens.fonts 没写的字体族，会被预载

export async function setup(ctx, tokens, lib) {
  // 可选，每个 worker 启动时调用一次，可以 await。
  // 用来算版式、生成纹理、编译 shader、加载图片。只能依赖 tokens 和常量，不能依赖时间。
}

export function renderAt(t, ctx, tokens, lib) {
  // 必需。画出 t 时刻的完整一帧。
}
```

约定：

- `t` 是秒，已量化成 `k/30`（k = 0…149）；帧号用 `lib.frame(t)`。
- `ctx` 是 1920×1080 的 `CanvasRenderingContext2D`。每帧调用前运行时会执行 `ctx.reset()`，像素和状态（变换、alpha、filter、字体……）全部清空，所以 `renderAt` 必须从背景开始画满整帧。
- `tokens` 是解析后的 `tokens.json`；`lib` 是 `lib.js` 整个模块。
- 需要着色器时，用 `lib.shader(frag)` 在离屏 WebGL2 canvas 上跑一个全屏片元着色器，再 `ctx.drawImage(fx.render(t, uniforms, textures), 0, 0)` 合进来。输入纹理可以是任何 canvas，所以"先用 2D 画，再过一遍 shader（半调、CRT、色差）"也能做到。
- 同目录的图片等素材用模块相对路径加载：`const img = new Image(); img.src = new URL("./paper.png", import.meta.url); await img.decode();`（放在 `setup` 里）。素材必须是自己做的或许可允许的。
- 风格文件夹里不能有 `.html` 文件（一个根目录只能有一个 composition，`render.sh` 会拒绝）。

出错时的表现：`setup` 或加载失败，每一帧都画成品红色的 SWATCH ERROR 卡片；`renderAt` 在某一帧抛异常，只有那一帧是错误卡片。卡片上印着错误信息和调用栈，同时 `console.error` 进 HyperFrames 的日志（`[Browser:ERROR] [swatch] …`）。`render.sh` 抽帧发现品红卡片就判失败。

## Blender 场景（swatch.py）

风格文件夹里只有 `swatch.py`、没有 `swatch.js` 时，`render.sh` 改用 Blender（Cycles）渲染。装法：`brew install --cask blender`（指南钉在 5.2 LTS，见 `engines/blender.md`），或者设 `BLENDER=/path/to/blender`；还要 fontconfig 的 `fc-match`。HyperFrames 和这一节无关，`bin/vh style <slug>` 遇到 Blender 场景时不装它。

`swatch.py` 是一个普通的 Python 模块，只在函数里用 bpy，所以 `python3 swatch.py --foley` 在 Blender 之外也能跑：

```python
FOLEY = [{"t": LAMP_ON, "sfx": "sfx/lamp_on.wav", "gain_db": -2, "pan": -0.55}, …]   # foley.mjs 照常写成 events.json
FONTS = {"title": "Big Caslon", "zh": "Songti SC:weight=bold"}                     # fontconfig 的匹配式；env.fonts["zh"] 是加载好的字体
RENDER = {"final": {"samples": 32}, "draft": {"samples": 20}}                      # 可选：覆盖 blender_render.py 的默认值

def build(env): …          # 每个 Blender 进程调用一次：搭整个场景，只能依赖 env.tokens 和常量
def apply(t, env): …       # 按 t（= k/30）直接设好每个会动的属性：t 的纯函数，不留跨帧状态
```

`env` 里有 `W H FPS DUR FRAMES POSTER_T SPEC TITLE_EN TITLE_ZH MOTIF`（和 `lib.js` 同值）、`tokens`、`fonts`、`scene`、`quality`（final、draft 或 fast）和 `hash(*xs)`（[0, 1)，跨机器一致，用来做手放抖动之类的"随机"）。

- **不打关键帧**：`apply` 直接设属性，渲染器逐帧 `apply(k/30)` 再渲。所以没有运动模糊；要运动模糊的项目按 `engines/blender.md` 逐帧采样成关键帧。
- **画质**：Cycles 的设置统一由性能层（`tools/blender_perf.py`，`engines/blender-perf.md`）给出：反弹 6/3/3/4/2/4、间接 clamp 10、OIDN（RGB+Albedo+Normal，Accurate 预过滤）、合成器走 CPU、AgX。三档：**final** 是确定性锚——final-cpu 档（CPU、固定 spp、无时限、无 persistent data；乱序逐像素相同）；**draft** 是速度预览——draft 档（GPU：Linux 上 CUDA 优先（T4 无 RT 核，OptiX 在那没有 BVH 优势；有 RT 核的卡自己传 `--device optix`），Mac 上 Metal；自适应 0.1、每帧 120 s 上限、Simplify 开）；**fast** 是 GPU 上的 final 档（Kaggle T4 出画质样片用；确定性锚仍可用 `--quality final`）。渲出的 PNG 在 `out/<slug>/frames/`（草稿是 `frames-draft/`），再按 BT.709、tv range 编成和 HyperFrames 一样的 1080p `hf.mp4`（CRF 8，单线程，每次同样的字节），后面的检查、配乐、混音、编码、封面、联系表全部共用。
- **为什么正式版用 CPU**【实测，M3 Max、Blender 5.2.2】：同一帧渲两次，CPU 上的 Cycles 逐像素相同；Metal 上的 Cycles 差一点（PSNR 92 dB），EEVEE 差得多一点（85 dB）。都在硬规则 1 的 45 dB 线以上，但这条流水线按体积上限爬 CRF，会把很小的差异放大成另一个 mp4（见"确定性"），所以和 HyperFrames 一样取逐像素相同的那一条路。代价是慢：`tabletop-miniature` 正式版每帧 15–19 s（32 spp），150 帧约 40 分钟；草稿每帧约 1.6 s，150 帧约 4 分钟。
- **时间预算**：Blender 场景的默认超时是草稿 1800 s、正式 7200 s。正式渲染前先用 `--png --frames 3,90,140` 渲三帧，按每帧的时间估全片。
- **`--png --frames 149,90,12`**：只渲这几帧，按这个顺序，写到 `out/<slug>/png-sample-w<N>/`（加 `--draft` 走 GPU）。看构图、调光的时候用它，几十秒一轮。
- **`--workers N`**：起 N 个 Blender，各渲一段连续的帧。默认 1 个：Cycles 本来就用满所有核，多开不会更快；它是给确定性检验用的。一段失败，其余几段立刻停掉。
- **`--hud`**：正式渲染加 `--hud` 时不写 `inputs.txt`，烧了读数的帧不会被 `determinism.sh` 拿去比。

**先看再跑，跑在笼子里**（`engines/blender.md` 的"安全"）。agent 写的 bpy 脚本有用户的全部权限，所以有三层，真正的边界是第 3 层：
1. **静态检查是 lint，不是门**。`blender_prep.py scan` 先把 `swatch.py` 当语法树读一遍，不执行，拦住手误和明显的出路，拦不住存心绕过的人。不通过就不渲；`foley.mjs` 读 FOLEY 之前也先过这一步。它拦的东西：
   - import 只许 `bpy bmesh mathutils math colorsys json sys`，连 `random`、`time` 也不许，顺带保证帧只依赖 t；`json` 只许 `dumps`、`loads`，`sys` 只许 `argv`。
   - 下划线开头的名字和属性一律不许，只放行 `_` 和 `__name__`；含 `__` 的字符串也不许。这挡住了 `bpy.utils._os`、`x.__dict__["__import__"]` 这类绕法。
   - 不许 `eval exec compile open getattr setattr type dir globals vars`。
   - 不许 bpy 读写或运行别的东西：.blend（`wm`、`libraries`）、文本块（`texts`、`run_script`）、驱动器（`driver_add`、`driver_namespace`）、`bpy.utils`、`save_render`、`handlers`、`timers`。
2. **干净的环境**。Blender 用 `env -i` 启动，只带 `PATH`、`LANG` 和 `PYTHONDONTWRITEBYTECODE`，`HOME` 和 `TMPDIR` 指向 `out/<slug>/.blender/`：环境变量里的 API key 到不了场景脚本。
3. **macOS 上的沙箱**（`sandbox-exec`，规则文件在渲染开始前写一次，见 `render.sh` 的 `bl_profile`）【实测，Blender 5.2.2】：
   - 禁网络，也不许把网址或 Apple 事件交给别的程序。
   - 只许写 `out/<slug>/` 和本用户缓存目录里 Blender 自己的那一个子目录（`$(getconf DARWIN_USER_CACHE_DIR)org.blenderfoundation.blender`），Metal 把编译好的着色器存在那里。不许写的话，每一帧都要重编，2 s 变成 13 s。临时目录不用放行。
   - **正式渲染（CPU）还不许读家目录**，只放行仓库、场景、Blender 安装目录和 `~/Library/Fonts`。`~/.ssh`、`~/.zsh_secrets` 这类文件读不到，要提交的帧里也就印不进它们（实测读取被拒；整片的第 90 帧和不加这条规则时逐像素相同）。
   - 草稿（Metal）加不了这条：家目录不可读时，Metal 加载 Cycles 缓存好的内核会崩溃（崩在 `-[_MTLDevice recordBinaryArchiveUsage:]`；放行 `~/Library` 也不行）。草稿的输出只留在不入库的 `out/` 里，又没有网络，读到什么也送不出去。
   - 冷启动时 Metal 编译内核要静默约 110 s，所以 Blender 场景的静默阈值默认是 300 s。日志里会有几行 "Error creating directory"，不影响渲染。
   - 放行的 Blender 文件按 `BLENDER` 的真实路径算：.app 包，或它所在的文件夹；这个文件夹装着家目录（比如 Blender 直接放在 `/Users` 下）时直接报错，不渲。`BLENDER` 是一个 wrapper 脚本时（Homebrew 的 `blender` 就是），放行的是脚本所在的文件夹，不是它启动的 .app：app 在 `/Applications` 时没关系，装在 `~/Applications` 时正式渲染会因读不到而失败，把 `BLENDER` 直接设成 .app 里的 `Contents/MacOS/Blender` 就好。
   - 规则文件写在系统临时目录里（沙箱里写不了），渲完或中断时删掉；macOS 上没有它，Blender 就不启动。
   - **Linux 上没有第 3 层**，只有前两层：只渲你读过的场景，或者放进容器里渲。

**字体**：`FONTS` 的每个角色是一个 fontconfig 匹配式，`blender_prep.py fonts` 用 `fc-match` 找到本机的字体文件（和 `fonts.css` 用的是同一批系统字体），结果写进 `out/<slug>/fonts.json`。Blender 只读 .ttc 里的第一个字形【实测：`Songti.ttc` 读出来是 Songti SC Black】，所以匹配到的不是第一个时（宋体 Bold 是第 2 个），先用 fontTools 把那一面写成单独的字体文件，放在 `out/<slug>/fonts/`：本机缓存，不入库，不分发。匹配不到要的族时直接报错（中文角色落到拉丁字体上会印出方块），不悄悄回落。抽出来的字形每次重写（约 0.3 s），写到一半中断也不会留下坏文件。

**不用 persistent data**【实测 5.2.2，CPU】：打开 `render.use_persistent_data`（跨帧保留场景数据，本想省同步时间），`tabletop-miniature` 按顺序渲的第 27–44 帧里茶杯整个变黑，单独渲这几帧又是正常的灰色：一帧的样子取决于它前面渲过哪些帧。`determinism.sh` 抓到了（第 30 帧，24.5 dB）。关掉以后每帧的时间几乎不变（15–19 s），所以渲染器固定关掉它。

**确定性**：`determinism.sh <slug>` 对 Blender 场景不重渲整片（太慢），按硬规则 1 的原话做：从片中均匀抽 12 帧，倒着顺序分给 3 个新开的 Blender 进程重渲，和整片按顺序渲出来的同一帧逐像素比。整片的帧取上一次正式渲染留下的 `out/<slug>/frames/`，前提是它的 `inputs.txt`（场景、tokens、渲染器和 Blender 版本的校验和，`render.sh <slug> --stamp` 打印当前值）和现在一致；不一致就先按顺序整片渲一遍。

**许可**：`blender_render.py` 和每个 `swatch.py` 调用 Blender 的 Python API，按 GPL-3.0-or-later 分发，文件头有 SPDX 标注（维护者 2026-10-01 的决定，见 `engines/blender.md` 的"许可证"）；`blender_prep.py` 不 import bpy，和仓库其余部分一样是 MIT。

## 统一内容规格

所有样片讲同一件事，画廊里比的才只是风格。时间和文案在 `lib.SPEC`、`lib.TITLE_EN`、`lib.TITLE_ZH`、`lib.MOTIF` 里，场景直接引用，不要自己改写。

| 时间 | 内容 |
|---|---|
| 0.0–0.8 s | 立起背景和质感（纸、颗粒、扫描线、光……）。第一个动作从 0.1–0.3 s 开始 |
| 0.8–2.6 s | 标题 **"Every frame is code."** 和中文 **"每一帧，都是代码。"**，用这个风格的招牌文字动画进场 |
| 2.0–4.0 s | 三元素母题：三个形状、节点、卡片或条，从左到右表示 大纲 → 分镜 → 初版（outline → storyboard → draft），用这个风格自己的图形语言画 |
| 4.0–5.0 s | 这个风格的招牌转场，转到结束画面 |
| **3.0 s** | 封面帧（poster.jpg）：标题、中文和三元素应该同时读得清 |

- 标题和中文到 2.6 s 都要定住；中英两行都得在画面里，字号可以由风格决定，但中文不小于 46 px。
- 文字留在安全框里：`lib.SAFE.action`（离左右 ≥ 96 px、上下 ≥ 54 px）；主标题最好在 `lib.SAFE.title` 里。
- 结束画面可以是纯色、标志性构图或风格名，不要再塞新信息。
- 不用原作的角色、logo、具体镜头和素材；学的是语法（见 `styles/_TEMPLATE.md`）。

下面四条来自第一次全库评审（26 个样片由一位没参与制作的 reviewer 按 `TASTE_CHECKLIST` 的打分层逐个打分）。当时的毛病大多是全库共性的，所以写成规格：

- **第一个事件在 0.1 s，而且要看得见**：占画面 ≥ 20% 的东西在动（一道光、一笔、一次开机、一次砸入），配乐在同一拍起音。"一张空纸慢慢亮"不算 hook。当时有 5 个样片前 1 s 几乎是空底。
- **三元素就位以后不许干等**：2.6–4.0 s 每一拍至少有一个次要动作，例如慢推、一次 punch-in、元素晃一下、数字跳动、一道扫光。这一段通常是配乐能量最高的时候，画面冻住就像播放卡了。当时有 12 个样片在这里冻了 0.5 s 以上。
- **用这个风格自己的图形语言画三元素，不要默认的 ▶**：当时 10 个样片都拿播放键当"初版"。结尾转场也要是这个风格自己的招牌，不要几个风格都用"一个圆长大铺满全屏"。
- **声音语法里写了的屏息、抽层，`score.json` 里就要真的有**。评审会逐条对照 STYLE.md 的声音语法。

## tokens.json：lib 读哪些字段

`tokens.json` 的其他字段随意（STYLE.md 的约定为准），lib 只读下面这些，读不到就用兜底值：

- `palette`（或 `colors`）：`lib.color(tokens, "fg")`、`lib.color(tokens, "extra.2")`。值是 `"#hex"` 或 `{hex}`。键写错会返回品红，一眼能看出来。`lib.palette(tokens)` 返回全部颜色的数组。
- `fonts`（或 `type` / `typography`）：每个角色（`display`、`body`、`zh`、`mono`，名字随意）可以是数组 `["Didot", "Bodoni 72"]`、字符串 `"Didot, Bodoni 72"`，或对象 `{ "family": [...], "weight": 700, "style": "italic", "tracking": -0.02 }`（tracking 以 em 计）。`lib.font(tokens, role, size, {weight})` 会在后面补上安全兜底：拉丁角色补 Helvetica Neue 和 PingFang SC，`zh` 补 PingFang SC 和 Hiragino Sans GB，`mono` 补 Menlo。
- 缓动：`lib.easeOf(x)` 接受 `"cubic-bezier(0.76,0,0.24,1)"`、`"ease-out"`、`"steps(4)"`、`[x1,y1,x2,y2]`、`lib.ease` 里的名字或函数，所以 `lib.easeOf(tokens.ease.enter)` 可以直接用。

## lib.js 速查

| 类别 | 函数 |
|---|---|
| 常量 | `W H FPS DUR FRAMES POSTER_T SPEC TITLE_EN TITLE_ZH MOTIF SAFE.action/.title`（`{x0,y0,x1,y1,w,h,cx,cy}`） |
| 布局 | `anchor("C4")`（安全框里的 6×6 锚点，A–F 是列，1–6 是行）· `slots(3, {area, y, gap})` 母题的三个槽位 |
| 时间 | `frame(t)` · `step(t, 12)`（按 12 fps 停帧，"一拍二"用 15）· `seg(t,a,b)` · `env(t,a,b,fadeIn,fadeOut)` · `tween(t,a,b,ease)` |
| 数学 | `clamp lerp invlerp remap smoothstep fract TAU` |
| 随机 | `hash(...nums)` → [0,1)，按 IEEE 位模式哈希，跨机器一致 · `hashS` → [-1,1) · `hash32` · `rng(seed)`（只在 setup 或单次调用里用）· `noise1 noise2 fbm2` |
| 缓动 | `bezier(x1,y1,x2,y2)` · `ease.{outExpo,outQuint,outCubic,inCubic,inExpo,inOutCubic,inOutQuart,inOutSine,outBack,steps(n)}` · `easeOf(spec)` |
| 弹簧 | `spring(tau, {w, zeta} 或 {stiffness, damping, mass}, v0)`：闭式解，没有积分也没有状态 · `springTrack(t, [{t,v}…])`：叠加弹簧，中途改目标 |
| 颜色 | `color(tokens, key)` · `palette(tokens)` · `rgb rgba mixColor luminance` · `tok(tokens, "a.b.c", fallback)` |
| 文字 | `fontStack font setFont tracking` · `layoutText(ctx, str, {x,y,align,tracking})` 返回每个字形的框，字距保留 · `drawGlyphs(ctx, layout, (g,i)=>({alpha,dx,dy,scale,sx,sy,rot,fill,stroke,ch}))`（`sx`、`sy` 缺省时取 `scale`；缩放为 0 就不画） · `drawText` · `fitText` · `wrapText`（中文逐字换行，避头标点）· `graphemes isCJK` · `fontAvailable(family)` |
| 解码 | `scrambleGlyphs(str, t, {start, stagger, settle, rate, seed, charset, charsetCJK})` 返回 `[{ch, final, state, u}]`；`scramble(...)` 返回字符串；随机字按 `rate` 次/秒量化到帧 · `typewriter(str, t, {start, cps})` |
| 图层 | `layer(name)` 返回清空过的离屏 ctx（名字全局共享，加自己的前缀）· `offscreen(name, draw)` 返回 canvas |
| 质感 | `grain(ctx, t, {amount, size, fps, mode})` · `paper(ctx, {tone, blotch, tooth, fiber, seed})` · `halftone(ctx, src, {cell, angle, color, shape, rect})`（src 为 canvas 或 `(x,y)=>暗度`）· `scanlines(ctx, t, {spacing, alpha, roll, flicker})` · `vignette(ctx, {strength, inner, cx, cy})` · `inkBleed(ctx, draw, {spread, rough, sharp, seed})` · `roughen(ctx, draw, {amount, freq, seed})` · `rgbSplit(ctx, src, {r,g,b})` |
| 线条 | `wobblePath(ctx, pts, {amp, seed, close})`（`seed: step(t, 8)` 就会"沸腾"）· `strokePartial(ctx, pts, u)`（描线动画） |
| 转场 | `cut` · `wipe(ctx, u, drawA, drawB, {angle, soft})` · `iris(…, {cx, cy, mode:"open"/"close", shape, feather})` · `whip(…, {dir, duration, shutter, samples:"auto"})` · `motionBlur(ctx, t, drawAt, {samples, shutter})` |
| WebGL | `shader(fragBody, {width, height})` 返回 `{canvas, render(t, uniforms, textures)}`。自动加的头部声明了 `v_uv outColor u_res u_time u_frame u_tex0 u_tex1` |

`inkBleed` 和 `roughen` 用的是 `index.html` 里的 SVG 滤镜（`ctx.filter = "url(#ovh-ink)"`），每次调用时改写滤镜属性，在渲染里实测可用。转场函数的 `drawA` / `drawB` 必须往传进来的 ctx 上画（那是一个离屏图层），不能画到主 canvas。

## 确定性规则

1. 每一帧只由 `t`、`tokens` 和常量决定。不用 `Math.random()`、`Date.now()`、`performance.now()`、`requestAnimationFrame` 计时、CSS 动画或 transition。
2. 随机一律 `lib.hash(seed, i, lib.frame(t))`。要"抖"或"沸腾"就把帧号量化：`lib.step(t, 8)`。
3. 不保存跨帧状态。模块级变量只能存 setup 算出的纯数据（版式、纹理、shader），缓存也必须是确定的（lib 的纹理缓存就是这样）。
4. 字体在第一帧之前必须加载完。`tokens.fonts` 里写到的字体族，以及 `export const fonts` 里列出的，运行时都会预载。另外运行时会先把 0、0.9、1.8、2.7、3.0、3.6、4.5、4.97 秒各预画一遍，再开始截帧。
5. 检验：`determinism.sh <slug>` 用 1 个 worker 和 3 个 worker 各渲一遍无损 PNG，逐帧比对。多 worker 时每个分段都在全新的 Chrome 里冷启动，等于乱序渲染。要求逐字节相同。硬规则 1 给 GPU 光栅化留的"PSNR ≥ 45 dB"余地在这条流水线上用不到：`render.sh` 让 HyperFrames 全程在 CPU 上渲（见下），有帧不同就先看 `out/<slug>/render.log` 里 `gl=` 那一行是不是又回到了 GPU。

为什么在 CPU 上渲：`render.sh` 给 HyperFrames 传 `--no-browser-gpu`，也就是它文档里的确定性模式（SwiftShader 渲 WebGL，2D canvas 和合成都在 CPU 上，截帧固定走 `Page.captureScreenshot`）。这样 halftone-comic、fui-hud，以及 crt-terminal、ink-wash、cutout-jazz、symmetry-pastel、pixel-16bit、guochao-festive、archival-pan-zoom，在 1 个和 3 个 worker、多次运行之间都是 150/150 帧逐字节相同，hf.mp4、swatch.mp4 和 poster.jpg 也是同样的字节。之前走 GPU（`--use-angle=metal`）时不是这样：同一帧里文字边缘有几十个像素在不同进程里差 1 个色阶（fui-hud 里飞行中的帧计数器、halftone-comic 的标题行，另有一处裁剪边缘差 99 个色阶）。这不是渲染顺序造成的（0 号 worker 每次都按同样顺序渲 0–49 帧，1 个 worker 连渲三次逐字节相同，2 个或 3 个 worker 每次都不同），也不是 Chrome 的 canvas 读回噪声（截帧不经过 JS 读回）。无损帧仍在 73 dB 以上，但 x264 会把几个像素沿参考帧放大成另一条码流，`render.sh` 里按体积上限爬 CRF 和 JPEG 质量的循环再把它放大成 halftone-comic 的 CRF 24 对 26、fui-hud 每次一张新 poster（约 44 dB）。还有第二个来源：GPU 模式下 HyperFrames 给 1 个 worker 走 drawElement + `toDataURL` 截帧、2 个以上走 `Page.captureScreenshot`，两条路差约 80 dB，而 `render.sh` 会按机器上有没有别的渲染在跑选 1 或 2 个 worker。切到 CPU 让每个 swatch 的画面一次性变了一点，所以所有 swatch 都要重渲一遍。大多数只是抗锯齿边缘（文字、轮廓、网点边缘）差几个色阶，2 倍放大也看不出：fui-hud 中位数 52.5 dB、最差帧 41 dB，guochao-festive 51.5 / 39.3 dB，halftone-comic 36.4 / 33.5 dB（SwiftShader 渲的印刷 shader，每个网点边缘都差一点），pixel-16bit 逐字节相同。四处并排看得出来：ink-wash 的洇墨轮廓和 cutout-jazz 的毛边形状变了（`lib.inkBleed`、`lib.roughen` 用的 SVG `feTurbulence`，Skia 的 CPU 实现和 GPU 实现不是同一份噪声；ink-wash 最差帧 20 dB），味道一样，抖动的形状不同；scratched-type 的字形骨架是从渲染好的文字 `getImageData` 描出来的，笔画走向跟着变（中位数 36.8 dB，poster 那帧 29.9 dB）；synthwave-outrun 的 GLSL 颗粒和 VHS 错位切片不同（中位数 35.3 dB，4.0 s 那帧 17 dB）。审重渲的样片时重点看这四个。代价是慢一些：无损 PNG 序列 1 个 worker 时 halftone-comic 22 s、fui-hud 31 s（GPU 时 17 s、10 s），3 个 worker 时 13–15 s。

最后一环也要盯住：`render.sh` 把 hf.mp4 转成 swatch.mp4 的 x264 编码开着 VBV（`-maxrate`/`-bufsize`），多线程时 x264 的 VBV 码率控制每次结果都不一样——同一个 hf.mp4、同一条音轨编 4 次，体积在 1 493 473–1 503 291 B 之间晃，正好跨过 1 500 000 B 的上限，所以帧已经逐字节相同了，halftone-comic 还是会在 CRF 24 和 26 之间跳。现在这一步用 `-threads 1`（同一套码率模型，每次同样的字节，720p 一遍约 3 s）。音乐和音效两步本来就是确定的（WAV 和 AAC 多次运行逐字节相同）。

## 字体

只用本机系统字体，通过 `@font-face { src: local("<PostScript 名>"), local("<全名>") }` 引用，不复制、不打包、不分发任何字体文件。`fonts.css` 由 `fonts.py` 从 `fc-list` 生成。每个字重都以真实族名单独声明，所以 tokens 里写 `"Songti SC"` 加 `weight: 900` 拿到的就是宋体 Black；只有一个字重的族声明成字重区间，Chrome 不会给它伪造粗体。

为什么不直接写族名：在 `hyperframes render` 里，泛称族（`monospace`、`ui-monospace`）和裸族名不可靠（showcase 00 的等宽字就中过招）。判断字体只看 `render.sh` 渲出来的帧，不看 snapshot。

下面是本机（macOS 15，Darwin 24.6）实测清单：`render.sh fontprobe` 在渲染用的 Chrome 里逐个加载，116/116 族通过。括号里是可用的 CSS 字重。† 表示 macOS 按需下载的资源字体：本机已下载，换一台 Mac 可能没有，这时会回落到栈里的下一个字体。‡ 表示用户自己装的字体，不可移植。

- **sans**: Helvetica Neue (100,200,300,400,500,700,900); Helvetica (300,400,700); Arial (400,700); Arial Black (900); Arial Narrow (400,700); Arial Rounded MT Bold (400); Avenir (300,400,500,900); Avenir Next (100,400,500,600,700,900); Avenir Next Condensed (100,400,500,600,700,900); Futura (500,700,800); Gill Sans (300,400,600,700,800); DIN Alternate (700); DIN Condensed (700); Optima (400,700,950); Seravek (100,300,400,500,700); Skia (300,400,700,900); Trebuchet MS (400,700); Verdana (400,700); Tahoma (400,700); Lucida Grande (500,700); Geneva (400); PT Sans (400,700); PT Sans Narrow (400,700); Impact (400)
- **serif**: Times New Roman (400,700); Times (400,700); Georgia (400,700); Baskerville (400,600,700); Big Caslon (500); Bodoni 72 (400,700); Bodoni 72 Oldstyle (400,700); Bodoni 72 Smallcaps (400); Didot (400,700); Hoefler Text (400,900); Palatino (400,700); Iowan Old Style (400,700,900); Charter (400,700,900); Cochin (500,700); Athelas (400,700); Superclarendon (300,400,700,900); Rockwell (400,700); American Typewriter (300,400,600,700); PT Serif (400,700); STIX Two Text (400,500,600,700); Marion (400,700)
- **mono**: Menlo (400,700); Monaco (400); Courier New (400,700); Courier (400,500,700); Andale Mono (400); PT Mono (400,700)
- **display / script**: Copperplate (300,400,700); Phosphate (400); Chalkduster (400); Chalkboard SE (300,400,700); Marker Felt (200,700); Noteworthy (300,700); Bradley Hand (700); Snell Roundhand (500,700,900); Zapfino (400); SignPainter (400,600); Savoye LET (400); Trattatello (400); Herculanum (400); Luminari (400); Party LET (400); Academy Engraved LET (400); Papyrus (400); Brush Script MT (400); Apple Chancery (400); Comic Sans MS (400,700); Krungthep (400); Silom (400)
- **中文**: PingFang SC† (100–600); PingFang TC† (100–600); Hiragino Sans GB (300,600); Heiti SC (300,500); STHeiti† (300,400); Lantinghei SC† (100,600,900); Songti SC (300,400,700,900); Songti TC (300,400,700); STSong (300); SimSong† (400,700); Kaiti SC† (400,700,900); Kaiti TC† (400,700,900); STKaiti† (400); STFangsong† (400); Libian SC† 隶变 (400); Xingkai SC† 行楷 (300,700); Yuanti SC† 圆体 (300,400,700); Wawati SC† 娃娃体 (400); HanziPen SC† 翩翩体 (400,700); Hannotate SC† 手札体 (400,700); Baoli SC† 报隶 (400); LingWai SC† 凌慧体 (500); Yuppy SC† 雅痞 (500); LXGW WenKai‡ 霞鹜文楷 (300,400,700)
- **日文**: Hiragino Sans (200–900); Hiragino Kaku Gothic ProN (300,600); Hiragino Mincho ProN (300,600); Hiragino Maru Gothic ProN (400); Toppan Bunkyu Mincho† (400); Toppan Bunkyu Gothic† (400,600); Toppan Bunkyu Midashi Mincho† (800); Toppan Bunkyu Midashi Gothic† (800); YuMincho† (500,600,800); YuGothic† (500,700); Klee† (500,600); Tsukushi A Round Gothic† (400,700); BIZ UDMincho† (400)
- **韩文**: Apple SD Gothic Neo (100–900); Nanum Myeongjo† (400,700,800); Nanum Gothic† (400,700,800); Nanum Brush Script† (400); Nanum Pen Script† (400); BM Jua† (400)

**本机没有、写了也会回落的字体**：`SF Mono` / `SF Pro`（SF Mono 只在 Terminal.app 包里，不是系统级字体，`local()` 找不到）、`Space Grotesk`、`Space Mono`、`Weibei SC`（魏碑）、`Noto Sans SC`、`Source Han *`、`Inter`。tokens 里写了没关系，会回落到栈里的下一个字体，渲染日志里会出现一行 `[Browser:WARN] [swatch] token font families not available (falling back): …`。但样片呈现的是回落后的字体，STYLE.md 里要照实写。等宽字体用 Menlo。

换机器或装了新字体后：`python3 styles/_swatch/fonts.py` 重新生成，再跑 `render.sh fontprobe --draft`，看日志里的 `fontprobe: N/N families OK`。

## 配乐（可选）

`styles/<slug>/score.json` 存在时，`render.sh` 会依次调用 `bin/vh music score.json`，再用 `bin/vh mix … profile=swatch dur=5 fade=0.45` 和拟音一起混（混音里截到 5 s、最后 0.45 s 淡出；一个整体增益，必要时接真峰值限幅，−14 LUFS），然后以 AAC 128k 封进 swatch.mp4。AAC 编码会让真峰值变高或变低，差多少看内容（现在的 28 个样片第一次编码在 −1.9 到 +1.4 dB 之间，editorial-data 的钢琴最高；限幅更重的重混还会更高，editorial-data 第二次重混 +2.4 dB），所以封装后再量一次：高于 −1.5 dBTP 时，从混音实际的真峰值（和原上限取较低者）再降低超出的量加 0.1 dB，重混、重新封装；最多 3 次，还超就报错退出。现在的 28 个样片里有 3 个需要重混：cutout-jazz 一次，dunhuang-mural 和 editorial-data 各两次。写法见 `bin/vh music --example` 和 `tools/audio/README.md` 的"score.json"。BPM 选能让 5 s 落在整拍上的值：96 BPM 是 8 拍（2 小节），120 BPM 是 10 拍，72 BPM 是 6 拍。段落边界对齐内容规格（0.8、2.0、4.0 s）。实测：96 BPM、2 小节的测试曲，封装后成片 1.06 MB，−14.6 LUFS。

**拟音**：再放一个 `styles/<slug>/events.json`，格式和 `bin/vh sfx place` 一样，是 `[{"t", "sfx", "gain_db", "pan", "dist"}]`，`render.sh` 就会把音效摆在每个动作发生的那一帧，按 swatch profile 和配乐一起混音：以配乐 3 s 的短时响度为锚点，每个音效按类（hero、detail、ambience、signal）往各自的电平走一半，身后一个 0.25 s 的短房间，配乐不做 ducking（起始平衡是原来的配乐 0 dB、音效 −3 dB；做法见 `playbook/04-audio.md` 的"混音"，数值见 `tools/audio/README.md` 的"混音"）。名字提示分错类时，在 `FOLEY` 里给那个事件写 `role`，`foley.mjs` 会带进 events.json。内置音效的塑形字段（`dur`、`pitch`、`center`、`dir`、`bright`、`tone`、`pan_from`、`pan_to`）和钉住的 `variant` 也照样带进去：转场按动作塑形，每个风格选一个合适的转场家族（见 `playbook/04-audio.md` 的"转场音效按风格选"）。`sfx` 可以是内置的 15 个音效名，也可以是风格文件夹里自己的 WAV，用相对路径，来源记进 STYLE.md。`t` 是声音落点，要和 swatch.js 里对应动作的时间取自同一个常量；声像 `pan` 取发声物体在画面上的 x。qa 会把这些落点当成设计好的起音，不报 click。推荐做法：在 swatch.js 里 `export const FOLEY = [{t, sfx, gain_db, pan}]`，t 直接引用动作的时间常量，再用 `node styles/_swatch/foley.mjs <slug>` 生成 events.json，画面和声音就只有一个时间来源。内置音效里没有合适的声音时，可以在 `styles/<slug>/sfx/` 放自己合成的 WAV，但生成代码必须写进 `styles/_swatch/custom_sfx.py`（带固定种子），保证 `uv run -q --with numpy --with scipy python styles/_swatch/custom_sfx.py` 能逐字节重建。不要放下载来的素材。

想让段落点精确落在 0.8 / 2.0 / 4.0 s，最省事的是 150 BPM 加 `"meters": {"1": 2, "2": 3, "3": 3, "4": 2, "5": 3}`（9 个电影、品牌类样片都这么做）。封装后 `render.sh` 会自动跑完整的 `bin/vh qa`（扫描、cue check、混音报告），先对混音 WAV（`out/<slug>/music.wav`），它是门禁，通过了 swatch.mp4 才放进 `media/`；再对 swatch.mp4 跑扫描和 cue check（单个 cue 的问题只作警告，整个编码偏了才判失败，那是封装错位；混音报告读的是 stems，不重跑）。都是 `--from 0.3 --to 4.5` 加 `--stems out/<slug>/stems`，结果写进 `out/<slug>/qa.txt` 和 `qa_mp4.txt`，日志在同名的 `.log`：出现数字静音、掉音、抽吸（配乐自己的凹陷不算）、WAV 上对不上的 cue、只以“弱”对上又被报告判为 `BURIED` 的 cue，或混音报告的硬失败，就判失败，失败的几行会打印出来。不带节拍表的话，qa 在 5 s 的片段上只会检查 1.0–2.2 s，所以不要手动省掉它。第一轮最常见的两种失败：只有 hats 的段落在拍与拍之间出现数字静音；稀疏段落出现抽吸凹坑。修法都是加一层 pad 或 sub 持续垫底。

## render.sh 做的检查

- **看门狗**：HyperFrames 在自己的进程组里运行，超时（draft 300 s、正式 600 s）或日志连续 `SWATCH_STALL`（默认 120 s）不动时，整组杀掉，Chrome 一起杀。离线时依赖 CDN 的页面就是这样静默挂住的。
- 退出码、输出文件存在、**帧数正好 150**、分辨率 1920×1080。
- **抽 4 帧**（t = 0.4 / 1.7 / 3.0 / 4.6，每个规格段一帧）看 signalstats：至少一帧 Y 的极差 ≥ 24（canvas 确实画了东西）；任何一帧都不是品红错误卡片；4 帧的 md5 不能全部相同（排除冻帧）。
- 日志里的 `[swatch]` 行去重后打印出来（字体回落、异常）。
- 转码：CRF 从 18 往上加，直到文件 ≤ 1 500 000 字节；封面的 JPEG q 从 2 往上加，直到 ≤ 200 000 字节。有声音时再量 AAC 编码后的真峰值，高于 −1.5 dBTP 就降低混音的上限重混（见上面的配乐一节）。
- 自查联系表：`styles/_swatch/out/<slug>/sheet.png`（t = 0.25 … 4.75，10 格，带时间戳）。它只是中间产物，不交付；按 `playbook/02-verification.md` 自查时用它，转场前后再单独抽 strip。

## 画廊

`gallery.py` 扫描 `styles/*/media/poster.jpg`（跳过 `_` 开头的文件夹），拼成 5 列的 `styles/gallery.jpg`（≤ 2 MB），每张下面写风格名。风格名取 STYLE.md 第一行 `# <风格名> · <slug>`，没有就取 tokens.json 的 `name`，再没有就用 slug。加 `--mp4` 时还会生成 `styles/gallery.mp4`：每个样片取 1.9–3.4 s，叠上名字，按顺序硬切，1280×720，≤ 12 MB。声音就是每个样片自己那一段，接缝处做 30 ms 的等功率交叉淡化（不爆音，也不凹下去），整条的开头和结尾各淡入淡出 30 ms；没有音轨的样片那一段垫房间底噪，不留数字静音，并打印一条警告。音频是 AAC 160k。实测 31 条（2026-10-02）：jpg 1.13 MB，mp4 7.65 MB（46.5 s，CRF 23）。

## 给预设作者的坑

1. **从 demo 起步**：`cp styles/_swatch/demo/{swatch.js,tokens.json} styles/<slug>/`，然后改。先 `render.sh <slug> --draft --hud` 看联系表，定稿后再不带参数渲正式版。
2. **每帧从零画起**。运行时会 `ctx.reset()`，上一帧留下的任何东西都没有了。想要"拖尾"或"残影"，就在同一帧里把过去几帧重画一遍（`motionBlur`，或者对 `t − k/30` 循环）。
3. **setup 不能依赖时间**。它在每个 worker 里各跑一次，而 worker 可能从第 100 帧开始。
4. **字体写进 tokens**，否则不会被预载；只在 renderAt 里用到的字体族，加进 `export const fonts`。用 `lib.setFont` 或 `lib.font` 设字体，不要手写 `ctx.font`，否则兜底栈就没了。
5. **颜色键写错会变品红**（`lib.color` 的兜底值）。整块品红同时也是错误卡片的颜色，看到就去查日志。
6. **图层名是全局的**。`lib.layer("foo")` 在整个页面里共用一张 canvas，自己的图层加上 slug 前缀。lib 自己用的名字都以 `__` 开头。
7. **转场的两个 painter 各画一整帧**，而且画到传进来的 ctx 上。转场前后的颗粒、暗角放在转场之后统一叠一次（demo 就是这么做的），否则会叠两遍。
8. **大面积的逐帧颗粒会吃码率**。实测 demo 把颗粒开到 0.22，CRF 18 仍然只有 1.18 MB。更重的噪声会让 render.sh 自动提高 CRF，画面随之变糊。质感优先用低频的（纸、半调、扫描线），颗粒按 12–24 fps 刷新。
9. **snapshot 不可信**：字体和某些时刻的画面以 render.sh 的输出为准。
10. **不要用网络资源**：页面加载那一刻只要有外部请求挂住，渲染就会静默卡死（看门狗会杀掉）。需要的库放进风格文件夹，用 `import … from "./x.js"` 引入；多个风格共用的库放进 `styles/_swatch/vendor/`（stage 会一起复制），在 swatch.js 里写 `import … from "../../vendor/x.js"`。换库版本时重跑 `determinism.sh`。
11. **中文最小字号 46 px**，英文 24 px 以上，1280×720 缩小后还要能读。
12. **WebGL 可以用，但不是必需的**。lib 里的质感都是 Canvas2D 加 SVG 滤镜做的；只有真的需要逐像素运算时（CRT 曲面、色差、流体噪声）才用 `lib.shader`。GLSL 里的 `fract(sin(…))` 哈希在 SwiftShader（CPU）上逐字节确定；只有改回 GPU 渲染时才可能随显卡不同而变。
13. 日志里的 "Parallel drawElement capture stays off…" 不用管：`--no-browser-gpu` 下 HyperFrames 本来就不走 drawElement 截帧（它只在 GPU 模式下启用，而且和 `Page.captureScreenshot` 差约 80 dB，是上面确定性问题的来源之一）。不要为 swatch 设 `HF_DE_PARALLEL_ROUTER=true`。

## 给 `bin/vh style` 的接线

```bash
bin/vh style <slug> [--draft] [--hud] [--workers N]   →  exec "$ROOT/styles/_swatch/render.sh" "$@"
bin/vh style gallery [--mp4]                          →  uv run -q --with pillow python "$ROOT/styles/_swatch/gallery.py" [--mp4]
bin/vh style check <slug> [workers_b]                 →  "$ROOT/styles/_swatch/determinism.sh" <slug> [workers_b]
```

首次使用前要有 `styles/_swatch/node_modules`：`bin/vh setup` 和 `install.sh` 都会装；`bin/vh style <slug>` 和 `bin/vh style check <slug>` 发现缺依赖时会先自动 `npm ci`（Blender 场景不需要它，跳过这一步）。直接调用 `render.sh` 或 `determinism.sh` 时缺依赖会报错，并提示 `(cd styles/_swatch && npm ci)`。
