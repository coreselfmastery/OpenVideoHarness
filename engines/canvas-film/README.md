# canvas-film：旁白驱动的 canvas 引擎

一页 `film.html` 加几份 `src/*.js`，在一块 2D canvas 上画出每一帧。镜头、字幕、章节条的时间都挂在旁白的字上：重配一句、改一个词、整片插进停顿，画面跟着走，不用手改秒数。它按页面合约（仓库里的 `engines/CONTRACT.md`）写了 `window.film`，`bin/vh frames` 取帧、`bin/vh textcheck` 查字都直接能用。这份说明在项目里有一份副本，叫 `ENGINE_README.md`。

## 什么时候用

- 旁白撑着的横屏长片：几分钟到十几分钟的科普、人物、讲解，几十上百个镜头，镜头跟着旁白的字切。
- 画面是代码画的 2D：纸面、卡片、图表、示意图、照片和截图。Three.js 底层以后再收进来，现在没有。
- 不合适的：DOM 排版和 GSAP 动效为主的短片（HyperFrames）、手绘角色（ClaudeAnimationBase）、数学推导（ManimGX）。

## 建项目

```bash
bin/vh new <type> <slug> --engine canvas-film      # 任何类型都行；画幅固定 16:9（1920×1080），--res 4k 照常
bin/vh frames projects/<date>-<slug> --at 1,5,9    # 模板自带一支 23 秒的示例片，建好就能取帧
```

| 文件 | 是什么 |
|---|---|
| `film.html` | 页面：`@font-face`（只用 `local()` 本机字体，不下载）、一块 canvas、按顺序载入 `src/` 的脚本。不用构建 |
| `src/00-core.js` | 设定 `FILM` 的默认值、时间（旁白时间轴、cue、镜头、章节、字幕）、录制器 |
| `src/10-draw.js` | 画字（字号下限在这一层）、量字、折行、形状、图片、缓存的纹理 |
| `src/15-fx.js` | 颗粒、暗角、整幅压暗 |
| `src/20-ui.js` | `label`、`drop`、`stamp`，章节进度条，字幕 |
| `src/30-transitions.js` | 转场 |
| `src/50-shots.js` | **这支片子**：`FILM` 设定、章节、镜头。其余文件是引擎，一般不用改 |
| `src/90-main.js` | 画第 t 秒，`ready` 时载入和检查，`window.film` |
| `audio/timeline.zh.json` | 示例旁白的时间轴（合成的，不是配音）。真片子跑 `bin/vh tts` 覆盖它 |
| `assets/` | 图片等素材，在 `FILM.images` 里登记 |

示例片的 `src/50-shots.js` 和 `audio/timeline.zh.json` 是成对的，开工时两样一起换掉：写 `audio/script.txt`（每行 `@id 一句旁白`），跑 `bin/vh tts`，再照着新的 id 写镜头。

设定都在 `src/00-core.js` 开头的 `FILM` 里，每项一行注释（语言、旁白前后留多久、字号下限、字幕、颗粒、片头片尾的淡入淡出、界面颜色、图片）；这支片子要改的，在 `src/50-shots.js` 里用 `Object.assign(FILM, {…})` 改。

## 时间：挂在旁白的字上

`bin/vh tts` 写出的 `audio/timeline.<lang>.json` 里，每句有 id、起止时间，对齐过的还有每个字的时间（`--align gemini`）。时间轴上的秒数就是片子里的秒数。旁白要晚一点开口，就在配音时加 `bin/vh tts … --lead <秒>`：人声和时间轴一起推后，画面不用另外挪。只有手上的时间轴从 0 开始、又想让画面先走一会儿，才设 `FILM.lead`：引擎把时间轴整体后移这么多秒，混音前人声也要垫上同样长的静音（`tools/audio/README.md` 的"手动的响度和合成命令"）。片长是 `FILM.lead + 时间轴长度 + FILM.tail`。

时间写成 cue：

| 写法 | 意思 |
|---|---|
| `"@b2"` | b2 这句开口 |
| `"@b2:跟着走"` | b2 里第一次说到"跟着走"的那一刻 |
| `"@b2>"` | b2 这句说完 |
| `"@b2:跟着走-0.3"`、`"@b2>+0.5"` | 再提前或推后几秒 |
| `3.2` | 就是第 3.2 秒 |

