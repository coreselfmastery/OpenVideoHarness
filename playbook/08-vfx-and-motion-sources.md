# 08 特效与动画：去哪里找、怎么接进来

特效和动画都是画面代码的一部分，同样必须是 t 的纯函数。本篇只讲**来源和接法**。审美规则见 `03-motion-design.md`；什么时候该用、用多少，看类型文档。

## 原则

1. **特效服务于内容**。每个特效都要能说出一句"因为这支片子（产品、概念）有 X，所以用 Y"（借鉴归藏的做法）。说不出来的，就是装饰。
2. **全片一套特效语汇**：2–3 种转场、1 种主背景手法，反复使用，不要每个镜头换一种。
3. **声画同源**：特效的触发点从 `music.beats.json` 的 `beats`、`downbeats`、`hits`，或者 `timeline.json` 的句子边界读取，不要手填时间。
4. **随机要可复现**：粒子、噪声、抖动全部用带种子的 hash。着色器里只用 `uTime = t`，不用系统时钟。

## 按引擎找现成的

| 需要什么 | HyperFrames（HTML + GSAP） | p5 / ClaudeAnimationBase | ManimGX | 通用 |
|---|---|---|---|---|
| 转场 | canvas 片子：lib.js 的 `wipe/iris/whip/dissolve/push/blinds/zoomDip` + `shaderTransition`（GLSL 像素级，七种；`engines/hyperframes-creative.md`，一条命令 `tools/hf_creative.sh --fx`）；DOM 场景：`npx hyperframes add <block>` 注册表里有着色器转场（例如 `flash-through-white`）；速度匹配的切法见 `references/repos/hyperframes/_upstream_claude/skills/cut-the-curve/` | `brushWipe`、`iris`、`irisShape`（见 ANIMATION_GUIDE） | `Transform`、`FadeTransform`、摄像机移动 | 跟着动作切、形状匹配切 |
| 背景和氛围 | canvas 片子：`lib.glow/duotone/lightLeak/shimmer`；Three.js 或 canvas 层；`hyperframes-creative/references/audio-reactive.md` | 水彩 fill、纸纹、`glow()` | `NumberPlane`、渐变背景 | 颗粒、暗角（成片后处理，见下） |
| 粒子、汇聚、流线场 | canvas 片子：`lib.particles`（drift/rise/fall/orbit/stream，种子化、无缝循环）；自己写时用 `hash(i)` 定初始状态 | `hash` + `jit` | `VMobject` 点阵 | 思路参考 guizang 的 `assets/fx-lab/`（AGPL，只看思路不复用代码） |
| 文字动效 | canvas 片子：`lib.drawKinetic`（rise/pop/wave/cascade/jitter 逐字编排）、`lib.scramble`、`lib.marker`（highlight/circle/underline 强调标记）；逐词 stagger、`steps()` 打字、`clip-path` 揭示（数值见 03 篇） | `letter()`、`sfx()` | `Write`、`TransformMatchingTex` | — |
| 配色 | canvas 片子：`lib.harmony`（一色生一族）+ `lib.ramp`；命令行 `tools/hf_creative.sh --palette <hex> --scheme triad` | — | — | 色板写进 STYLE.md |
| 数据图表动画 | `npx hyperframes add data-chart`；`hyperframes-creative/references/data-in-motion.md` | — | `Axes`、`BarChart` | `references/repos/data-animation-skills/` |
| 角色动画 | — | Clawd 的 31 种情绪、转身、舞蹈（ANIMATION_GUIDE） | — | 生成视频打底 + 转描（`05-hybrid-genvideo.md`） |
| 3D、着色器 | Three.js 层 + postprocessing | — | `ThreeDScene` | `references/repos/awesome-opus5-5-videos/` 的 3d 类作品和 prompt |
| 光标、UI 演示 | `oversized-cursor` 技法（`_upstream_claude/skills/oversized-cursor/`） | — | — | 用真实 UI，不用占位 |

