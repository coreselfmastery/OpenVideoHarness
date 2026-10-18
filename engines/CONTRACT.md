# 页面合约：`window.film`

本仓库里凡是"用网页画画面"的引擎，都按这一页对外交代自己：给出画第 t 秒的函数、片长和就绪信号。`bin/vh` 里取帧、查字、以后的出片和导出，只认这个合约，不认引擎。新引擎进来，写清楚它怎么满足这一页就行。

合约的核心字段和 [OpenFilm](https://github.com/openfilm/openfilm) 协议 0.1 的页面同名同义（它的 `packages/openfilm/SPEC.md` 第 2–4 节），所以按这一页写的片子，也能在 OpenFilm 的 Studio 里打开（试验，见 `docs/proposals/01-client-and-workflow.md`）。下面"扩展"一节的字段是本仓库加的，别的宿主会忽略它们。

ManimGX、Blender 和生成式视频直接出视频文件，不是页面，不在这一页管的范围里；放进时间线时，它们就是视频片段。

## 页面给出什么

```js
window.film = {
  frame(t) { /* 画出第 t 秒的完整画面 */ },   // 必填；可以返回 Promise，resolve 时画面才算画完
  duration: 24.8,                             // 片长（秒）
  ready: loadEverything(),                    // Promise，或返回 Promise 的函数：字体、图片、数据都载好了
  width: 1920, height: 1080,                  // 可选：画面尺寸（CSS 像素）
};
```

| 字段 | 必填 | 意思 |
|---|---|---|
| `frame(t)` | 是 | 画出 t 秒（`0 ≤ t < duration`）的完整画面，连同它自己管的 DOM（比如字幕）。硬规则 1：同一个 t 永远画出同一帧，不管之前画过什么、按什么顺序要帧。浏览器重画同一帧不总是逐字节相同（图层会重新光栅化），所以比较时留一点容差，同硬规则 1 的 45 dB；OpenFilm 规范第 3 节也这么说。 |
| `duration` | 是 | 片长，秒。OpenFilm 允许不写（当作静帧）；本仓库的片子都有长度，所以必填。 |
| `ready` | 否 | 宿主等它 resolve 之后才调 `frame`；是函数时按方法调（`film.ready()`）。网页字体要逐个 `document.fonts.load('900 60px X')`，不能只等 `document.fonts.ready`。 |
| `width`、`height` | 否 | 写了就以它为准。不写时，宿主按 HyperFrames 根元素的 `data-width` × `data-height`，或者页面的 `<meta name="viewport" content="width=…, height=…">`，再不然 1920 × 1080（`bin/vh frames --size` 可以另给）。出 4K 不改这两个数，而是把设备像素比设成 2：画布要按 `innerWidth × devicePixelRatio` 分配像素，固定尺寸的画布只会被放大。 |

页面应当在 `load` 事件之前设好 `window.film`；宿主在 `load` 之后最多等 10 秒。

### 扩展（本仓库的工具读，可选）

| 字段 | 格式 | 谁读 |
|---|---|---|
| `texts` | 数组，或 `ready` 之后调用、返回数组的函数：`[{text, start, end, read?}]`，同 readcheck 的 `texts.json` | `bin/vh textcheck`、`bin/vh readcheck` |
| `events` | 画面事件：`[{t, kind, x?}]`，时刻、事件的种类（贴纸落下、盖章、翻页这类）、在画面上的横坐标（给声像用）。配什么声是另一步：`bin/vh sfx place` 读的 `events.json` 里写的是声音的名字 | 配音效、`bin/vh qa` 的 cue check（以后） |
| `chapters` | `[{t, title}]` | 进度条、发布文案的章节表（以后） |
| `cues` | 时间挂在旁白字词上时，每个挂点的解析结果：`[{id, ref, t}]` | `bin/vh cues`：列出来；`--save` 存下，换了配音以后再跑，说出哪些挪了 |
| `covers` | 封面：`[{id, t, title?}]`，取哪一帧（`t`，挂在字上的片子由 cue 算出）。页面另有方法 `cover(id)` 时，宿主调它画这张封面（自己的机位微调、标题），没有就画 `frame(t)` | `bin/vh frames --covers`：每张一个 PNG，在 `out/covers/` |
| `timeline` | 这些 cue 挂在哪份旁白时间轴上：相对页面的路径（`audio/timeline.zh.json`），没有旁白时是 `null` | `bin/vh cues` 记下它的 sha256，认出换过的配音 |
| `ui(t)` | 方法：t 秒时常驻界面（进度条、署名、字幕）的字和线在哪：`[{name, box: [x0, y0, x1, y1]}]`，画面的 CSS px；只框界面自己的字和线，垫在下面的底板、渐变不算。写了它，`frame(t, { layer: "scene" })` 就要画出不带界面的这一帧（不认这个参数的页面照常画整帧，宿主会看出来、说一声） | `bin/vh textcheck`：两种画法各画一遍，场景自己在这些框里画了线、边、字的，报出来（警告） |

这几项都是数据，在 `ready` 里算好：OpenFilm 的说法是"跟着声音走的时间是数据，不是接口"。`cover(id)` 和 `ui(t)` 是方法，同样是 t 的纯函数。

### 以前的 `window.__vh`

`bin/vh textcheck` 原来认的是 `window.__vh = { draw, texts, ready }`，现在仍然认。新写的页面写 `window.film`，`frame` 就是原来的 `draw`。两个都写了，以 `window.film` 为准。

## 宿主做什么

本仓库的宿主是 `tools/film/host.mjs`，`bin/vh frames`（取帧）、`bin/vh render`（出片）、`bin/vh determinism`（查硬规则 1）、`bin/vh cues`（列 cue）都用它，`bin/vh readcheck` 读 canvas-film 项目的字时也用它：

1. 从页面所在的文件夹起一个只在本机 `127.0.0.1` 的服务来打开页面（不用 `file://`），所以页面能 `fetch` 这个文件夹里的文件；项目根目录的页面，就是整个项目。时区固定为 UTC，所以显示本地时间的页面在哪台机器上都画得一样。
2. 页面的脚本运行之前，先设好 `window.filmHost = { version: '0.1', name: 'ovh' }`。看到它，页面就不能自己往前走：不开自转的动画循环，不自动播放，不开开发界面。
3. **时钟兜底**：从画第一帧起，`performance.now()`、`requestAnimationFrame` 的时间戳、`Date`、页面留着在跑的 CSS 和 Web Animations 都钉在 t 上，`Math.random` 每帧按 t 重新播种。硬规则 1 照旧是"不许用这些"；兜底的作用是写错了也不出错，宿主还会报出哪些帧调了 `Math.random`（`Date` 和 `performance.now` 常被库自己读，比如 HyperFrames 的运行时，所以不报）。加载阶段（`ready` 之前）照常走真实时间。思路和 OpenFilm 的 `FILM_CLOCK` 一样，代码是本仓库自己写的（`tools/film/clock.js`）。
4. 等 `ready`，再调 `frame(t)`，等它 resolve，然后截取视口（无损 PNG）。`ready` 包括字体：字体文件都载好了。字形不归页面自己查（页面问不出一个字是哪个字体画的），由宿主查，见第 6 条。
5. 页面抛错、请求失败，都报出来，不当作成功：加载时的、画某一帧时的、最后一帧之后才冒出来的（比如一帧留下的定时器抛的错）都算。

6. **字形**：页面要的字体里缺某个字时，浏览器不报错，换一个字体画它，哪个字体都没有就画成空的"缺字"字形。`bin/vh fonts check` 在页面脚本之前挂上 canvas 的 `fillText` / `strokeText`，按时间抽帧（再加上 `texts` 里每段字的中间），记下画了哪些字、用的什么字体，DOM 里的字按算出的样式记；然后问浏览器每个字实际由哪个平台字体画（DevTools 的 `CSS.getPlatformFontsForNode`），不是字体栈里第一个字体（`@font-face` 的 `local()`；`url()` 或 FontFace API 加的字体，按这个字体族单独画出来是哪个字体认；或者装在本机的那个字体族）画的算换了字体；画出来和一个哪个字体都没有的字（U+10FFFD）一模一样的，算缺字。有一个就退出码 1。落到同一个栈里后面写明的字体的（`"Helvetica Neue", "PingFang SC"` 里的中文），是栈本来的意思，只说一声，`--strict` 才算失败。`bin/vh render` 每个 worker 出完自己那段也查一遍画过的字，有问题打出来，不判失败。工具在 `tools/film/glyphs.mjs`、`fonts.mjs`。

还没做的：页面用 `<video>` 取画面时，OpenFilm 的宿主会把 seek 落到那一帧里面、等新的一帧上屏再截图，这个宿主还没有；它的服务也不答 HTTP Range 请求。

## 各引擎怎么满足

| 引擎 | 怎么满足 | 备注 |
|---|---|---|
| canvas-film（`engines/canvas-film/`，`bin/vh new … --engine canvas-film`） | `src/90-main.js` 写 `window.film`。`ready` 载入字体（本机缺的字体直接报名字；缺字形由 `bin/vh fonts check` 查）、图片和旁白时间轴，把全部 cue 换成秒（有解析不了的就让 `ready` 失败，一次列出前 12 处），排好字幕，再把每个镜头抽 5 个时刻画一遍，收集 `texts`、`events`；`chapters`、`cues` 也在这时算好。`frame(t)` 每次先 `reset()` 画布再画；`covers` 和 `cover(id)` 来自 `src/50-shots.js` 的 `COVERS`；`ui(t)` 给出章节条和字幕的框，`frame(t, { layer: "scene" })` 不画这两样 | 成片走 `bin/vh render`（4K 加 `--dpr 2`），见 `engines/canvas-film/README.md` |
| ClaudeAnimationBase（手绘） | `src/core.js` 自己写 `window.film`：`frame(t)` 就是 `T = t; await redraw(); composite(t)`，就绪看 `window.ready`；有 `filmHost` 时 `studio.html` 只露出画面那块 canvas，不开开发界面 | 成片照旧走 `node render.mjs`。画布固定 1920 × 1080，设备像素比设成 2 也只是放大 |
| HyperFrames | 合成不用改。宿主照 HyperFrames 自己的做法，在 `</head>` 前插入项目里的运行时（`node_modules/hyperframes/dist/hyperframe.runtime.iife.js`，项目里没有就用 `styles/_swatch` 装的那份），再把运行时的 `window.__player.renderSeek(t)` 包成 `window.film` | 成片照旧走 `npx hyperframes render`。HyperFrames 渲染时还做了别的事（虚拟时间、GSAP 缓冲，把 Google 字体换成它本地缓存的一份），所以宿主取的帧和它渲染的帧只保证接近，不保证逐字节相同（见下面的实测）。它的 seek 看上去会把 t 对齐到合成自己的帧率（默认 30），两帧之间的时刻画的是较近的那一帧 |
| 页面自己写了 `window.film` 或 `window.__vh` 的合成 | 用页面自己的 | canvas 合成大多已经写了 `window.__vh` |

## 实测（2026-10-11，M3 Max）

| 片子 | 和谁比 | 结果 |
|---|---|---|
| showcase 00（HyperFrames，嵌套合成） | `npx hyperframes snapshot` 同样的时刻 | 1、5、10、14 s 单独画时都逐像素相同。14 s 接在 1、5、10 s 后面画时，有 0.012% 的像素差 1 级（87.5 dB）：DOM 页面重画同一帧不总是逐字节相同，比较要留容差 |
| showcase 02（HyperFrames，DOM 和 GSAP） | 同上 | 图形逐像素相同；文字边缘不同（31–33 dB），因为 HyperFrames 把 Google 字体换成了它本地缓存的一份 |
| showcase 01（手绘引擎） | `node render.mjs --stills` 同样的时刻 | 用同一个浏览器（系统 Chrome 154）时逐像素相同；用 HyperFrames 带的 chrome-headless-shell 150 时 51–54 dB，差别来自浏览器版本 |
| 本仓库的测试页（`tools/film/fixture/`） | 自己：先画别的帧再画，和单独画 | 逐字节相同，`Math.random` 被钉在 t 上并报了出来；关掉时钟兜底（`--real-clock`）就不同 |