- 找词时去掉空格、标点和符号再比，所以"“第一”"写成"第一"就行。同一句里出现两次的词取第一次；要后面那次，多写几个字把它和前一次分开。
- 字的时间按最长公共子序列对到对齐结果上：识别把某个字听成别的，就跳过它，用前后对上的字插值。没有逐字时间的句子，按字数在整句里均分。
- id 只用字母、数字和下划线（`@intro-1` 会被读成 id `intro` 加 `-1` 秒）。
- 词本身以"-数字"结尾（GPT-4、COVID-19）时，`"@g1:GPT-4"` 有两种读法：这个词，或者"GPT"之前 4 秒。这句里正好有"GPT-4"时，`ready` 会停下来让你写清楚：`"@g1:GPT-4+0"` 是这个词，`"@g1:GPT-4.0"` 是提前 4 秒。
- 镜头的 `at`，以及 `o` 里任何一层的 cue 字符串，都在 `ready` 时换成秒。**解析不了就立刻停**：`ready` 失败，`bin/vh frames` 和 `bin/vh textcheck` 退出码 2，一次列出出问题的地方（前 12 处，其余给个数）：哪个镜头、哪个字段、cue 原文、这一句现在的文字、句子里最像的几个词。时间轴里缺 id、起止时间的行，转场的长度写错（`["turn", -1]`，或者给 `cut` 写了长度），也在这里一起报。不会等到超时。

  ```
  shot S02 (o.two), cue "@a2:第三张": line a2 has no "第三张"; it now reads "说到第一张，卡片落下；说到第二张，第二张跟上。"; nearest: "第一张", "第二张", "到第一张"
  ```

- `draw` 里也可以直接调 `cueT("@b2:跟着走")`，但那样要到画到这一帧才检查。要在 `ready` 就查到，把它写进 `o`。
- 不配旁白的片子：`FILM.timeline = false`，再给 `FILM.duration`，时间都写秒。

## 镜头、章节、转场

```js
const SHOTS = [
  { id: "S02", at: "@a2", tin: "settle",
    see: "两张卡片：说到“第一张”，第一张落下；说到“第二张”，第二张落下",
    o: { one: "@a2:第一张", two: "@a2:第二张" },
    draw(t, s) { … card(t, s.o.one, 660, 580, "1", "第一张"); … } },
];
const CHAPTERS = [{ at: 0, title: "挂在字上" }, { at: "@b1", title: "翻一页" }];
```

- 一个镜头从它的 `at` 开始，到下一个镜头的 `at` 结束；第一个镜头从 0 开始。镜头顺序不对、短于 0.2 s、短于自己的转场，`ready` 都会报出来。
- `draw(t, s)`：`t` 是整片的秒数，`s` = `{ id, t0, t1, lt, u, o, din, dout }`（镜头起止、镜内秒数、镜内进度 0–1、解析好的 `o`、进出转场的长度）。
- 其他字段：`see` 写观众要看懂什么（分镜和审阅用）；`cam: [z0, z1, cx, cy]` 让镜头在整镜里从 z0 缓推到 z1，停着的画面也不会冻住；`light: true` 表示浅色画面，字幕改垫一块深色底；`nocap: ["a1"]` 表示画面上已经用大字写了这句，整句不出字幕。
- 转场 `tin` 写名字，或者 `["turn", 1.2]` 改时长。新镜头从自己的 cue 开始计时，旧镜头在下面接着走到转场结束；两边每帧都整幅重画（需要时画进离屏画布），不留跨帧的状态。

  | 名字 | 默认时长 | 样子 |
  |---|---|---|
  | `cut` | 0 | 硬切（默认） |
  | `settle` | 0.5 s | 硬切，新画面从 1.06 倍收回原大，没有叠化 |
  | `dim` | 1.0 s | 暗下去，再从暗处亮起新画面 |
  | `fold` | 0.85 s | 旧画面像一块板，绕左边转开，露出下面的新画面 |
  | `turn` | 1.0 s | 翻书页：旧画面的右半页翻过来，背面是新画面的左半页 |
  | `blot` | 1.2 s | 墨从几处晕开，软边，晕到的地方露出新画面 |

- 章节进度条（顶上）：每章一格，宽度按章名；当前一章随进度填满，章名一直显示；每章开头约 3 s 显示全部章名（章名太多、一行放不下时，只显示当前一章）。显示的时段由 `FILM.bar = { from, to }` 定，默认从第一章到片尾。