更多风格来源：
- `references/community-skills.md` §2 收录了 lemo-opuscar 的 43 种影片风格，每种都有风格 prompt 和纯代码样片；
- `references/repos/hyperframes/skills/hyperframes-creative/references/visual-styles.md` 是 8 种设计师风格预设。

## 特效做成预设栈

"炫酷"要到什么程度，事先很难说清，定稿后还常常改主意。所以特效强度不要写死在代码里，而是做成一张预设表，用一个 HyperFrames 变量（介绍片叫 `fx`）来选。这样 look-dev 的几个变体、定稿后"再狠一点"，都只是换个变量重渲一遍，代价就是一次渲染。

```js
// js/fx.js：每个效果一个系数，0 = 关
export const PRESETS = {
  A: { bloom: 0.95, rays: 0.75, whip: 0.55, mblur: 0.25, shake: 1.0, flash: 0.5, decode: 0, glitchExit: 0 /* … */ },
  B: { bloom: 1.0,  rays: 1.0,  whip: 1.0,  mblur: 1.0,  shake: 1.7, flash: 1,   decode: 1, glitchExit: 0.35 },
  C: { /* B 再加扫描线、RGB 分离、整帧 glitch、HUD */ },
};
const P = PRESETS[window.__hyperframes?.getVariables?.()?.fx] ?? PRESETS.B;
// 用的地方只乘自己的系数，例如 bloom.strength = P.bloom * (1 + 0.3 * big(t))
```

```bash
npx hyperframes render --variables '{"fx":"A"}' --output out/lookdev/A.mp4
```

介绍片的三档（数值来自项目的 `js/fx.js`；look-dev 之后选了 B，NOTES 里记的是"协调方转达"，不是用户本人的原话）：

| 效果组 | A 克制电影感 | B 大片 | C 赛博 | 因为这支片子有 X，所以用 Y |
|---|---|---|---|---|
| 调色：暗部 teal、高光 amber、压黑、S 曲线 | 对比 1.12 | 1.20 | 1.22 | 唯一的强调色琥珀只以"光"出现 → 高光推琥珀、暗部推冷，不引入第二个饱和色 |
| bloom / god rays / 横向光条 | 0.95 / 0.75 / 0.11 | 1 / 1 / 0.17 | 同 B | t 轴、光环、门缝都是光源 → 给光体积，强度随 downbeat 呼吸 |
| 甩镜调速（slow–FAST–slow）/ 运动模糊 / 速度线 | 0.55 / 0.25 / 关 | 全开 | 同 B | 一镜到底，换段全靠镜头 → 平移换成甩镜，模糊按镜头的实际速度算 |
| 打点：震动、FOV punch、冲击波环、色差、闪白 | 震动 1×，其余 0.3–0.5 | 全开，震动 1.7× | 同 B | 配乐有 4 个大冲击 → 画面在同一帧"挨打"，约 6 帧衰减完 |
| 手持漂移 | 0.5 | 1 | 1 | 停站时镜头也要活着 |
| 纵深火花 / 沿 t 轴的数据流 | 0.5 / 0.6 | 1 / 1 | 1 / 1 | 片子讲"时间轴上的帧" → 数据沿 t 轴流，火花给纵深和视差 |
| 字：decode、tracking-in、扫光、退场 glitch | 只有扫光 | 全开，退场 glitch 0.35 | 退场 glitch 1 | 片子讲"代码写出画面" → 字像被程序解码出来，≤ 0.3 s 定住 |
| 扫描线、RGB 分离、整帧 glitch 切片、HUD 读数 | 关 | 只开 HUD（0.5） | 全开 | 只作比较用的赛博方向 |

- 表的最后一列是硬要求（原则 1）：每个效果都要写得出"因为 X，所以 Y"，写进 NOTES.md；写不出来的效果不进预设表。
- 另留一档旧版基线（介绍片叫 `v2`，新加的效果全关），用来和改版前逐帧对比。
- 选定的预设名写进 STYLE.md。look-dev 怎么组织见 `video-types/03-product-promo.md`。

### 任何预设都不能突破的底线

