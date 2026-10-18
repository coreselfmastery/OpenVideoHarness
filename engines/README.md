# 引擎：初始化与安装

新项目一律建在 `projects/<date>-<slug>/` 下。本目录里的东西是模板，不要直接在里面改。

最快的方式是 `bin/vh new <type> <slug>`：它会建好目录、复制模板；手绘和 MV 类还会复制 ClaudeAnimationBase 并装好依赖，short、promo、data、meme 类会自动运行 `bin/vh hf-init` 装好 HyperFrames（离线失败时会提示稍后重跑）。加 `--engine canvas-film` 时，不管哪一类，都改成复制旁白驱动的 canvas 引擎（下面"canvas-film"一节）。只有 Remotion、ManimGX 要在建好目录后，按下面对应的一节手动初始化；MV 或论文类改用 HyperFrames 时，以及 edit 类（实验性，首选 HyperFrames，做法见 [`editing.md`](editing.md)），对项目目录单独运行一次 `bin/vh hf-init`。

## ClaudeAnimationBase（p5.js + p5.brush），已装好

```bash
cp -R engines/ClaudeAnimationBase projects/<date>-<slug>
cd projects/<date>-<slug> && npm install
node render.mjs --sheet=0.5,2,4 --cols=3 --w=480 --out=out/check/sheet.jpg   # 验证环境，约 5 秒
```