## 字

- 画字一律用 `txt(s, x, y, o)`。字号在最底层兜住：`font()` 不会给出小于 `FILM.minText`（默认 44 px，按 BRIEF 的"在哪看"改，见 `playbook/03` §4）的字号，`measure()` 用的是同一个字号，排版不会和画出来的对不上。字幕的字号另有一档，`minText` 管不到：`FILM.caption.size`（默认 52；`playbook/03` §4 的字幕下限 desktop 48、feed 115），改"在哪看"时两样一起改。
- 故意要小、要淡的字（一页原文当底纹、时间轴的刻度）写 `texture: true`：它可以小于下限，也不算 read。
- `ready` 时每个镜头抽 5 个时刻各画一遍，绕过 `txt()` 自己设 `X.font` 写下的小字也会被抓到，打成一行 `console.error`（`bin/vh frames` 在开头"while loading"下面列出来），写明镜头和那段字。判的是代码要的字号，不是动画缩放途中的大小。
- `label(t, at, s, x, y, o)`：一行字在 `at` 升起，停到镜头结束（或 `o.until` 前淡出）；完全出来以后登记成 read，`bin/vh textcheck` 按它查遮挡和对比。`stamp()` 盖下以后也算 read。自己画的字要登记，就在 `draw` 里调 `read(text, start, end)`。
- 三个字体族 `"Film Sans"`、`"Film Serif"`、`"Film Mono"` 在 `film.html` 里声明，`o.family` 写 `sans`、`serif`、`mono`。换字体改 `@font-face` 的 `local()`，族名不动；`ready` 逐个载入，本机没有的会报出名字，画的时候落到后备字体。
- 字体在，某个字它没有，也会悄悄换字体画（`"Film Mono"` 的 Menlo 没有中文，宋体的 Black 没有"–"）。`bin/vh fonts check <项目>` 一个字一个字查，`bin/vh render` 出片时也会说。`local()` 写什么名字，`bin/vh fonts list --cjk` 列出本机有的；要让片子不靠本机字体，`bin/vh fonts subset <项目>` 把用到的字抽成 woff2 放进 `assets/fonts/`，按它打出的那行写进 `src` 的最前面（系统字体的子集是一份拷贝，只留在项目里，不发出去）。

## 字幕

- 按旁白的每句自动生成，画在底部一条软的暗带上（`light` 的镜头改成一块底板）：一行，不超过 `FILM.caption.max` 个汉字宽（默认 16，拉丁字母按 0.55 个算；英文片调到 24 左右）；句号、问号、叹号处必断，两句话不进同一条（半角的句点、逗号后面紧跟字母或数字时不算，3.5、1,000、12:30、Node.js 不会被切开；e.g.、Dr. 这类缩写和"1. 2."这样的编号会被当成句末，看到了就改旁白稿）；一句太长时按逗号分，分得尽量一样长；逗号显示成空格，末尾标点不显示（问号、叹号和省略号留着）。
- 时间取每段第一个字的时间（提前 0.1 s），一句的最后一条可以留到停顿里（`hold`，0.8 s）；不到 1.8 s 的往后借停顿，不占下一条；两条之间的缝小于 0.25 s 就首尾相接，字幕带不会闪一帧。
- 引擎自己切字幕时，太长的一段没有逗号就按宽度从中间切，可能切在词中间（不会切在拉丁字母的词和数字中间）。要按词切：跑 `bin/vh captions <项目> --cards`（用 jieba 找词边界，读 `audio/capbreaks.json` 的手工断点表），再在 `src/50-shots.js` 里写 `FILM.caption = { ...FILM.caption, from: "audio/captions.json" }`，引擎就用这份字幕的切法和时间（加上 `FILM.lead`），最短停留、短缝相接照旧在引擎里做。改了配音要重跑 `bin/vh captions --cards`（`bin/vh pace` 会照原来的模式重做）。这份文件不是一行一条的卡（不带 `--cards` 跑出来的）、有卡宽过 `FILM.caption.max`、或者卡对应的句子在现在的时间轴里没有（换过稿子）、卡的时间落在它那句之外（换过一条配音），`ready` 都会报出来，不会悄悄照画；单独一个比 `FILM.caption.max` 还宽的英文词（一个链接）照画。
- 一句里紧跟着又一句、前一句又很短时（"他说："走吧。""），那一条可能只亮半秒：`bin/vh readcheck <项目>` 按字幕的下限查得出来。