- **全屏闪白每秒不超过 3 次**（WCAG 2.3.1 的三次闪烁阈值）。介绍片只在 4 个大冲击上闪白，全片一共 4 次。
- **光效不能把字烧掉**：
  - bloom、god rays、闪白叠在同一帧会过曝，介绍片 braam 那一帧就是这样；冲击的峰值帧要逐帧看。
  - 扫过字面的光做成金色色带，亮度不超过字本身。
  - URL、命令这类要让人抄下来的字出现之前，横向光条先收掉。
- **必读字在画面上时，运动模糊压到约 5%**：介绍片按必读字的不透明度自动压（`guard = 1 − 0.95 × opacity`），色差同时减 60%。要读长句时，下面不要甩镜，改成慢摇臂。

## 真正的子帧运动模糊

屏幕空间的后期模糊（按镜头速度做径向和方向模糊，介绍片用的就是这种）很便宜，但它抹的是整张图：跟着镜头走、在画面上根本没动的字也会被抹花，只能靠上面"压到 5%"兜底。真正的运动模糊，是在一帧的曝光时间里多采几个时刻，再取平均：

```text
第 f 帧 = (1/N) · Σ render(t_f + (k/N) · s / fps)，k = 0 … N−1，s = 快门角 / 360°
```

- 180° 快门（s = 0.5）只平均这一帧时间间隔的前一半，是电影的常规观感；360° 平均整段，更糊。
- 硬规则 1 在这里直接变成能力：每一帧都是 t 的纯函数，分数的 t 也能渲。
- 代价是渲染时间 ×N，N 取 4–8 一般就够。只在最终版开，draft 不开。
- 好处：跟镜头的字在 N 个子时刻的位置都一样，自动保持清晰；只有真正在画面上移动的东西才会糊，不再需要 guard 之类的补丁。