- 使用前完整读一遍 `ANIMATION_GUIDE.md`。
- 它按页面合约（`engines/CONTRACT.md`）写了 `window.film`，所以 `bin/vh frames <项目>` 和其他宿主能直接从 `studio.html` 取帧。用和 `render.mjs` 同一个浏览器时（`CHROME_PATH`），取出的帧和 `--stills` 逐像素相同。
- 在 `src/scenes/` 下新建自己的场景文件，然后把 `studio.html` 里 `demo.js` 的 script 标签换成它。
- 在 `src/config.js` 里设置 `duration`、`bpm`、`offset`，需要时再设 `fps`（默认 24，`--fps=` 可以临时覆盖）；有音乐时在配置里设 `PROJECT.audio`（路径相对项目根目录），或者加 `--audio=audio/song.mp3`。`--clip` 和 `--encode` 都会混入音频，并截到或补到画面的精确长度：音频比画面短时补静音并打出警告（硬规则 2：让 `duration` 跟着音频走），不会像 `-shortest` 那样把画面截掉。
- 长片用 `--frames --workers=4` 渲 JPEG 帧（可并行、可续渲），再 `--encode`。`--encode` 不开浏览器，自己读 `src/config.js` 里的 PROJECT，按 `out/frames/frames.json` 记下的 fps 编码；只编 `duration × fps` 帧，从磁盘上的第一帧开始。时长改短后多出来的旧帧会被排除并提示。开头或结尾缺帧（只渲了一段 `--range`）只给警告；两段已渲染的帧中间有缺口时直接报错并列出缺的帧，因为编出来的视频会停在缺口处。`--loop=<name>` 的帧单独放在 `out/frames_loop_<name>`，编成 `out/loop_<name>.mp4`，不会和正片混在一起。
- 没有 GPU 时加 `--soft-gl`，用 SwiftShader 软件渲染 WebGL。它同时关掉 2D canvas 的 GPU 加速：开着加速时，同一帧每次启动渲出来都不一样（PSNR 约 39 dB，过不了硬规则 1 的 45 dB）；关掉后，跨进程、乱序渲染都逐像素一致，demo 单帧也从约 40 s 降到约 12 s（无 GPU 的 Linux 实测）。另外，所有路径都关掉了 Chrome 的 CanvasNoise：它给 GPU 加速的 2D canvas 读回加每次启动都不同的噪声（反指纹功能），是上面那种差异的主因。有 GPU 的机器上 2D canvas 默认也走 GPU 加速，同样受 CanvasNoise 影响；关掉以后，2026-09-30 在 macOS 的 Metal GPU 上实测：同一帧跨启动、乱序渲染都逐像素一致（见 CHANGELOG 里的 “Verified on macOS with a GPU”）。
- 本机实测：1080p 约 0.13 秒/帧（Metal），11 秒的 demo 渲染 37 秒。
- 来源：[JohnHeibel/ClaudeAnimationBase](https://github.com/JohnHeibel/ClaudeAnimationBase)，MIT。复制过来时没有带 `.git`。

## canvas-film（canvas 2D，旁白驱动），已装好

完整说明：[`canvas-film/README.md`](canvas-film/README.md)。

```bash
bin/vh new <type> <slug> --engine canvas-film     # 复制 engines/canvas-film/template，不用装依赖；画幅 16:9
bin/vh frames projects/<date>-<slug> --at 1,5,9   # 模板带一支 23 秒的示例片，建好就能取帧
```

- 适合旁白撑着的横屏长片：镜头、字幕、章节进度条的时间都写成挂在旁白字上的 cue（`"@b2:跟着走-0.3"`），重配、改词、插停顿以后自己跟着走。一个 cue 找不到它的句子或词，`ready` 立刻失败，写明镜头、cue 原文和这句现在的文字，不会等到超时。
- 一页 `film.html` 加 `src/*.js`，不用构建。它按页面合约写了 `window.film`，`bin/vh frames` 取帧、`bin/vh textcheck` 查字直接能用；reads 和字幕（`texts`）、画面事件（`events`）、章节和 cue 表都在 `ready` 里算好。
- 字号下限在画字的最底层兜住，故意要小的字写 `texture: true`；绕过它写下的小字，`ready` 时会被报出来。
- 成片画面用 `bin/vh render <项目>`（4K 加 `--dpr 2`），再用 `bin/vh mux` 套上混音。出片后只改了一镜，用 `bin/vh patch <成片> --seconds <起>-<止>` 只重画那一段、在关键帧处接回去（套过混音的成片加 `--sidecar out/film.mp4.render.json`）。现在只有 2D canvas，没有 Three.js 底层。

## HyperFrames（HTML + GSAP）

要求 Node ≥ 22 和 FFmpeg。**版本固定在实测过的 0.8.82**（`bin/vh` 默认使用；想试新版，就设 `HYPERFRAMES_VERSION=0.8.84`，先跑 lint 和一次冒烟渲染确认没有回归，再把默认版本改上去）。**`bin/vh new short|promo|data|meme <slug>` 会自动初始化**，也可以对已有项目单独运行 `bin/vh hf-init <项目目录> [landscape|portrait|square]`。

> ⚠️ HyperFrames 0.8.x 的 `init` 和 `skills update` 会把 skills 装进**全局**的 `~/.claude/skills` 和 `~/.agents/skills`。`--skip-skills` 参数目前不生效，只能用环境变量 `HYPERFRAMES_SKIP_SKILLS=1` 跳过。`bin/vh hf-init` 已经设置了这个变量，并且只把工程文件拷进项目，不拷它生成的 CLAUDE.md 和 AGENTS.md，避免和本仓库的路由冲突。自己手动运行 npx 时，也要带上这个变量：

```bash
export HYPERFRAMES_SKIP_SKILLS=1 DO_NOT_TRACK=1          # 每次开终端先设置
npx hyperframes lint                                    # 写的过程中随时检查
npx hyperframes check --snapshots                       # 最终关卡
npx hyperframes snapshot --at 1.5,4.2 --describe false  # 单帧；--describe false 不能省，见下
npx hyperframes preview                                 # 浏览器预览
npx hyperframes render --quality draft --fps 30 --output out/draft.mp4
npx hyperframes render --quality delivery --fps 30 --output out/final.mp4
```

用 `&` 或 `nohup` 把渲染放到后台、这条命令在渲染结束前就返回时（agent 常这样跑），在这一行加上 `HYPERFRAMES_RENDER_DETACHED=1`：

```bash
export HYPERFRAMES_SKIP_SKILLS=1 DO_NOT_TRACK=1
HYPERFRAMES_RENDER_DETACHED=1 nohup caffeinate -i npx hyperframes render --quality draft --fps 30 --output out/draft.mp4 > out/draft.log 2>&1 &
```

- **为什么**：0.8.82 的 render 开始时记下启动它的那串父进程，之后其中任何一个退出，它就自己取消，日志末尾是 `Render cancelled: render_cancelled_parent_exited`。agent 的一条 Bash 命令返回，那个 shell 就退出了。`nohup … & disown` 挡不住，因为渲染查的是父进程还在不在，不是收没收到信号。设了这个变量，它就不再记父进程（`render --help` 里没写，见 hyperframes 包里 `dist/cli.js` 的 `createRenderCancellationScope`）。
- **时有时无**：shell 在渲染起来之前就退了的话，父进程链里已经没有它，能渲完；同一条命令里还在 `sleep` 或 `tail` 日志，就会被取消。所以跑通过一次，不说明可以不加。
- **别把长渲染交给 agent 自己的后台任务**：agent 的后台命令往往有时长上限（2026-10 的 Claude Code 默认 30 分钟），到点连同渲染一起被停。照上面那行把渲染脱离出去，命令立刻返回，再看日志等它结束。
- **代价**：加了变量，父进程退出，渲染也不会停，要停得自己杀，按输出路径匹配：`pkill -f "[h]yperframes render.*out/draft.mp4"`（`[h]` 让执行 pkill 的 shell 不匹配到自己）。变量只写在后台那一行，不 export，前台渲染照旧跟着父进程停。`caffeinate -i` 防止 Mac 睡眠，只有 macOS 有，Linux 上去掉。

### 出 4K

照常按 1080p 写合成。`render --resolution 4k` 让 Chrome 按 2 倍像素密度渲（`devicePixelRatio` = 2）：页面仍按 1920×1080 排版，每个排版像素画成 2×2 个物理像素。这不是把 1080 的画面放大。DOM 和 SVG 自己会变清楚；代码自己画像素的地方，要自己处理这个 2 倍，处理错了不是发糊，而是大小和位置错（介绍片第一版 4K 的标签大了一倍，就是这样）。

`--resolution 4k` 会按合成的画幅自动选预设（竖屏合成用 `portrait-4k`）；显式写 `landscape-4k`、`portrait-4k`、`square-4k` 时要和画幅一致，4:5 没有 4K 预设。4K 只是渲染参数：建项目、`bin/vh hf-init` 的画幅写 landscape、portrait、square、4:5 或 3:4（`*-4k` 预设会搭出原生 3840 宽的合成，按 1080p 定的字号下限就失效了，`hf-init` 会拒绝）。4:5 和 3:4 只出 1080p。

| 自己就对，不用改代码 | 要写代码 |
|---|---|
| DOM 文字、CSS 的线和边框、SVG | 2D `<canvas>`：宽高乘 `devicePixelRatio`，CSS 尺寸仍是合成尺寸，再 `ctx.scale(dpr, dpr)`，之后坐标照旧按 1080p 写（只开大画布、不 scale，画面会挤在左上角四分之一）。每帧开头重置变换也要带上 dpr：`ctx.setTransform(dpr, 0, 0, dpr, 0, 0)`；写成 `setTransform(1, 0, 0, 1, 0, 0)` 或 `resetTransform()` 会清掉这个 2 倍，1080p 下看不出来，4K 下又挤回左上角（清屏、按设备像素整幅贴一张离屏层时可以先用单位矩阵，画完再设回 dpr） |
| `ctx.scale` 之后画的 canvas 内容，包括 `lineWidth`、`measureText` | 拿 `canvas.width`、`image.width`、`getImageData` 去算布局的地方：这些是物理像素，要除以 dpr |
| 4K 的 `<video>` 源（HyperFrames 按源分辨率取帧） | Three.js：`renderer.setPixelRatio(dpr)`，后期链 `composer.setPixelRatio(dpr)` |
| | 先画好、再 `drawImage` 进 2D canvas 的 WebGL 离屏层：它的 canvas 和 `viewport` 也乘 dpr，`drawImage` 的目标尺寸照旧按合成尺寸写；按 1080 开的话，这一层在 4K 下被放大发糊。着色器里的位置按 CSS 像素算（由 `uv` 和这块矩形的 CSS 尺寸换算），不用 `gl_FragCoord`，图案就不随 dpr 变 |
| | 着色器里的 `gl_PointSize` 按设备像素算，要乘 dpr，上限的 `min()` 也要乘 |
| | 1 px 的 WebGL 线永远是 1 个设备像素，4K 下变细；要粗细一致，用 `Line2` 或面片 |
| | `shadowBlur`、`ctx.filter` 的 blur、`UnrealBloomPass` 的核按设备像素算，4K 下光晕变紧；用 `gl_FragCoord` 算的图案频率加倍 |
| | 1080 尺寸的贴图、截图、视频代理在 4K 下会被放大发糊：这类素材按 2 倍准备 |
| | 按设备像素加的颗粒会让文件变大约 4 倍 |

每次出 4K 都这样查：

1. 先渲一个 4K draft（`--quality draft` 就够），和人认可过的 1080p 成片比：`bin/vh check out/draft-4k.mp4 --against out/final.mp4`。两边缩到 480 宽逐帧比（颗粒、抗锯齿这类正常的分辨率差异会被平均掉），连续半秒画面不一样就失败，并在视频旁边的 `check/` 里出"1080 | 4K 缩小 | 差值"的对照图。判失败看的是差异持续多久，不是掉得多低：布局错（大一倍、挪了位置、少了东西）只要元素在画面上就一直低于 18 dB；光晕、闪光会掉得很低但很快回来（介绍片修好的 4K 里最低到 10 dB，最长连续 9 帧），所以要连续半秒（30 fps 下 15 帧）才算失败，介于 18–24 dB 的给 WARN。阈值只在介绍片和合成测试片上标定过（2026-10-04），余量不大：报 WARN 或 FAIL 都先看对照图再下结论。
2. 再从 4K 成片里裁一两帧原尺寸，看字和细线锐不锐。这一步只查"发糊"，查不出大小和位置错。
3. `hyperframes snapshot` 永远按 dpr 1 渲，`--zoom-scale 2` 也是页面建好以后才放大，不能当 4K 预览。

成本（介绍片 103 s，M3 Max）：HyperFrames high 画质 1080p 约 4 分钟、509 MB，4K 约 9–13 分钟、1.5 GB（约 125 Mbps，2 个 worker）。发布前用 x264 CRF 18–19、`-preset slow` 重编码：1080p 297 MB，4K 1.04 GB。GitHub release 每个文件不能超过 2 GiB，按 high 画质的码率，超过约 135 s 的 4K 要先重编码。Blender 原生 4K 每帧约是 1080p 的 4 倍（`engines/blender.md`）。

**长片出 4K 先看磁盘。** 4K 一律走截屏（drawElement 和 Linux 的 BeginFrame 截帧都不支持 2 倍密度），而 0.8.82 的多 worker 截屏默认先把每一帧存成 JPEG，最后再编码；只有 `--workers 1` 默认是流式的。临时帧写在 `--output` 旁边的 `work-…` 文件夹里（Windows 上是系统临时目录），按每帧约 4 MB 估：一支 7–8 分钟的片子（约 14000 帧）要五六十 GB。开渲前它按这个估算查那块盘，超过空余空间的 90% 就直接拒绝，截完前 10 帧再按实测大小查一次；报错开头是 `Disk capture may need ~… MB of temporary frame storage`。三个办法：

- 设 `HF_CAPTURE_PARALLEL_STREAM=true`：多个 worker 截下的帧直接流进编码器，不落盘。那支片子 4 个 worker 在 M3 Max 上渲了十来分钟；
- `--workers 1`：单个 worker 本来就是流式的，只是慢；
- 把 `--output` 指到空间够的盘上。

```bash
HF_CAPTURE_PARALLEL_STREAM=true NODE_OPTIONS=--max-old-space-size=8192 npx hyperframes render --resolution 4k --quality delivery --fps 30 --workers 4 --output out/final-4k.mp4
```

`NODE_OPTIONS` 把 Node 的堆开到 8 GB，这是 HyperFrames 自己的建议：它按每个 worker 约 640 MB、另留 1 GB 来估，这台 M3 Max 默认约 4 GB 的堆够 4 个；自动选出的 worker 比这多时，日志里会打出 `capture workers may exceed this process's V8 heap`，显式写了 `--workers` 就不提醒。那次渲染带着它，没试过去掉。放到后台跑时，照上文在这一行加 `HYPERFRAMES_RENDER_DETACHED=1`。

码率和耗时随画面差很多：这支 canvas 片子的 4K 约 26 Mbps，渲 1 s 片长约 1.4 s；上面的介绍片（3D）约 125 Mbps，要 5–8 s。所以上面"超过约 135 s 的 4K 要先重编码"是按介绍片的码率算的，自己的片子先量再定。

### 最小写法（0.8.82）

`bin/vh hf-init` 搭出来的 `index.html` 就是最小的合成（`bin/vh new short|promo|data|meme` 会自动跑它；`--aspect 4:5` / `3:4` 用竖屏模板，把视口、CSS 高度和 `data-height` 改成 1350 / 1440），手写时照着改；完整样板见 `showcase/02-short-leo-doppler/index.html`。`<body>` 里是这样：

```html
<div id="root" data-composition-id="main" data-start="0" data-duration="10" data-width="1080" data-height="1920">
  <h1 id="title" class="clip" data-start="0" data-duration="10" data-track-index="0">标题</h1>
</div>
<script>
  const tl = gsap.timeline({ paused: true });   // 必须 paused：时间由渲染器推进，不是 GSAP 自己走
  tl.fromTo("#title", { opacity: 0, y: 24 }, { opacity: 1, y: 0, duration: 0.6 }, 0);   // 第 3 个参数是绝对时间（秒）
  window.__timelines["main"] = tl;              // 用 data-composition-id 当 key 登记，渲染器只认这里
</script>
```

- **根元素**：`data-composition-id` 必填；`data-start`、`data-duration` 是秒；`data-width`、`data-height` 是像素。项目根目录只放一个 composition（`index.html`）。`<head>`（viewport、gsap 的 `<script>`、把 `html, body` 定成画布大小的样式、用 `local()` 声明本机字体的 `@font-face`）照脚手架抄。
- **`.clip`**：要按时间出现的元素加 `class="clip"`，写 `data-start`（第几秒出现）和 `data-duration`（持续几秒），渲染器按它们决定元素什么时候在画面上。`data-track-index` 只是 Studio 时间线上的行号，渲染不读它，也管不了叠放顺序，叠放用 CSS `z-index`。
- **动画都挂在这条 paused 的 timeline 上**（`to`、`from`、`fromTo`、`set`），不用 CSS `animation` / `transition`、`Math.random()`、`Date.now()`（硬规则 1）。
- **驱动 tween**：曲线、轨道、物理这类每帧重算的画面，在同一条 timeline 上挂一个 `ease: "none"` 的代理 tween，在回调里按 t 重画，画面就仍是 t 的纯函数。showcase 02 的 `draw(t)` 这样画出了全部物理画面，`DUR` 是片长（秒）：

  ```js
  const drv = { t: 0 };
  tl.fromTo(drv, { t: 0 }, { t: DUR, duration: DUR, ease: "none", onUpdate: () => draw(drv.t) }, 0);
  ```

- **写一段，查一段**：`npx hyperframes lint` 到 0 error 再往下；`snapshot --at <秒> --describe false` 看几个关键时刻的单帧；`render --quality draft --fps 30 --output out/draft.mp4` 出草稿，字体和接缝以渲出来的 mp4 为准；最后 `--quality delivery` 出成片。完整写法见上面那一块命令。

### 画面文字检查（canvas 片子）

`npx hyperframes check` 只量 DOM 文字，脚本画进 `<canvas>` 的字在它眼里只是像素。canvas 片子用 `bin/vh textcheck <项目>` 查：哪条字被后画的东西盖住、和画面对比不够、出了画面或被边缘裁掉、被 DOM 字幕压住。合成的内联脚本里按页面合约（`engines/CONTRACT.md`）加一行就能用：

```js
window.film = {
  frame: (t) => drawFrame(t),   // 必填：画出第 t 秒，连同它自己管的 DOM（比如字幕），和渲染出的那一帧一样；可以返回 Promise
  duration: 24.8,               // 片长（秒）
  texts: TEXTS,                 // 可选：reads 登记表，格式同 readcheck 的 texts.json：[{text, start, end, read?}]
};
```

原来的写法 `window.__vh = { draw, texts }` 仍然认，`draw` 就是 `frame`。

- **画字的函数不用改。** 检查在合成的脚本运行之前挂上 canvas 的 `fillText` / `strokeText`，记下每条字画在哪、用什么字体，能单独去掉一条字重画这一帧。所以字要用 2D canvas 的 `fillText` / `strokeText` 画：做成图片的、画进 WebGL 的、画在离屏 canvas 里再贴上来的字，它看不到，登记了会报"没画成 canvas 字"。字底下的"画面"是页面上所有 canvas、video、img 按层叠顺序合成的结果，字画在透明的一层上也按它后面那层量；CSS 背景、SVG 这类 DOM 不算在内。逐字出现的动画字、拆成几次画的一行字、中间的"·"和箭头画成图形的，都按字母对得上。
- **登记表**：命令行给了 `--texts <文件>` 就用它，否则用页面的 `texts`（`window.film.texts` 或 `window.__vh.texts`），再没有就读 `out/texts.json`（readcheck 读的同一份）。每条在它的时间窗里取 3 个时刻（开始后 0.4 s 到结束前 0.3 s），所以 start 要是字完整显示的那一刻，这也是 readcheck 的约定；登记早了会报"有的时刻没画全"。没有登记表也能跑，只做下面那遍扫描。
- **没登记的字**每秒扫一遍全片，每行字在它最完整的那一刻量一次，有问题只警告：观众该读的，就登记进去。
- `draw(t)` 要是 t 的纯函数（硬规则 1）：同一个 t 会画好几遍，两遍画面不一样会报出来，那一刻的数字不可信。
- **界面压在场景上**：页面给了 `ui(t)`（常驻界面的字和线在哪）、`frame(t, { layer: "scene" })` 能只画场景时（`engines/CONTRACT.md`；canvas-film 引擎自带），每秒把场景单独画一遍，看它在界面的框里画了什么：和那一块的底色（每 32 px 一格取中位色，格间渐变）差 60 级以上（r + g + b）的像素算场景的东西，纸面、渐变、暗角和颗粒都不算。超过框的 0.2%（至少 30 个像素），或者在很长的框里有 150 个像素以上，或者有一块从框的这边穿到那边（一条线竖着穿过细细的进度条），就报，同一段只报一次、附裁图，只警告（`ui(t)` 抛错和画帧函数抛错一样算页面出错）：占得少是一条线、一个边穿过了进度条或字幕（挪开一个），占得多（15% 以上）是界面压在一张很花的画面上（该有底板或压暗的一条）。界面挪了位置（比如进度条挪进安全框）以后，最容易出这种事。
- **浏览器**：`CHROME_PATH`，否则用这个项目 `render` 时用的 chrome-headless-shell（`HYPERFRAMES_BROWSER_PATH`，或项目里装的 HyperFrames 固定的那个版本；还没下载就先 `npx hyperframes browser ensure`），再否则用 `~/.cache/puppeteer` 里最新的 chrome-headless-shell，最后是系统的 Chrome 或 Chromium，不用装 npm 包。用的不是 `render` 那个时会提示一行：版本不同，字的排布可能和成片有细微差别。合成从项目目录起一个只在本机 127.0.0.1 的服务来打开，尺寸按根元素的 `data-width` × `data-height`，设备像素比 1；先等 `window.__hf.buildReady`、`window.__vh.ready`（可选）和字体加载完。
- **结果**：有登记的 read 被盖住（露出不到 70%）、低于 3:1、出画或被裁、压在字幕下，或画帧函数抛错，退出码 1；没登记的字、字幕底下的画面太亮、场景画到界面底下只警告；没法检查（没有 `window.film.frame` 也没有 `window.__vh.draw`、页面没加载起来、找不到浏览器、一条 canvas 字都没量到）是 2，不算通过。每处问题存一张裁图到 `out/check/textcheck/`，全部数字在同一目录的 `textcheck.json`；阈值都能调，见 `bin/vh textcheck -h`。一支七八分钟、一百来条登记文字的片子，在 M3 Max 上十几秒跑完。

### 注意事项和已知问题（0.8.82 实测）

- **`snapshot` 一律带 `--describe false`。** 环境里有 `GEMINI_API_KEY`（或 `GOOGLE_API_KEY`）时，`snapshot` 默认把每一帧发给 Gemini 做画面描述，结果写进 `snapshots/descriptions.md`：画面离开本机，还要按 Gemini 计费。本仓库的 `bin/vh tts … --align gemini` 也要这个 key，所以 key 多半是设了的。`--describe false` 和 `--describe=false` 都能关掉；没设 key 时它只打一行 "skipping"。`check` 不受影响。
- **第一次 `render` 会下载 chrome-headless-shell，而且几乎没有提示。** 现象：在非交互的 shell 里（agent 就是这样跑的），终端只有 "Checking browser…" 在转圈，没有大小和百分比，下载期间一直是这一行，网慢时看上去就像卡死了。原因：`render` 用 HyperFrames 自己管理的 chrome-headless-shell（0.8.82 固定为 152.0.7977.30，macOS 12 上是 150.0.7871.124），缓存里没有就先下载：约 100 MB，解压后约 200 MB，放在 `~/.cache/hyperframes/chrome`，所有项目共用。它先看 `HYPERFRAMES_BROWSER_PATH`（设了就用它指的那个），再看这个缓存里的固定版本，都没有就下载；装了 Google Chrome、`~/.cache/puppeteer` 里有别的版本，也一样下载。下完会打出 `Browser: download`，以后是 `Browser: cache`。解决：第一次渲染之前先跑 `npx hyperframes browser ensure`，它会写明在下什么、多大，下完打印路径；下不了，看 wiki 的[国内网络](https://github.com/ZLHad/OpenVideoHarness/wiki/%E5%9B%BD%E5%86%85%E7%BD%91%E7%BB%9C)。
- **`snapshot` 和 `render` 用的可能不是同一个 Chrome。** `snapshot`、`check`、`validate`、`layout`、`compare` 找浏览器的顺序和 `render` 不一样：`HYPERFRAMES_BROWSER_PATH`，然后 `~/.cache/puppeteer/chrome-headless-shell` 里最新的版本，再是上面那个固定版本，再是系统的 Chrome，都没有才下载。所以 `~/.cache/puppeteer` 里有 chrome-headless-shell 的机器上，快照和成片出自两个版本（实测一台 Mac 上 `snapshot` 用 150.0.7871.24，`render` 用 152.0.7977.30），字的排布会有细微差别。要让快照、成片、`bin/vh textcheck` 和别的机器上的结果可比，把 `HYPERFRAMES_BROWSER_PATH` 设成同一个 chrome-headless-shell 的路径（`npx hyperframes browser ensure` 下完打印的那个），这几样都认它；只固定 textcheck 就设 `CHROME_PATH`。
- **`font-weight: 800` 在 macOS 自带的 PingFang SC 上等于 600。** 现象：字幕规格写了字重 800，渲出来却不够粗，也没有报错。原因：PingFang SC 只有 6 个字重，从 Ultralight 到 Semibold（CSS 的 100–600），没有 Bold 和 Heavy；请求 700、800、900 都落到 600，实测渲出的字和 600 逐像素相同，浏览器也不会再合成粗体。解决：用 PingFang SC 就写 600，并在 STYLE.md 里记下；真要 800，自己带一个有这个字重的字体（Noto Sans SC 等，不联网的取法见 wiki 的[国内网络](https://github.com/ZLHad/OpenVideoHarness/wiki/%E5%9B%BD%E5%86%85%E7%BD%91%E7%BB%9C)），或者换一个有更粗字重的系统字体（比如 Songti SC 有 900，`styles/_swatch/README.md` 的字体表列了各字体实测可用的字重）。
- **`--format png-sequence` 写出的是 RGBA，而且不画页面背景。** `html`、`body` 和合成根元素上的 `background` 都不会进 PNG（那些地方 alpha = 0），只有元素自己的底色会留下。做确定性检查时要留意，细节和比对办法见 `playbook/02-verification.md` 的"确定性"一节。
- **不要运行 `npx hyperframes skills update`**。skill 文档已经拉到本地，直接读：`references/repos/hyperframes/skills/`（工作流和参考资料）、`references/repos/hyperframes/_upstream_claude/skills/`（motion-doctrine 等内部规范，写动画前先读 motion-doctrine）。
- 想让所有项目都能用 `/hyperframes`、`/faceless-explainer` 等命令，可以装成 Claude Code 的用户级插件（`claude plugin marketplace add heygen-com/hyperframes && claude plugin install hyperframes@hyperframes`）。这会修改全局配置，**必须先征得用户同意**。
- **没有 `@font-face` 的字体，渲染时会去 Google Fonts 取。** `render`、`snapshot`、`check` 每次运行都请求，连不上就挂住（render 停在 5% 的 "Compiling composition"）。lint 拦不住其中两种：它别名表里的名字（Arial、Helvetica Neue、Menlo 等）没有声明也算通过，渲染时被换成 Inter、JetBrains Mono 去取；以 `sans-serif` 这类通用族名开头的栈，前面会被补上 Inter。所以本机字体也写 `@font-face`、`src` 用 `local()`，栈里排第一的写声明过的字体，照 `bin/vh hf-init` 搭的脚手架做。渲染日志里出现 `[Compiler] Injected deterministic @font-face rules`，就是还有字体没声明。国内网络下的做法见 wiki 的[国内网络](https://github.com/ZLHad/OpenVideoHarness/wiki/%E5%9B%BD%E5%86%85%E7%BD%91%E7%BB%9C)。
- **字体里缺的字**：字体在、字不在时，浏览器换一个字体画这个字，哪个字体都没有就画成空的缺字字形（苹方的是空白），lint 和渲染都不报。`bin/vh fonts check <项目>` 用 HyperFrames 自己的运行时抽帧，查每个 clip 的 DOM 字和 canvas 字实际由哪个字体画（2026-10-12 在一台 Mac 上：showcase 00 的 "LF Mono" 里有三个汉字落到了苹方，showcase 02 的"Δ"落到了 Arial）。HyperFrames 渲染时把 Google 字体换成它缓存的一份，这个检查看的是页面声明的字体，所以 `local()` 和项目里的字体文件最准。
- **中文字体**：lint 会拒绝没有 `@font-face` 或 Google Fonts `<link>` 的字体。Noto Sans SC 不在它的自动字体列表里（列表里只有 Noto Sans JP），要显式用 `<link>` 引入，或者把字体文件放进 `assets/` 并写 `@font-face`。
- **0.8.82 实测的上游问题**：
  - 两条 lint 规则互相矛盾：`gsap_repeated_fromto_without_baseline` 建议加 `tl.set(…,0)`，加了又会触发 `gsap_timeline_set_initial_hide`。解法是在时间线外用 `gsap.set()` 设初始状态，同时给 tween 加 `immediateRender:false`。
  - 某次渲染后，本机被切换到较慢的截帧路径，之后每次渲染的耗时约为原来的 3 倍。这是本机设置，不跟着项目走；用 `HF_DE_PARALLEL_ROUTER=true` 可以恢复。
  - **浏览器 GPU 开着时，长片偶尔出单帧坏帧。** drawElement 截帧自检失败、退回多 worker 截屏以后（日志：`drawElement self-verification failed; re-rendering via screenshot`），一支 160 s 的 canvas 片子渲 4 次有 1 次出了坏帧：6 处各一帧、一处连着 3 帧，闪进别的场景，或者字被画成乱码。同一时刻的 snapshot 是干净的，抽 snapshot 查不出；`bin/vh check` 的孤立帧扫描会列出其中的单帧坏帧（连着几帧的看不到）。修法（还在验证，之后 7 次渲染都干净）：`npx hyperframes render … --no-browser-gpu --experimental-fast-capture=false`，软件渲染。扫描的做法和它漏掉的情况见 `playbook/02-verification.md` 的"静默失败"。
- **外部 `<script src>` 的两个坑**：一支 canvas 片子把场景代码放在 `assets/js/*.js` 里用 `<script src>` 引入，渲出来整片空白，把这些文件依次内联进 `index.html` 以后正常（原因没细查）；另一支的外部脚本执行时 `<canvas>` 元素还不存在，脚本顶层的 `getElementById` 拿到 null，snapshot 全黑。稳妥做法：场景代码内联进 `index.html`（文件多就写个小 build 脚本拼起来），DOM 引用放到第一次画的时候再取。另外，lint 只认内联脚本里的 `window.__timelines` 登记（否则报 `missing_timeline_registry`），登记那几行写在内联 `<script>` 里。
- 空格会被吞：sub-composition 模板里的连续空格和词间空格、JS 设置的文本前导空格，都可能被 HTML 合并掉。需要保留时用 `&nbsp;` 或 `white-space: pre`。
- **等宽字体的坑**：`ui-monospace, monospace` 能通过字体 lint，快照里看起来也是等宽，但 `hyperframes render` 渲染出来却是比例字体（showcase 00 在第一版全片都中了招）。要用 `@font-face` 显式声明，例如 `@font-face{font-family:"LF Mono";src:local("SF Mono"),local("Menlo")}`。**判断字体要看 mp4 渲染出的帧，不要看快照。**`check --snapshots` 只保存对比度检查用的 PNG，不能替代 `snapshot --at`。
- `snapshot` 在 tween 刚开始的那一刻，可能和最终渲染出的帧不一致。关键帧以渲染出的 mp4 为准，逐帧 strip 的做法见 `playbook/02-verification.md`。
- 完整样板：`showcase/02-short-leo-doppler/`（竖屏科普，单个 `index.html`）。
- **HyperFrames 加 Three.js（3D 世界、一镜到底）的坑**，多数来自介绍片的制作：
  - 每一帧都用 `renderAt(t)` 从 t 算出摄像机和所有物体的状态。摄像机路线用按 t 参数化的样条，不用 Three.js 的动画时钟。关卡处可以用 stop 关键帧停站，但要叠一层低幅的手持漂移，镜头不要完全停死（原因见 `playbook/08-vfx-and-motion-sources.md` 的"一镜到底"一节）。
  - `VideoTexture` 必须**每帧**设置 `texture.needsUpdate = true`，否则渲染出的屏幕是全黑的。视频按 t 去 seek，而且要等 seek 完成。
  - `__hf.buildReady` 要在普通 `<script>`（不是 module）里**同步注册**，否则每个并行 worker 的开头都会出现空帧。
  - 项目根目录只能有一个 composition。局部测试文件放在 `out/`，要跑时临时拷回来。
  - `snapshot` 看不到视频纹理（屏幕是暗的），检查必须看渲染出的 mp4 帧。
  - **把 3D 点投影到屏幕前先 `camera.updateMatrixWorld()`**：同一帧里刚 `lookAt` 过，矩阵还没更新，钉在 3D 点上的标注会错位。
  - **`EdgesGeometry(geo, 阈值角)` 只画相邻面夹角大于阈值的边**：20 段的圆柱相邻面差 18°，阈值设 20° 就一条侧边线都画不出来。线框画法的圆柱少分几段（12 段是 30°），或者把阈值调低。
  - **物体的位置在建的时候就设好**：只在每帧的动画函数里设 `position` 的话，不参与动画的零件永远停在原点（盒子以中心为原点，会半截埋进地面）。
  - **玻璃器皿上一道从上到下的亮条**：用 `RoomEnvironment` 做环境贴图时，它的反射会在每个玻璃件上留下一道亮竖条，一排玻璃件就是一排亮条；`LatheGeometry` 转满一圈的接缝默认也正对 +z 方向的镜头，一起转到背面（`phiStart` 设 `Math.PI`）。玻璃所在的场景不设 `scene.environment`（同一场景里别的材质也跟着没了环境反射，用灯光补），玻璃感改由一层菲涅尔边光壳来给：同一个几何体放大约 1.004 倍，`ShaderMaterial` 加法混合、不写深度，亮度取 `pow(1 − |N·V|, 2.6)`，只有边缘微微发亮。
  - **渲染时不要依赖在线 CDN。** importmap 指向 CDN 时，只要页面加载那一刻断网，渲染就会静默挂住：日志 0 字节，也不报错。介绍片的第一次 final 渲染就卡在这里。把 three.js 装进项目，importmap 指向 `node_modules`，snapshot 和 render 都能读到这些文件：

    ```bash
    npm i -D --save-exact three@0.181.2      # 写精确版本，换版本时重新比对无损帧
    ```
    ```html
    <script type="importmap">{"imports":{"three":"./node_modules/three/build/three.module.js","three/addons/":"./node_modules/three/examples/jsm/"}}</script>
    ```

    渲染命令外面再包一层看门狗：超时就杀掉进程，核对退出码和帧数，再抽几帧查 YAVG，确认 3D 层确实画出来了。

    GSAP 也一样。HyperFrames 的脚手架默认从 CDN 加载 `gsap@3.14.2`；`bin/vh hf-init` 现在会自动把它装进项目，并把 `<script src>` 改成 `node_modules/gsap/dist/gsap.min.js`，如果还有别的 CDN 引用，会打出警告。showcase 00 和 02 已经照此改过。剩下的网络依赖是 Google Fonts 的 `<link>`（showcase 02 的 Noto Sans SC、ClaudeAnimationBase 的 `studio.html`）：离线时要么先用本机字体（见 `styles/_swatch/README.md` 的字体表），要么把字体文件放进项目并在 NOTES 里记下许可；国内网络下的具体做法（系统字体、字体文件、从 npm 镜像装 Fontsource）见 wiki 的[国内网络](https://github.com/ZLHad/OpenVideoHarness/wiki/%E5%9B%BD%E5%86%85%E7%BD%91%E7%BB%9C)。
  - **`renderAt` 里抛异常时，画面会停在上一帧，不报错。** 介绍片有一版 draft 读了一个还没声明的 `const`（TDZ），36–48 s 整整 12 s 都停在 t=0 的画面。画面角落常驻一个 t 读数的 HUD，抽一帧就能看出停帧；成片级的检测方法见 `playbook/02-verification.md`。
  - **Hermite 路径在"快甩、慢推"的站点会冲过头。** 关键帧的切线默认由前后两个邻居估出来，甩镜到站时，站点的切线带着甩镜的速度，镜头会冲进字里（介绍片的架构站把节点标签推出了画面）。给关键帧加一个切线模式：到站的关键帧用 `tm: "f"`，切线只取后面那段慢推；离站的关键帧用 `tm: "b"`，只取前面那段慢推。两站之间的甩镜就成了一条干净的 S 曲线。
  - **世界里的节点标签按屏幕像素定字号**，不要按画面宽度的比例缩放，否则长标签的中文会掉到 20 多 px。介绍片的 `pin()` 每帧把节点投影到屏幕，用 `2·d·tan(fov/2) / 1080` 算出这个深度上 1 px 对应的世界长度（d 是节点沿视线方向的深度，fov 是竖直视场角），据此缩放面向镜头的标签平面，字号就固定了（英文 54–56 px，中文 ≥ 46 px）。另外两件事：标签框夹在安全框里；节点出画、或者标签被推离节点太远时就淡出，否则镜头离开后，标签会在画面边上堆成一摞。
  - **变拍只改一个 `bar(k)`。** 画面、事件表、字幕、HUD 都从同一个 `bar(k, beat)` 取时间，不手写秒数。介绍片把第 11 小节改成 6/4 时，画面这边只在 `bar()` 里给第 12 小节以后统一加 2 拍，HUD 改用按真实拍号换算的 `barBeat()`；作曲那边在 `score.json` 写 `"meters": {"11": 6}`（`bin/vh music` 现在也支持这个字段，beat map 会多出 `bars`）。其他秒数一个都不用手改。

## Remotion（React），未安装

```bash
cd projects && npx create-video@latest     # 选模板；做字幕短视频可选 TikTok 模板
cd <slug> && npx skills add remotion-dev/skills
npx remotion studio                        # 预览
```

- 许可：个人和 3 人以内的公司免费，超过这个规模需要购买授权。
- 官方 skills 已拉到本地：`references/repos/remotion-skills/skills/`。

## ManimGX（Python，uv 按项目安装）

完整指南：[`manimgx.md`](manimgx.md)（什么时候用、全部旗标、限制、GPU/T4×2、什么时候回退 CE、Kaggle 排障）；速度实测与优化研究（缓存、Vulkan 队列、显存、异步、多进程）：[`manimgx-advanced.md`](manimgx-advanced.md)。三个配套工具：`tools/manimgx_probe_gpu.sh`（Kaggle 第一格跑，确认 T4 真的在渲）、`tools/manimgx_bench.sh`（本机测速出表）、`tools/manimgx_render.sh`（场景没改就跳过重渲）。

Manim CE 已换下，改用 ManimGX（2026-10-18）：同一套 Manim CE Python API，Rust/wgpu GPU 核心逐帧绘制，Typst 排版公式，自带编码出 MP4。不装 LaTeX、ffmpeg、cairo、pango（都不需要）；无 GPU 时 Linux wheel 自带 lavapipe 在 CPU 上画。实测（showcase/03-math-fourier 已迁移）：25 s 成片，1080p30 在 2 核 CPU 上 40 s 渲完，草稿 480p15 约 11 s；`manimgx inspect` 自带 2D 布局检查（文字重叠/出画面/小字，有问题 exit 1）。

```bash
cd projects/<date>-<slug>
uv init --bare --python 3.14 && uv add manimgx   # 实测：manimgx 0.1.1 / Python 3.14.8；ManimGX 要求 >=3.13，uv 会自己下载
uv run manimgx render -r 854x480 --fps 15 scene.py MyScene    # 草稿
uv run manimgx render -r 1920x1080 --fps 30 scene.py MyScene   # 成片 1080p30（不带 --fps 默认 60）
uv run manimgx inspect scene.py MyScene                        # 分镜/storyboard + 布局检查，不渲染视频
```

- 用 `--bare`：普通的 `uv init` 会在项目里多生成 `.git`、`main.py`、`README.md`、`.python-version`。
- **4K**：`-r 3840x2160 --fps 30`，画面比例和构图不变。
- **竖屏**：`-r 1080x1920`（或场景里 `m.config.pixel_width, m.config.pixel_height = 1080, 1920`）。竖屏的 frame 自动变成 8 宽 × ~14.2 高（短边恒为 8 个单位），CE 那套 `manim.cfg` 重算 `frame_width` 的麻烦不存在了；中间 8×8 的方块横竖屏都在，按竖屏重新排版即可。
- **配音/按词触发**：引擎内置（不再装 manim-voiceover）：`self.say("…[x squared]…", anim1, anim2)` 把动画对到方括号里的词上；`self.add_sound("click.wav")` 直接加声音。本仓库自己的音频先行管线（`tools/build_audio.sh`、timeline、foley）照旧，两边不冲突。
- **公式**：`MathTex`/`Tex` 用内置 mitex 转 Typst 排版（New Computer Modern 字体，和 CE 的 CMU 同源），不装 LaTeX；宏包和 `\def` 不支持，报错会带 TypstError。
- **GPU（Kaggle T4×2 等 Linux 机器）**：走 Vulkan，每个进程选一个高性能 adapter；看不到 GPU 时自动落到自带 lavapipe（CPU），不用另装任何东西。Kaggle 上跑：先 `curl -LsSf https://astral.sh/uv/install.sh | sh` 装 uv；如需真正吃到 T4，`sudo apt-get install -y libvulkan1`，必要时 `export VK_ICD_FILELIST=/usr/share/vulkan/icd.d/nvidia_icd.json`；`vulkaninfo --summary` 里能看到 T4 即生效。两块 T4 可以同时跑两个渲染进程（比如草稿和成片、或两个项目各一个）。
- 输出写在场景文件旁边（`-o` 可指定路径）；颜色为 limited-range 且带标签（matrix smpte170m / transfer sRGB / primaries bt709）。配乐混音那一步本来就要重编码，交付重编码到 BT.709 的规则不变（playbook/10）。
- 锚点网格和包围盒审计有现成实现：`showcase/03-math-fourier/scenes/style.py`（已迁到 ManimGX），可以复制到自己的项目里用。
- 写代码前先读 `references/repos/3brown1blue/src/three_b1b/skill/SKILL.md` 开头的 Gotchas（CE 的坑在 GX 里大多还在，同一个 API）。
- 【迁移注意】（CE 代码搬过来时）：`from manim import *` → `from manimgx import *`（或 `import manimgx as m`）；`rate_functions.smooth` 这类模块路径没了，函数都在包上（`m.smooth`、`m.ease_in_out_sine`）；`manimgx` 导出一个 `Path` mobject 类，`pathlib.Path` 要起别名；`import numpy as np` 要显式写；质量旗标 `-ql/-qh` → `-r 宽x高 --fps`。CE 与 ManimGL 不能混用的老提醒作废（GX 实现的就是 CE 的 API）。

## Blender，按需使用（部分验证）

完整指南：[`blender.md`](blender.md)。**部分验证：维护者的 Mac 装了 Blender 5.2.2，风格样片 `tabletop-miniature` 用它渲染（`styles/_swatch/README.md` 的"Blender 场景"）；指南里项目用的两段式命令有几条还没跑过。渲染时间先渲 3–5 帧校准。**

- 安装：`brew install --cask blender`，也可以从官网下载。指南钉在 5.2 LTS（5.0 起只支持 Apple Silicon，Python API 有破坏性改动）。
- 渲染用脚本方式，保证结果可复现，分两段：`blender -b --factory-startup --python build.py -- …` 生成 `scene.blend`，再 `blender -b scene.blend … -a` 渲 PNG 序列。同时固定随机种子，并烘焙好模拟缓存。
- 能跑的样板：`styles/_swatch/blender_render.py`（逐帧 `apply(t)` 再渲，正式版走 CPU 求逐像素相同）、`blender_prep.py`（渲染前的静态检查和字体解析）和 `render.sh` 里的 `bl_run`（`env -i` 加 `sandbox-exec`）。调用 bpy 的文件按 GPL-3.0-or-later 分发（见指南的"许可证"）。
- 探索阶段要用 MCP，就用 [`blender-mcp-ultra`](blender-mcp-ultra.md)（carlosh7/blender-mcp，MIT，248 个工具）：强制 token、AST 拦截在网关和 addon 各跑一次、限速——这些都实测过；它也是三个 MCP 里唯一官方支持 headless 的（CI 就是这么跑的）。**默认仍不用**：要用先问用户，放在虚拟机或单独的 macOS 用户下。官方 MCP 和社区的 `ahujasid/mcp-for-blender` 则会直接执行 LLM 生成的 Python，没有任何防护，不推荐。没有沙箱，就不要让 LLM 生成的 bpy 代码经过任何 MCP 执行。管线里跑 agent 写的脚本，加静态检查、`sandbox-exec` 和 `env -i`（见指南的"安全"一节）。配套工具：`tools/blender_mcp_setup.sh`（装网关、数工具；`--headless` 再起一个一次性 `blender -b` 服务器，把 token 认证、AST 拦截、建对象、Cycles 渲 PNG 全部证一遍）。

## 生成式视频（fal 等），按需使用

见 `playbook/05-hybrid-genvideo.md`。API key 从环境变量读取（例如 `FAL_KEY`），不要写进文件。花钱前先在 BRIEF 里和用户确认预算。