## 封面

`src/50-shots.js` 里写 `COVERS`，每张一项：

```js
const COVERS = [
  { id: "A", at: "@a2:第二张+0.6", cam: { z: 1.12, x: 0, y: -60 }, title: { text: ["改一个字，镜头跟着走"], size: 150, x: 960, y: 1010, align: "center" } },
];
```

- `at` 和镜头的一样写成 cue：改了开场、重配一句，封面跟着取到同一个画面，不会过期。`bin/vh cues` 把它列成 `cover.A.at`。
- `cam: { z, x, y }`：只在这张封面上生效的机位微调，绕画面中心放大 z 倍，再挪 x、y 像素，给标题让出地方。挪动不能超过放大留出的余量（横向 (z − 1) × 960，纵向 (z − 1) × 540），超了 `ready` 会报出来，免得露出画面的边。
- `title: { text: [行…], size: [每行字号] 或一个数, x, y（第一行的基线）, align, color, band }`：用 `"Film Heavy"` 画，这一档是各系统最粗的中文黑体，带深色描边和一条压暗的底；`band: false` 不要底。章节条和字幕默认不上封面，要的话写 `bar: true`、`caption: true`。
- `bin/vh frames <项目> --covers` 把每张封面画进 `out/covers/<id>.png`（`--covers=A,B` 只画这几张，`--dpr 2` 出 3840 × 2160），再用 `bin/vh cover-preview out/covers/*.png` 看在信息流里的大小。

`"Film Heavy"` 在 `film.html` 里按这个顺序找（`bin/vh fonts list --cjk` 列出本机的中文字体，对一下表里的名字；`ready` 报出本机一个都没有的情况；标题里的字这一档字体有没有，`bin/vh fonts check` 也查，它会把封面画一遍）：

| 系统 | 字体（`local()` 的名字） | 备注 |
|---|---|---|
| macOS | 兰亭黑 Heavy（`FZLTTHK--GBK1-0`、`Lantinghei SC Heavy`） | 系统按需下载的字体：第一次用时才装，没装就落到下一个 |
| macOS | 冬青黑体简体 W6（`HiraginoSansGB-W6`） | 系统自带 |
| Linux | 思源黑体 / Noto Sans CJK SC Black 或 Heavy（`NotoSansCJKsc-Black`、`SourceHanSansSC-Heavy`） | `fonts-noto-cjk-extra` 这类包里才有 Black |
| Windows | 微软雅黑 Bold（`Microsoft YaHei Bold`） | 没有更粗的一档 |
| 最后 | 苹方 Semibold（`PingFangSC-Semibold`） | 每台 Mac 都有；苹方最粗只到 Semibold |

## 事件和 reads：录制器

画东西的小函数开头调一次 `cue(kind, t0, { x })`（`drop`、`stamp` 已经调了），平时什么都不做；`ready` 时每个镜头抽 5 个时刻各画一遍，录下镜头在画面上时发生的事件（落下、盖章、亮起……）和 reads，去掉重复。`x` 写这件事在镜头里的位置（不随 t 变），按变换换算成屏幕横坐标，配音效时给声像用；推镜时取离事件最近的那次抽样的变换（推镜很慢，差不了多少）。同一个调用在几次抽样里各录一次，只留一条。每个镜头边界的转场也记成事件（`kind` 就是转场名，`cut` 也在内），评审前拿它和 STYLE 写的转场对一遍。

## `window.film` 给出什么

| 字段 | 内容 |
|---|---|
| `frame(t)` | 清掉画布，画出第 t 秒：镜头（或转场里的两个镜头）、颗粒、章节条、字幕、片头片尾的淡入淡出。`frame(t, { layer: "scene" })` 不画章节条和字幕 |
| `duration` | 片长（秒） |
| `ready` | 字体、图片、时间轴载入，全部 cue 解析，字幕排好，录制器跑完 |
| `width`、`height` | 1920 × 1080；画布按 `devicePixelRatio` 开大，`--dpr 2` 就是 4K |
| `texts` | reads 和字幕：`[{text, start, end, read}]`，字幕的 `read` 是 `subtitle` |
| `events` | `[{t, kind, shot, x?, dur?}]` |
| `chapters` | `[{t, title}]` |
| `cues` | 每个 cue 的解析结果：`[{id, ref, t}]`，`id` 像 `S02.o.one`、`chapter2.at`、`cover.A.at` |
| `covers`、`cover(id)` | 封面：`[{id, t, title}]`，`cover(id)` 按它的机位和标题画这一张 |
| `timeline` | 载入的旁白时间轴，相对 `film.html` 的路径；无声片是 `null` |
| `ui(t)` | 章节条和字幕在 t 秒时的框：`[{name, box}]`。全部章名都亮着时，章节条一个框，从进度线上的圆点到章名下沿；只亮当前一章时，进度线一个框（`chapter bar`），当前章名一个框（`chapter title`）；字幕只框字，不框暗带（`caption`） |