两种接法：
- **在 Three.js 层里累积**：`renderAt(t)` 把场景在 N 个子时刻各渲一次，累加进一张浮点 render target 取平均；bloom、调色、颗粒这些后期只在平均之后做一次。
- **整页高帧率渲染，再用 ffmpeg 平均**：[product-film-skill](https://github.com/Rieranthony/product-film-skill)（Remotion）就是这样做的：渲 240 fps 母版，用 `tmix=frames=4` 加 `select='not(mod(n+1\,4))'` 降到 60 fps，相当于 360° 快门。HyperFrames 本地渲染的 `--fps` 文档只列了 24/30/60，输出 30 fps 时这条路最多只有 2 个子帧；它较新的版本有整帧子采样的 `motionBlur` 渲染选项（见 `references/repos/hyperframes/skills/hyperframes-animation/references/motion-blur.md`），在 0.8.82 上没有验证过。社区里也有人用 Playwright 渲子帧做运动模糊（`cases/opus55-gallery.md` 里 @twoclipping 那条）。

还有两个细节，来自 abstract-algebra-promo 的 `promo.html`（无许可证，只读；拆解见 `cases/opus55-gallery.md` §7）。它在单个 canvas 里每帧取 3–4 个子时刻，按 180° 快门以 t 为中心前后展开，累加进一张 WebGL 浮点纹理：

- **子帧不能跨切点**：子时刻落进了另一个场景或另一个镜头，这个子帧就改用 t 本身来渲。不这样做，切点两侧的画面会在同一帧里叠印，硬切变成一帧溶。它的做法是每个场景除了 `draw(lt)` 还带一个 `shot(lt)`，返回场景内当前镜头的编号；子时刻 tₖ 所在的场景或 `shot(tₖ)` 和 t 的不一样，就退回 t。一拍一个镜头的快切蒙太奇最需要这条。
- **顺手得到抗锯齿**：每个子帧再给整个画面加一个不同的亚像素平移（一张固定的 8 组偏移表，范围 ±0.5 px），平均之后边缘自然变柔，等于白送了一次超采样抗锯齿。偏移表是固定的，所以仍然是 t 的纯函数。偏移只加在画面层；字幕、章节标题、闪白在平均和调色之后按 t 单独画，不参与模糊，始终清晰。

## 一镜到底（3D 世界）的做法

来自介绍片（`showcase/04-intro-film/`），包括 v3 返工时学到的：

- **世界而不是幻灯片**：所有章节都是同一个空间里的"地点"，换场靠摄像机穿过物体、沿轴飞行、拉远看到全貌，不靠剪切。
- **字是世界里的物体**：大字是空间里的平面，按"在画面上占多宽"反推尺寸和距离，保证读的那一刻够大；字的出现和摄像机的运动一起设计。
- **高速镜头里的字要 ride**：读的那段时间，字骑在镜头前方一段固定距离上（例如从 16 m 缓到 11 m），看上去只以 2–3 m/s 接近，读完再淡出或让镜头穿过去。字设 `depthTest: false`，仍在空间里，但不会被别的物体挡住。甩镜时必须看清的东西（例如"通过"章）直接跟镜头走，放在画面下三分之一，避开光晕。
- **节点标签用 pin**：挂在节点上的标签按屏幕像素定字号，夹在安全框里，节点出画就淡出，镜头怎么飞，字号都稳定（实现要点见 `engines/README.md`）。
- **产品信息图是世界里的地点**：架构是一张会通电的节点网络，工作流是一条导管，人工关卡是镜头能飞穿的门，自查回环是一个圆环。能量头沿导管走到哪，镜头就跟到哪，节点在拍点上点亮；整张图至少给一次俯瞰全景，让人看到全貌。节点和边的文字逐字照抄 README 或架构图。
- **停站不是停机**：v2 在三道关卡上让音乐和摄像机同时停住，用户的反馈是音乐"卡顿或者消失"，看上去就像播放器卡了。v3 的做法：
  - 镜头减速成慢推，再叠一层低幅手持漂移。漂移用带种子的低频平滑噪声（约 0.5–2 Hz）；逐帧取随机数即使带种子，也只是抖动，不是手持；
  - "停"交给光、声和盖章来表达：鼓先撤，pad 和 sub 持续垫底，一道 riser 吸进下一个强拍，配乐里不出现数字静音（见 `04-audio.md`）。
- **复杂运镜写成动作编排**：一段路径只有一个主运镜。次运镜挂在触发点上，例如能量头到达某个节点、一句字读完。再写明哪些量保持不变（字号、主体大小、轴线）。短段落最多两个主动作。给视频模型写运镜也是这套办法，见 `05-hybrid-genvideo.md`。
- **真实素材放在世界里**：成片挂在空间里的屏幕上，联系表立成一面墙；每一帧都能追溯到真实来源。关卡也一样：门里放被审的那份东西（这支片子自己的大纲、分镜联系表、初版联系表），镜头穿门而过；关卡的字幕在通过那一拍从 ○ 变成 ✓，是同一句话，不是新的一读（v5）。
- **氛围层先画，永远让字**：v5 正文里飘着上千张小影片，是透明物体；一开始它们按默认顺序画，离镜头近的卡片压在字和面板上面，“102 instruments”被盖成“02”。氛围层设最小的 `renderOrder`（例如 −100）最先画，字、面板、成片都盖在它上面；离镜头太近的卡片在几米内淡掉，不让一张大卡一两帧闪过镜头。
- **要读的字不要亮到触发后期**：光条、泛光按亮度阈值取高光，要读的琥珀字如果超过阈值，会被自己的横向光条吃掉，看上去是柠檬黄压在橙色上。要读的彩色字把线性亮度压在阈值以下（v5 的光条阈值是最亮通道 0.82，琥珀字从 #FFB224 改成 #DCA234），光效留给不用读的东西。
- **一个节拍函数给画面和配乐共用**，比如 `bar(k, beat)`。90 BPM 在 30fps 下一拍正好 20 帧，所有细分都落在整帧上。变拍（例如加一个 6/4 小节）也只改这一个函数，见 `engines/README.md`。v5 为了让字多停 12.5 % 降到 80 BPM（一拍 22.5 帧），画面按帧取整，音效按精确时间放，cue check 仍在一帧以内。
- **停留之后接远跳，出发关键帧要用停留段的切线**：Hermite / Catmull-Rom 按前后两个关键帧算切线。停留段后面紧接一次远距离的跳（例如拉到全景）时，停留段末尾的切线会被远处那一帧拽歪，镜头先往前冲一截再退回来，标签被挤出画面（v5 正文 44.4–45.3 s）。出发的那一帧用停留段自己的切线（介绍片代码里的 `"b"`），到达的那一帧用下一段停留的切线（`"f"`）。

## 声画联动的接法

```js
// 引擎里读节拍表（music.beats.json）和字幕（captions.json），全部按 t 查表
const beat = beats.beats.findLast(b => b <= t);            // 最近一拍
const k = Math.exp(-(t - beat) / 0.12);                     // 每拍的衰减脉冲，用于缩放或亮度
const hit = beats.hits.find(h => Math.abs(h.t - t) < 1/30); // 冲击点所在帧 → 闪白、抖动
const cap = captions.find(c => c.start <= t && t < c.end);  // 当前字幕
```

**细到每一个音。** 角色走在琴键上、每一步都是一个音的片子，要的不只是拍点，而是每个音的起止和音高。给那个声部写 `"note_map": true`，`bin/vh music` 就把它的每个音写进节拍表的 `notes`（字段见 `tools/audio/README.md` 的"score.json"）：

```js
// notes: [{t, end, midi, vel, part}]，按 t 排好；part 是声部的 id（没写 id 时是 "piano#0" 这样的乐器名加序号）
const down = (m) => beats.notes.some(n => n.part === "keys" && n.midi === m && n.t <= t && t < n.end);   // 第 m 个键此刻按着吗
const walk = beats.notes.filter(n => n.part === "walk");                     // 角色走的那一行：单音旋律，每一步一个音
const step = walk.findLast(n => n.t <= t), next = walk.find(n => n.t > t);   // 最近踩下的那一步，和下一步
const from = step ?? next, to = next ?? step;                                 // 第一步之前站在第一个键上，最后一步之后站住
const u = step && next ? (t - step.t) / (next.t - step.t) : 0;               // 两步之间走到哪了
const x = keyX(from.midi) + (keyX(to.midi) - keyX(from.midi)) * u;           // 音高 → 键在画面上的位置（keyX 是场景自己的映射）
```

- 琴键在 `t` 按下、在 `end` 抬起；按下的深度可以用 `vel` 调。`end` 是谱面上的松键时刻，钢琴的余音会比它响得久。
- 角色的脚在 `t` 那一帧落到 `midi` 对应的键上，从一个音的 `t` 跳到下一个音的 `t`，走一条抛物线。驱动走路的声部写成单音旋律：和弦每个音一条，轮指按每一次击弦列出，扫弦按每根弦列出，它们会挤在同一个时刻。
- 时间一律从节拍表读，不要把秒数抄进场景代码：谱子改一个音，声音和画面一起变。
- `bin/vh qa` 不读 `notes`。这些音要做 cue check（混音以后还听不听得见、落没落在那一帧），声部上再写 `"hit": true`。

音效同理：画面上发生动作的帧就是 `events.json` 里的 `t`。先定画面的时间，再生成音效轨，不要反过来去凑。

**声像也跟着画面走。** 发声的物体在画面左边，声音就从左边来：事件的 pan 取发声物体在那一帧投影到屏幕上的 x（NDC，−1 到 1），出画的物体夹在 ±1；距离再决定衰减，例如距离每翻一倍降 6 dB。摄像机和物体都是 t 的纯函数，所以 pan 和衰减都由同一份相机代码按事件的 t 算出来，不要手填。`events.json` 里的声像字段，以及混音要保留立体声，见 `04-audio.md`。

## 成片后处理（ffmpeg，可选）

本机的 ffmpeg 可能没有编译文字绘制功能，但这几种滤镜可以直接用：

```bash
ffmpeg -i in.mp4 -vf "noise=alls=6:allf=t,vignette=PI/5" -c:a copy out.mp4     # 轻颗粒 + 暗角
```

颗粒会让 GIF 体积暴涨，给 README 用的 GIF 要从无颗粒版本生成（见 `video-types/03-product-promo.md`）。