页面从不自己往前走，只在 `frame(t)` 被调用时画；直接用浏览器打开 `film.html`（`file://`）读不到时间轴，什么也不画。

## 检查和出片

```bash
bin/vh frames <项目> --at 4.9,12.8           # 单帧，无损 PNG，在 <项目>/out/frames/
bin/vh frames <项目> --strip 12.2:13.4 --fps 10   # 一段的每一帧拼成一张，看转场和动作
bin/vh frames <项目> --at 4.9 --dpr 2        # 4K 的帧
bin/vh textcheck <项目>                       # reads 和字幕有没有被盖住、对比够不够、出没出画；镜头有没有画到章节条、字幕底下
bin/vh frames <项目> --covers                 # 封面：out/covers/<id>.png（COVERS，取帧时间挂在字上）
bin/vh cues <项目> --chapters                 # 章节表，写进简介用：0:00 章名……，也写进 out/chapters.txt
bin/vh cues <项目> --save                     # 每个 cue 落在第几秒，存进 out/cues.json；换了配音再跑，列出哪些镜头挪了、挪了多少
bin/vh readcheck <项目>                       # reads 和字幕够不够时间读（读时底线）：先把 window.film.texts 写成 out/texts.json
bin/vh determinism <项目>                     # 同几个时刻换顺序画、换进程画，看是不是 t 的纯函数
bin/vh render <项目> [--dpr 2]                # 成片画面：<项目>/out/film.mp4（--dpr 2 是 4K），没有声音
bin/vh patch <项目>/out/film.mp4 --seconds 142.2-159.2   # 只重画改过的一镜，接回成片（片子要是 bin/vh render 出的，旁边有 .render.json）
bin/vh mux <项目>/out/film.mp4 <混音.wav> <成片.mp4>   # 套上混音
```

## 守硬规则 1

- 随机一律用 `hash(i)`、`hash2(i, j)`、`noise1(x)`；不用 `Math.random`、`Date`、`performance.now`，不在帧和帧之间留状态。
- 只画一次就反复用的东西（`texture()`、颗粒的噪点块、转场的离屏画布）只依赖自己的参数，命中缓存和重画一遍是同一个结果。`texture()` 常常第一次画在 `ready` 的抽样里，那时宿主还没把时钟钉在某个 t 上，所以里面更不能用 `Math.random`、`Date`。
- `frame(t)` 每次先 `reset()` 画布，上一帧哪怕中途抛错留下的状态也会清掉。
- 实测（2026-10-11，M3 Max，`bin/vh frames` 用的 chrome-headless-shell 150）：1080p 下同一个 t 单独画、先画别的帧再画（包括转场中的帧），PNG 逐字节相同。4K（`--dpr 2`）在 GPU 上，先画过别的帧再画，标题字形里有几个像素差 1 级（看先画哪一帧，PSNR 107–119 dB，远高于 45 dB 的线）；同样的顺序跨启动逐字节相同，加 `--soft-gl` 时不管顺序都逐字节相同。

## 局限

- 只有 16:9。别的画幅要同时改 `FILM.width`、`FILM.height` 和 `film.html` 里的尺寸，`bin/vh textcheck` 也还是按 1920 × 1080 打开页面。
- SRT、镜头表（`shots.json`）还没有导出。
- 没有 Three.js 底层。
- 引擎自己切字幕时不按词切；按词切要先跑 `bin/vh captions --cards`，见"字幕"。
- 录制器只看得到每镜 5 个时刻画到的东西：一个只在两个时刻之间才调用的 `cue()` 或 `read()` 会漏掉。把它们写在 `if` 外面，先登记，再判断这一帧要不要画。
